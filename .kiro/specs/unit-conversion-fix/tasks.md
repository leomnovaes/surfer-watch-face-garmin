# Implementation Plan

## Overview

Fix unit conversion bugs where the display layer uses `distanceUnits` as a proxy for all unit decisions instead of the correct `temperatureUnits` and `elevationUnits` fields, and where temperature values are shown with imperial suffixes without applying mathematical conversion. Follows TDD approach: create testable UnitConverter module, write tests that demonstrate the bug, then apply fixes across all display sites.

## Tasks

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Unit Conversion Missing/Wrong Field
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope property to concrete failing cases: temperature display with Fahrenheit preference, tide/swell display with feet preference
  - Create `source/UnitConverter.mc` module with pure conversion functions:
    - `celsiusToFahrenheit(c as Float) as Float` → `c * 1.8 + 32`
    - `metersToFeet(m as Float) as Float` → `m * 3.281`
    - `msToKmh(ms as Float) as Float` → `ms * 3.6`
    - `msToMph(ms as Float) as Float` → `ms * 2.237`
    - `msToKnots(ms as Float) as Float` → `ms * 1.944`
    - `isTemperatureImperial() as Boolean` → reads `System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE`
    - `isElevationImperial() as Boolean` → reads `System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE`
  - Create `source/tests/UnitConverterTest.mc` with `:test` annotated tests:
    - Test `celsiusToFahrenheit`: 0→32, 100→212, -40→-40, 22→71.6, -5→23
    - Test `metersToFeet`: 0→0, 1→3.281, 1.5→4.9215, 0.3→0.9843
    - Test `msToKmh`: 0→0, 1→3.6, 10→36
    - Test `msToMph`: 0→0, 1→2.237, 10→22.37
    - Test `msToKnots`: 0→0, 1→1.944, 10→19.44
    - Test edge cases: -40°C = -40°F (crossover), negative temps, zero height, small decimals (0.01m)
    - Test `isTemperatureImperial()` reads `temperatureUnits` (NOT `distanceUnits`)
    - Test `isElevationImperial()` reads `elevationUnits` (NOT `distanceUnits`)
  - Update `monkey.jungle` to add test source path: `base.sourcePath = $(base.sourcePath);source/tests`
  - Run tests on UNFIXED code (View/Delegate still use distanceUnits)
  - **EXPECTED OUTCOME**: UnitConverter module tests PASS (pure functions are correct), but integration with View will FAIL because View still uses `distanceUnits` — confirms the bug exists in the display layer
  - Document: the display code uses `distanceUnits` as proxy for all unit decisions, ignoring `temperatureUnits` and `elevationUnits`
  - _Requirements: 1.1, 1.3, 1.4, 1.5_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Wind Speed Conversion Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe wind speed conversion behavior on UNFIXED code for non-buggy inputs:
    - `msToKmh(10.0)` returns 36.0 (matches original `speedMs * 3.6` for Auto+metric)
    - `msToMph(10.0)` returns 22.37 (matches original `speedMs * 2.237` for Auto+imperial)
    - `msToKnots(10.0)` returns 19.44 (matches original `speedMs * 1.944` for knots setting)
    - `msToKmh(0.0)` returns 0.0, `msToMph(0.0)` returns 0.0, `msToKnots(0.0)` returns 0.0
  - Write property-based tests in `source/tests/UnitConverterTest.mc`:
    - For all wind speed values ≥ 0, `msToKmh` result equals `input * 3.6` (within float tolerance)
    - For all wind speed values ≥ 0, `msToMph` result equals `input * 2.237` (within float tolerance)
    - For all wind speed values ≥ 0, `msToKnots` result equals `input * 1.944` (within float tolerance)
    - All wind conversions are monotonically increasing (higher m/s → higher output)
    - Temperature conversion preserves ordering: if a > b then celsiusToFahrenheit(a) > celsiusToFahrenheit(b)
    - Meters-to-feet preserves ordering: if a > b then metersToFeet(a) > metersToFeet(b)
  - Verify tests PASS on UNFIXED code (pure math functions are correct regardless of display bug)
  - **EXPECTED OUTCOME**: Tests PASS (confirms baseline wind conversion behavior to preserve)
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix unit conversion bug across all display sites

  - [x] 3.1 Fix OWM delegate — always pass `units=metric`
    - In `SurferWatchFaceDelegate.mc`, function `startWindFetch()`
    - Remove: `if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) { units = "imperial"; }`
    - Hardcode: `var units = "metric";`
    - In `startShoreWeatherFetch()`, same change for OWM branch
    - OWM will now always return temperature in °C and wind in m/s
    - _Bug_Condition: isBugCondition where weatherSource=2 AND distanceUnits=UNIT_STATUTE causes imperial fetch_
    - _Expected_Behavior: OWM always returns metric (°C, m/s) regardless of device settings_
    - _Preservation: Open-Meteo and Garmin fetch layers unchanged (already metric)_
    - _Requirements: 2.5, 2.7, 3.4, 3.5_

  - [x] 3.2 Fix shore temperature display
    - In `SurferWatchFaceView.mc`, function `drawWeatherWidget()`
    - Replace `distanceUnits` check with `UnitConverter.isTemperatureImperial()`
    - Apply `UnitConverter.celsiusToFahrenheit()` when imperial (currently only suffix changes)
    - _Bug_Condition: distanceUnits used instead of temperatureUnits, no conversion math applied_
    - _Expected_Behavior: celsiusToFahrenheit applied when temperatureUnits=UNIT_STATUTE_
    - _Requirements: 2.1, 2.2_

  - [x] 3.3 Fix surf water temperature display
    - In `SurferWatchFaceView.mc`, function `drawTopSection_Surf()`
    - Replace `distanceUnits` check with `UnitConverter.isTemperatureImperial()`
    - Conversion logic already exists (`* 1.8 + 32`) — just needs the correct settings field
    - _Bug_Condition: distanceUnits used instead of temperatureUnits_
    - _Expected_Behavior: uses temperatureUnits to decide C/F conversion_
    - _Requirements: 2.1, 3.6_

  - [x] 3.4 Fix tide height display (all locations: shore, surf, subscreen)
    - In `SurferWatchFaceView.mc`: `drawTopSection()`, `drawTopSection_Surf()`, `drawTideCurve()`
    - In `DataManager.mc`: `updateSubscreenAndArc()` (interpTideHeight display)
    - Replace all `distanceUnits` checks for tide height with `UnitConverter.isElevationImperial()`
    - Apply `UnitConverter.metersToFeet()` when imperial
    - _Bug_Condition: distanceUnits used instead of elevationUnits_
    - _Expected_Behavior: metersToFeet applied when elevationUnits=UNIT_STATUTE_
    - _Requirements: 2.3, 2.4_

  - [x] 3.5 Fix swell height display
    - In `SurferWatchFaceView.mc`, function `drawSwellSection()`
    - Replace `distanceUnits` check with `UnitConverter.isElevationImperial()`
    - Apply `UnitConverter.metersToFeet()` when imperial
    - _Bug_Condition: distanceUnits used instead of elevationUnits_
    - _Expected_Behavior: metersToFeet applied when elevationUnits=UNIT_STATUTE_
    - _Requirements: 2.3, 2.4_

  - [x] 3.6 Remove OWM wind back-conversion
    - In `SurferWatchFaceView.mc`, wind display code
    - Delete the `/ 2.237` special case for OWM weather source (no longer needed since OWM returns m/s)
    - All weather sources now consistently store wind in m/s
    - _Bug_Condition: back-conversion from imperial introduces precision loss_
    - _Expected_Behavior: no back-conversion needed, stored value is already m/s_
    - _Preservation: forward conversion (m/s → display unit) via WindSpeedUnit unchanged_
    - _Requirements: 2.6, 2.7, 3.1, 3.2, 3.3_

  - [x] 3.7 Bump Storage version
    - In `SurferWatchFaceView.mc`, `onUpdate()` lazy init block
    - Change `storedVer != 4` to `storedVer != 5`
    - Change `Application.Storage.setValue("av", 4)` to `Application.Storage.setValue("av", 5)`
    - This invalidates cached imperial OWM data from before the fix
    - _Bug_Condition: stale imperial data in Storage from pre-fix OWM fetches_
    - _Expected_Behavior: Storage cleared on version mismatch, fresh metric data fetched_
    - _Requirements: 3.7_

  - [x] 3.8 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Unit Conversion Correct
    - **IMPORTANT**: Re-run the SAME tests from task 1 - do NOT write new tests
    - The UnitConverter module tests should still pass (pure functions unchanged)
    - The display layer now uses `isTemperatureImperial()` and `isElevationImperial()` correctly
    - Run bug condition exploration tests from step 1
    - **EXPECTED OUTCOME**: All tests PASS (confirms bug is fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 3.9 Verify preservation tests still pass
    - **Property 2: Preservation** - Wind Speed Conversion Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions in wind speed conversions)
    - Confirm all wind conversion functions produce identical results after fix

