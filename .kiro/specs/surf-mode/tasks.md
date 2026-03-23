# Implementation Plan: Surf Mode

## Overview

Implement surf mode as an alternate watch face layout on top of the existing shore mode codebase. All changes go into existing `.mc` and resource files — no new source files. Tasks are ordered for incremental development: settings/data model → background fetching → view rendering → button toggle → tide curve → integration and release.

## Tasks

- [ ] 1. Add surf mode settings and string resources
  - [ ] 1.1 Add new properties to `resources/settings/properties.xml`
    - Add `SurfMode` (number, default 0), `SurfSpotLat` (string, default "0.0"), `SurfSpotLng` (string, default "0.0"), `CopyGPSToSurfSpot` (boolean, default false)
    - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3_
  - [ ] 1.2 Add setting UI entries to `resources/settings/settings.xml`
    - Add `SurfMode` as a list setting (0=Shore, 1=Surf), `SurfSpotLat` and `SurfSpotLng` as alphaNumeric, `CopyGPSToSurfSpot` as boolean
    - _Requirements: 1.1, 2.1, 2.3_
  - [ ] 1.3 Add string resources to `resources/strings/strings.xml`
    - Add `SurfModeTitle`, `SurfModeShore`, `SurfModeSurf`, `SurfSpotLatTitle`, `SurfSpotLngTitle`, `CopyGPSToSurfSpotTitle`
    - _Requirements: 1.1, 2.1, 2.3_

- [ ] 2. Extend DataManager with surf mode fields and methods
  - [ ] 2.1 Add surf data fields to `DataManager.mc`
    - Add `swellHeight`, `swellPeriod`, `swellDirection`, `surfWindSpeed`, `surfWindDeg`, `swellFetchedDay`, `waterTemp`, `solarIntensity`, `interpTideHeight`, `bottomToggleState` fields per design data model
    - Initialize `bottomToggleState = 0` in `initialize()`
    - _Requirements: 6.1, 6.2, 9.6, 12.1, 3.1, 3.4, 4.2, 14.1, 8.4_
  - [ ] 2.2 Implement `interpolateTideHeight()` in `DataManager.mc`
    - Cosine interpolation between surrounding tide extremes per design algorithm
    - Handle edge cases: null/empty tideExtremes, before first event, after last event
    - _Requirements: 14.1, 14.2, 14.3, 14.4_
  - [ ]* 2.3 Write property test for tide interpolation
    - **Property 6: Tide Interpolation Correctness**
    - **Validates: Requirements 14.1, 7.2**
  - [ ] 2.4 Implement `onSwellData(data)` in `DataManager.mc`
    - Parse swell dictionary (swellHeight, swellPeriod, swellDirection, windSpeed, windDeg), persist to `surf_` prefixed Application.Storage keys
    - _Requirements: 9.6, 12.1, 12.2_
  - [ ] 2.5 Implement `loadSurfCache()` and `loadShoreCache()` in `DataManager.mc`
    - `loadSurfCache()` reads from `surf_` prefixed keys; `loadShoreCache()` reads from unprefixed keys and calls existing `loadWeatherData()`
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - [ ]* 2.6 Write property test for cache key isolation
    - **Property 11: Cache Key Isolation by Mode**
    - **Validates: Requirements 9.6, 10.1, 10.2, 10.5, 12.2**
  - [ ] 2.7 Implement `checkCopyGPS()` in `DataManager.mc`
    - One-shot GPS copy: if `CopyGPSToSurfSpot` is true and GPS available, copy lat/lng to `SurfSpotLat`/`SurfSpotLng` and reset flag to false
    - _Requirements: 2.4, 2.5_
  - [ ]* 2.8 Write property test for CopyGPS round trip
    - **Property 1: CopyGPS Round Trip**
    - **Validates: Requirements 2.4, 2.5**
  - [ ] 2.9 Implement `updateSurfSensors()` in `DataManager.mc`
    - Read water temperature from `SensorHistory.getTemperatureHistory()` and solar intensity from `SensorHistory.getSolarIntensityHistory()`, each with period of 1 sample
    - _Requirements: 3.5, 4.3, 3.4_
  - [ ] 2.10 Update `clearWeatherData()` in `DataManager.mc`
    - Also clear surf-specific fields (swellHeight, swellPeriod, swellDirection, surfWindSpeed, surfWindDeg) when called
    - _Requirements: 10.3, 10.4_

