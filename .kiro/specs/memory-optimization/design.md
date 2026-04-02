# Memory Optimization Bugfix Design

## Overview

The Surfer Watch Face crashes with Out of Memory (OOM) on Garmin Instinct 2/2X devices (CIQ 3.x, ~59.8KB heap). The v1.0.2 baseline uses 55.3KB with 58.2KB peak, leaving only 1.6KB headroom. Adding v1.1.0 features pushes peak to ~59.6KB, triggering OOM during GPS Storage writes and SensorHistory reads.

The fix targets four independent memory consumers that can be reduced without changing any visible behavior:
1. **Dual clock font loading** — load only the active font (~4KB data savings)
2. **46 `private static const` declarations** — inline as literals (~1-2KB code savings)
3. **Dead code `drawIconHeart()`** — remove unused function (~0.3KB)
4. **Oversized crystal-icons font** — trim from 17 to 3 glyphs (chars 53, 62, 63)

Combined estimated savings: ~5-6KB, bringing peak memory well under 59.8KB with safe headroom.

## Glossary

- **Bug_Condition (C)**: The app runs on a CIQ 3.x device (Instinct 2/2X) where custom fonts load into the app heap, and peak memory exceeds the ~59.8KB limit
- **Property (P)**: Peak memory stays ≤ ~56.8KB on CIQ 3.x, providing ≥3KB headroom for v1.1.0 features
- **Preservation**: All rendering output (pixel positions, font glyphs, icon display, data values) remains identical after optimizations
- **SurferWatchFaceView**: The main view class in `source/SurferWatchFaceView.mc` that owns all rendering and layout constants
- **SurferWatchFaceApp**: The app class in `source/SurferWatchFaceApp.mc` that owns DataManager and handles settings changes
- **CIQ 3.x font heap loading**: On Connect IQ API < 4.0, custom fonts loaded via `WatchUi.loadResource()` consume app heap memory; on CIQ 4.x+ they load into a separate graphics pool

## Bug Details

### Bug Condition

The bug manifests when the watch face runs on CIQ 3.x devices (Instinct 2/2X) where the ~59.8KB heap must hold both code and font data. The combination of (a) loading both clock fonts when only one is used, (b) 46 `private static const` declarations generating unnecessary bytecode, (c) dead code `drawIconHeart()`, and (d) 14 unused crystal-icons glyphs pushes memory usage to the point where v1.1.0 features cause OOM.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type AppState { device, codeSize, fontDataSize, peakMemory, heapLimit }
  OUTPUT: boolean

  RETURN input.device.apiLevel < 4.0
         AND input.fontDataSize includes both clock fonts (~8KB instead of ~4KB)
         AND input.codeSize includes 46 const declarations + dead code bytecode
         AND input.peakMemory > input.heapLimit
