# Unit Conversion Fix — Bugfix Design

## Overview

The watch face stores all temperature, wind speed, tide height, and swell height values in metric units internally (Celsius, m/s, meters). However, at display time the code uses `distanceUnits` as a proxy for ALL unit decisions — appending imperial suffixes without actually converting values (temperature), using the wrong DeviceSettings field for elevation data, and conditionally fetching imperial data from OWM which creates an ambiguous storage format. The fix standardizes on: always store metric, convert at display time using the CORRECT `DeviceSettings` field per data type, and extract pure conversion helpers into a testable module.

## Glossary

- **Bug_Condition (C)**: The condition where a display-time unit conversion is either missing (suffix shown without math), uses the wrong DeviceSettings field, or depends on an ambiguous stored value from OWM imperial fetch
- **Property (P)**: The desired behavior — correct numeric conversion applied at display time using the appropriate DeviceSettings field (`temperatureUnits`, `elevationUnits`, `distanceUnits`)
- **Preservation**: Existing wind speed conversion logic (already correct, uses `WindSpeedUnit` + `distanceUnits` for Auto mode), Open-Meteo/Garmin fetch layer (already metric), tide/swell storage format (already meters), background delegate GPS/BT reads
- **UnitConverter**: New module (`source/UnitConverter.mc`) containing pure conversion functions and DeviceSettings reader helpers
- **Storage version bump**: Incrementing `"av"` key from 4 to 5 to invalidate cached imperial OWM data from before the fix

## Bug Details

### Bug Condition

The bug manifests when displaying temperature, tide height, or swell height values on a device where the user has set imperial units. The display code either (a) appends an imperial suffix without applying any mathematical conversion, (b) uses `distanceUnits` instead of the semantically correct `temperatureUnits` or `elevationUnits` field, or (c) stores an ambiguous value from OWM that depends on fetch-time settings.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type {dataType: String, deviceSettings: DeviceSettings, weatherSource: Number}
  OUTPUT: boolean

  // Temperature: wrong field used OR no conversion applied
  IF input.dataType == "temperature"
    RETURN input.deviceSettings.temperatureUnits != input.deviceSettings.distanceUnits
           OR (input.deviceSettings.distanceUnits == UNIT_STATUTE
               AND input.weatherSource IN [0, 1])  // Garmin/Open-Meteo: suffix shown, no conversion

  // Tide/Swell height: wrong field used
  IF input.dataType IN ["tideHeight", "swellHeight"]
    RETURN input.deviceSettings.elevationUnits != input.deviceSettings.distanceUnits

  // OWM wind: back-conversion from imperial introduces precision loss
  IF input.dataType == "windSpeed" AND input.weatherSource == 2
    RETURN input.deviceSettings.distanceUnits == UNIT_STATUTE  // stored as mph, back-converted

  RETURN false
