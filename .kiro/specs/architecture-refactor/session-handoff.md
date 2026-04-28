# Architecture Refactor — Session Handoff

## Current State (commit bc7f1be)

Source code is working and verified on Instinct 2 simulator.

### What's done:
1. **onBackgroundData refactored** — App writes to Storage with flags, DataManager reads flags in `checkBackgroundFlags()` called from `onUpdate()`. Crystal Face pattern. Verified: tide=200, weather/swell display correctly.
2. **Sensor gating** — HR and stress only read in shore mode (surf doesn't display them).
3. **Unused fonts removed** — 30 files deleted, ~0.6KB saved.
4. **Dead code removed** — `drawIconHeart()` deleted.
5. **Debug print warning** — documented in steering that `System.println()` in background causes -403.

### What's NOT done:
1. **onSettingsChanged still calls DataManager directly** — v1.0.2 pattern. Attempted to refactor via Storage flag but hit a type comparison bug (`!=` on PropertyValueType vs StorageValueType throws "Unexpected Type Error" at runtime). Reverted.
2. **DataManager still on App class** — `var dataManager as DataManager or Null` field pulls DataManager type into background. Attempted to move to View but added too much code, causing foreground OOM.
3. **Single clock font loading** — not implemented yet.
4. **Mode-specific field nulling** — attempted, reverted (added too much code).

### Memory measurements (Instinct 2):
- Shore mode: 56.8KB used, 59.6KB peak (0.2KB headroom)
- Surf mode: 57.4KB used, 59.6KB peak
- Background free at start: ~7,400 bytes
- Background free before tide: ~4,300 bytes (after OWM weather fetch)
- Tide fetch: succeeds (code 200)

### Known bugs in current state:
- None in the committed code. The type error was in the reverted onSettingsChanged refactor.

## Architecture Vision (not yet implemented)

The ideal architecture for Garmin watch faces with background processes:

```
App (`:background`, thin shell):
  - onStart(): register background events
  - getServiceDelegate(): return delegate
  - getInitialView(): create View (no DataManager)
  - onBackgroundData(): write raw data to Storage + flags ← DONE
  - onSettingsChanged(): write flag to Storage ← NOT DONE (type bug)

DataManager (NOT `:background`, business logic):
  - Owns all data fields
  - checkBackgroundFlags(): reads Storage flags, processes data
  - updateSensorData(): reads sensors (gated by mode)
  - computeSunriseSunset(): separate from weather refresh
  - All business logic lives here

View (NOT `:background`, rendering only):
  - onLayout(): load fonts
  - onUpdate(): 
    1. Lazy-init DataManager on first tick
    2. dm.checkBackgroundFlags()
    3. dm.updateSensorData() (gated by mode)
    4. dm.computeXxx() for derived values
    5. Draw everything from dm fields
  - No business logic, just reads and draws

ServiceDelegate (`:background`):
  - onTemporalEvent(): fetch APIs, write to Storage, exit
  - No foreground class references
```

## Remaining Tasks for Next Session

### Priority 1: Fix the type comparison bug
The `!=` operator on `PropertyValueType` vs `StorageValueType` throws at runtime. The fix is to use `.equals()` or cast both to Number. But every code addition risks foreground OOM (0.2KB headroom). Need to find code to REMOVE before adding the fix.

### Priority 2: Move onSettingsChanged to Storage flag pattern
Same pattern as onBackgroundData. App sets flag, DataManager processes. But needs the type bug fixed first.

### Priority 3: Move DataManager from App to View
Remove `var dataManager` from App. Create in View's first `onUpdate()` (not `onLayout()` — fonts use too much stack). This is the payoff — removes DataManager from background binary.

### Priority 4: Simplify refreshWeatherOnBackgroundEvent
Split into: `computeSunriseSunset()` (called when GPS changes or daily), Garmin weather read (called when WeatherSource=0 on background events). Currently does too much and is called from too many places.

### Priority 5: Move per-tick computations to event-driven
- `computeMoonPhase()`: once per day or on background event, not per tick
- `checkCopyGPS()`: only on settings change, not per tick

### Priority 6: Single clock font loading
Load only the active font. Reload on settings change via flag.

### Priority 7: v1.1.0 features
Only after architecture is clean and memory has headroom.

## Key Learnings for Next Session

1. **Every line of code costs foreground memory.** We have 0.2KB headroom. Any fix must be paired with code removal elsewhere.
2. **`System.println()` in background allocates strings** — causes -403 OOM. Never use in background for production.
3. **`!=` on mixed Garmin types throws at runtime.** Use `.equals()` or cast both sides to the same type.
4. **`Application.Storage.setValue()` is flash I/O** — avoid per tick. Reading a boolean flag per tick is acceptable but minimize.
5. **`Application.Properties.getValue()` is in-memory** — safe per tick.
6. **Font loading in `onLayout()` uses stack memory** — don't do heavy work (DataManager init, sensor reads) in the same call.
7. **The Garmin compiler default is -O2** — manual constant inlining is unnecessary.
8. **Instinct 2 foreground: 59.8KB. Background: 28.5KB.** Both are tight.

## How to Clear Simulator Storage (for clean testing)
```bash
rm -f "$TMPDIR/com.garmin.connectiq/GARMIN/APPS/DATA/SURFERWATCHFACEINSTINCT2XSOLAR.DAT" \
      "$TMPDIR/com.garmin.connectiq/GARMIN/APPS/DATA/SURFERWATCHFACEINSTINCT2XSOLAR.IDX" \
      "$TMPDIR/com.garmin.connectiq/GARMIN/APPS/DATA/SURFERWATCHFACEINSTINCT2XSOLAR.IMT"
```
Then rebuild (F5). Settings are preserved, Storage is cleared.
