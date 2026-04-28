# Memory Optimization — Implementation Plan

## Status: READY — execute in order, measure after each step

## Background

v1.0.2 works but is at the memory edge:
- Foreground: 55.3KB / 58.2KB peak (59.8KB max, 1.6KB headroom)
- Background: 21,056 used / 28,488 total (3,424 free before tide fetch)
- Adding new properties/strings breaks tide fetching (-403 OOM in background)
- Root cause: App class references DataManager, pulling 51 fields into background
- Compiler optimization -O2 is already the default — no gains from changing it

## Baseline Measurements (v1.0.2, Instinct 2X simulator)

| Metric | Where to measure | v1.0.2 value |
|--------|-----------------|--------------|
| Foreground used | View > Memory, idle shore mode | 55.3 KB |
| Foreground peak | View > Memory, after background events + GPS set | 58.2 KB |
| Foreground max | View > Memory (device limit) | 59.8 KB |
| BG used at start | Console: `System.getSystemStats().usedMemory` in `onTemporalEvent()` | 21,056 bytes |
| BG free at start | Console: `System.getSystemStats().freeMemory` in `onTemporalEvent()` | 7,416 bytes |
| BG free before tide | Console: `System.getSystemStats().freeMemory` in `startTideFetch()` | 3,424 bytes |
| BG total | Console: `System.getSystemStats().totalMemory` | 28,488 bytes |
| Tide fetch result | Console: response code from `onTideResponse()` | 200 (success) |

## Tasks

### Phase 1 — Quick wins (no architecture changes)

- [ ] 1. Remove unused font files
  - [ ] 1.1 Delete all .fnt/.png files in resources/fonts/ not referenced by fonts.xml (29 files)
  - [ ] 1.2 Build for Instinct 2X
  - [ ] 1.3 USER: Measure foreground memory (View > Memory, idle shore mode)
  - [ ] 1.4 USER: Add debug prints to delegate (`System.getSystemStats().freeMemory`), fire background event, record BG memory
  - Note: Confirmed 0.6KB foreground savings in previous testing.

- [ ] 2. Remove dead code
  - [ ] 2.1 Delete `drawIconHeart()` function (uses seg34IconsFont, never called)
  - [ ] 2.2 Build for Instinct 2X
  - [ ] 2.3 USER: Measure foreground memory

- [ ] 3. Phase 1 checkpoint
  - [ ] 3.1 USER: Full test — shore mode, surf mode, background events, tide fetch, weather
  - [ ] 3.2 USER: Record Phase 1 measurements (foreground + background)
  - [ ] 3.3 USER: Fire background event on surf mode with swell + tide, verify tide still succeeds (response code 200)
  - Note: Phase 1 saves foreground memory only. Background -403 issue remains — proceed to Phase 2.

### Phase 2 — Architecture refactor (unblocks v1.1.0)

The App class (`:background`) references DataManager through `var dataManager` field and 11 method calls. This pulls DataManager's 51 fields into the background process, consuming ~500+ bytes. The fix follows the Crystal Face pattern: App writes to Storage, View reads from Storage.

- [ ] 4. Refactor onBackgroundData to not reference DataManager
  - [ ] 4.1 In `onBackgroundData()`, write weather data to Storage: `Storage.setValue("bgWeatherData", weatherDict)` + `Storage.setValue("bgWeatherReady", true)`
  - [ ] 4.2 Write swell data to Storage with flag: `Storage.setValue("bgSwellData", swellDict)` + `Storage.setValue("bgSwellReady", true)`
  - [ ] 4.3 Tide already uses Storage pattern — no change needed
  - [ ] 4.4 Remove surf mode branching from `onBackgroundData()` — just write raw data, let the View decide how to route it
  - [ ] 4.5 In DataManager, add `checkBackgroundDataFlags()` method that checks flags and loads from Storage when set
  - [ ] 4.6 Call `checkBackgroundDataFlags()` from `onUpdate()` (runs every tick, flags only set on BG events so no I/O per tick — just a Storage.getValue of a boolean)
  - [ ] 4.7 Build and verify: fire background event, check weather/swell/tide display
  - [ ] 4.8 USER: Measure background memory — compare against Phase 1

- [ ] 5. Move onSettingsChanged logic to the View
  - [ ] 5.1 In App's `onSettingsChanged()`, just set `Storage.setValue("settingsChanged", true)` and call `requestUpdate()`
  - [ ] 5.2 In View's `onUpdate()` (or helper), check flag and handle: clear weather, reload caches, recompute sunrise/sunset
  - [ ] 5.3 Remove all `dataManager.*` calls from App's `onSettingsChanged()`
  - [ ] 5.4 Build and verify: change settings (weather source, surf mode, clock font), confirm updates
  - [ ] 5.5 USER: Measure background memory

- [ ] 6. Remove DataManager field from App
  - [ ] 6.1 Remove `var dataManager as DataManager or Null` from the App class
  - [ ] 6.2 Remove `getDataManager()` from the App
  - [ ] 6.3 Create DataManager in the View (field on View, initialized in `onLayout()`)
  - [ ] 6.4 Update View to use its own DataManager field instead of `getApp().getDataManager()`
  - [ ] 6.5 Remove `getInitialView()` DataManager initialization logic — move to View
  - [ ] 6.6 Build for Instinct 2X
  - [ ] 6.7 USER: Measure background memory — this is the big payoff
  - [ ] 6.8 USER: Fire background event with swell + tide, verify tide succeeds (response code 200)

- [ ] 7. Phase 2 checkpoint
  - [ ] 7.1 USER: Full test — shore mode, surf mode, all background events, all settings changes
  - [ ] 7.2 USER: Record final measurements (foreground + background)
  - [ ] 7.3 Compare BG free before tide against baseline (was 3,424 in v1.0.2 — should be higher now)
  - [ ] 7.4 Verify no regressions: weather, tide, swell, wind, sunrise/sunset all display correctly
  - [ ] 7.5 Test on Instinct 3 as well — verify no regressions on CIQ 4.x+

### Phase 3 — Additional foreground optimizations

- [ ] 8. Single clock font loading
  - [ ] 8.1 Load only the selected clock font in `onLayout()`
  - [ ] 8.2 Signal font reload via Storage flag from `onSettingsChanged()` (already refactored in Phase 2)
  - [ ] 8.3 View checks flag and reloads font
  - [ ] 8.4 Build and measure (expect ~0.7KB foreground savings)

### Phase 4 — v1.1.0 features (after refactor verified)

See `.kiro/specs/surf-mode/tasks.md` Phase 5 for feature tasks.
Each feature added incrementally with memory measurement after each step.
Ensure background memory is checked when adding new properties/strings.
