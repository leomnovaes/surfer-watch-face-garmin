# Implementation Plan: Surf Mode

## Overview

Implement surf mode as an alternate watch face layout on top of the existing shore mode codebase. All changes go into existing `.mc` and resource files — no new source files. Tasks are ordered for incremental development: settings/data model → background fetching → view rendering → bottom toggle → tide curve → integration and release.

## Tasks

- [x] 1. Add surf mode settings and string resources
  - [x] 1.1 Add new properties to `resources/settings/properties.xml`
  - [x] 1.2 Add setting UI entries to `resources/settings/settings.xml`
  - [x] 1.3 Add string resources to `resources/strings/strings.xml`

- [x] 2. Extend DataManager with surf mode fields and methods
  - [x] 2.1 Add surf data fields (swell, surf wind, water temp, solar intensity, interp tide, toggle state)
  - [x] 2.2 Implement `interpolateTideHeight()` — cosine interpolation
  - [x] 2.4 Implement `onSwellData(data)` — parse and persist to surf_ keys
  - [x] 2.5 Implement `loadSurfCache()` and `loadShoreCache()`
  - [x] 2.7 Implement `checkCopyGPS()` — one-shot GPS copy
  - [x] 2.9 Implement `updateSurfSensors()` — water temp + solar intensity
  - [x] 2.10 Update `clearWeatherData()` to also clear surf fields

- [x] 3. Checkpoint — DataManager compiles

- [x] 4. Add swell fetching to background delegate
  - [x] 4.1 Add `fetchSwell()` method to `TideService.mc` — StormGlass weather endpoint
  - [x] 4.4 Add surf-mode coordinate branching to `SurferWatchFaceDelegate.mc`
  - [x] 4.6 Add swell fetch chaining — tide → swell in surf mode

- [x] 5. Route swell data in SurferWatchFaceApp
  - [x] 5.1 Update `onBackgroundData()` to route swell data
  - [x] 5.2 Update `onSettingsChanged()` for mode switch cache loading

- [x] 6. Checkpoint — Background fetching compiles and data flows

- [x] 7. Implement surf mode subscreen circle rendering
  - [x] 7.1 `drawHrCircle_Surf()` — tide height + solar arc + tide direction arrow (placeholder icons)

- [x] 8. Implement surf mode top section rendering
  - [x] 8.1 `drawTopSection_Surf()` — battery, water temp (placeholder icon at notification position), next tide

- [x] 9. Implement surf mode middle section rendering
  - [x] 9.1 `drawMiddleSection_Surf()` — wind (from StormGlass), time, moon/AM/PM/seconds

- [x] 10. Implement surf mode bottom section — swell view
  - [x] 10.1 `drawSwellSection()` — swell height, period, direction (placeholder icons)

- [x] 11. Wire surf mode branch into onUpdate()
  - [x] 11.1 Surf mode branch in `onUpdate()` with all surf draw methods

- [x] 12. Checkpoint — Surf mode renders with swell view

- [x] 13. Implement bottom toggle via double wrist gesture
  - [x] 13.1 Double wrist gesture detection in `onExitSleep()` — two raises within window toggles bottom view
  - Note: Watch faces cannot receive button input (onSelect). BehaviorDelegate approach was abandoned. Double wrist gesture (raise, lower, raise) is the toggle mechanism.
  - Note: Toggle window is 4s (raise, lower, raise within 4 seconds).

- [x] 14. Implement tide curve rendering
  - [x] 14.1 `drawTideCurve()` — filled area under cosine-interpolated curve
  - [x] 14.2 Dithered checkerboard "now" marker (gray effect on MIP)
  - [x] 14.3 Downward triangle above curve at "now" position
  - [x] 14.4 Time labels above curve — short format ("6p") rounded to nearest hour
  - [x] 14.5 Local time range (Time.today()) instead of UTC midnight
  - [x] 14.6 Tweakable constants: TC_Y, TC_LABEL_HEIGHT, TC_CURVE_HEIGHT, TC_LABEL_GAP, TC_NOW_GAP_HALF, TC_TRI_WIDTH/HEIGHT/GAP, TC_HEIGHT_PAD, TC_HEIGHT_PAD_BOTTOM

- [x] 15. Checkpoint — Both bottom views toggle correctly

