# Memory Optimization — Implementation Plan

## Status: READY — execute in order, measure after each step

## Background

v1.0.2 works but is at the memory edge:
- Foreground: 55.3KB / 58.2KB peak (59.8KB max, 1.6KB headroom)
- Background: 21,056 used / 28,488 total (3,424 free before tide fetch)
- Adding new properties/strings breaks tide fetching (-403 OOM in background)
- Root cause: App class references DataManager, pulling 51 fields into background

## Baseline Measurements (v1.0.2, Instinct 2X simulator)

Record these BEFORE making any changes. All measurements on Instinct 2X (`instinct2x`).

| Metric | Where to measure | v1.0.2 value |
|--------|-----------------|--------------|
| Foreground used | View > Memory, idle shore mode | 55.3 KB |
| Foreground peak | View > Memory, after background events + GPS set | 58.2 KB |
| Foreground max | View > Memory (device limit) | 59.8 KB |
| Background used at start | Console: `System.getSystemStats().usedMemory` in `onTemporalEvent()` | 21,056 bytes |
| Background free at start | Console: `System.getSystemStats().freeMemory` in `onTemporalEvent()` | 7,416 bytes |
| Background free before tide | Console: `System.getSystemStats().freeMemory` in `startTideFetch()` | 3,424 bytes |
| Background total | Console: `System.getSystemStats().totalMemory` | 28,488 bytes |
| Tide fetch result | Console: response code from `onTideResponse()` | 200 (success) |

## Tasks

### Phase 1 — Zero-risk quick wins

- [ ] 1. Enable compiler optimization -O2
  - [ ] 1.1 Add `project.optimization = 2` to `monkey.jungle`
  - [ ] 1.2 Build for Instinct 2X
  - [ ] 1.3 USER: Measure foreground memory (View > Memory, idle shore mode)
  - [ ] 1.4 USER: Add debug prints to delegate, fire background event, measure background memory
  - [ ] 1.5 USER: Fire background event with StormGlass key + GPS set, verify tide fetch succeeds (response code 200)
  - [ ] 1.6 Record all measurements, compare against baseline
  - Note: SDK 4.1.4+ compiler does constant folding, branch elimination. May save 1-2KB with zero code changes. If this alone fixes the background -403, Phase 2 may be less urgent.

- [ ] 2. Remove unused font files
  - [ ] 2.1 Delete all .fnt/.png files in resources/fonts/ not referenced by fonts.xml (29 files identified)
  - [ ] 2.2 Build for Instinct 2X
  - [ ] 2.3 USER: Measure foreground memory, compare against task 1 result
  - Note: Confirmed 0.6KB foreground savings in previous testing. May also reduce background code size.

- [ ] 3. Remove dead code
  - [ ] 3.1 Delete `drawIconHeart()` function (uses seg34IconsFont, never called)
  - [ ] 3.2 Build for Instinct 2X
  - [ ] 3.3 USER: Measure foreground memory, compare against task 2 result

- [ ] 4. Phase 1 checkpoint
  - [ ] 4.1 USER: Full test — shore mode, surf mode, background events, tide fetch, weather
  - [ ] 4.2 USER: Record final Phase 1 measurements (foreground + background)
  - [ ] 4.3 USER: Fire background event on surf mode with swell + tide, check if tide succeeds now
  - [ ] 4.4 Decision: if tide fetch now succeeds (-O2 freed enough background memory), Phase 2 may be deferred. If still -403, proceed to Phase 2.

### Phase 2 — Architecture refactor (unblocks v1.1.0)

Only proceed if Phase 1 checkpoint shows tide still fails with -403.

- [ ] 5. Refactor onBackgroundData to not reference DataManager
  - [ ] 5.1 Change `onBackgroundData()` to write received weather data to Storage with a flag key (e.g., `Storage.setValue("bgWeatherData", weatherDict)` + `Storage.setValue("bgDataReady", true)`)
  - [ ] 5.2 Swell data: same pattern — write to Storage with flag
  - [ ] 5.3 Tide data already uses this pattern (delegate writes to Storage, foreground reloads on `tideUpdated` flag) — no change needed
  - [ ] 5.4 In DataManager, add a method to check flags and load from Storage (called from `onUpdate()` or on background event)
  - [ ] 5.5 Remove all `dataManager.onWeatherData()`, `dataManager.onSurfWindData()`, `dataManager.onSwellData()` calls from the App
  - [ ] 5.6 Build and verify data still flows: fire background event, check weather/swell/tide display
  - [ ] 5.7 USER: Measure background memory — compare against Phase 1 checkpoint

- [ ] 6. Move onSettingsChanged logic to the View
  - [ ] 6.1 In App's `onSettingsChanged()`, just set `Storage.setValue("settingsChanged", true)` and call `requestUpdate()`
  - [ ] 6.2 In View's `onUpdate()` (or a helper called from it), check the flag and handle: clear weather data, reload caches, recompute sunrise/sunset, reload clock font
  - [ ] 6.3 Remove all `dataManager.*` calls from App's `onSettingsChanged()`
  - [ ] 6.4 Build and verify: change settings (weather source, surf mode, clock font), confirm everything updates correctly
  - [ ] 6.5 USER: Measure background memory

- [ ] 7. Remove DataManager field from App
  - [ ] 7.1 Remove `var dataManager as DataManager or Null` from the App class
  - [ ] 7.2 Remove `getDataManager()` from the App
  - [ ] 7.3 Create DataManager in the View (e.g., in `onLayout()` or as a field initialized in `initialize()`)
  - [ ] 7.4 Update View to access DataManager as its own field instead of `getApp().getDataManager()`
  - [ ] 7.5 Build for Instinct 2X
  - [ ] 7.6 USER: Measure background memory — this is the big payoff, DataManager type no longer in background
  - [ ] 7.7 USER: Fire background event with swell + tide, verify tide fetch succeeds (response code 200)

- [ ] 8. Phase 2 checkpoint
  - [ ] 8.1 USER: Full test — shore mode, surf mode, all background events, all settings changes
  - [ ] 8.2 USER: Record final measurements (foreground + background)
  - [ ] 8.3 Compare background free memory before tide fetch against baseline (was 3,424 in v1.0.2)
  - [ ] 8.4 Verify no regressions: weather, tide, swell, wind, sunrise/sunset all display correctly

### Phase 3 — Additional foreground optimizations

- [ ] 9. Single clock font loading
  - [ ] 9.1 Load only the selected clock font in `onLayout()`
  - [ ] 9.2 Signal font reload via Storage flag from `onSettingsChanged()` (already refactored in Phase 2)
  - [ ] 9.3 View checks flag and calls `reloadClockFont()` 
  - [ ] 9.4 Build and measure (expect ~0.7KB foreground savings)

### Phase 4 — v1.1.0 features (after refactor verified)

See `.kiro/specs/surf-mode/tasks.md` Phase 5 for feature tasks.
Each feature added incrementally with memory measurement after each step.
Ensure background memory is checked when adding new properties/strings.
