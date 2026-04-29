# Architecture Refactor Bugfix Design

## Overview

The Garmin Instinct 2/2X background process runs out of memory (-403 OOM) when parsing StormGlass tide JSON because the `:background`-annotated `SurferWatchFaceApp` class references `DataManager` — pulling its entire type (51 fields, all methods) into the 28KB background process. The fix decouples App from DataManager using the Crystal Face pattern: App writes to `Application.Storage`, View owns DataManager and reads from Storage. Secondary fixes include sensor gating, mode-specific field nulling, unused font removal, and dead code deletion.

## Glossary

- **Bug_Condition (C)**: The App class references DataManager via `var dataManager as DataManager or Null` and calls 11 methods on it from `onBackgroundData()`, `onSettingsChanged()`, and `getInitialView()`, causing the compiler to include DataManager in the background binary
- **Property (P)**: The App class contains zero references to DataManager or any foreground-only class, reducing background memory usage by 500+ bytes and allowing StormGlass tide JSON parsing to succeed
- **Preservation**: All weather, swell, tide, and sensor data continues to flow from background to display identically; all settings changes apply immediately; all rendering is pixel-identical
- **DataManager**: The class in `source/DataManager.mc` with 51 fields (41 public + 10 private) that caches weather, tide, swell, sensor, and computed data for rendering
- **Crystal Face pattern**: Reference architecture where App writes to `Application.Storage` on background events, and View reads from Storage — no foreground class references in App
- **Background process**: Separate Garmin process with ~28KB memory budget that runs `ServiceDelegate.onTemporalEvent()` for HTTP requests; shares the App class binary
- **Storage flag**: A boolean key in `Application.Storage` (e.g., `"weatherUpdated"`, `"settingsChanged"`) set by App, checked and cleared by View on the next `onUpdate()` tick

## Bug Details

### Bug Condition

The bug manifests when the background process attempts to parse a StormGlass tide JSON response on Instinct 2/2X devices. The `SurferWatchFaceApp` class has `var dataManager as DataManager or Null` and calls DataManager methods from `onBackgroundData()` (6 calls: `onWeatherData`, `onSurfWindData`, `onTideData`, `onSwellData`, `refreshWeatherOnBackgroundEvent`, plus mode branching) and `onSettingsChanged()` (5 calls: `clearWeatherData`, `clearPersistedWeatherData`, `loadSurfCache`/`loadShoreCache`, `refreshWeatherOnBackgroundEvent`, `checkCopyGPS`). This forces the compiler to include DataManager's entire type in the background binary, consuming 500+ bytes of the 28KB budget.

**Formal Specification:**
```
FUNCTION isBugCondition(appClass)
  INPUT: appClass of type ClassDefinition (the compiled SurferWatchFaceApp)
  OUTPUT: boolean

  RETURN appClass.hasAnnotation(":background")
         AND (appClass.hasField("dataManager", type=DataManager)
              OR appClass.hasMethodCall(target=DataManager, from="onBackgroundData")
              OR appClass.hasMethodCall(target=DataManager, from="onSettingsChanged")
              OR appClass.hasMethodCall(target=DataManager, from="getInitialView"))
END FUNCTION
```

### Examples

- **Weather background event (shore mode)**: `onBackgroundData()` receives `{"weather": {...}}`, calls `dataManager.onWeatherData(weatherData)` — this reference pulls DataManager into background. Expected: App writes weather dict to Storage, View reads it.
- **Swell background event (surf mode)**: `onBackgroundData()` receives `{"swell": {...}}`, calls `dataManager.onSwellData(swellData)` — same pull. Expected: App writes swell dict to Storage with `"swellUpdated"` flag.
- **Settings change (weather source switch)**: `onSettingsChanged()` calls `dataManager.clearWeatherData()`, `dataManager.clearPersistedWeatherData()`, `dataManager.loadSurfCache()` — anchors DataManager to App. Expected: App sets `"settingsChanged"` flag in Storage, View handles all DataManager calls.
- **Tide background event**: `onBackgroundData()` receives `{"tideUpdated": true}`, calls `dataManager.onTideData()` — already uses Storage pattern for data, but the method call still pulls DataManager. Expected: App sets flag only, View calls `dataManager.onTideData()`.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- All weather data (temperature, condition, wind, sunrise/sunset, precip probability, isDay) displays identically on screen after background fetch
- All swell data (height, period, direction, sea surface temp) displays identically in surf mode
- All tide data (next tide time/type/height, tide curve, interpolated height) displays identically
- Mouse/touch interactions (wrist gesture toggle for bottom section) work identically
- Settings changes (weather source, surf mode, clock font, surf spot coordinates) apply within one `onUpdate()` cycle
- Background temporal events re-register every 5 minutes
- `Application.Properties.getValue()` remains the per-tick read API; `Application.Storage.setValue()` remains event-only
- Bluetooth icon rendering via `seg34IconsFont` is unaffected (only `drawIconHeart()` dead code is removed)
- All CIQ 4.x+ device rendering (Instinct 3) is unaffected — only data flow changes, not rendering