- [x] 16. Integration and release
  - [x] 16.1 Verify all surf mode requirements are covered
  - [x] 16.2 Update `README.md` with surf mode documentation
  - [x] 16.3 Update `store-description.txt` with surf mode features
  - [x] 16.4 Add `CHANGELOG.md` entry for surf mode release
  - [x] 16.5 Regenerate screenshots and annotated diagram
  - [x] 16.6 Build `.iq` package and upload to Connect IQ

- [x] 17. Final checkpoint — Ensure all tests pass

## Remaining polish tasks (not blocking release)
- [ ] Rasterize proper tide direction icon for subscreen circle (currently tide H/L icons)
- [ ] Rasterize proper thermometer icon for water temp (currently surfer-icons "T")
- [x] Tune double-gesture window to 4s for real watch hardware

## Phase 2 — API Refactor (data sources optimization)

### Task 18: Switch swell from StormGlass to Open-Meteo Marine API
- [x] Replace `TideService.fetchSwell()` StormGlass call with Open-Meteo Marine API
  - Endpoint: `https://marine-api.open-meteo.com/v1/marine?latitude={lat}&longitude={lon}&hourly=swell_wave_height,swell_wave_period,swell_wave_direction&forecast_days=1`
  - Free, no API key, no quota, flat array response (~1.2KB for 24h)
- [x] Store full 24h hourly arrays in Application.Storage (surf_swellHeights, surf_swellPeriods, surf_swellDirections)
- [x] On each `onUpdate()`, pick the current hour's entry for display via `updateSwellFromForecast()`
- [x] Remove StormGlass swell fetch code
- [x] Update surf mode chain: Open-Meteo swell → SG tide → OWM wind

### Task 19: Separate surf/shore wind fields
- [x] Add `surfWindSpeed` and `surfWindDeg` fields to DataManager (separate from shore `windSpeed`/`windDeg`)
- [x] Delegate `onWindDone()` extracts only wind from OWM response in surf mode
- [x] `drawMiddleSection_Surf()` reads from `surfWindSpeed`/`surfWindDeg`
- [x] Shore mode wind fields unaffected by surf mode fetches

### Task 20: Verify StormGlass usage is tide-only
- [x] Confirm StormGlass is only called for tide extremes (1 call/day)
- [x] StormGlass backup key logic works for tide (flag-based: 402 → set sgUseBackup, next cycle uses backup)
- [x] Update specs to reflect Open-Meteo swell, separated wind, removed StormGlass swell
- [x] Update README with surf mode documentation
- [x] Update store-description.txt with surf mode features

### Task 21: Add Open-Meteo as third weather source
- [x] 21.1 Update `WeatherSource` setting from 2-value to 3-value list: 0=Garmin, 1=Open-Meteo, 2=OWM
- [x] 21.2 Update `properties.xml`, `settings.xml`, `strings.xml` with new option
- [x] 21.3 Update all code that reads `WeatherSource` to handle value 2 for OWM (was 1)
- [x] 21.4 Implement `OpenMeteoService` class (`:background` annotated) with `fetchCurrent()` for shore mode
- [x] 21.5 Parse Open-Meteo current response: temperature_2m, weather_code, wind_speed_10m, wind_direction_10m, precipitation_probability, is_day
- [x] 21.6 Parse sunrise/sunset from daily response (ISO local time → Unix timestamp using utc_offset_seconds)
- [x] 21.7 Add `precipProbability` and `isDay` fields to DataManager, populated from Open-Meteo response
- [x] 21.8 Update view to use `dm.precipProbability` when WeatherSource=1, Garmin built-in otherwise
- [x] 21.9 Wire Open-Meteo shore weather into delegate chain (WeatherSource=1 → OpenMeteoService.fetchCurrent() → onShoreWeatherDone())

### Task 22: Implement WMO weather code mapper
- [x] 22.1 Implement `wmoToWeatherGlyph(code, isNight)` in SurferWatchFaceView
- [x] 22.2 Map all WMO codes (0, 1-3, 45/48, 51-57, 61-67, 71-77, 80-86, 95-99) to existing glyphs
- [x] 22.3 Use `is_day` from Open-Meteo response for day/night variant selection
- [x] 22.4 Update `drawIconWeather()` to select mapper based on WeatherSource (0=Garmin, 1=WMO, 2=OWM)