- [ ] 3. Checkpoint — Verify DataManager compiles
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Add swell fetching to background delegate
  - [ ] 4.1 Add `fetchSwell()` method to `TideService.mc`
    - Build StormGlass `/v2/weather/point` URL with `swellHeight,swellPeriod,swellDirection,windSpeed,windDirection` params, 24h window (start of day UTC to end of day UTC)
    - Parse response: find hourly entry closest to `now`, extract `sg` values, invoke callback with dictionary
    - Handle quota check via `meta.requestCount` / `meta.dailyQuota`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 11.4, 12.1_
  - [ ]* 4.2 Write property test for closest hourly entry selection
    - **Property 10: Closest Hourly Entry Selection**
    - **Validates: Requirements 9.4**
  - [ ]* 4.3 Write property test for 24-hour swell window
    - **Property 14: Swell Request 24-Hour Window**
    - **Validates: Requirements 9.3**
  - [ ] 4.4 Add surf-mode coordinate branching to `SurferWatchFaceDelegate.mc`
    - In `onTemporalEvent()`: when `SurfMode=1`, read `SurfSpotLat`/`SurfSpotLng`, use as coordinates for tide + swell fetches; when `SurfMode=0`, use GPS/Home (existing behavior)
    - Guard: skip surf fetches if surf spot is "0.0"/"0.0"
    - _Requirements: 2.7, 2.8, 2.6_
  - [ ]* 4.5 Write property test for mode-based coordinate selection
    - **Property 2: Mode Determines API Coordinates**
    - **Validates: Requirements 2.7, 2.8**
  - [ ] 4.6 Add swell fetch chaining to `SurferWatchFaceDelegate.mc`
    - Chain `fetchSwell()` after tide fetch completes in surf mode; add `onSwellComplete()` callback; track `_swellNeeded` flag with daily refresh logic using `surf_swellFetchedDay` key
    - Write fetch metadata to `surf_` prefixed storage keys
    - Package swell data in `Background.exit()` result under `"swell"` key
    - _Requirements: 9.5, 11.1, 11.2, 11.3, 10.5_
  - [ ]* 4.7 Write property test for StormGlass daily call limit
    - **Property 13: StormGlass Daily Call Limit in Surf Mode**
    - **Validates: Requirements 11.1, 9.5**

- [ ] 5. Route swell data in SurferWatchFaceApp
  - [ ] 5.1 Update `onBackgroundData()` in `SurferWatchFaceApp.mc`
    - Route `data["swell"]` to `dataManager.onSwellData()` when present
    - _Requirements: 9.6_
  - [ ] 5.2 Update `onSettingsChanged()` in `SurferWatchFaceApp.mc`
    - Detect `SurfMode` change: load surf cache (`loadSurfCache()`) when switching to 1, load shore cache (`loadShoreCache()`) when switching to 0
    - Clear weather data on mode change to prevent stale cross-mode rendering
    - _Requirements: 1.5, 10.3, 10.4_
  - [ ]* 5.3 Write property test for cache round trip on mode switch
    - **Property 12: Cache Round Trip on Mode Switch**
    - **Validates: Requirements 10.3, 10.4**

- [ ] 6. Checkpoint — Verify background fetching compiles and data flows
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Implement surf mode subscreen circle rendering
  - [ ] 7.1 Add `drawHrCircle_Surf(dc, dm)` to `SurferWatchFaceView.mc`
    - Display interpolated tide height (m/ft per device units) centered in subscreen circle, replacing heart rate BPM
    - Display tide direction arrow (up for rising/next=high, down for falling/next=low), replacing heart icon
    - Display solar intensity as 0-100% arc gauge using existing `drawStressArc()` geometry, replacing stress arc
    - Show "--" if tide height unavailable, empty arc if solar unavailable
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 14.2_
  - [ ]* 7.2 Write property test for tide direction arrow
    - **Property 3: Tide Direction Arrow Matches Next Tide Type**
    - **Validates: Requirements 3.3**

- [ ] 8. Implement surf mode top section rendering
  - [ ] 8.1 Add `drawTopSection_Surf(dc, dm)` to `SurferWatchFaceView.mc`
    - Row 1: battery percentage and icon (identical to shore mode)
    - Row 2: water temperature in °C or °F per device unit setting, replacing BT+notification row
    - Row 3: next tide event time and height (identical to shore mode)
    - Show "--" if water temp unavailable
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 13.1, 13.2_
  - [ ]* 8.2 Write property test for water temperature unit conversion
    - **Property 4: Water Temperature Unit Conversion**
    - **Validates: Requirements 4.4**

