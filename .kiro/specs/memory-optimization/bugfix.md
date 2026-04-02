# Bugfix Requirements Document

## Introduction

The watch face crashes with Out of Memory (OOM) on Garmin Instinct 2/2X devices (CIQ 3.x, ~59.8KB available). The v1.0.2 release uses 55.3KB with 58.2KB peak, leaving only 1.6KB headroom. Adding v1.1.0 features (configurable arc, configurable subscreen, always-show-seconds) adds ~2.2KB of code, pushing peak memory to ~59.6KB which causes OOM during GPS coordinate Storage writes and SensorHistory reads.

The root cause is that on CIQ 3.x devices, custom fonts load into the app heap (~38KB for 8 fonts), whereas CIQ 4.x+ devices load fonts into a separate graphics pool. Combined with Monkey C compiler limitations (no constant folding, bytecode cost per `private static const`), the app is at 96% memory usage with no room for new features.

Four confirmed optimizations are needed:
1. Load only the active clock font instead of both (~4KB data savings)
2. Replace 46 `private static const` declarations with inline literals (~1-2KB code savings)
3. Remove dead code: `drawIconHeart()` and its unused seg34Icons heart glyph (~0.3KB)
4. Trim crystal-icons font from 17 glyphs to the 3 actually used (chars 53, 62, 63)

Combined estimated savings: ~5-6KB, bringing peak memory well under the 59.8KB limit with safe headroom for v1.1.0 features.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the watch face runs on Instinct 2/2X (CIQ 3.x, ~59.8KB heap) with v1.1.0 features enabled THEN the system crashes with OOM during GPS coordinate Storage writes or SensorHistory reads because peak memory (~59.6KB) exceeds available heap

1.2 WHEN `onLayout()` executes THEN the system loads both `ClockSaira40` and `ClockRajdhani40` fonts into the app heap (~4KB each) even though only one is used at a time based on the `ClockFont` setting

1.3 WHEN the Monkey C compiler processes the 46 `private static const` declarations in `SurferWatchFaceView` THEN the system generates bytecode for each declaration plus reference, consuming ~1-2KB of code memory because Monkey C does not fold constants (and 8 constants that reference other constants like `TOP_ROW2_Y = TOP_ROW1_Y + ROW_SPACING_TOP` are even worse since the compiler does not perform constant folding)

1.4 WHEN the watch face is compiled THEN the system includes the `drawIconHeart()` function and its seg34Icons heart glyph reference even though this function is never called (dead code — `drawHrHeart()` using `heartIconFont` is the one actually used)

1.5 WHEN the crystal-icons font is loaded THEN the system loads all 17 glyphs into memory even though only 3 are used (char 53=notification bell, char 62=sunrise, char 63=sunset)

### Expected Behavior (Correct)

2.1 WHEN the watch face runs on Instinct 2/2X (CIQ 3.x) with v1.1.0 features enabled THEN the system SHALL operate within the ~59.8KB heap limit with at least 3KB headroom (peak memory ≤ ~56.8KB), preventing OOM crashes

2.2 WHEN `onLayout()` executes THEN the system SHALL load only the clock font selected by the `ClockFont` setting (Saira or Rajdhani, not both), and SHALL reload the correct font when the setting changes via a `reloadClockFont()` mechanism triggered from `onSettingsChanged()`

2.3 WHEN the watch face is compiled THEN the system SHALL use inline literal values with comments instead of `private static const` declarations for all 46 layout constants in `SurferWatchFaceView`, eliminating the bytecode overhead of constant declarations and references

2.4 WHEN the watch face is compiled THEN the system SHALL NOT include the dead `drawIconHeart()` function, as it is unused code that wastes memory

2.5 WHEN the crystal-icons font is loaded THEN the system SHALL load only the 3 glyphs actually used (char 53=notification, char 62=sunrise, char 63=sunset), with the `.fnt` and `.png` files trimmed to exclude the 14 unused glyphs

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the watch face runs on CIQ 4.x+ devices (Instinct 3) THEN the system SHALL CONTINUE TO render all UI elements identically, since fonts load into a separate graphics pool and the optimizations only affect code/data size

3.2 WHEN the user switches the `ClockFont` setting between Saira and Rajdhani THEN the system SHALL CONTINUE TO display the selected font correctly on the next screen update

3.3 WHEN rendering any UI element that previously used a layout constant (e.g., `TOP_ROW1_Y`, `MID_Y`, `WX_COL2_X`) THEN the system SHALL CONTINUE TO position elements at exactly the same pixel coordinates as before

3.4 WHEN the `drawIconBluetooth()` function renders the Bluetooth icon THEN the system SHALL CONTINUE TO use `seg34IconsFont` with glyph "L" at the correct position, since only `drawIconHeart()` is removed (not the font itself)

3.5 WHEN rendering notification, sunrise, or sunset icons via crystal-icons font THEN the system SHALL CONTINUE TO display the correct glyphs (chars 53, 62, 63) at the same size and position

3.6 WHEN the watch face is in shore mode or surf mode THEN the system SHALL CONTINUE TO display all data fields (battery, tide, weather, wind, swell, moon phase, heart rate, stress arc, etc.) with identical values and formatting

3.7 WHEN `onUpdate()` executes THEN the system SHALL CONTINUE TO complete rendering within the per-second tick budget without visible lag or missed frames