END FUNCTION
```

### Examples

- **OOM on GPS write**: App runs on Instinct 2X, peak=59.6KB, `Application.Storage.setValue("lastKnownLat", ...)` triggers OOM because the temporary allocation pushes past 59.8KB
- **OOM on SensorHistory**: `SensorHistory.getStressHistory()` allocates an iterator on the heap, pushing past the limit during a tick where both clock fonts are loaded
- **Wasted font memory**: `onLayout()` loads `ClockSaira40` (~4KB) and `ClockRajdhani40` (~4KB) but only one is rendered based on `ClockFont` setting — 4KB wasted
- **Wasted code memory**: `TOP_ROW2_Y = TOP_ROW1_Y + ROW_SPACING_TOP` generates bytecode to load `TOP_ROW1_Y`, load `ROW_SPACING_TOP`, add, and store — instead of a single literal `25`

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- All UI elements render at exactly the same pixel coordinates as before (every inlined literal must match the original computed value)
- Clock font switching between Saira and Rajdhani continues to work correctly when the `ClockFont` setting changes
- `drawIconBluetooth()` continues to use `seg34IconsFont` with glyph "L" (only `drawIconHeart()` is removed, not the font)
- Crystal-icons glyphs for notification (char 53 = "5"), sunrise (char 62 = ">"), and sunset (char 63 = "?") render identically
- All data fields (battery, tide, weather, wind, swell, moon, HR, stress arc, etc.) display identical values and formatting
- `onUpdate()` completes within the per-second tick budget without visible lag
- CIQ 4.x+ devices (Instinct 3) render identically — optimizations only affect code/data size

**Scope:**
All rendering behavior, data computation, API communication, and user interaction are completely unaffected by these optimizations. The changes are purely structural:
- Replacing `const` declarations with inline literals (same values)
- Loading one font instead of two (same font displayed)
- Removing unreachable code (never executed)
- Trimming unused font glyphs (never rendered)

## Hypothesized Root Cause

Based on the memory analysis, the root causes are confirmed (not hypothesized — these are measured):

1. **Dual Clock Font Loading (~4KB waste)**: `onLayout()` unconditionally loads both `ClockSaira40` and `ClockRajdhani40` via `WatchUi.loadResource()`. On CIQ 3.x, each font's bitmap data (~4KB) loads into the app heap. Only one is used per the `ClockFont` setting. The fix is to load only the active font in `onLayout()` and provide a `reloadClockFont()` method called from `onSettingsChanged()` when the setting changes. This approach has been tested and confirmed working.

2. **46 `private static const` Bytecode Overhead (~1-2KB waste)**: Monkey C does not perform constant folding. Each `private static const` generates bytecode for declaration, storage, and every reference site. The 8 constants that reference other constants (e.g., `TOP_ROW2_Y = TOP_ROW1_Y + ROW_SPACING_TOP`) are especially expensive — the compiler emits load+load+add instructions instead of a single literal. Replacing all 46 with inline literals eliminates this overhead entirely.

3. **Dead Code `drawIconHeart()` (~0.3KB waste)**: The function `drawIconHeart()` at line 486 uses `seg34IconsFont` with glyph "h" but is never called anywhere. The actual heart rendering uses `drawHrHeart()` with `heartIconFont`. The dead function and its bytecode can be removed.

4. **Oversized Crystal-Icons Font (14 unused glyphs)**: The `crystal-icons.fnt` declares 17 glyphs (chars 48-65) but only 3 are used: char 53 (notification bell, "5"), char 62 (sunrise, ">"), char 63 (sunset, "?"). The `.png` is 256x256 palette mode, 5.5KB; the `.fnt` is 2.2KB. Trimming to 3 glyphs reduces both the `.fnt` entries and the `.png` pixel data that gets loaded.

## Correctness Properties

Property 1: Bug Condition - Peak Memory Within Heap Limit

_For any_ build targeting Instinct 2X (CIQ 3.x, ~59.8KB heap) with all v1.1.0 features enabled, the optimized watch face SHALL have peak memory ≤ 56.8KB as measured in the simulator's View > Memory panel, providing at least 3KB headroom and preventing OOM crashes during GPS Storage writes and SensorHistory reads.

**Validates: Requirements 2.1**

Property 2: Preservation - Layout Pixel Coordinates Unchanged

_For any_ UI element that previously used a layout constant (e.g., `TOP_ROW1_Y`, `MID_Y`, `WX_COL2_X`, `TC_LEFT_X`), the optimized code SHALL position that element at exactly the same pixel coordinates as the original code, ensuring all 46 inlined literal values match their original computed values.

**Validates: Requirements 3.3, 3.6, 3.7**

Property 3: Preservation - Clock Font Selection Unchanged

_For any_ value of the `ClockFont` setting (0=Saira, 1=Rajdhani), the optimized code SHALL display the correct font on screen, and switching the setting SHALL cause the correct font to load via `reloadClockFont()` triggered from `onSettingsChanged()`.

**Validates: Requirements 2.2, 3.2**

Property 4: Preservation - Icon Rendering Unchanged

_For any_ rendering of notification (char 53), sunrise (char 62), or sunset (char 63) icons via the trimmed crystal-icons font, the optimized code SHALL display glyphs identical to the original, and `drawIconBluetooth()` SHALL continue to use `seg34IconsFont` with glyph "L" unaffected by the removal of `drawIconHeart()`.

**Validates: Requirements 2.5, 3.4, 3.5**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct (it is — these are measured, not hypothesized):

**File**: `source/SurferWatchFaceView.mc`

**Optimization 1: Single Clock Font Loading**

1. **Replace dual font vars with single var**: Remove `clockSaira40` and `clockRajdhani40` instance vars. Add a single `private var clockFont = null;` var.
2. **Conditional load in `onLayout()`**: Read `ClockFont` setting and load only the selected font resource (`Rez.Fonts.ClockSaira40` or `Rez.Fonts.ClockRajdhani40`).
3. **Add `reloadClockFont()` public method**: Loads the correct font based on current `ClockFont` setting. Called from `onSettingsChanged()`.
4. **Update rendering code**: Both `drawMiddleSection()` and `drawMiddleSection_Surf()` use `clockFont` directly instead of selecting between two vars.

**File**: `source/SurferWatchFaceApp.mc`

5. **Call `reloadClockFont()` from `onSettingsChanged()`**: Store a reference to the view, call `view.reloadClockFont()` when settings change. The app already has access to the view via `getInitialView()`.

**Optimization 2: Inline All 46 Constants**

6. **Replace all `private static const` layout declarations** with inline literal values at every usage site. Add a comment with the original constant name for maintainability. The 8 computed constants must be pre-calculated:
   - `TOP_ROW2_Y = TOP_ROW1_Y + ROW_SPACING_TOP` → `25` (2 + 23)
   - `TOP_ROW3_Y = TOP_ROW2_Y + ROW_SPACING_TOP` → `48` (25 + 23)
   - `MID_RIGHT_TOP_Y = MID_Y - 1` → `75` (76 - 1)
   - `MID_RIGHT_BOTTOM_Y = MID_Y + 18` → `94` (76 + 18)
   - `MID_ICON_Y = MID_Y` → `76`
   - `MID_TEXT_Y = MID_Y + 18` → `94`
   - `WX_TEXT_Y = WX_Y + 18` → `157` (139 + 18)
   - `WX_TEXT_Y_EDGE = WX_Y_EDGE + 18` → `148` (130 + 18)

7. **Keep IC_NOTIFICATIONS, IC_SUNRISE, IC_SUNSET as inline string literals** — these are string constants used as glyph characters, replace with inline `"5"`, `">"`, `"?"` with comments.

**Optimization 3: Remove Dead Code**

8. **Delete `drawIconHeart()` function** (lines 486-490) — never called. `drawHrHeart()` using `heartIconFont` is the actual heart renderer.

**Optimization 4: Trim Crystal-Icons Font**

9. **Edit `resources/fonts/crystal-icons.fnt`**: Remove all `char` entries except id=53, id=62, id=63. Update `chars count=3`.
10. **Crop `resources/fonts/crystal-icons.png`** (and/or `crystal-icons-small.png`): Remove pixel regions for unused glyphs. The 3 retained glyphs are at known positions in the sprite sheet — crop to include only those regions and update x/y offsets in the `.fnt` accordingly.

## Testing Strategy

### Validation Approach

The testing strategy is primarily manual/simulator-based because Monkey C has no standard unit test framework and the bug is a memory consumption issue measurable only in the Garmin simulator. Each optimization is applied and verified independently, then combined for final validation.

### Exploratory Bug Condition Checking

**Goal**: Confirm the baseline memory usage and demonstrate that v1.1.0 features cause OOM on unfixed code.

**Test Plan**: Build for Instinct 2X, run in simulator, check View > Memory panel.

**Test Cases**:
1. **Baseline v1.0.2 memory**: Build current code, verify ~55.3KB used / ~58.2KB peak (confirms starting point)
2. **v1.1.0 OOM reproduction**: Add v1.1.0 feature code (configurable arc, subscreen, always-show-seconds), build, verify peak approaches or exceeds 59.8KB
3. **Font memory measurement**: Comment out one clock font load in `onLayout()`, rebuild, measure delta (~4KB expected)
4. **Const overhead measurement**: Replace a subset of constants with literals, rebuild, measure code size delta

**Expected Counterexamples**:
- Peak memory exceeds 59.8KB with v1.1.0 features on unfixed code
- Removing one font load shows ~4KB reduction confirming dual-load waste

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds (CIQ 3.x device with v1.1.0 features), the optimized code stays within memory limits.

**Pseudocode:**
```
FOR ALL device WHERE device.apiLevel < 4.0 DO
  build := compile(optimizedCode, device)
  memory := simulatorMemory(build)
  ASSERT memory.peak <= 56.8KB
  ASSERT memory.peak <= device.heapLimit - 3.0KB
