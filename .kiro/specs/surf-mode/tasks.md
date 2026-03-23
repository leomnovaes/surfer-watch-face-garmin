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
- [ ] Replace `TideService.fetchSwell()` StormGlass call with Open-Meteo Marine API
  - Endpoint: `https://marine-api.open-meteo.com/v1/marine?latitude={lat}&longitude={lon}&hourly=swell_wave_height,swell_wave_period,swell_wave_direction&forecast_days=1`
  - Free, no API key, no quota, flat array response (~1.2KB for 24h)
  - Response format: `{hourly: {time: [...], swell_wave_height: [...], swell_wave_period: [...], swell_wave_direction: [...]}}`
- [ ] Parse response into flat array of `{time, height, period, direction}` entries
- [ ] Store full 24h hourly array in DataManager (not just closest entry)
- [ ] On each `onUpdate()`, pick the entry closest to current time for display
- [ ] As time passes, display advances through the forecast automatically
- [ ] Remove StormGlass swell fetch code and `surf_swell*` storage keys
- [ ] Update surf mode chain: Open-Meteo swell → SG tide → OWM wind

### Task 19: Store swell forecast array for offline use
- [ ] Persist full swell hourly array to `Application.Storage` (surf_swellForecast key)
- [ ] Load on startup / mode switch
- [ ] DataManager.getCurrentSwell() picks closest-to-now entry from stored array
- [ ] Works offline — display advances through forecast without phone connection

### Task 20: Verify StormGlass usage is tide-only
- [ ] Confirm StormGlass is only called for tide extremes (1 call/day)
- [ ] Remove any remaining StormGlass swell-related code
- [ ] Update backup key logic — only needed for tide now
- [ ] Update specs, README, store description

### Task 21: Research hourly wind forecast source for offline use
- [ ] Evaluate options:
  - Open-Meteo Weather API (free, no key, has hourly wind forecast)
  - OWM One Call 3.0 (hourly but requires credit card)
  - Other sources
- [ ] Test response size and memory fit
- [ ] If viable: store hourly wind forecast array, advance with time offline
- [ ] If not viable: document limitation (wind freezes when offline)

### Task 22: Clean up debug println statements
- [ ] Remove all `System.println()` debug statements from delegate, TideService, view
- [ ] Keep code clean for production

### Task 23: Release v2.0.0 (surf mode)
- [ ] Follow release checklist from structure.md
- [ ] Update all specs, README, CHANGELOG, store description
- [ ] Regenerate screenshots (shore + surf mode)
- [ ] Regenerate annotated diagrams for both modes
- [ ] Build and upload to Connect IQ

## Notes

- All changes went into existing files — no new `.mc` files created
- The `SurferWatchFaceBehaviorDelegate` class exists in `SurferWatchFaceView.mc` but is NOT used (watch faces can't receive button input)
- Double wrist gesture (onExitSleep timing) is the toggle mechanism instead
- Surf mode uses `surf_` prefixed Application.Storage keys to isolate cache from shore mode
- Solar intensity (`getSolarIntensityHistory`) may not be available on Instinct 2X — guarded with `has` check, falls back to null/empty arc
