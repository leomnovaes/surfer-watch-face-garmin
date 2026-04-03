# Memory Optimization — Implementation Plan

## Status: ON HOLD — v1.1.0 features blocked until background memory issue resolved

## Key Findings

### Foreground Memory (Instinct 2X, 59.8KB max)
- v1.0.2 baseline: 55.3KB used, 58.2KB peak (1.6KB headroom)
- After optimizations (dead code, single clock font, inline constants, font cleanup): 53.8KB used, 56.6KB peak (3.2KB headroom)
- v1.1.0 features add ~2.2KB code — fits in foreground with optimizations

### Background Memory (28,488 bytes total)
- v1.0.2: 21,056 used, 7,416 free at start, 3,424 free before tide fetch
- v1.1.0 (any changes): 21,536+ used, 6,936 free at start, 2,936 free before tide fetch
- Tide JSON parsing needs >3KB — fails with -403 (NETWORK_RESPONSE_OUT_OF_MEMORY) at 2.9KB free
- **Root cause**: Any new properties/strings/settings increase the compiled app size, which reduces background free memory. The App class is `:background` and pulls in all referenced types.
- **The swell fetch consumes ~4.5KB** in the background before tide fetch starts. This was already marginal in v1.0.2 (3.4KB free) and any code additions push it over.

### Confirmed Working Optimizations (foreground only)
- [x] Remove dead code: `drawIconHeart()` — saves ~0.1KB
- [x] Load only active clock font — saves ~0.7KB
- [x] Inline 46 `private static const` as literals — saves ~0.1KB
- [x] Remove 30 unused font files from resources/fonts/ — saves ~0.6KB
- [x] Trim crystal-icons from 17 to 3 glyphs — no measurable savings (Garmin may use fixed texture size)

### Attempted But Failed (background memory)
- [ ] Move DataManager to Globals module — added 80 bytes overhead, didn't help
- [ ] Remove bodyBattery field + helper functions — no change (overhead is from properties/strings, not DataManager fields)
- [ ] Untyped Globals var — no change (compiler still resolves types from App method calls)

### Unresolved: Background Memory Architecture
The fundamental issue is that the App class (`:background`) references DataManager through its methods (`onBackgroundData`, `onSettingsChanged`, `getInitialView`). This pulls DataManager's type into the background process. Every new property/string/setting increases the compiled app size and reduces background free memory.

Possible solutions (not yet attempted):
1. **Reduce swell memory in background** — store only current hour values instead of full 24h arrays, freeing ~3KB for tide. Tradeoff: loses offline hourly swell advancement.
2. **Refactor App to not reference DataManager** — move all foreground logic to the View, use Storage flags for background→foreground communication. Big refactor, risk of I/O-per-tick regression.
3. **Split swell and tide into separate background cycles** — fetch swell on one temporal event, tide on the next. Doubles the time to get both datasets but avoids memory contention.
4. **Use Prettier Monkey C optimizer** — community tool that does constant inlining, dead code removal, constant folding automatically. May reduce compiled code size enough.

## WARNING: Do NOT implement v1.1.0 features without resolving the background memory issue first.
Adding any new properties, strings, or settings will increase background memory usage and break tide fetching on Instinct 2/2X.