END FUNCTION
```

### Examples

- **Temperature, Open-Meteo, imperial distance**: Stored value = 22.0 (°C). Displayed as "22°F" — suffix is "F" but no C→F conversion applied. Should display "72°F" (22×1.8+32).
- **Temperature, metric distance, Fahrenheit preference**: Stored value = 22.0 (°C). Displayed as "22°C" because `distanceUnits == UNIT_METRIC`. User wants Fahrenheit via `temperatureUnits`. Should display "72°F".
- **Tide height, metric distance, feet elevation**: Stored value = 1.5 (meters). Displayed as "1.5m" because `distanceUnits == UNIT_METRIC`. User has `elevationUnits == UNIT_STATUTE`. Should display "4.9ft" (1.5×3.281).
- **Swell height, imperial distance, meters elevation**: Stored value = 0.9 (meters). Displayed as "3.0ft" because `distanceUnits == UNIT_STATUTE`. User has `elevationUnits == UNIT_METRIC`. Should display "0.9m".
- **OWM wind, imperial**: Fetched as mph (e.g., 15.0). Stored as 15.0. Display code does `15.0 / 2.237 = 6.706...` to get m/s, then `6.706 × 2.237 = 15.003...`. Floating point precision loss vs always storing as m/s.
- **Edge case: -40°C**: Displayed as "-40°F" — correct since -40°C = -40°F (crossover point).

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Wind speed unit logic: `WindSpeedUnit` app setting (0=Auto uses `distanceUnits` for km/h vs mph selection, 1=km/h, 2=knots, 3=mph, 4=m/s) — this is ALREADY correct and must not change
- Open-Meteo fetch logic: already returns temperature in °C and wind in m/s — no fetch-layer change needed
- Garmin built-in weather: already returns temperature in °C and wind in m/s from the OS — no change needed
- StormGlass tide fetch: already returns heights in meters — no change needed
- Open-Meteo Marine swell fetch: already returns heights in meters — no change needed
- Background delegate GPS/BT reads: direct OS calls, unrelated to units
- Surf mode sunrise/sunset display: computed from coordinates, not affected by unit settings
- Moon phase display: computed from synodic period, not affected by unit settings

**Scope:**
All inputs that do NOT involve temperature display, tide height display, swell height display, or OWM fetch unit parameter should be completely unaffected by this fix. This includes:
- Wind speed conversion (already correct)
- All non-display logic (data fetching from Open-Meteo/Garmin, tide computation, background scheduling)
- All icon rendering and layout positioning
- Clock, date, battery, notifications, bluetooth, seconds display

## Hypothesized Root Cause

Based on the bug description and code analysis, the root causes are:

1. **Missing temperature conversion**: In `drawWeatherWidget()` and `drawTopSection_Surf()`, the code checks `distanceUnits` and sets the suffix to "C" or "F" but never applies `× 1.8 + 32` for the Fahrenheit case (Open-Meteo and Garmin sources store Celsius).

2. **Wrong DeviceSettings field for temperature**: The code uses `distanceUnits` instead of `temperatureUnits`. A user with `distanceUnits=metric` but `temperatureUnits=Fahrenheit` sees Celsius.

3. **Wrong DeviceSettings field for elevation**: In `updateSubscreenAndArc()` (DataManager) and `drawTopSection()`/`drawTopSection_Surf()`/`drawSwellSection()` (View), the code uses `distanceUnits` instead of `elevationUnits` for tide and swell height. A user with `distanceUnits=metric` but `elevationUnits=feet` sees meters.

4. **OWM fetched conditionally in imperial**: In `startWindFetch()` and `startShoreWeatherFetch()`, the code passes `units = "imperial"` when `distanceUnits == UNIT_STATUTE`. This means stored temperature is sometimes °F and wind is sometimes mph. The display layer then has to "undo" the imperial conversion (wind `/ 2.237`), introducing precision loss. And temperature from OWM in imperial mode happens to display correctly by accident (already Fahrenheit), masking the fact that no conversion logic exists.

5. **No conversion logic exists at all**: The codebase has zero conversion functions. Each display site just formats the raw stored value with a suffix.

## Correctness Properties

Property 1: Bug Condition - Temperature displays correctly using temperatureUnits

_For any_ device configuration where `temperatureUnits` indicates Fahrenheit, and any temperature value stored in Celsius (from any weather source after the fix), the display layer SHALL convert the value using `value × 1.8 + 32` and append "°F". When `temperatureUnits` indicates Celsius, the display layer SHALL show the stored value directly with "°C".

**Validates: Requirements 2.1, 2.2**

Property 2: Bug Condition - Elevation displays correctly using elevationUnits

_For any_ device configuration where `elevationUnits` indicates feet (UNIT_STATUTE), and any tide height or swell height value stored in meters, the display layer SHALL convert the value using `value × 3.281` and append "ft". When `elevationUnits` indicates meters (UNIT_METRIC), the display layer SHALL show the stored value directly with "m".

**Validates: Requirements 2.3, 2.4**

Property 3: Bug Condition - OWM always fetches metric

_For any_ OWM API call, regardless of device settings, the request SHALL include `units=metric` so that temperature is stored in Celsius and wind speed in m/s.

**Validates: Requirements 2.5, 2.7**

Property 4: Preservation - Wind speed conversion unchanged

_For any_ wind speed display, the fixed code SHALL produce the same conversion behavior as the original code for all `WindSpeedUnit` settings (Auto/km-h/knots/mph/m-s), given that the stored value is in m/s. The only difference is that OWM values no longer need back-conversion from mph.

**Validates: Requirements 3.1, 3.2, 3.3**

Property 5: Preservation - Non-OWM weather sources unchanged

_For any_ weather fetch from Open-Meteo or Garmin built-in, the fixed code SHALL produce exactly the same stored values (Celsius temperature, m/s wind speed) as the original code, preserving all existing fetch behavior.

**Validates: Requirements 3.4, 3.5**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `source/UnitConverter.mc` (NEW)

**Purpose**: Pure conversion helpers + DeviceSettings readers, extracting unit logic into a testable module.

**Functions**:
1. `celsiusToFahrenheit(c as Float) as Float` → `c * 1.8 + 32`
2. `metersToFeet(m as Float) as Float` → `m * 3.281`
3. `msToKmh(ms as Float) as Float` → `ms * 3.6`
4. `msToMph(ms as Float) as Float` → `ms * 2.237`
5. `msToKnots(ms as Float) as Float` → `ms * 1.944`
6. `isTemperatureImperial() as Boolean` → reads `System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE`
7. `isElevationImperial() as Boolean` → reads `System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE`

**File**: `source/SurferWatchFaceDelegate.mc`

**Function**: `startWindFetch()`, `startShoreWeatherFetch()`

**Specific Changes**:
1. **Remove imperial conditional**: Delete the `if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) { units = "imperial"; }` logic
2. **Always pass `"metric"`**: Hardcode `var units = "metric";` so OWM always returns Celsius + m/s

**File**: `source/SurferWatchFaceView.mc`

**Function**: `drawWeatherWidget()`, `drawTopSection_Surf()`, `drawTopSection()`, `drawSwellSection()`

**Specific Changes**:
1. **Temperature display**: Replace `distanceUnits` check with `UnitConverter.isTemperatureImperial()`. Apply `UnitConverter.celsiusToFahrenheit()` when imperial.
2. **Tide height display**: Replace `distanceUnits` check with `UnitConverter.isElevationImperial()`. Apply `UnitConverter.metersToFeet()` when imperial.
3. **Swell height display**: Replace `distanceUnits` check with `UnitConverter.isElevationImperial()`. Apply `UnitConverter.metersToFeet()` when imperial.
4. **Remove OWM wind back-conversion**: Delete `if (isImperial) { speedMs = rawSpeed / 2.237; }` block since OWM now always returns m/s.
5. **Water temperature (surf)**: Replace `distanceUnits` check with `UnitConverter.isTemperatureImperial()`. Conversion logic already exists (`* 1.8 + 32`) — just needs the correct settings field.

**File**: `source/DataManager.mc`

**Function**: `updateSubscreenAndArc()`

**Specific Changes**:
1. **Tide subscreen**: Replace `System.getDeviceSettings().distanceUnits == System.UNIT_METRIC` with `UnitConverter.isElevationImperial()` (inverted logic) for `interpTideHeight` display.

**File**: `source/SurferWatchFaceView.mc`

**Function**: `onUpdate()` (lazy init block)

**Specific Changes**:
1. **Bump Storage version**: Change `storedVer != 4` to `storedVer != 5` and `Application.Storage.setValue("av", 5)`. This invalidates any cached imperial OWM temperature/wind data from before the fix.

**File**: `source/tests/UnitConverterTest.mc` (NEW)

**Purpose**: `:test` annotated unit tests for conversion formulas.

**File**: `monkey.jungle`

**Specific Changes**:
1. **Add test source path**: Add `base.sourcePath = $(base.sourcePath);source/tests` if needed for the test runner to pick up test files.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Examine the display output for various device settings combinations by tracing through the code. Since this is a Garmin watch face (no browser DOM, no easy UI test harness), we confirm by code inspection and simulator testing.

**Test Cases**:
1. **Temperature suffix without conversion**: Set `distanceUnits = UNIT_STATUTE`, use Open-Meteo (WeatherSource=1). Store temp=22.0. Observe display shows "22°F" instead of "72°F" (will fail on unfixed code).
2. **Wrong settings field for temperature**: Set `distanceUnits = UNIT_METRIC`, `temperatureUnits = Fahrenheit`. Store temp=22.0. Observe display shows "22°C" instead of "72°F" (will fail on unfixed code).
3. **Wrong settings field for tide**: Set `distanceUnits = UNIT_METRIC`, `elevationUnits = UNIT_STATUTE`. Store tide=1.5m. Observe display shows "1.5m" instead of "4.9ft" (will fail on unfixed code).
4. **OWM imperial fetch precision loss**: Set `distanceUnits = UNIT_STATUTE`, use OWM. Observe URL contains `units=imperial`. Wind stored as mph, then divided by 2.237 at display (will show precision artifacts on unfixed code).

**Expected Counterexamples**:
- Temperature displayed with imperial suffix but metric value
- Tide/swell displayed using wrong unit preference field
- Possible causes: missing conversion math, wrong DeviceSettings field, conditional OWM fetch

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := displayValue_fixed(input)
  ASSERT correctConversion(result, input.storedValue, input.deviceSettings)
END FOR
```

