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

### 2. HIGH: Compiler optimization level not set (saves ~1-2KB code, both foreground and background)
**Impact**: Free code size reduction
**Risk**: None

The Garmin compiler (SDK 4.1.4+) has built-in optimization levels: `-O0` (none) to `-O2` (release). Our `monkey.jungle` has no optimization setting, so we're using the default. Setting `-O2` enables constant folding, constant substitution, branch elimination — exactly the optimizations we tried to do manually by inlining constants.

**Fix**: Add `project.optimization = 2` to `monkey.jungle`. This is a one-line change with zero risk. It may also make our manual constant inlining unnecessary.

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

1. **Set compiler optimization to -O2** (1 line, zero risk, may save 1-2KB)
2. **Remove unused font files** (confirmed 0.6KB savings)
3. **Remove dead code** (confirmed 0.1KB savings)
4. **Refactor App to not reference DataManager** (the big one — unblocks v1.1.0)
   - Step 4a: Make `onBackgroundData()` write to Storage only (no DataManager calls)
   - Step 4b: Make View/DataManager read from Storage on flag change
   - Step 4c: Move `onSettingsChanged()` logic to View
   - Step 4d: Remove `dataManager` field from App
   - Step 4e: Measure background memory — should be significantly lower
5. **Single clock font loading** (confirmed 0.7KB savings)
6. **Implement v1.1.0 features** with continuous memory monitoring

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