### Task 23: Implement surf mode hourly wind forecast (Open-Meteo)
- [x] 23.1 Add `fetchSurfWind()` to OpenMeteoService — hourly wind_speed_10m + wind_direction_10m, forecast_days=1
- [x] 23.2 Store 24h wind arrays in Application.Storage (`surf_windSpeeds`, `surf_windDirections`)
- [x] 23.3 Implement `updateSurfWindFromForecast()` in DataManager — picks current hour's entry (same pattern as swell)
- [x] 23.4 Wire into onUpdate() surf mode: call `updateSurfWindFromForecast()` when WeatherSource=1
- [x] 23.5 Update delegate surf chain: when WeatherSource=1, chain to OpenMeteoService.fetchSurfWind() instead of WeatherService.fetch()
- [x] 23.6 When WeatherSource=0 (Garmin), skip wind fetch in surf mode (display "--")
- [x] 23.7 When WeatherSource=2 (OWM), keep existing OWM wind fetch (current only, no forecast array)

### Task 24: Checkpoint — Open-Meteo weather works in both modes
- [x] 24.1 Verify shore mode with WeatherSource=1: temp, condition icon, wind, precip, sunrise/sunset all display correctly
- [x] 24.2 Verify surf mode with WeatherSource=1: wind advances hourly through forecast array
- [x] 24.3 Verify shore mode with WeatherSource=2 (OWM): unchanged behavior
- [x] 24.4 Verify surf mode with WeatherSource=2 (OWM): current wind only, freezes offline
- [x] 24.5 Verify shore mode with WeatherSource=0 (Garmin): unchanged behavior
- [x] 24.6 Verify surf mode with WeatherSource=0 (Garmin): wind shows "--"
- [x] 24.7 Verify weather data clears on source switch (no condition code mismatch)

### Task 25: Update docs and release
- [x] 25.1 Update README: document 3-tier weather source, Open-Meteo tradeoffs (fewer condition icons), surf mode wind behavior per source
- [x] 25.2 Update store-description.txt
- [x] 25.3 Update CHANGELOG
- [x] 25.4 Update steering files (tech.md, product.md) with Open-Meteo weather API docs
- [x] 25.5 Regenerate screenshots and annotated diagrams for both modes

## Notes

