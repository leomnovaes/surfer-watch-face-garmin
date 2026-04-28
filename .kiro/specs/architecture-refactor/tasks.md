# Implementation Plan

- [ ] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - App References DataManager in Background
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior — it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate DataManager is pulled into the background binary
  - **Scoped PBT Approach**: The bug is deterministic — scope the property to the concrete failing case: `SurferWatchFaceApp` has `var dataManager as DataManager or Null` field and calls DataManager methods from `onBackgroundData()`, `onSettingsChanged()`, and `getInitialView()`
  - Test that `SurferWatchFaceApp.mc` source contains NO field declarations of type `DataManager`, NO method calls to `dataManager.*`, and NO `new DataManager()` constructor calls (from Bug Condition in design: `isBugCondition(appClass)` returns true when App has DataManager field or method calls)
  - The test assertions should match the Expected Behavior Properties from design: App class contains zero references to DataManager
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct — it proves the bug exists: App references DataManager 11+ times)
  - Document counterexamples found: `var dataManager as DataManager or Null` field, `dataManager.onWeatherData()`, `dataManager.onSurfWindData()`, `dataManager.onTideData()`, `dataManager.onSwellData()`, `dataManager.refreshWeatherOnBackgroundEvent()`, `dataManager.clearWeatherData()`, `dataManager.clearPersistedWeatherData()`, `dataManager.loadSurfCache()`, `dataManager.loadShoreCache()`, `dataManager.checkCopyGPS()`, `new DataManager()`
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.2, 1.3, 1.4, 2.1, 2.2_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Data Flow and Settings Behavior Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe on UNFIXED code: `onBackgroundData()` with weather dict → `dataManager.onWeatherData()` sets temperature, weatherConditionId, windSpeed, windDeg, sunrise, sunset, precipProbability, isDay, owmFetchedAt and calls `persistWeatherData()`
  - Observe on UNFIXED code: `onBackgroundData()` with swell dict → `dataManager.onSwellData()` sets swellHeight, swellPeriod, swellDirection, seaSurfaceTemp and reloads forecast caches from Storage
  - Observe on UNFIXED code: `onBackgroundData()` with tideUpdated flag → `dataManager.onTideData()` reloads tide arrays from Storage and calls `extractTideCurveData()`
  - Observe on UNFIXED code: `onSettingsChanged()` with weather source change → calls `clearWeatherData()`, `clearPersistedWeatherData()`, loads mode cache, calls `refreshWeatherOnBackgroundEvent()`, `checkCopyGPS()`
  - Observe on UNFIXED code: `onBackgroundData()` always calls `refreshWeatherOnBackgroundEvent()` and re-registers background event in 5 minutes
  - Write property-based test: for all valid background data payloads (weather dict, swell dict, tide flag, combinations), the DataManager field values after the Storage-flag-based flow (new code) match the values after the direct-call flow (old code)
  - Write property-based test: for all valid settings configurations (mode × weather source), the DataManager state after the settingsChanged flag handler matches the state after direct `onSettingsChanged()` calls
  - Verify tests pass on UNFIXED code
  - _Requirements: 3.1, 3.2, 3.3, 3.5, 3.6, 3.7, 3.8_

- [ ] 3. Baseline measurement (USER captures current numbers)
  - USER: Build the project for Instinct 2X (`instinct2x`)
  - USER: Launch simulator, open the watch face
  - USER: Foreground memory — open View > Memory in simulator, record peak and current usage
  - USER: Background memory — trigger a background event, read `System.getSystemStats()` debug prints in the delegate's `onTemporalEvent()`, record free memory before tide fetch
  - USER: Verify tide fetch succeeds (response code 200, not -403)
  - USER: Record baseline numbers in a comment or note for comparison after each step
  - These numbers are the "before" reference for every subsequent task
  - _Requirements: 1.1, 1.2_