**Scope:**
All inputs that do NOT involve the App-to-DataManager coupling should be completely unaffected by this fix. This includes:
- All rendering logic in `SurferWatchFaceView`
- All background HTTP request logic in `SurferWatchFaceDelegate`
- All `WeatherService`, `OpenMeteoService`, and `TideService` logic
- All `Application.Properties` settings definitions and UI

## Hypothesized Root Cause

Based on the bug description and code analysis, the root causes are:

1. **App field pulls DataManager type into background**: `var dataManager as DataManager or Null` on the `:background`-annotated `SurferWatchFaceApp` forces the Monkey C compiler to include DataManager's class definition (51 fields, all method signatures) in the background binary. This is the primary cause — it consumes 500+ bytes of the 28KB background budget.

2. **`onBackgroundData()` calls 6 DataManager methods**: Even without the field, method calls like `dataManager.onWeatherData(weatherData)` would still pull DataManager into the background. The method body references `DataManager` as a type, which the compiler must resolve.

3. **`onSettingsChanged()` calls 5 DataManager methods**: Same issue — `dataManager.clearWeatherData()`, `dataManager.loadSurfCache()`, etc. all reference DataManager from the `:background` App class.

4. **`getInitialView()` creates DataManager**: `dataManager = new DataManager()` in `getInitialView()` is a direct constructor call. While `getInitialView()` only runs in foreground, the compiler still includes the type reference because it's in the App class body.

5. **Secondary: unconditional sensor reads waste heap**: `updateSensorData()` reads HR and stress in surf mode where neither is displayed. The `SensorHistory.getStressHistory()` iterator allocates heap memory unnecessarily.

6. **Secondary: inactive mode fields hold stale data**: 22 surf-only fields (including 6×24-element forecast arrays) stay allocated in shore mode, and 12 shore-only fields in surf mode.

## Correctness Properties

Property 1: Bug Condition - App Has No DataManager Reference

_For any_ compiled build of `SurferWatchFaceApp`, the App class SHALL contain zero field declarations, method calls, constructor invocations, or type references to `DataManager` or any other foreground-only class, ensuring the background binary does not include DataManager's type definition.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - Data Display Identical After Refactor

_For any_ background data event (weather, swell, tide) or settings change, the fixed code SHALL produce the same DataManager field values (and therefore the same rendered output) as the original code within one `onUpdate()` cycle, preserving all weather, swell, tide, sensor, and computed data display.

**Validates: Requirements 3.1, 3.2, 3.3, 3.5, 3.6**

## Fix Implementation (COMPLETED — v1.0.3)

### Changes Implemented

**File**: `source/SurferWatchFaceApp.mc`
- Removed `dataManager` field, `getDataManager()` method, `_lastWeatherSource` field
- `getInitialView()` returns `[new SurferWatchFaceView()]` — no DataManager init
- `onBackgroundData()` writes to Storage flags only (`"bwd"`, `"wu"`, `"bsd"`, `"su"`, `"tu"`, `"bge"`)
- `onSettingsChanged()` writes `"sc"` flag only
- Removed `getApp()` helper function (dead code)
- App has ZERO references to DataManager

**File**: `source/SurferWatchFaceView.mc`
- Owns DataManager via `private var dataManager` field with lazy init on first `onUpdate()` tick
- Handles `"sc"` (settings changed) flag: weather source change detection, cache reload, font swap, GPS copy
- Single clock font loading in `onLayout()` with live reload on settings change
- `_readNumProp()` helper handles Garmin type quirk (Properties can return String/Float instead of Number)
- Storage version gating: checks `"av"` key, calls `clearValues()` on mismatch

**File**: `source/SurferWatchFaceView.mc` (per-tick optimizations)
- `computeMoonPhase()` moved from per-tick to event-driven (background events + settings changes + init)
- `checkCopyGPS()` moved from per-tick to settings-changed handler only
- GPS read (`Position.getInfo()`) moved from per-tick to event-driven `updateGPS()`

**File**: `source/DataManager.mc`
- `updateSensorData()` reads display sensors only (battery, HR, stress, BT, notifications) — no GPS, no Storage writes
- `updateGPS()` new method: reads `Position.getInfo()` on background events and init
- `checkBackgroundFlags()` processes weather/swell/tide flags, calls `updateGPS()`, `refreshWeatherOnBackgroundEvent()`, `computeMoonPhase()`
- `refreshWeatherOnBackgroundEvent()` only computes sunrise/sunset for Garmin mode — API modes get values from API response
- `calcSunTimes()` replaces old simplified algorithm with SunCalc Julian date algorithm (equation of time + atmospheric refraction, ±1 min accuracy)
- Sensor gating: HR/stress only read in shore mode when displayed
- Removed `persistTideData()` (dead code), `_prevStoredLat`/`_prevStoredLng`/`_prevStoredBt` fields, `dayOfYear()` helper
- All Storage keys shortened to 2-3 chars (full reference in comment block at top of file)

**File**: `source/SurferWatchFaceDelegate.mc`
- Reads GPS directly via `Position.getInfo()` instead of Storage relay
- Reads BT directly via `System.getDeviceSettings()` instead of Storage relay
- Shore tide keys use explicit short names (`"th"`, `"tt"`, `"tp"`) instead of prefix concatenation