- All changes went into existing files — no new `.mc` files created
- The `SurferWatchFaceBehaviorDelegate` class exists in `SurferWatchFaceView.mc` but is NOT used (watch faces can't receive button input)
- Double wrist gesture (onExitSleep timing) is the toggle mechanism instead
- Surf mode uses `surf_` prefixed Application.Storage keys to isolate cache from shore mode
- Solar intensity read from System.getSystemStats().solarIntensity (works on all Instinct Solar models)


### Task 26 (previously 22): Clean up debug println statements
- [x] Remove all `System.println()` debug statements from delegate, TideService, view

### Task 27 (previously 23): Release v2.0.0 (surf mode)
- [x] Follow release checklist from structure.md
- [x] Tune double wrist gesture window to 4s for real watch hardware
- [x] Update all specs, README, CHANGELOG, store description
- [x] Regenerate screenshots (shore + surf mode)
- [x] Regenerate annotated diagrams for both modes
- [ ] Build and upload to Connect IQ


## Phase 4 — Production Release (Surfer Watch v1.0.0)

### Task 28: Rename app from "Shore Watch" to "Surfer Watch"
- [x] 28.1 Update `resources/strings/strings.xml`: change AppName from "Shore Watch" to "Surfer Watch"
- [x] 28.2 Update `README.md`: all references to "Shore Watch" → "Surfer Watch"
- [x] 28.3 Update `store-description.txt`: title and all references
- [x] 28.4 Update `CHANGELOG.md`: any references to "Shore Watch"
- [x] 28.5 Update `.kiro/steering/product.md`: product name
- [x] 28.6 Update `.kiro/specs/` docs: any references to "Shore Watch"
- [x] 28.7 Regenerate `store-cover.png` with new name (run `generate-cover.py`)
- [x] 28.8 Verify no remaining "Shore Watch" references in codebase (grep)

### Task 29: Generate new UUID for production release
- [x] 29.1 Generate a new UUID (e.g., via `uuidgen` command)
- [x] 29.2 Replace the `id` attribute in `manifest.xml` `<iq:application>` tag with the new UUID
- [x] 29.3 Note: beta and production apps need different UUIDs on Connect IQ — this creates a new store listing

### Task 30: Clean CHANGELOG for v1.0.0 production release
- [x] 30.1 Collapse all beta version entries (v1.0.0, v1.1.0, v2.0.0) into a single v1.0.0 entry
- [x] 30.2 Write clean release notes summarizing all features as if shipping for the first time
- [x] 30.3 Remove historical development notes, intermediate fixes, and beta-specific entries
- [x] 30.4 The CHANGELOG should read as a fresh v1.0.0 with all current features listed

### Task 31: Final production release
- [ ] 31.1 Follow release checklist from structure.md
- [ ] 31.2 Build `.iq` package via `Monkey C: Export Project`
- [ ] 31.3 Create NEW app listing on Connect IQ developer dashboard (not the beta one)
- [ ] 31.4 Upload `.iq` package, screenshots, store-cover, store-description
- [ ] 31.5 Submit for approval


## Phase 5 — v1.1.0 Customization Features

### Task 32: Always Show Seconds setting
- [x] 32.1 Add `AlwaysShowSeconds` boolean property (default false) to properties.xml
- [x] 32.2 Add setting UI entry to settings.xml with label "(more battery)"
- [x] 32.3 Add string resources
- [x] 32.4 Update `drawRightColumn()`: show seconds when `!isSleeping || AlwaysShowSeconds`
- [x] 32.5 Implement `onPartialUpdate(dc)` for per-second updates in low-power mode
  - Clips to seconds region (20x18px), clears, redraws seconds text
  - Early return when AlwaysShowSeconds is off (near-zero battery cost)
  - Note: `onPartialUpdate` is called by the system every second on MIP devices regardless — cannot be unregistered. The early return is the gating mechanism.

### Task 33: Refactor subscreen + arc to display-ready abstraction
- The View currently has separate `drawHrCircle()` (shore) and `drawHrCircle_Surf()` (surf) methods with hardcoded content (HR vs tide height) and arc sources (stress vs solar). This refactor creates a single `drawSubscreen()` that renders whatever DataManager provides, enabling future configurability without View changes.

- [x] 33.1 Add display-ready fields to DataManager
  - `subscreenIcon as String` — font glyph character to render (e.g., "h" for heart, "H"/"L" for tide, "T" for thermometer)
  - `subscreenValue as String` — formatted display string (e.g., "72", "1.2m", "--")
  - `subscreenFont` — which icon font to use (heartIconFont, surferIconsFont, etc.) — stored as a Number enum, View maps to font
  - `arcValue as Number or Null` — 0-100 gauge value, null = disabled (no arc drawn)
  - Initialize all to defaults in constructor

- [x] 33.2 Add `updateSubscreenData()` method to DataManager
  - Called from `updateSensorData()` (per-tick, after sensor reads)
  - Reads `SurfMode` to determine current mode
  - Shore mode: icon = heart glyph, value = heartRate formatted or "--", font = heartIconFont enum
  - Surf mode: icon = tide direction glyph ("H"/"L"), value = interpolated tide height formatted or "--", font = surferIconsFont enum
  - Handles unit conversion (metric/imperial) internally
  - View never formats sensor values — DataManager provides display-ready strings

- [x] 33.3 Add `updateArcData()` method to DataManager
  - Called from `updateSensorData()` (per-tick, after sensor reads)
  - Shore mode: reads stress (existing), sets `arcValue = stress`
  - Surf mode: reads solar intensity (existing), sets `arcValue = solarIntensity`
  - If sensor unavailable: `arcValue = null`
  - Consolidate solar read from `updateSurfSensors()` into `updateSensorData()` (read from same `System.getSystemStats()` call as battery)

- [x] 33.4 Rename `drawHrCircle()` and `drawHrCircle_Surf()` to single `drawSubscreen(dc, dm)`
  - Draw filled white circle
  - If `dm.arcValue != null`: draw arc gauge with `dm.arcValue`
  - Draw `dm.subscreenIcon` using the appropriate font (map enum to font var)
  - Draw `dm.subscreenValue` as text
  - One method for both modes — no mode branching in View

- [x] 33.5 Build and verify
  - Shore mode: subscreen shows heart + BPM + stress arc (same as before)
  - Surf mode: subscreen shows tide direction + height + solar arc (same as before)
  - No visual change — this is a pure refactor
  - Measure memory — should be similar (moved code, not added)

### Task 33b: Add configurable arc setting
- Builds on Task 33's abstraction. Adds ShoreArc/SurfArc settings so users can choose which metric the arc displays.

- [x] 33b.1 Add `ShoreArc` list property: 0=Stress (default), 1=Solar, 2=Body Battery, 3=Disabled
- [x] 33b.2 Add `SurfArc` list property: 0=Solar (default), 1=Stress, 2=Body Battery, 3=Disabled
- [x] 33b.3 Add setting UI entries and string resources
- [x] 33b.4 Add `bodyBattery as Number or Null` field to DataManager
- [x] 33b.5 Update `updateArcData()` to read the active arc setting per mode:
  - Determine active arc from `SurfMode` + `ShoreArc`/`SurfArc`
  - If Stress: read `SensorHistory.getStressHistory()` → `arcValue`
  - If Body Battery: read `SensorHistory.getBodyBatteryHistory()` → `arcValue`
  - If Solar: read from `System.getSystemStats().solarIntensity` → `arcValue`
  - If Disabled: `arcValue = null` (arc not drawn)
  - SensorHistory constraint: only one iterator per tick — Stress and Body Battery are mutually exclusive arc options
- [x] 33b.6 Build and verify
  - Change ShoreArc to Solar → arc shows solar intensity in shore mode
  - Change ShoreArc to Body Battery → arc shows body battery
  - Change ShoreArc to Disabled → no arc, circle + content only
  - Change SurfArc to Stress → arc shows stress in surf mode
  - Measure memory
- Memory: 2 Properties + ~8 strings + 1 DataManager field (~8 bytes) + body battery sensor read (~10 lines). No new Storage keys.

### Task 34: Configurable shore subscreen content
- Builds on Task 33's abstraction. Adds ShoreSubscreen setting so users can choose what the subscreen circle displays in shore mode.

- [ ] 34.1 Add `ShoreSubscreen` list property: 0=Heart Rate (default), 1=Temperature, 2=Altitude, 3=Steps
- [ ] 34.2 Add setting UI entry and string resources
- [ ] 34.3 Add `altitude as Number or Null` and `steps as Number or Null` fields to DataManager
- [ ] 34.4 Update `updateSubscreenData()` for shore mode to read `ShoreSubscreen`:
  - 0=HR: icon = heart, value = heartRate or "--", font = heartIconFont
  - 1=Temperature: icon = thermometer "T", value = temperature formatted, font = surferIconsFont
  - 2=Altitude: icon = mountain "M", value = altitude formatted, font = surferIconsFont
  - 3=Steps: icon = shoe-prints "W", value = steps formatted, font = surferIconsFont
- [ ] 34.5 Gate sensor reads by ShoreSubscreen:
  - HR: only read when ShoreSubscreen=0
  - Altitude: read from `SensorHistory.getElevationHistory()` when ShoreSubscreen=2
  - Steps: read from `ActivityMonitor.getInfo().steps` when ShoreSubscreen=3
  - Temperature: already available from weather data, no extra sensor read
  - SensorHistory constraint: altitude uses an iterator — mutually exclusive with stress/body battery per tick
- [ ] 34.6 Rasterize mountain icon into surfer-icons font (char M=77)
- [ ] 34.7 Rasterize steps/shoe-prints icon into surfer-icons font (char W=87)
- [ ] 34.8 Build and verify
  - Change ShoreSubscreen to Temperature → circle shows thermometer + temp
  - Change ShoreSubscreen to Altitude → circle shows mountain + elevation
  - Change ShoreSubscreen to Steps → circle shows shoe-prints + step count
  - Measure memory
- Memory: 1 Property + ~4 strings + 2 DataManager fields (~16 bytes) + 2 sensor reads + 2 icon glyphs in font. No new Storage keys.

### Task 32b: Surf bottom view configuration
- [x] 32b.1 Add `SurfDefaultView` list property: 0=Swell (default), 1=Tide Curve
- [x] 32b.2 Add `SurfViewToggle` boolean property: true=enabled (default), false=locked to default view
- [x] 32b.3 Add setting UI entries and string resources
- [x] 32b.4 Cache `_surfViewToggle` in View field (read on init + settings change, not per-tick)
- [x] 32b.5 Gate double wrist gesture in `onExitSleep()` by `_surfViewToggle`
- [x] 32b.6 Set `bottomToggleState` from `SurfDefaultView` on init and settings change
- Memory: 2 Properties (in-memory reads), 4 strings, 1 View field (~8 bytes), no Storage keys, no per-tick reads
- No new DataManager fields — reuses existing `bottomToggleState`

### Task 35: Update docs and release v1.1.0
- [ ] 35.1 Update README with new settings
- [ ] 35.2 Update store-description.txt
- [ ] 35.3 Update CHANGELOG
- [ ] 35.4 Update specs (requirements, design)
- [ ] 35.5 Build and upload to Connect IQ
