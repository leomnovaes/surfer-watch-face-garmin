# Implementation Plan

- [x] 1. Write bug condition exploration test
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

- [x] 2. Write preservation property tests (BEFORE implementing fix)
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

- [x] 3. Baseline measurement (USER captures current numbers)
  - USER: Build the project for Instinct 2X (`instinct2x`)
  - USER: Launch simulator, open the watch face
  - USER: Foreground memory — open View > Memory in simulator, record peak and current usage
  - USER: Background memory — trigger a background event, read `System.getSystemStats()` debug prints in the delegate's `onTemporalEvent()`, record free memory before tide fetch
  - USER: Verify tide fetch succeeds (response code 200, not -403)
  - USER: Record baseline numbers in a comment or note for comparison after each step
  - These numbers are the "before" reference for every subsequent task
  - _Requirements: 1.1, 1.2_

- [x] 4. Remove unused font files (zero risk, confirmed savings)
  - Delete 29 font files in `resources/fonts/` that are NOT referenced by `fonts.xml`
  - Referenced fonts (keep): `crystal-icons.fnt`, `crystal-icons.png`, `weather-icons.fnt`, `weather-icons_0.png`, `moon.fnt`, `moon.png`, `seg34-icons.fnt`, `seg34-icons.png`, `surfer-icons.fnt`, `surfer-icons.png`, `heart-icon.fnt`, `heart-icon.png`, `clock-SairaCondensed-Bold-40.fnt`, `clock-SairaCondensed-Bold-40.png`, `clock-Rajdhani-Bold-40.fnt`, `clock-Rajdhani-Bold-40.png`, `fonts.xml`
  - Delete all other `.fnt` and `.png` files in `resources/fonts/` (garmin-icons-*, weather-icons-12/15/16/18/20/22/24*, fa-brands-16*, crystal-icons-small.png)
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory (View > Memory)
  - USER: Measure background memory (System.getSystemStats prints)
  - _Requirements: 1.7, 2.7_

- [x] 5. Remove dead code `drawIconHeart` (zero risk)
  - Delete the `drawIconHeart()` function from `source/SurferWatchFaceView.mc` (line ~486, uses seg34IconsFont glyph "h", never called)
  - Do NOT remove `seg34IconsFont` — it is still used by `drawIconBluetooth()` for glyph "L"
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory
  - USER: Measure background memory
  - _Requirements: 1.8, 2.8, 3.9_

- [x] 6. Gate sensors by mode in `updateSensorData()` (low risk)
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

- [x] 7. Null inactive mode fields on mode switch (low risk)
  - In `DataManager.loadSurfCache()`, after loading surf data, null out shore-only fields: `temperature`, `weatherConditionId`, `windSpeed`, `windDeg`, `sunrise`, `sunset`, `owmFetchedAt`, `precipProbability`, `isDay`, `heartRate`, `stress`
  - In `DataManager.loadShoreCache()`, after loading shore data, null out surf-only fields: `swellHeight`, `swellPeriod`, `swellDirection`, `surfWindSpeed`, `surfWindDeg`, `surfSunrise`, `surfSunset`, `waterTemp`, `seaSurfaceTemp`, `solarIntensity`, `interpTideHeight`, `_swellHeightsCache`, `_swellPeriodsCache`, `_swellDirectionsCache`, `_seaSurfaceTempsCache`, `_windSpeedsCache`, `_windDirectionsCache`
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory in shore mode
  - USER: Measure foreground memory in surf mode
  - USER: Switch modes back and forth, verify data reloads correctly each time
  - _Requirements: 1.6, 2.6_

- [x] 8. Refactor `onBackgroundData` to write Storage only (medium risk — critical step)

  - [x] 8.1 Refactor `onBackgroundData()` in `SurferWatchFaceApp.mc`
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

  - [x] 8.2 Add Storage flag handling in `DataManager.checkBackgroundFlags()`
    - Check Storage flags set by `onBackgroundData()`:
    - `"weatherUpdated"` → read `Application.Storage.getValue("bgWeatherData")`, call `onWeatherData()` or `onSurfWindData()` based on SurfMode, clear flag
    - `"swellUpdated"` → read `Application.Storage.getValue("bgSwellData")`, call `onSwellData()`, clear flag
    - `"tideUpdated"` → call `onTideData()`, clear flag
    - After any flag handled, call `refreshWeatherOnBackgroundEvent()` (computes sunrise/sunset + Garmin weather)
    - _Requirements: 2.3, 3.1, 3.2_

  - [x] 8.3 Build and full verification
    - Build for Instinct 2X — must succeed
    - USER: Measure foreground memory (View > Memory)
    - USER: Measure background memory (System.getSystemStats prints)
    - USER: Verify tide fetch succeeds (response code 200, not -403)
    - USER: Verify weather data displays correctly (temperature, condition icon, wind)
    - USER: Verify swell data displays correctly in surf mode (height, period, direction)
    - USER: Verify tide data displays correctly (next tide time/type, tide curve in surf mode)
    - USER: Verify settings changes still work (weather source, surf mode, clock font)
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 3.5, 3.6_

