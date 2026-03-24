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
  - Note: Toggle window is 10s for simulator testing, needs tuning to 4-5s on real watch.

- [x] 14. Implement tide curve rendering
  - [x] 14.1 `drawTideCurve()` — filled area under cosine-interpolated curve
  - [x] 14.2 Dithered checkerboard "now" marker (gray effect on MIP)
  - [x] 14.3 Downward triangle above curve at "now" position
  - [x] 14.4 Time labels above curve — short format ("6p") rounded to nearest hour
  - [x] 14.5 Local time range (Time.today()) instead of UTC midnight
  - [x] 14.6 Tweakable constants: TC_Y, TC_LABEL_HEIGHT, TC_CURVE_HEIGHT, TC_LABEL_GAP, TC_NOW_GAP_HALF, TC_TRI_WIDTH/HEIGHT/GAP, TC_HEIGHT_PAD, TC_HEIGHT_PAD_BOTTOM

- [x] 15. Checkpoint — Both bottom views toggle correctly

- [ ] 16. Integration and release
  - [ ] 16.1 Verify all surf mode requirements are covered
  - [ ] 16.2 Update `README.md` with surf mode documentation
  - [ ] 16.3 Update `store-description.txt` with surf mode features
  - [ ] 16.4 Add `CHANGELOG.md` entry for surf mode release
  - [ ] 16.5 Regenerate screenshots and annotated diagram
  - [ ] 16.6 Build `.iq` package and upload to Connect IQ

- [ ] 17. Final checkpoint — Ensure all tests pass

## Remaining polish tasks (not blocking release)
- [ ] Rasterize proper tide direction icon for subscreen circle (currently tide H/L icons)
- [ ] Rasterize proper thermometer icon for water temp (currently surfer-icons "T")
- [ ] Tune double-gesture window from 10s to 4-5s after real watch testing

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
- [ ] 21.1 Update `WeatherSource` setting from 2-value to 3-value list: 0=Garmin, 1=Open-Meteo, 2=OWM
- [ ] 21.2 Update `properties.xml`, `settings.xml`, `strings.xml` with new option
- [ ] 21.3 Update all code that reads `WeatherSource` to handle value 2 for OWM (was 1)
- [ ] 21.4 Implement `OpenMeteoService` class (`:background` annotated) with `fetchCurrent()` for shore mode
- [ ] 21.5 Parse Open-Meteo current response: temperature_2m, weather_code, wind_speed_10m, wind_direction_10m, precipitation_probability, is_day
- [ ] 21.6 Parse sunrise/sunset from daily response (ISO local time → Unix timestamp using utc_offset_seconds)
- [ ] 21.7 Add `precipProbability` field to DataManager, populated from Open-Meteo response
- [ ] 21.8 Update view to use `dm.precipProbability` when WeatherSource=1, Garmin built-in otherwise
- [ ] 21.9 Wire Open-Meteo shore weather into delegate chain (WeatherSource=1 → OpenMeteoService.fetchCurrent() → onShoreWeatherDone())

### Task 22: Implement WMO weather code mapper
- [ ] 22.1 Implement `wmoToWeatherGlyph(code, isNight)` in SurferWatchFaceView
- [ ] 22.2 Map all WMO codes (0, 1-3, 45/48, 51-57, 61-67, 71-77, 80-86, 95-99) to existing glyphs
- [ ] 22.3 Use `is_day` from Open-Meteo response for day/night variant selection
- [ ] 22.4 Update `drawIconWeather()` to select mapper based on WeatherSource (0=Garmin, 1=WMO, 2=OWM)

### Task 23: Implement surf mode hourly wind forecast (Open-Meteo)
- [ ] 23.1 Add `fetchSurfWind()` to OpenMeteoService — hourly wind_speed_10m + wind_direction_10m, forecast_days=1
- [ ] 23.2 Store 24h wind arrays in Application.Storage (`surf_windSpeeds`, `surf_windDirections`)
- [ ] 23.3 Implement `updateSurfWindFromForecast()` in DataManager — picks current hour's entry (same pattern as swell)
- [ ] 23.4 Wire into onUpdate() surf mode: call `updateSurfWindFromForecast()` when WeatherSource=1
- [ ] 23.5 Update delegate surf chain: when WeatherSource=1, chain to OpenMeteoService.fetchSurfWind() instead of WeatherService.fetch()
- [ ] 23.6 When WeatherSource=0 (Garmin), skip wind fetch in surf mode (display "--")
- [ ] 23.7 When WeatherSource=2 (OWM), keep existing OWM wind fetch (current only, no forecast array)

### Task 24: Checkpoint — Open-Meteo weather works in both modes
- [ ] 24.1 Verify shore mode with WeatherSource=1: temp, condition icon, wind, precip, sunrise/sunset all display correctly
- [ ] 24.2 Verify surf mode with WeatherSource=1: wind advances hourly through forecast array
- [ ] 24.3 Verify shore mode with WeatherSource=2 (OWM): unchanged behavior
- [ ] 24.4 Verify surf mode with WeatherSource=2 (OWM): current wind only, freezes offline
- [ ] 24.5 Verify shore mode with WeatherSource=0 (Garmin): unchanged behavior
- [ ] 24.6 Verify surf mode with WeatherSource=0 (Garmin): wind shows "--"
- [ ] 24.7 Verify weather data clears on source switch (no condition code mismatch)

### Task 25: Update docs and release
- [ ] 25.1 Update README: document 3-tier weather source, Open-Meteo tradeoffs (fewer condition icons), surf mode wind behavior per source
- [ ] 25.2 Update store-description.txt
- [ ] 25.3 Update CHANGELOG
- [ ] 25.4 Update steering files (tech.md, product.md) with Open-Meteo weather API docs
- [ ] 25.5 Regenerate screenshots and annotated diagrams for both modes

## Notes

- All changes went into existing files — no new `.mc` files created
- The `SurferWatchFaceBehaviorDelegate` class exists in `SurferWatchFaceView.mc` but is NOT used (watch faces can't receive button input)
- Double wrist gesture (onExitSleep timing) is the toggle mechanism instead
- Surf mode uses `surf_` prefixed Application.Storage keys to isolate cache from shore mode
- Solar intensity (`getSolarIntensityHistory`) may not be available on Instinct 2X — guarded with `has` check, falls back to null/empty arc


### Task 26 (previously 22): Clean up debug println statements
- [x] Remove all `System.println()` debug statements from delegate, TideService, view

### Task 27 (previously 23): Release v2.0.0 (surf mode)
- [ ] Follow release checklist from structure.md
- [ ] Tune double wrist gesture window from 10s (simulator) to 4-5s for real watch hardware
- [ ] Update all specs, README, CHANGELOG, store description
- [ ] Regenerate screenshots (shore + surf mode)
- [ ] Regenerate annotated diagrams for both modes
- [ ] Build and upload to Connect IQ
