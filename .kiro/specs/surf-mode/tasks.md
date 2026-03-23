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
- [ ] Rasterize proper tide direction icon for subscreen circle (currently "^"/"v" text)
- [ ] Rasterize proper thermometer icon for water temp (currently "T" text)
- [ ] Rasterize proper wave icon for swell height (currently "~" text)
- [ ] Tune double-gesture window from 10s to 4-5s after real watch testing
- [ ] Test swell data fetching with real StormGlass API key and SurfSpotLat/Lng

## Notes

- All changes went into existing files — no new `.mc` files created
- The `SurferWatchFaceBehaviorDelegate` class exists in `SurferWatchFaceView.mc` but is NOT used (watch faces can't receive button input)
- Double wrist gesture (onExitSleep timing) is the toggle mechanism instead
- Surf mode uses `surf_` prefixed Application.Storage keys to isolate cache from shore mode
- Solar intensity (`getSolarIntensityHistory`) may not be available on Instinct 2X — guarded with `has` check, falls back to null/empty arc