**File**: `source/WeatherService.mc`
- Removed `_lat`/`_lon` fields and `owmFetchLat`/`owmFetchLon` Storage writes (dead code)
- Removed unused `System` import

**File**: `source/OpenMeteoService.mc`
- Removed unused `System` import

**File**: `source/TideService.mc`
- Removed `System.println()` from background (was causing string allocation OOM)
- Removed unused `System` import

**Files**: `resources/settings/properties.xml`, `resources/settings/settings.xml`, `resources/strings/strings.xml`
- Removed `HomeLat`/`HomeLng` properties, settings UI entries, and string resources
- Removed unused font files from `resources/fonts/`

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior. Each implementation step is independently testable with memory measurements.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Inspect the compiled binary and runtime memory to confirm DataManager is pulled into the background process. Measure background memory usage before and after each refactor step.

**Test Cases**:
1. **Background memory baseline**: Measure `System.getSystemStats().freeMemory` in `onTemporalEvent()` on v1.0.2 code — expect ~7,416 bytes free at start (will fail to parse tide JSON with v1.1.0 additions)
2. **DataManager type in background**: Verify that adding `System.println(dataManager)` in a `:background` method compiles — confirming DataManager type is available in background (will succeed on unfixed code, proving the type is pulled in)
3. **Tide fetch OOM**: Trigger a StormGlass tide fetch with v1.1.0 properties/strings added — expect -403 response code (will fail on unfixed code)
4. **Sensor reads in surf mode**: Log `SensorHistory.getStressHistory()` calls in surf mode — expect calls even though stress is not displayed (will show unnecessary allocation on unfixed code)

**Expected Counterexamples**:
- Background free memory is ~7,416 bytes (v1.0.2) or ~6,500 bytes (with v1.1.0 additions), insufficient for tide JSON parsing
- Possible causes: DataManager type in background binary, unnecessary field/method inclusion

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL appBuild WHERE isBugCondition(appBuild) DO
  result := compileAndMeasureBackground(appBuild_fixed)
  ASSERT NOT isBugCondition(result)  // No DataManager references in App
  ASSERT result.backgroundFreeMemory > v1.0.2_baseline + 500  // Memory savings
  ASSERT result.tideJsonParse == SUCCESS  // Tide fetch works
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT renderOutput_original(input) = renderOutput_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many combinations of weather/swell/tide data and settings configurations
- It catches edge cases in Storage flag handling (e.g., multiple flags set simultaneously)
- It provides strong guarantees that data flow through Storage produces identical DataManager state

**Test Plan**: Observe behavior on UNFIXED code first for all data flows and settings changes, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Weather data preservation**: For each weather source (Garmin/Open-Meteo/OWM) × mode (shore/surf), verify that DataManager fields after `onBackgroundData` → Storage → View read are identical to direct `onWeatherData()` call
2. **Swell data preservation**: Verify swell fields (height, period, direction, seaSurfaceTemp) and forecast cache arrays are identical after Storage round-trip
3. **Tide data preservation**: Verify tide arrays and computed values (nextTideTime, nextTideType, currentTideHeight) are identical — this already uses Storage, so minimal risk
4. **Settings change preservation**: Verify that weather source change → clear → reload → refresh sequence produces identical DataManager state whether triggered directly or via Storage flag

### Unit Tests

- Test that `SurferWatchFaceApp` has no `dataManager` field or `getDataManager()` method
- Test that `onBackgroundData()` writes correct keys to Storage for each data type
- Test that `onSettingsChanged()` sets `"settingsChanged"` flag and nothing else
- Test that View's `onUpdate()` correctly reads and clears each Storage flag
- Test sensor gating: HR not read in surf mode, stress not read when arc setting doesn't require it
- Test mode-switch nulling: surf fields nulled after `loadShoreCache()`, shore fields nulled after `loadSurfCache()`
- Test that unused font files are not present in the build

### Property-Based Tests

- Generate random weather dictionaries and verify Storage round-trip produces identical DataManager field values
- Generate random swell dictionaries and verify forecast cache arrays match after Storage round-trip
- Generate random settings configurations (mode × weather source × arc setting) and verify the settingsChanged handler produces identical state to direct calls
- Generate random sensor gating scenarios and verify only the correct sensors are read

### Integration Tests

- Full background cycle: trigger temporal event → delegate fetches → `Background.exit()` → `onBackgroundData()` writes Storage → `requestUpdate()` → `onUpdate()` reads flags → DataManager updated → rendering correct
- Settings change cycle: user changes weather source → `onSettingsChanged()` sets flag → `onUpdate()` handles flag → weather cleared, cache reloaded, sunrise/sunset recomputed
- Mode switch cycle: user toggles SurfMode → `onSettingsChanged()` sets flag → `onUpdate()` handles flag → correct cache loaded, inactive fields nulled
- Memory measurement: background free memory after fix > v1.0.2 baseline + 500 bytes
- Multi-flag scenario: weather + swell + tide all arrive in same background event → all three flags set → all three handled in single `onUpdate()`