- [ ] 4. Remove unused font files (zero risk, confirmed savings)
  - Delete 29 font files in `resources/fonts/` that are NOT referenced by `fonts.xml`
  - Referenced fonts (keep): `crystal-icons.fnt`, `crystal-icons.png`, `weather-icons.fnt`, `weather-icons_0.png`, `moon.fnt`, `moon.png`, `seg34-icons.fnt`, `seg34-icons.png`, `surfer-icons.fnt`, `surfer-icons.png`, `heart-icon.fnt`, `heart-icon.png`, `clock-SairaCondensed-Bold-40.fnt`, `clock-SairaCondensed-Bold-40.png`, `clock-Rajdhani-Bold-40.fnt`, `clock-Rajdhani-Bold-40.png`, `fonts.xml`
  - Delete all other `.fnt` and `.png` files in `resources/fonts/` (garmin-icons-*, weather-icons-12/15/16/18/20/22/24*, fa-brands-16*, crystal-icons-small.png)
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory (View > Memory)
  - USER: Measure background memory (System.getSystemStats prints)
  - _Requirements: 1.7, 2.7_

- [ ] 5. Remove dead code `drawIconHeart` (zero risk)
  - Delete the `drawIconHeart()` function from `source/SurferWatchFaceView.mc` (line ~486, uses seg34IconsFont glyph "h", never called)
  - Do NOT remove `seg34IconsFont` — it is still used by `drawIconBluetooth()` for glyph "L"
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory
  - USER: Measure background memory
  - _Requirements: 1.8, 2.8, 3.9_

- [ ] 6. Gate sensors by mode in `updateSensorData()` (low risk)
  - In `DataManager.updateSensorData()`, gate HR read: only read `Activity.getActivityInfo().currentHeartRate` when NOT in surf mode (shore mode only, when ShoreSubscreen setting needs it)
  - Gate stress read: only call `SensorHistory.getStressHistory()` when the active arc setting requires it (ShoreArc=0 in shore mode, or SurfArc=1 in surf mode) — skip entirely otherwise and set `stress = null`
  - Read `SurfMode`, `ShoreArc`, `SurfArc` from `Application.Properties.getValue()` at the top of the function
  - Battery, GPS, notifications, BT remain unconditionally read (always needed)
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory
  - USER: Measure background memory
  - USER: Verify all data displays correctly in both shore and surf mode
  - USER: Verify stress arc still works when ShoreArc=0 or SurfArc=1
  - _Requirements: 1.5, 2.5_

- [ ] 7. Null inactive mode fields on mode switch (low risk)
  - In `DataManager.loadSurfCache()`, after loading surf data, null out shore-only fields: `temperature`, `weatherConditionId`, `windSpeed`, `windDeg`, `sunrise`, `sunset`, `owmFetchedAt`, `precipProbability`, `isDay`, `heartRate`, `stress`
  - In `DataManager.loadShoreCache()`, after loading shore data, null out surf-only fields: `swellHeight`, `swellPeriod`, `swellDirection`, `surfWindSpeed`, `surfWindDeg`, `surfSunrise`, `surfSunset`, `waterTemp`, `seaSurfaceTemp`, `solarIntensity`, `interpTideHeight`, `_swellHeightsCache`, `_swellPeriodsCache`, `_swellDirectionsCache`, `_seaSurfaceTempsCache`, `_windSpeedsCache`, `_windDirectionsCache`
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory in shore mode
  - USER: Measure foreground memory in surf mode
  - USER: Switch modes back and forth, verify data reloads correctly each time
  - _Requirements: 1.6, 2.6_