Specifically:
- `celsiusToFahrenheit(22.0)` == 71.6 (≈72 when rounded to integer for display)
- `celsiusToFahrenheit(-40.0)` == -40.0
- `celsiusToFahrenheit(0.0)` == 32.0
- `metersToFeet(1.5)` == 4.9215 (displays as "4.9ft")
- `metersToFeet(0.0)` == 0.0
- `metersToFeet(0.3)` == 0.9843 (displays as "1.0ft" at one decimal)

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT displayValue_original(input) == displayValue_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Verify wind speed conversions produce identical results. Since OWM will now always return m/s (same as Open-Meteo/Garmin), the back-conversion code path (`/ 2.237`) is removed — but the forward conversion (m/s → display unit) must produce the same results for all `WindSpeedUnit` settings.

**Test Cases**:
1. **Wind speed Auto+metric preservation**: Verify `msToKmh(10.0)` == 36.0 (matches original `speedMs * 3.6`)
2. **Wind speed Auto+imperial preservation**: Verify `msToMph(10.0)` == 22.37 (matches original `speedMs * 2.237`)
3. **Wind speed knots preservation**: Verify `msToKnots(10.0)` == 19.44 (matches original `speedMs * 1.944`)
4. **Tide display metric preservation**: When `elevationUnits == UNIT_METRIC`, verify tide shows raw meters (same as before for users whose distance and elevation settings agree)