- [x] 9. Refactor `onSettingsChanged` to Storage flag + move DataManager to View (medium risk — the payoff)
  - This task combines the settings refactor and DataManager move because they are tightly coupled: we can't remove DataManager from App until `onSettingsChanged()` stops calling it, and moving DataManager to View is the whole point. Doing them together avoids an intermediate broken state.
  - **Current state**: `onSettingsChanged()` in App still calls DataManager directly (clearWeatherData, clearPersistedWeatherData, loadSurfCache/loadShoreCache, refreshWeatherOnBackgroundEvent, checkCopyGPS). `getInitialView()` creates DataManager and runs init sequence. View accesses DataManager via `getApp().getDataManager()`.

  - [x] 9.1 Refactor `onSettingsChanged()` in `SurferWatchFaceApp.mc`
    - Replace all `dataManager.*` calls with a Storage flag:
    - `Application.Storage.setValue("settingsChanged", true)`
    - `Application.Storage.setValue("newWeatherSource", currentWeatherSourceValue)` (so View can detect source changes)
    - Keep `WatchUi.requestUpdate()` and background re-registration attempt
    - Remove `_lastWeatherSource` field from App class
    - _Requirements: 1.4, 2.4, 3.3_

  - [x] 9.2 Simplify `getInitialView()` in `SurferWatchFaceApp.mc`
    - Remove `dataManager = new DataManager()` and all `dataManager.*` calls
    - Just return `[new SurferWatchFaceView()]`
    - _Requirements: 2.1, 2.2_

  - [x] 9.3 Remove DataManager field and getter from `SurferWatchFaceApp.mc`
    - Delete `var dataManager as DataManager or Null` field
    - Delete `getDataManager()` method
    - Delete `_lastWeatherSource` field
    - At this point, App should have ZERO references to DataManager
    - _Requirements: 2.1, 2.2_

  - [x] 9.4 Add DataManager ownership to `SurferWatchFaceView.mc`
    - Add `private var dataManager as DataManager or Null` field to View
    - In `onLayout()` (after font loading): create DataManager, load mode-specific cache, run initial sensor read, call `refreshWeatherOnBackgroundEvent()` — same init sequence as current `getInitialView()`
    - Add `_lastWeatherSource` field to View (initialized from Properties in `onLayout()`)
    - _Requirements: 2.2, 2.3, 2.4_

  - [x] 9.5 Add `settingsChanged` flag handling in View's `onUpdate()`
    - At the top of `onUpdate()`, after getting `dm`, check `"settingsChanged"` flag in Storage
    - Read `"newWeatherSource"` — compare with `_lastWeatherSource` to detect weather source change
    - If source changed: call `dm.clearWeatherData()`, `dm.clearPersistedWeatherData()`, update `_lastWeatherSource`
    - Load correct mode cache: `dm.loadSurfCache()` or `dm.loadShoreCache()` based on SurfMode
    - Call `dm.refreshWeatherOnBackgroundEvent()` (computes sunrise/sunset + Garmin weather)
    - Call `dm.checkCopyGPS()`
    - Clear `"settingsChanged"` and `"newWeatherSource"` flags
    - _Requirements: 2.4, 3.3_

  - [x] 9.6 Update View's `onUpdate()` and `onExitSleep()` DataManager access
    - Replace `var dm = (Application.getApp() as SurferWatchFaceApp).getDataManager()` with the local `dataManager` field (2 call sites: `onUpdate()` line 134, `onExitSleep()` line 1196)
    - _Requirements: 2.2_

  - [x] 9.7 Build and full verification
    - Build for Instinct 2X — must succeed
    - USER: Measure foreground memory (View > Memory) — expect similar to before
    - USER: Measure background memory (System.getSystemStats prints) — expect 500+ bytes improvement over baseline
    - USER: Verify tide fetch succeeds (response code 200, not -403) — this is the critical validation
    - USER: Verify all weather data displays correctly
    - USER: Verify all swell data displays correctly in surf mode
    - USER: Verify all tide data displays correctly
    - USER: Change weather source (Garmin → Open-Meteo → OWM) — verify stale data clears and new data loads
    - USER: Toggle surf mode on/off — verify correct cache loads
    - USER: Change clock font — verify font switches correctly
    - USER: Double wrist gesture in surf mode — verify bottom section toggles
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 9.8 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - App Has No DataManager Reference
    - Re-run the SAME test from task 1 — do NOT write a new test
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed — DataManager is no longer in background binary)
    - _Requirements: 2.1, 2.2_

  - [x] 9.9 Verify preservation tests still pass
    - **Property 2: Preservation** - Data Flow and Settings Behavior Unchanged
    - Re-run the SAME tests from task 2 — do NOT write new tests
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)