- [ ] 8. Refactor `onBackgroundData` to write Storage only (medium risk — critical step)

  - [ ] 8.1 Refactor `onBackgroundData()` in `SurferWatchFaceApp.mc`
    - Remove all `dataManager.*` calls from `onBackgroundData()`
    - Weather data: `Application.Storage.setValue("bgWeatherData", weatherData)` + `Application.Storage.setValue("weatherUpdated", true)`
    - Swell data: `Application.Storage.setValue("bgSwellData", swellData)` + `Application.Storage.setValue("swellUpdated", true)`
    - Tide data: keep `Application.Storage.setValue("tideUpdated", true)` (already flag-based), remove `dataManager.onTideData()` call
    - Remove `dataManager.refreshWeatherOnBackgroundEvent()` call — View will handle this
    - Keep `WatchUi.requestUpdate()` and `Background.registerForTemporalEvent(new Time.Duration(5 * 60))` re-registration
    - _Bug_Condition: isBugCondition(appClass) — removing onBackgroundData DataManager calls_
    - _Expected_Behavior: App writes to Storage only, no foreground class references_
    - _Preservation: All data still flows to DataManager via View on next onUpdate()_
    - _Requirements: 1.3, 2.1, 2.3, 3.1, 3.2, 3.8_

  - [ ] 8.2 Add Storage flag handling in `SurferWatchFaceView.mc` `onUpdate()`
    - At the top of `onUpdate()`, before rendering, check Storage flags:
    - `"weatherUpdated"` → read `Application.Storage.getValue("bgWeatherData")`, call `dataManager.onWeatherData()` or `dataManager.onSurfWindData()` based on SurfMode, clear flag
    - `"swellUpdated"` → read `Application.Storage.getValue("bgSwellData")`, call `dataManager.onSwellData()`, clear flag
    - `"tideUpdated"` → call `dataManager.onTideData()`, clear flag (same as current pattern)
    - After any flag handled, call `dataManager.refreshWeatherOnBackgroundEvent()` (computes sunrise/sunset + Garmin weather)
    - _Requirements: 2.3, 3.1, 3.2_

  - [ ] 8.3 Build and full verification
    - Build for Instinct 2X — must succeed
    - USER: Measure foreground memory (View > Memory)
    - USER: Measure background memory (System.getSystemStats prints)
    - USER: Verify tide fetch succeeds (response code 200, not -403)
    - USER: Verify weather data displays correctly (temperature, condition icon, wind)
    - USER: Verify swell data displays correctly in surf mode (height, period, direction)
    - USER: Verify tide data displays correctly (next tide time/type, tide curve in surf mode)
    - USER: Verify settings changes still work (weather source, surf mode, clock font)
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 3.5, 3.6_

- [ ] 9. Move `onSettingsChanged` logic to View (medium risk)

  - [ ] 9.1 Refactor `onSettingsChanged()` in `SurferWatchFaceApp.mc`
    - Remove all `dataManager.*` calls from `onSettingsChanged()`
    - Replace with: `Application.Storage.setValue("settingsChanged", true)` + store current weather source for change detection: `Application.Storage.setValue("lastWeatherSource", currentSource)`
    - Keep `WatchUi.requestUpdate()` and background re-registration attempt
    - Remove `_lastWeatherSource` field from App class
    - _Bug_Condition: isBugCondition(appClass) — removing onSettingsChanged DataManager calls_
    - _Expected_Behavior: App sets Storage flag only, View handles all DataManager interactions_
    - _Preservation: Settings changes apply within one onUpdate() cycle_
    - _Requirements: 1.4, 2.4, 3.3_

  - [ ] 9.2 Add `settingsChanged` flag handling in View's `onUpdate()`
    - Check `"settingsChanged"` flag in Storage
    - Read `"lastWeatherSource"` — compare with previous source to detect weather source change
    - If source changed: call `dataManager.clearWeatherData()`, `dataManager.clearPersistedWeatherData()`
    - Load correct mode cache: `dataManager.loadSurfCache()` or `dataManager.loadShoreCache()` based on SurfMode
    - Call `dataManager.refreshWeatherOnBackgroundEvent()` (computes sunrise/sunset + Garmin weather)
    - Call `dataManager.checkCopyGPS()`
    - Clear `"settingsChanged"` flag
    - Track `_lastWeatherSource` in View instead of App
    - _Requirements: 2.4, 3.3_

  - [ ] 9.3 Build and full verification
    - Build for Instinct 2X — must succeed
    - USER: Measure foreground memory
    - USER: Measure background memory
    - USER: Verify tide fetch succeeds (response code 200, not -403)
    - USER: Change weather source (Garmin → Open-Meteo → OWM) — verify stale data clears and new data loads
    - USER: Toggle surf mode on/off — verify correct cache loads
    - USER: Change clock font — verify font switches correctly
    - USER: Verify all data displays correctly in both modes
    - _Requirements: 2.4, 3.3, 3.5, 3.6_