### Unit Tests

- `celsiusToFahrenheit`: 0→32, 100→212, -40→-40, 22→71.6, -5→23
- `metersToFeet`: 0→0, 1→3.281, 1.5→4.9215, 0.3→0.9843
- `msToKmh`: 0→0, 1→3.6, 10→36
- `msToMph`: 0→0, 1→2.237, 10→22.37
- `msToKnots`: 0→0, 1→1.944, 10→19.44
- `isTemperatureImperial()`: returns correct boolean based on `temperatureUnits`
- `isElevationImperial()`: returns correct boolean based on `elevationUnits`
- Edge cases: negative temperatures, zero values, very small swell heights

### Property-Based Tests

- Generate random Float temperatures in [-50, 50] range and verify `celsiusToFahrenheit` satisfies `result == input * 1.8 + 32` (within floating-point tolerance)
- Generate random Float heights in [0, 20] range and verify `metersToFeet` satisfies `result == input * 3.281` (within floating-point tolerance)
- Generate random Float wind speeds in [0, 50] range and verify all conversion functions are monotonically increasing and preserve ordering
- Verify round-trip: for any Celsius value, `fahrenheitToCelsius(celsiusToFahrenheit(x))` ≈ x (within tolerance) — ensures no information loss

### Integration Tests

- Full simulator test: set `temperatureUnits = Fahrenheit`, `elevationUnits = feet`, `distanceUnits = metric`. Verify temperature shows °F conversion, tide shows ft conversion, wind uses km/h (from distanceUnits Auto mode).
- Full simulator test: set `temperatureUnits = Celsius`, `elevationUnits = meters`, `distanceUnits = imperial`. Verify temperature shows °C, tide shows meters, wind uses mph.
- Storage version bump test: flash watch face with old version (av=4), upgrade to new version (av=5), verify Storage.clearValues() is called and old imperial OWM data is purged.
- OWM fetch test: verify the outgoing URL always contains `units=metric` regardless of device settings.