- [x] 10. Split `refreshWeatherOnBackgroundEvent()` into focused methods (low risk — code clarity + enables future optimization)
  - Currently `refreshWeatherOnBackgroundEvent()` does three things: (1) compute sunrise/sunset for the current mode, (2) read Garmin built-in weather when WeatherSource=0, (3) flow Garmin weather through `onWeatherData()`. It's called from `checkBackgroundFlags()`, `onUpdate()` via settings handler, and startup — but not all callers need all three behaviors.
  - This task splits it so each caller invokes only what it needs, reducing unnecessary work per tick and making the code easier to reason about.

  - [x] 10.1 Extract `computeSunriseSunsetForMode()` from `refreshWeatherOnBackgroundEvent()`
    - New method in DataManager: reads SurfMode, calls `computeSurfSunriseSunset()` or `computeSunriseSunset()` accordingly
    - This is the "always needed on background event or GPS change" part
    - _Requirements: 3.1, 3.5, 3.6_

  - [x] 10.2 Extract Garmin weather read into `readGarminWeatherFull()`
    - New method in DataManager: the "build weather dict from Weather.getCurrentConditions + computed sunrise/sunset, flow through onWeatherData()" logic
    - Only called when WeatherSource=0 AND shore mode — not needed for API weather sources or surf mode
    - _Requirements: 3.1, 3.5_

  - [x] 10.3 Update callers to use the new focused methods
    - `checkBackgroundFlags()`: call `computeSunriseSunsetForMode()` + `readGarminWeatherFull()` (replaces `refreshWeatherOnBackgroundEvent()`)
    - Settings changed handler in View: call `computeSunriseSunsetForMode()` + `readGarminWeatherFull()` (replaces `refreshWeatherOnBackgroundEvent()`)
    - Startup in `onLayout()`: call `computeSunriseSunsetForMode()` + `readGarminWeatherFull()` (replaces `refreshWeatherOnBackgroundEvent()`)
    - Remove `refreshWeatherOnBackgroundEvent()` once all callers are updated
    - _Requirements: 3.1, 3.5, 3.6_

  - [x] 10.4 Build and verify
    - Build for Instinct 2X — must succeed
    - USER: Verify weather displays correctly for all three sources (Garmin, Open-Meteo, OWM)
    - USER: Verify sunrise/sunset displays correctly in both shore and surf mode
    - USER: Verify settings changes still work
    - _Requirements: 3.1, 3.3, 3.5, 3.6_

- [ ] 11. Move per-tick computations to event-driven (low risk — reduces unnecessary work each second)
  - Currently `computeMoonPhase()` runs every `onUpdate()` tick (once per second) but the moon phase only changes daily. `checkCopyGPS()` runs every tick in surf mode but only matters on settings change.

  - [x] 11.1 Move `computeMoonPhase()` to event-driven
    - Call `computeMoonPhase()` in `checkBackgroundFlags()` (runs on background events, ~every 5 min) and in the settings-changed handler — NOT per tick in `onUpdate()`
    - Remove the `dm.computeMoonPhase()` calls from both shore and surf branches of `onUpdate()`
    - Also call it once during startup (in `onLayout()` init sequence)
    - Moon phase value persists in DataManager field between ticks — no visual change
    - _Requirements: 3.5, 3.6_

  - [x] 11.2 Move `checkCopyGPS()` to settings-changed handler only
    - Remove `dm.checkCopyGPS()` from the surf mode branch of `onUpdate()`
    - It's already called in the settings-changed handler (task 9.5) — that's the only time it matters (user toggles CopyGPSToSurfSpot in Garmin Connect app, which triggers `onSettingsChanged`)
    - _Requirements: 3.3_

  - [x] 11.3 Build and verify
    - Build for Instinct 2X — must succeed
    - USER: Verify moon phase icon displays correctly in both modes
    - USER: Verify CopyGPSToSurfSpot still works when toggled in settings
    - USER: Measure foreground memory — may see slight improvement from less per-tick work
    - _Requirements: 3.5, 3.6_

- [x] 12. Single clock font loading (low risk, confirmed savings)
  - In `SurferWatchFaceView.onLayout()`, read `Application.Properties.getValue("ClockFont")` and load only the active font
  - If `ClockFont == 1`: load only `clockRajdhani40`, set `clockSaira40 = null`
  - Else (default): load only `clockSaira40`, set `clockRajdhani40 = null`
  - In the clock drawing code (both shore and surf `drawTime` sections), the existing `clockFont` selection logic already handles null — just ensure it falls back gracefully
  - Note: font change requires app restart (settings sync restarts the watch face), so loading once in `onLayout()` is correct
  - Build for Instinct 2X — must succeed
  - USER: Measure foreground memory — expect ~4KB savings from loading one font instead of two
  - USER: Verify clock displays correctly with both Saira (default) and Rajdhani (setting=1)
  - _Requirements: 1.7, 2.7_

- [x] 13. Final verification — all measurements, full functional test
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
