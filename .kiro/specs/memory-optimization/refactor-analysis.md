# Code Refactor Analysis — Memory & Architecture

## Current State (v1.0.2)
- Foreground: 55.3KB / 58.2KB peak (59.8KB max) — 1.6KB headroom
- Background: 21,056 used / 28,488 total — 7,416 free at start, 3,424 free before tide fetch
- Adding ANY new properties/strings/settings breaks tide fetching on Instinct 2/2X

## Issues Found — Ranked by Impact

### 1. CRITICAL: App class pulls DataManager into background (saves ~500+ bytes background)
**Impact**: Blocks all v1.1.0 features
**Risk**: Medium (architectural refactor)

The App class is `:background` annotated. It has `var dataManager as DataManager or Null` and calls 11 DataManager methods from `onBackgroundData()`, `onSettingsChanged()`, and `getInitialView()`. This pulls DataManager's entire type (41 public fields, 10 private fields, all methods) into the background process.

**Crystal Face pattern** (reference implementation): `onBackgroundData()` does NOT reference any foreground class. It writes received data directly to `Application.Storage` and calls `Ui.requestUpdate()`. The View reads from Storage on the next `onUpdate()`.

**Fix**: Refactor `onBackgroundData()` to write data to Storage instead of calling DataManager methods. The View/DataManager reads from Storage when data changes (flag-based, same pattern we already use for tide data). Move `onSettingsChanged()` logic to the View. The App becomes a thin shell: `getServiceDelegate()`, `onStart()`, `onBackgroundData()` (Storage writes only), `getInitialView()`.

**This is the #1 priority — nothing else matters until this is fixed.**

### ~~2. HIGH: Compiler optimization level not set~~ — REMOVED
**The default optimization level is already -O2.** Confirmed via Garmin forums: "The default is -O2." Our SDK 9.1.0 already applies constant folding, constant substitution, and branch elimination. No action needed.

### 3. HIGH: 30 unused font files in resources/fonts/ (saves ~0.6KB foreground)
**Impact**: Confirmed savings from our testing
**Risk**: None

29 font files (.fnt + .png) are not referenced by `fonts.xml` but are included in the build. Removing them saved 0.6KB in our testing.

**Fix**: Delete all font files not referenced by `fonts.xml`.

### 4. MEDIUM: Single clock font loading (saves ~0.7KB foreground)
**Impact**: Confirmed savings from our testing
**Risk**: Low (needs `reloadClockFont()` mechanism)

Both clock fonts (Saira 4.3KB + Rajdhani 4.0KB) are loaded in `onLayout()`. Only one is used at a time. Loading only the active one saved 0.7KB.

**Fix**: Load only the selected font in `onLayout()`. Add `reloadClockFont()` on the View, triggered from `onSettingsChanged()`. Requires the App to signal the View (via Storage flag or direct reference — but direct reference pulls View into background, so use Storage flag).

### 5. MEDIUM: Dead code (saves ~0.1KB)
**Impact**: Small but free
**Risk**: None

`drawIconHeart()` using `seg34IconsFont` is never called. `drawHrHeart()` using `heartIconFont` is the actual renderer.

**Fix**: Delete `drawIconHeart()`.

### 6. LOW: DataManager has 51 fields (41 public + 10 private)
**Impact**: Each field costs ~8-16 bytes. Currently amplified by issue #1 (fields pulled into background). After #1 is fixed, this becomes less critical.
**Risk**: Medium (requires careful analysis of which fields are needed)

Many fields could potentially be computed on the fly instead of cached:
- `tideCurveMinH`, `tideCurveMaxH`, `tideCurveHRange` — computed once when tide data changes, used only in `drawTideCurve()`
- `nextTideTime`, `nextTideType`, `currentTideHeight` — recomputed every tick anyway
- `owmFetchedAt` — read from Storage, could stay there

**Fix**: Defer until after issue #1 is resolved. Re-evaluate if still needed.

### ~~7. LOW: Inline constants~~ — REMOVED
~~Our testing showed only 0.1KB savings from inlining 46 constants.~~
**The compiler with `-O2` handles constant folding, constant substitution, and branch elimination automatically.** Manual inlining is unnecessary and reduces readability. Do not inline constants — use `private static const` for layout values and let the compiler optimize.

### 7. INFO: Sensor gating (no memory savings, prevents OOM on specific configs)
**Impact**: Required for v1.1.0 body battery feature
**Risk**: Low