- [ ] 9. Implement surf mode middle section rendering
  - [ ] 9.1 Add `drawMiddleSection_Surf(dc, dm)` to `SurferWatchFaceView.mc`
    - Left column: wind direction arrow (reuse `drawWindArrow()`) and wind speed text (from `surfWindSpeed`/`surfWindDeg`), replacing sunrise/sunset
    - Center: current time (same font and position as shore mode)
    - Right column: moon phase icon, AM/PM, seconds on wrist raise (identical to shore mode)
    - Show "--" for wind speed and omit arrow if wind data unavailable
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 13.5_

- [ ] 10. Implement surf mode bottom section — swell view
  - [ ] 10.1 Add `drawSwellSection(dc, dm)` to `SurferWatchFaceView.mc`
    - Three-column layout at weather widget positions: swell height (m/ft), swell period (seconds), swell direction arrow (reuse `drawWindArrow()`)
    - Show "--" for all three fields if swell data unavailable
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [ ]* 10.2 Write property test for swell height unit conversion
    - **Property 5: Swell Height Unit Conversion**
    - **Validates: Requirements 6.2**

- [ ] 11. Wire surf mode branch into onUpdate()
  - [ ] 11.1 Add surf mode branch to `onUpdate()` in `SurferWatchFaceView.mc`
    - Read `SurfMode` property; when 1, call surf-specific update methods (`updateSurfSensors`, `checkCopyGPS`, `interpolateTideHeight`) and surf draw methods; when 0, existing shore rendering
    - Add surf-mode layout constants at top of file per design
    - _Requirements: 1.3, 1.4, 1.5, 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_

- [ ] 12. Checkpoint — Verify surf mode renders with swell view
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 13. Implement bottom toggle via button press
  - [ ] 13.1 Add `SurferWatchFaceBehaviorDelegate` class to bottom of `SurferWatchFaceView.mc`
    - `onSelect()`: when `SurfMode=1`, toggle `dm.bottomToggleState` between 0 and 1, call `WatchUi.requestUpdate()`, return true; when `SurfMode=0`, return false
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  - [ ] 13.2 Update `getInitialView()` in `SurferWatchFaceApp.mc`
    - Return `[new SurferWatchFaceView(), new SurferWatchFaceBehaviorDelegate()]` instead of view-only array
    - _Requirements: 8.1_
  - [ ]* 13.3 Write property test for onSelect behavior
    - **Property 8: onSelect Behavior Based on Mode**
    - **Validates: Requirements 8.1, 8.5**
  - [ ]* 13.4 Write property test for toggle round trip
    - **Property 9: Bottom Toggle Round Trip**
    - **Validates: Requirements 8.2**

- [ ] 14. Implement tide curve rendering
  - [ ] 14.1 Add `drawTideCurve(dc, dm)` to `SurferWatchFaceView.mc`
    - Plot tide extremes as cosine-interpolated polyline from x=12 to x=164, y=114 to y=170
    - Draw vertical "now" marker at current time position
    - Label H/L heights on Y axis
    - Show "--" if fewer than 2 tide extremes available
    - Wire into `onUpdate()` surf branch when `bottomToggleState == 1`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  - [ ]* 14.2 Write property test for now marker time-to-X mapping
    - **Property 7: Now Marker Time-to-X Mapping**
    - **Validates: Requirements 7.3**

- [ ] 15. Checkpoint — Verify both bottom views toggle correctly
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 16. Integration and release
  - [ ] 16.1 Verify all surf mode requirements are covered
    - Walk through Requirements 1-14 and confirm each acceptance criterion is implemented and reachable via the code paths
    - _Requirements: 1.1–14.4_
  - [ ] 16.2 Update `README.md` with surf mode documentation
    - Add surf mode features, surf spot configuration guide, data refresh table updates, bottom toggle usage
    - _Requirements: structure.md release checklist item 2_
  - [ ] 16.3 Update `store-description.txt` with surf mode features
    - _Requirements: structure.md release checklist item 3_
  - [ ] 16.4 Add `CHANGELOG.md` entry for surf mode release
    - _Requirements: structure.md release checklist item 7_

- [ ] 17. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- All changes go into existing files — no new `.mc` files created
- The `SurferWatchFaceBehaviorDelegate` class is added to the bottom of `SurferWatchFaceView.mc` per design
- Property tests reference design Properties 1-14 for traceability
- Checkpoints at tasks 3, 6, 12, 15, and 17 ensure incremental validation
- Surf mode uses `surf_` prefixed Application.Storage keys to isolate cache from shore mode