- [x] 4. Checkpoint - Ensure all tests pass
  - Run full test suite: all UnitConverter tests pass
  - Verify no compile errors across all source files
  - Verify `monkey.jungle` source path includes tests directory
  - Ask the user if questions arise

## Task Dependency Graph

```json
{
  "waves": [
    { "tasks": ["1"] },
    { "tasks": ["2"] },
    { "tasks": ["3.1"] },
    { "tasks": ["3.2", "3.3", "3.4", "3.5", "3.6", "3.7"] },
    { "tasks": ["3.8"] },
    { "tasks": ["3.9"] },
    { "tasks": ["4"] }
  ]
}
```

## Notes

- The `monkey.jungle` file currently only has `project.manifest = manifest.xml`. A `base.sourcePath` line must be added for the test runner to discover `source/tests/`.
- Monkey C `:test` annotated functions run via the Connect IQ SDK test runner (`monkeyc --test` or via VS Code test command).
- The UnitConverter module uses `module` (not `class`) so functions are called as `UnitConverter.celsiusToFahrenheit()` without instantiation — saves heap allocation.
- Float tolerance in tests: use `Math.abs(expected - actual) < 0.01` for conversion comparisons due to floating-point precision.
- The `isTemperatureImperial()` and `isElevationImperial()` functions cannot be unit-tested in isolation without mocking `System.getDeviceSettings()` — they are validated via simulator integration testing.