- [ ] 10. Remove DataManager from App, move to View (medium risk — the payoff)

  - [ ] 10.1 Remove DataManager field and methods from `SurferWatchFaceApp.mc`
    - Delete `var dataManager as DataManager or Null` field
    - Delete `getDataManager()` method
    - Simplify `getInitialView()`: remove `dataManager = new DataManager()` and all `dataManager.*` calls, just return `[new SurferWatchFaceView()]`
    - At this point, App should have ZERO references to DataManager
    - _Bug_Condition: isBugCondition(appClass) — removing the field and constructor that pull DataManager type into background_
    - _Expected_Behavior: App class contains zero DataManager references_
    - _Requirements: 2.1, 2.2_

  - [ ] 10.2 Add DataManager ownership to `SurferWatchFaceView.mc`
    - Add `private var dataManager as DataManager or Null` field to View
    - In `onLayout()` (after font loading): create DataManager, load mode-specific cache, run initial sensor read, call `refreshWeatherOnBackgroundEvent()` — same init sequence as current `getInitialView()`
    - Replace all `(Application.getApp() as SurferWatchFaceApp).getDataManager()` calls with the local `dataManager` field
    - _Requirements: 2.2, 2.3, 2.4_

  - [ ] 10.3 Build and full verification
    - Build for Instinct 2X — must succeed
    - USER: Measure foreground memory (View > Memory) — expect similar to before
    - USER: Measure background memory (System.getSystemStats prints) — expect 500+ bytes improvement over baseline
    - USER: Verify tide fetch succeeds (response code 200, not -403) — this is the critical validation
    - USER: Verify all weather data displays correctly
    - USER: Verify all swell data displays correctly in surf mode
    - USER: Verify all tide data displays correctly
    - USER: Verify settings changes work (weather source, surf mode, clock font)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [ ] 10.4 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - App Has No DataManager Reference
    - **IMPORTANT**: Re-run the SAME test from task 1 — do NOT write a new test
    - The test from task 1 encodes the expected behavior: App contains zero DataManager references
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed — DataManager is no longer in background binary)
    - _Requirements: 2.1, 2.2_

  - [ ] 10.5 Verify preservation tests still pass
    - **Property 2: Preservation** - Data Flow and Settings Behavior Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions — all data flows identically through Storage)
    - Confirm all tests still pass after fix (no regressions)

- [ ] 11. Single clock font loading (low risk, confirmed savings)
  - In `SurferWatchFaceView.onLayout()`, read `Application.Properties.getValue("ClockFont")` and load only the active font
  - If `ClockFont == 1`: load only `clockRajdhani40`, set `clockSaira40 = null`
  - Else (default): load only `clockSaira40`, set `clockRajdhani40 = null`
  - In the clock drawing code (both shore and surf `drawTime` sections), the existing `clockFont` selection logic already handles null — just ensure it falls back gracefully
  - Note: font change requires app restart (settings sync restarts the watch face), so loading once in `onLayout()` is correct
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory — expect ~4KB savings from loading one font instead of two
  - USER: Verify clock displays correctly with both Saira (default) and Rajdhani (setting=1)
  - _Requirements: 1.7, 2.7_

- [ ] 12. Final verification — all measurements, full functional test
  - USER: Build for Instinct 2X — must succeed
  - USER: Foreground memory (View > Memory) — record final number, compare to baseline from task 3
  - USER: Background memory (System.getSystemStats prints) — record final number, expect 500+ bytes more free than baseline
  - USER: Trigger tide fetch — must succeed with response code 200 (not -403)
  - USER: Shore mode — verify: time, date, battery, HR, stress arc, weather icon + temp, wind, tide, sunrise/sunset, moon, notifications, BT
  - USER: Surf mode — verify: time, swell height/period/direction, tide curve, interpolated tide height, water temp, solar arc, surf wind, surf sunrise/sunset, moon
  - USER: Settings — change weather source (Garmin → Open-Meteo → OWM), verify data clears and reloads
  - USER: Settings — toggle surf mode on/off, verify correct data loads
  - USER: Settings — change clock font, verify font switches
  - USER: Double wrist gesture in surf mode — verify bottom section toggles between swell and tide curve
  - USER: Verify background re-registers for next event in 5 minutes
  - Ensure all tests pass, ask the user if questions arise
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9_