Reading unused sensors (HR in surf mode, stress when arc shows solar) wastes SensorHistory iterator allocations. Gating prevents OOM when multiple SensorHistory reads would overlap.

**Fix**: Gate sensors by mode and setting. Already designed and tested — see steering/tech.md Sensor Gating Rules.

## Recommended Execution Order

1. **Remove unused font files** (confirmed 0.6KB foreground savings)
2. **Remove dead code** (confirmed 0.1KB foreground savings)
3. **Refactor App to not reference DataManager** (the big one — unblocks v1.1.0)
   - Step 3a: Make `onBackgroundData()` write to Storage only (no DataManager calls)
   - Step 3b: Make View/DataManager read from Storage on flag change
   - Step 3c: Move `onSettingsChanged()` logic to View
   - Step 3d: Remove `dataManager` field from App
   - Step 3e: Measure background memory — should be significantly lower
4. **Single clock font loading** (confirmed 0.7KB foreground savings)
5. **Implement v1.1.0 features** with continuous memory monitoring

Note: Compiler -O2 is already the default — no action needed. Manual constant inlining is unnecessary.

## Reference Architecture (Crystal Face pattern)

```
App (`:background`, thin shell):
  - getServiceDelegate() → returns BackgroundService
  - onBackgroundData(data) → writes to Storage, calls requestUpdate()
  - getInitialView() → creates View (no DataManager reference)
  - onSettingsChanged() → writes flag to Storage, calls requestUpdate()

View (NOT `:background`):
  - onUpdate() → checks Storage flags, loads data if changed
  - Owns DataManager or handles data directly
  - All foreground logic lives here

BackgroundService (`:background`):
  - onTemporalEvent() → fetches data, writes to Storage, calls exit()
  - No foreground class references
```


## Additional Findings — Data Held in Memory Unnecessarily

### Mode-specific fields always allocated (both modes)

DataManager has 51 fields total:
- 12 shore-only fields (weather, HR, stress, notifications, etc.)
- 22 surf-only fields (swell, surf wind, water temp, solar, tide curve, 6 forecast cache arrays)
- 17 shared fields (tide, moon, battery, GPS, etc.)

**In shore mode**: 22 surf-only fields are allocated and may hold stale data from a previous surf session. The 6 forecast cache arrays (`_swellHeightsCache`, etc.) each hold 24-element arrays — that's significant memory for data that's never displayed.

**In surf mode**: 12 shore-only fields hold stale weather/HR/stress data.

**Recommendation**: When switching modes, null out the inactive mode's fields to free memory. The `loadSurfCache()` and `loadShoreCache()` methods already reload the active mode's data — they should also clear the other mode's fields. This is a low-risk change.

### Per-tick reads not gated by mode (v1.0.2)

In surf mode, `updateSensorData()` reads:
- **HR** (Activity.getActivityInfo) — not displayed in surf mode. Low cost but unnecessary.
- **Stress** (SensorHistory.getStressHistory) — not displayed in surf mode. HIGH cost (SensorHistory iterator).
- **Notifications** — not displayed in surf mode. Negligible cost (same getDeviceSettings call as BT).

**Recommendation**: Gate HR and stress to shore mode only. Already designed in the Sensor Gating Rules (steering/tech.md). This was tested and works — just needs to be applied to v1.0.2 base.

### checkCopyGPS() runs every tick in surf mode

Reads `Properties.getValue("CopyGPSToSurfSpot")` every tick. This is a one-shot action that only fires when the user toggles the setting. Could be moved to `onSettingsChanged()` only.

**Recommendation**: Low priority — Properties reads are in-memory and cheap.

### Background delegate patterns — OK

The delegate correctly:
- Reads from Storage/Properties (14 reads, 13 Properties reads)
- Writes results to Storage (14 writes)
- Chains API calls sequentially (swell → tide → wind)
- Has -403 guard to stop chain on memory exhaustion

No issues found with the delegate pattern itself. The problem is purely that the App class pulls DataManager into the background.

### Forecast arrays loaded on startup regardless of mode

`DataManager.initialize()` calls `loadTideData()` and `loadWeatherData()` unconditionally. If the user is in surf mode, shore tide/weather data is loaded unnecessarily (and vice versa).

**Recommendation**: Load only the active mode's data on startup. Already partially done — `getInitialView()` calls `loadSurfCache()` if in surf mode. But `initialize()` always loads shore data first. Could be optimized.
