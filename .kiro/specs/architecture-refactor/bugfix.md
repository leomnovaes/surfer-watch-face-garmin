# Bugfix Requirements Document

## Introduction

The watch face crashes with -403 (NETWORK_RESPONSE_OUT_OF_MEMORY) when parsing StormGlass tide JSON responses in the background process on Instinct 2/2X devices. The v1.0.2 background process uses 21,056 of 28,488 bytes at start, leaving only 3,424 bytes free before tide fetch — barely enough for the ~3.5KB needed for JSON parsing. Adding any v1.1.0 code (new properties, strings, settings) increases compiled app size, reducing background free memory to 2,936 bytes, which triggers the -403 OOM on tide fetch. This completely blocks all v1.1.0 feature development.

Five root causes contribute to the memory pressure:

1. **App class pulls DataManager into background** — The `:background`-annotated `SurferWatchFaceApp` has `var dataManager as DataManager` and calls 11 DataManager methods. This pulls DataManager's entire type (41 public + 10 private fields, all methods) into the 28KB background process, consuming ~500+ bytes.
2. **Unnecessary sensor reads in surf mode** — `updateSensorData()` unconditionally reads HR and stress (SensorHistory iterator) every tick, even in surf mode where neither is displayed. The SensorHistory iterator allocates heap memory.
3. **Mode-specific data held in memory for inactive mode** — DataManager has 22 surf-only fields (including 6 forecast cache arrays with 24 elements each) that stay allocated during shore mode, and 12 shore-only fields during surf mode.
4. **Unused font files included in build** — 29 font files not referenced by fonts.xml are included, consuming ~0.6KB.
5. **Dead code** — `drawIconHeart()` is never called (drawHrHeart uses heartIconFont instead).

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the background process runs on Instinct 2/2X with v1.1.0 code added THEN the system returns -403 (NETWORK_RESPONSE_OUT_OF_MEMORY) on the StormGlass tide JSON response because background free memory before tide fetch drops to 2,936 bytes, below the ~3.5KB threshold needed for JSON parsing

1.2 WHEN the background process starts on Instinct 2/2X (v1.0.2) THEN the system uses 21,056 of 28,488 bytes because the App class references DataManager via `var dataManager as DataManager or Null`, pulling DataManager's entire type (51 fields, all methods) into the background process where it is never used

1.3 WHEN `onBackgroundData()` executes THEN the system calls 6 DataManager methods (`onWeatherData`, `onSurfWindData`, `onTideData`, `onSwellData`, `refreshWeatherOnBackgroundEvent`, plus surf mode branching) which forces the compiler to include DataManager in the background binary

1.4 WHEN `onSettingsChanged()` executes THEN the system calls 5 DataManager methods (`clearWeatherData`, `clearPersistedWeatherData`, `loadSurfCache`, `loadShoreCache`, `refreshWeatherOnBackgroundEvent`, `checkCopyGPS`) through the `dataManager` field, further anchoring DataManager to the `:background`-annotated App class

1.5 WHEN `updateSensorData()` runs in surf mode THEN the system reads HR via `Activity.getActivityInfo()` and stress via `SensorHistory.getStressHistory()` even though neither value is displayed in surf mode, wasting a SensorHistory iterator allocation on the heap

1.6 WHEN the watch is in shore mode THEN the system holds 22 surf-only fields in DataManager (including 6 forecast cache arrays of 24 elements each) in memory, and conversely when in surf mode the system holds 12 shore-only fields in memory

1.7 WHEN the project is compiled THEN the system includes 29 font files (.fnt/.png) not referenced by fonts.xml, consuming ~0.6KB

1.8 WHEN the project is compiled THEN the system includes the dead `drawIconHeart()` function which is never called

### Expected Behavior (Correct)

2.1 WHEN the background process runs on Instinct 2/2X with v1.1.0 code added THEN the system SHALL successfully parse the StormGlass tide JSON response (response code 200) with at least 3.5KB free memory before tide fetch, because the App class no longer pulls DataManager into the background

