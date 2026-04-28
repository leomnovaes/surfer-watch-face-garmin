# Memory Optimization — Implementation Plan

## Status: READY — execute in order, measure after each step

## Background

v1.0.2 works but is at the memory edge:
- Foreground: 55.3KB / 58.2KB peak (59.8KB max, 1.6KB headroom)
- Background: 21,056 used / 28,488 total (3,424 free before tide fetch)
- Adding new properties/strings breaks tide fetching (-403 OOM in background)
- Root cause: App class references DataManager, pulling 51 fields into background

## Tasks

### Phase 1 — Zero-risk quick wins

- [ ] 1. Enable compiler optimization -O2
  - [ ] 1.1 Add `project.optimization = 2` to `monkey.jungle`
  - [ ] 1.2 Build for Instinct 2X, measure foreground + background memory
  - [ ] 1.3 Compare against baseline (foreground: 55.3/58.2, background: 21,056 used)
  - Note: SDK 4.1.4+ compiler does constant folding, branch elimination automatically. May save 1-2KB with zero code changes.

- [ ] 2. Remove unused font files
  - [ ] 2.1 Delete all .fnt/.png files in resources/fonts/ not referenced by fonts.xml (29 files)
  - [ ] 2.2 Build and measure memory
  - Note: Confirmed 0.6KB foreground savings in previous testing.

- [ ] 3. Remove dead code
  - [ ] 3.1 Delete `drawIconHeart()` function (uses seg34IconsFont, never called — `drawHrHeart()` is the actual renderer)
  - [ ] 3.2 Build and measure memory

### Phase 2 — Architecture refactor (unblocks v1.1.0)

- [ ] 4. Refactor onBackgroundData to not reference DataManager
  - [ ] 4.1 Change `onBackgroundData()` to write received weather/swell data to Application.Storage with flag keys (e.g., `weatherDataReady=true`, `swellDataReady=true`)
  - [ ] 4.2 Tide data already uses this pattern (delegate writes to Storage, foreground reloads on `tideUpdated` flag) — no change needed for tide
  - [ ] 4.3 In DataManager or View's `onUpdate()`, check the flags and load data from Storage when set
  - [ ] 4.4 Remove all `dataManager.onWeatherData()`, `dataManager.onSurfWindData()`, `dataManager.onSwellData()` calls from the App
  - [ ] 4.5 Build and measure background memory — should see significant reduction
  - Note: This follows the Crystal Face pattern where onBackgroundData only writes to Storage.

- [ ] 5. Move onSettingsChanged logic to the View
  - [ ] 5.1 In App's `onSettingsChanged()`, just set a Storage flag (`settingsChanged=true`) and call `requestUpdate()`
  - [ ] 5.2 In View's `onUpdate()`, check the flag and handle: clear weather data, reload caches, recompute sunrise/sunset, reload clock font
  - [ ] 5.3 Remove all `dataManager.*` calls from App's `onSettingsChanged()`
  - [ ] 5.4 Build and measure

- [ ] 6. Remove DataManager field from App
  - [ ] 6.1 Remove `var dataManager as DataManager or Null` from the App class
  - [ ] 6.2 Remove `getDataManager()` from the App
  - [ ] 6.3 Create DataManager in the View's `onLayout()` or `initialize()` instead of `getInitialView()`
  - [ ] 6.4 Update View to access DataManager directly (it already does via `getApp().getDataManager()` — change to local field)
  - [ ] 6.5 Build and measure background memory — this is the big payoff
  - [ ] 6.6 Test tide fetching on Instinct 2X — should work now with more background free memory

- [ ] 7. Verify all functionality
  - [ ] 7.1 Shore mode: weather, tide, sunrise/sunset, all sensors
  - [ ] 7.2 Surf mode: swell, tide, wind, water temp, solar
  - [ ] 7.3 Settings changes: weather source switch, mode switch, clock font switch
  - [ ] 7.4 Background events: fire multiple, verify data flows correctly
  - [ ] 7.5 Memory: foreground and background within safe limits on Instinct 2X

### Phase 3 — Additional foreground optimizations

- [ ] 8. Single clock font loading
  - [ ] 8.1 Load only the selected clock font in `onLayout()`
  - [ ] 8.2 Add `reloadClockFont()` on View, triggered by settings change flag
  - [ ] 8.3 Build and measure (expect ~0.7KB savings)

### Phase 4 — v1.1.0 features (after refactor verified)

See `.kiro/specs/surf-mode/tasks.md` Phase 5 for feature tasks.
Each feature should be added incrementally with memory measurement after each step.