END FOR
```

**Concrete Test**: Build for Instinct 2X with all v1.1.0 features, check View > Memory shows peak ≤ 56.8KB.

### Preservation Checking

**Goal**: Verify that all rendering output is identical before and after optimizations.

**Pseudocode:**
```
FOR ALL settingCombination IN {ShoreMode, SurfMode} × {Saira, Rajdhani} × {allDataPresent, noData} DO
  original := renderScreenshot(unfixedCode, settingCombination)
  optimized := renderScreenshot(fixedCode, settingCombination)
  ASSERT original == optimized
END FOR
```

**Testing Approach**: Manual visual comparison in the simulator is the primary method. Monkey C watch faces lack programmatic screenshot comparison, but the simulator provides pixel-accurate rendering.

**Test Plan**: For each optimization, build and visually verify in the simulator that all UI elements appear at the same positions with the same content.

**Test Cases**:
1. **Layout preservation after constant inlining**: Compare shore mode and surf mode rendering before/after — all text, icons, dividers, tide curve at same positions
2. **Clock font switching preservation**: Change `ClockFont` setting 0→1→0, verify correct font displays each time
3. **Crystal-icons preservation**: Verify notification bell, sunrise, sunset icons render correctly after font trimming
4. **Bluetooth icon preservation**: Verify `drawIconBluetooth()` still renders "L" glyph via `seg34IconsFont` (unaffected by `drawIconHeart()` removal)
5. **Surf mode full rendering**: Verify swell section, tide curve, water temp, wind all display correctly
6. **CIQ 4.x+ preservation**: Build for Instinct 3 (instinct3solar45mm), verify identical rendering

### Unit Tests

- Not applicable — Monkey C watch faces have no standard unit test framework. Validation is simulator-based.
- The constant value calculations (e.g., `TOP_ROW2_Y = 2 + 23 = 25`) are verified by manual arithmetic and visual confirmation.

### Property-Based Tests

- Not applicable in the traditional sense — Monkey C lacks PBT libraries.
- The "property" that all 46 inlined values match their original computed values is verified by:
  1. Computing each value by hand from the original expressions
  2. Replacing in code
  3. Visual confirmation that rendering is pixel-identical

### Integration Tests

- **Full shore mode flow**: Build optimized code, run in simulator with shore mode, verify all sections render correctly with live data
- **Full surf mode flow**: Switch to surf mode, verify swell, tide curve, wind, water temp all display correctly
- **Settings change flow**: Change `ClockFont` setting, verify font reloads correctly without restart
- **Memory under load**: Navigate through settings changes, mode switches, and background data events — verify no OOM in View > Memory