2.2 WHEN the background process starts on Instinct 2/2X THEN the system SHALL use significantly less memory (target: 500+ bytes less than v1.0.2 baseline of 21,056 bytes) because the App class contains no reference to DataManager or any other foreground-only class

2.3 WHEN `onBackgroundData()` executes THEN the system SHALL write received data directly to `Application.Storage` (weather dict, swell dict, tide flag) and call `WatchUi.requestUpdate()` without referencing DataManager or any foreground class, following the Crystal Face pattern

2.4 WHEN `onSettingsChanged()` executes THEN the system SHALL set a `Storage.setValue("settingsChanged", true)` flag and call `WatchUi.requestUpdate()`, with all DataManager interactions (clear weather, reload caches, recompute sunrise/sunset, checkCopyGPS) handled by the View on the next `onUpdate()` tick

2.5 WHEN `updateSensorData()` runs in surf mode THEN the system SHALL skip HR and stress reads entirely, only reading sensors that are displayed in the current mode per the Sensor Gating Rules (battery, GPS, BT are always read; stress/HR only when the active mode + arc/subscreen settings require them)

2.6 WHEN the user switches between shore and surf mode THEN the system SHALL null out the inactive mode's fields in DataManager to free memory (e.g., nulling 6 forecast cache arrays and surf-specific fields when entering shore mode, and nulling shore weather/HR/stress fields when entering surf mode)

2.7 WHEN the project is compiled THEN the system SHALL NOT include font files that are not referenced by fonts.xml

2.8 WHEN the project is compiled THEN the system SHALL NOT include the dead `drawIconHeart()` function

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the background process fetches weather, swell, and tide data THEN the system SHALL CONTINUE TO deliver all data to the foreground for display, with weather/swell/tide values appearing identically on screen as before the refactor

3.2 WHEN `onBackgroundData()` writes data to Storage and the View reads it on the next tick THEN the system SHALL CONTINUE TO display updated weather, swell, and tide data within one `onUpdate()` cycle of the background event completing (no user-visible delay)

3.3 WHEN the user changes settings (weather source, surf mode, clock font, surf spot coordinates) THEN the system SHALL CONTINUE TO apply changes immediately — clearing stale weather data on source change, reloading mode-specific caches, recomputing sunrise/sunset, and copying GPS to surf spot when toggled

3.4 WHEN the watch face runs on CIQ 4.x+ devices (Instinct 3) THEN the system SHALL CONTINUE TO render all UI elements identically, since the architecture refactor only changes data flow patterns and does not alter rendering logic

3.5 WHEN the watch is in shore mode THEN the system SHALL CONTINUE TO display all shore data fields (time, date, battery, HR, stress arc, weather, wind, tide, sunrise/sunset, moon phase, notifications, BT) with identical values and formatting

3.6 WHEN the watch is in surf mode THEN the system SHALL CONTINUE TO display all surf data fields (time, swell height/period/direction, tide curve, interpolated tide height, water temp, solar arc, surf wind, surf sunrise/sunset, moon phase) with identical values and formatting

3.7 WHEN `Application.Properties.getValue()` is called per tick for settings reads THEN the system SHALL CONTINUE TO use this in-memory API (not Storage) for per-tick reads, and SHALL CONTINUE TO use `Application.Storage.setValue()` only for infrequent writes (background events, settings changes, GPS changes) — never per tick

3.8 WHEN the background temporal event fires THEN the system SHALL CONTINUE TO re-register for the next event in 5 minutes via `Background.registerForTemporalEvent(new Time.Duration(5 * 60))`

3.9 WHEN the `seg34IconsFont` is used by `drawIconBluetooth()` THEN the system SHALL CONTINUE TO render the Bluetooth icon correctly — only `drawIconHeart()` is removed, not the font itself
