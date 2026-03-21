# Watch Face Design

## Reference
See `reference-design.png` in this folder for the visual design this spec is implementing.

## Overview
Technical design for the Surfer Watch Face. Translates requirements into concrete architecture, pixel layout, class responsibilities, and data flow.

---

## 1. Screen Layout

### 1.1 Canvas
- Total canvas: 176x176 pixels
- Shape: semi-octagon (corners clipped) — avoid placing content in the extreme corners
- Safe drawing area: approximately x=8–168, y=20–166 (top-left and top-right corners are clipped by the semi-octagon; the first safe y for left-aligned text is ~y=22)
- Colors: black (0x000000) background, white (0xFFFFFF) foreground only

### 1.1b Sub-screen (HR Circle) — from simulator.json
The Instinct 2X has a physical sub-screen circle in the top-right corner. From `simulator.json` datafield layouts:
- Canvas position: x=113, y=1, width=62, height=62
- Center: **(144, 31)**
- Radius: **31**
- This is the built-in circular cutout — our white HR circle should match these coordinates exactly
- Source: `Devices/instinct2x/simulator.json` → datafields → field with `"x": 113, "y": 1, "width": 62, "height": 62`

### 1.1a Font Sizes (Instinct 2X, from simulator.json)
| Constant | Font file | Nominal size |
|----------|-----------|-------------|
| `FONT_XTINY` | Roboto 15M | 15px |
| `FONT_TINY` | Roboto 15M | 15px (same as XTINY) |
| `FONT_SMALL` | Roboto 18M | 18px |
| `FONT_MEDIUM` | Roboto 20M | 20px |
| `FONT_LARGE` | Roboto 23B | 23px bold |

Row spacing must exceed the font's nominal size to avoid overlap. For `FONT_XTINY` (15px), use at least 18px between row y-coordinates.

### 1.2 Layout Zones (pixel coordinates)

```
┌─────────────────────────────────────┐  y=0
│  [BAT%] [BAT_ICON]    ┌──────────┐  │  y=12  TOP SECTION
│  [NOTIF_COUNT] [💬]   │  ♥       │  │  y=24
│  [↑↓][TIDE_TIME] [HT] │  [BPM]   │  │  y=36
├───────────────────────│          │  │  y=48  DIVIDER
│ [☀↑↓]  [HH:MM]  [🌙%] │          │  │  y=60  MIDDLE SECTION
│ [TIME]  [large] [AMPM]└──────────┘  │  y=88
│         [secs]                      │
├─────────────────────────────────────│  y=96  DIVIDER
│  [BT] Wed Mar 18                    │  y=108 DATE ROW
├─────────────────────────────────────│  y=116 DIVIDER
│ [☁][TEMP]  [→][WIND]  [☂][PRECIP%] │  y=128 WEATHER WIDGET
└─────────────────────────────────────┘  y=176
```

### 1.3 Precise Coordinates

**Heart Rate Circle**
- Center: x=144, y=31 (from simulator.json sub-screen geometry, tuned to fit)
- Radius: 31px (matches sub-screen: 62x62 at x=113, y=1)
- Drawn as filled white circle, then stress arc, heart icon, and BPM text on top in black
- Heart icon at (144, 14), BPM text at (144, 34) — both `TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER`
- Stress arc: 6px wide band from 2 o'clock to 10 o'clock (300° clockwise through bottom), black fill proportional to stress %
- Stress data from `SensorHistory.getStressHistory({:period=>1})`, 0-100, updates ~every 3 min

**Top Section** (left side of screen, y=2 to ~y=70)
- Row spacing: 23px between rows
- Row 1 (battery): y=2
  - Battery %: right-justified to x=81 (anchor), font=FONT_XTINY
  - Battery icon: left-justified from x=85
- Row 2 (bluetooth + notifications): y=25
  - Bluetooth icon: x=21, center-justified (only when connected)
  - Notification count: right-justified to x=75, font=FONT_XTINY
  - Notification icon: left-justified from x=79
- Row 3 (tide): y=48
  - Tide direction icon: x=1, left-justified (surfer-icons font)
  - Next tide time: x=1 + iconWidth, font=FONT_XTINY
  - Tide height: right-justified to x=106, font=FONT_XTINY

**Middle Section** (y=76 to y=94)
- Left column (sun): center-justified on x=22
  - Sun icon: y=72, centered
  - Sun time: y=94, centered
- Center column (time): x=88, y=90 (center + vcenter)
  - Font: Saira Condensed Bold 40px (default) or Rajdhani Bold 40px (via ClockFont setting)
- Right column: 2x2 grid
  - Left edge x=132, right edge x=174
  - Top row y=74, bottom row y=94
  - Top-left: moon phase icon (Erik Flowers Weather Icons, 28 phases, rasterized at 24px)
  - Bottom-left: am/pm, left-justified
  - Bottom-right: seconds (only when awake — wrist gesture active)

**Divider Lines** (single line)
- Top divider: drawLine(x=8, y=68, x=160, y=68)

**Date Row** (y=114)
- Date string: x=88, y=114, font=FONT_XTINY, center-justified, month uppercase (e.g., "Wed MAR 19")

**Weather Widget** (y=130–156, three columns)
- Edge columns (1 and 3) use WX_Y_EDGE=130 to account for semi-octagon bottom corners
- Center column uses WX_Y=138
- Col 1 (weather): x=42, icon at y=130, text at y=148
- Col 2 (wind): x=88, icon at y=138, text at y=156
- Col 3 (precipitation): x=134, icon at y=130, text at y=148
- Wind speed displayed as "kph" not "km/h" for space efficiency

**Weather Widget** (y=118 to y=166)
- Column 1 (weather): x=8
  - Condition icon: y=126, 16x16px bitmap
  - Temperature: y=146, font=FONT_XTINY
- Column 2 (wind): x=72 (center)
  - Wind direction icon: y=126, 16x16px bitmap (rotated arrow)
  - Wind speed: y=146, font=FONT_XTINY, justified center
- Column 3 (precipitation): x=136
  - Umbrella icon: y=126, 16x16px bitmap
  - Precip %: y=146, font=FONT_XTINY, right-aligned

**Divider Lines** — see Divider Lines section above

---

## 2. Class Architecture

### 2.1 Source Files

```
SurferWatchFaceApp.mc       — AppBase subclass, entry point, owns DataManager singleton,
                              registers background temporal event (5 min interval).
                              MUST be annotated (:background) because getServiceDelegate()
                              runs in the background process.
                              DataManager is created in getInitialView() (foreground only),
                              NOT in onStart() which runs in both foreground and background.
                              MUST implement getServiceDelegate() returning
                              [System.ServiceDelegate]:
                              (:background)
                              function getServiceDelegate() as [Background.ServiceDelegate] {
                                  return [new SurferWatchFaceDelegate()];
                              }
SurferWatchFaceView.mc      — WatchFace subclass, owns all rendering in onUpdate()
SurferWatchFaceBackground.mc— Drawable subclass, fills background black
SurferWatchFaceDelegate.mc  — System.ServiceDelegate (NOT Background.ServiceDelegate on API 3.4),
                              runs in background process,
                              makes all HTTP requests via WeatherService and TideService,
                              exits with packaged data via Background.exit()
DataManager.mc              — Singleton accessed via getApp().getDataManager(),
                              holds all cached data read by the view
WeatherService.mc           — OWM HTTP request and response parsing (called from ServiceDelegate)
TideService.mc              — StormGlass HTTP request and response parsing (called from ServiceDelegate)
```

### 2.2 DataManager (singleton)

Holds all state the view needs to render. Updated by `onBackgroundData()` and `updateSensorData()`.

```
// Cached weather data (from OWM, received via onBackgroundData)
var temperature as Float or Null
var weatherConditionId as Number or Null   // OWM condition code
var windSpeed as Float or Null             // m/s, converted to km/h or mph at render time
var windDeg as Number or Null
var sunrise as Number or Null              // Unix timestamp
var sunset as Number or Null               // Unix timestamp
var moonPhase as Float or Null             // 0.0–1.0 (computed locally via synodic period)
var owmFetchedAt as Number or Null         // Unix timestamp of last successful fetch

// Cached tide data (from StormGlass, received via onBackgroundData)
var tideExtremes as Array or Null          // array of {height, time (unix), type}
var tideFetchedDay as String or Null       // "YYYY-MM-DD" UTC of last fetch

// Computed from tideExtremes on each onUpdate()
var nextTideTime as Number or Null         // Unix timestamp
var nextTideType as String or Null         // "high" or "low"
var currentTideHeight as Float or Null     // predicted height of next tide event (meters)

// Device/sensor data (updated each onUpdate())
var heartRate as Number or Null
var stress as Number or Null               // 0-100, from SensorHistory.getStressHistory()
var battery as Number                      // 0–100
var notificationCount as Number
var bluetoothConnected as Boolean
var lastKnownLat as Float or Null
var lastKnownLng as Float or Null
```

**Key methods:**
- `initialize()` — loads persisted tide data from `Application.Storage`
- `updateSensorData()` — called from `onUpdate()`, reads HR, battery, notifications, BT, GPS; writes lat/lng to `Application.Storage` for background process
- `onWeatherData(data as Dictionary)` — receives parsed OWM fields from `onBackgroundData()`, stores in fields. Reads `owmFetchedAt` from `Application.Storage` (written by `WeatherService` in the background process) as single source of truth for staleness checks.
- `onTideData(data as Array)` — receives parsed tide array from `onBackgroundData()`, stores and persists
- `computeNextTide()` — walks `tideExtremes` to find next event after now, reads predicted height of that event (not interpolated)
- `computeMoonPhase()` — calculates moon phase from current date using synodic period (29.53 days), sets `moonPhase` as 0.0–1.0
- `persistTideData()` — saves `tideExtremes` and `tideFetchedDay` to `Application.Storage`
- `loadTideData()` — restores from `Application.Storage` on startup

### 2.3 WeatherService

Runs inside `SurferWatchFaceDelegate` (background process). Returns a parsed Dictionary to the delegate.

- `fetch(lat, lon, apiKey, units)` — builds OWM One Call 3.0 URL, calls `Communications.makeWebRequest()`
- Callback parses response JSON, extracts only the fields we need, returns Dictionary:
  `{:temp, :conditionId, :windSpeed, :windDeg, :sunrise, :sunset}`
- On success: writes `owmFetchedAt`, `owmFetchLat`, `owmFetchLon` to `Application.Storage` before invoking callback
- On error: returns null, delegate skips packaging weather data

### 2.4 TideService

Runs inside `SurferWatchFaceDelegate` (background process). Returns a parsed Array to the delegate.

- `fetch(lat, lng, apiKey)` — builds StormGlass URL with 48h window and `datum=MLLW`, sets `Authorization` header, calls `Communications.makeWebRequest()`
- Uses `datum=MLLW` (Mean Lower Low Water) so heights are always positive and match what tide websites/surfers expect
- Callback parses response, converts ISO time strings to Unix timestamps, returns Array of `{:height, :time, :type}`
- Checks `meta.requestCount` vs `meta.dailyQuota`; if exhausted, writes `stormGlassQuotaExhausted=true` to `Application.Storage`
- On error: returns null, delegate skips packaging tide data

**Request chaining in `onTemporalEvent()`**: `makeWebRequest()` is async and only one request runs at a time. The delegate MUST chain requests:
1. Call `WeatherService.fetch()` if OWM refresh needed
2. In OWM callback: call `TideService.fetch()` if StormGlass refresh needed
3. In tide callback (or after OWM if no tide fetch needed): call `Background.exit(payload)`
4. If neither fetch is needed: call `Background.exit({})` immediately

### 2.5 SurferWatchFaceView

- `onUpdate(dc)` — single method that draws everything in order:
  1. Clear background (black)
  2. Call `DataManager.updateSensorData()`
  3. Call `DataManager.computeNextTide()`
  4. Draw HR circle
  5. Draw top section (battery, notifications, tide)
  6. Draw divider lines
  7. Draw middle section (sun, time, moon/seconds)
  8. Draw date row
  9. Draw weather widget
- No layout XML — all drawing via `dc` methods
- Private helper methods per section: `drawHrCircle(dc)`, `drawTopSection(dc)`, `drawMiddleSection(dc)`, `drawDateRow(dc)`, `drawWeatherWidget(dc)`

---

## 3. Data Flow

```
onUpdate() (1Hz, main process)
  └─ DataManager.updateSensorData()     ← reads watch sensors
  └─ DataManager.computeNextTide()      ← local computation from cached array
  └─ SurferWatchFaceView.draw*()        ← renders from DataManager fields

onBackgroundData(data) (on AppBase class, NOT WatchFace — called after background exits)
  └─ if data[:weather] != null → DataManager.onWeatherData(data[:weather])
  └─ if data[:tides] != null  → DataManager.onTideData(data[:tides])

Background.ServiceDelegate.onTemporalEvent() (background process, every 5 min)
  └─ reads last fetch timestamps from Application.Storage
  └─ if OWM refresh conditions met → WeatherService.fetch() → packages result
  └─ if StormGlass refresh conditions met → TideService.fetch() → packages result
  └─ Background.exit({:weather => weatherDictOrNull, :tides => tideArrayOrNull})
```

**Key constraint**: background process has ~28KB memory budget. Parse only the fields we need from API responses — do not store full JSON.

---

## 4. Refresh Logic

### 4.1 OWM Refresh Conditions (any one triggers fetch)
1. `owmFetchedAt == null` (never fetched)
2. `now - owmFetchedAt >= 5 * 60` (5 minutes elapsed)
3. `distanceBetween(lastKnownLat, lastKnownLng, owmFetchLat, owmFetchLon) > 5000` (moved >5km)

Guard: skip if no phone connection (`bluetoothConnected == false`)

### 4.2 StormGlass Refresh Conditions (any one triggers fetch)
1. `tideExtremes == null` (never fetched or storage empty)
2. `tideFetchedDay != todayUTC()` (new calendar day)
3. `distanceBetween(currentPos, tideFetchLat, tideFetchLng) > 50000` (moved >50km)
4. All events in `tideExtremes` are in the past (stale 48h window — set by `computeNextTide()` writing `tideDataExpired=true` to `Application.Storage`)

Guard: skip if no phone connection, skip if StormGlass quota exhausted

### 4.3 Distance Calculation
```
// Haversine approximation (sufficient for these thresholds)
function distanceBetween(lat1, lon1, lat2, lon2) as Float
```

### 4.4 Wind Speed and Tide Height Unit Conversion
OWM returns wind speed in m/s. StormGlass returns tide height in meters.
Convert both based on `System.getDeviceSettings().distanceUnits`:
- `UNIT_METRIC` → wind: multiply by 3.6 → "X km/h"; tide: display as "X m"
- `UNIT_STATUTE` → wind: multiply by 2.237 → "X mph"; tide: multiply by 3.281 → "X ft"

### 4.5 Refresh Timestamps in Application.Storage
The background process has no access to DataManager. All shared state uses `Application.Storage`:
- `"owmFetchedAt"` — Unix timestamp of last successful OWM fetch
- `"owmFetchLat"`, `"owmFetchLon"` — coordinates used for last OWM fetch
- `"tideFetchedDay"` — "YYYY-MM-DD" UTC string of last StormGlass fetch
- `"tideFetchLat"`, `"tideFetchLng"` — coordinates used for last tide fetch
- `"stormGlassQuotaExhausted"` — boolean, set true when `requestCount >= dailyQuota`; MUST be cleared when `tideFetchedDay` changes to a new calendar day
- `"tideDataExpired"` — boolean, set true by `computeNextTide()` when all tide events are in the past; cleared when new tide data is received
- `"lastKnownLat"`, `"lastKnownLng"` — current GPS position, written by main process in `updateSensorData()`, read by background process in `onTemporalEvent()` to evaluate distance-based refresh conditions
- `"bluetoothConnected"` — boolean, written by main process, read by background as connectivity guard

### 4.6 OWM Units Parameter
Map `System.getDeviceSettings().distanceUnits` to OWM `units` parameter:
- `UNIT_METRIC` → `units=metric` (temperature in °C, wind in m/s)
- `UNIT_STATUTE` → `units=imperial` (temperature in °F, wind in mph — note: OWM imperial wind is already mph, no conversion needed)

For imperial: OWM returns wind speed in mph directly, so skip the m/s→mph conversion in design §4.4 when `units=imperial`.

---

## 5. Icon Strategy

### 5.1 Rasterization Pipeline (proven)

All custom icons are rasterized from TTF source fonts to BMFont format (.fnt + .png) using this pipeline:

**Prerequisites:**
- `fontbm` — BMFont-compatible rasterizer (macOS binary in `tools/fontbm`)
- `magick` (ImageMagick) — for PNG format conversion
- Source TTF font with the glyphs you need

**Step 1: Rasterize with fontbm**
```bash
tools/fontbm \
  --font-file <source.ttf> \
  --font-size 17 \
  --chars <decimal_codepoints_comma_separated> \
  --spacing-horiz 1 --spacing-vert 1 \
  --padding-up 0 --padding-right 0 --padding-down 0 --padding-left 0 \
  --texture-size 256x256 \
  --output /tmp/<name>
```
This produces `<name>.fnt` and `<name>_0.png` (RGBA format).

**Step 2: Convert PNG to 8-bit grayscale**
```bash
magick /tmp/<name>_0.png -alpha extract -type grayscale -depth 8 resources/fonts/<final>.png
```
This extracts the alpha channel into a pure 8-bit grayscale PNG — the format Garmin's renderer expects.

**Step 3: Edit .fnt file**
Copy the .fnt to `resources/fonts/` and make these edits:
1. Remap high unicode `char id=XXXXXX` to simple ASCII IDs (e.g., 85 for 'U')
2. Set channel flags: `alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0`
3. Update `file=` to point to the final PNG filename

**Step 4: Register in fonts.xml**
```xml
<font id="MyIcons" filename="my-icons.fnt" antialias="false" />
```

**Step 5: Load and use in code**
```java
var myFont = WatchUi.loadResource(Rez.Fonts.MyIcons);
dc.drawText(x, y, myFont, "U", Graphics.TEXT_JUSTIFY_CENTER);
```

### 5.1a Critical Format Requirements

The output PNG **must be 8-bit grayscale** (not RGBA). The .fnt **must have** `alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0`.

Why: Garmin's MIP renderer reads the grayscale pixel value as glyph opacity. With RGBA + `alphaChnl=0`, the renderer misinterprets the channels, causing lines to appear bold/fat. This was the root cause of our initial quality issues.

Reference: Crystal Face (warmsound/crystal-face) uses this exact format — 8-bit grayscale 256x256 PNGs with `alphaChnl=1`.

### 5.1b Size Selection

- **17px** — best general-purpose size, matches Crystal Face and FONT_XTINY row height
- **19px** — viable alternative when more detail is needed
- **Max texture size: 256x256** — Instinct 2X does not support 512x512 (causes garbled rendering)
- Tested 14-20px; 17px and 19px produced the cleanest results on the Instinct 2X simulator
- Monochrome (`--monochrome` flag) gives thinnest lines but loses detail vs grayscale AA
- The Gemini 2x supersample approach (render at 2x, downscale) did not produce usable results

### 5.1c Approaches That Did NOT Work

| Approach | Result | Why |
|----------|--------|-----|
| fontbm RGBA output directly | Bold/fat lines | Garmin renderer misinterprets RGBA channels |
| Gemini 2x supersample + Mitchell downscale | White blobs | Downscale destroyed glyph detail |
| Monochrome at various sizes | Too thin, asymmetric | Lost AA detail, half-pixel misalignment visible |
| Varying spacing/padding (0-2px) | No visible difference | At 17px, spacing/padding don't affect quality |

### 5.2 Font Files In Use

| Font file | Source | Glyphs | Format |
|-----------|--------|--------|--------|
| `weather-icons.fnt/.png` | Erik Flowers Weather Icons (SIL OFL), rasterized at 17px via fontbm | 29 weather glyphs: day (A-V) + night (a-g) | 8-bit grayscale 256x256 |
| `crystal-icons.fnt/.png` | Crystal Face (custom pixel-art) | Notifications (5), sunrise (>), sunset (?) | 8-bit colormap 256x256 |
| `moon.fnt/.png` | Erik Flowers Weather Icons (SIL OFL), rasterized at 24px via fontbm | 28 moon phases (mapped to ASCII chars) | 8-bit grayscale 256x256 |
| `seg34-icons.fnt/.png` | Segment34mkII | Bluetooth (L) | 8-bit grayscale |
| `surfer-icons.fnt/.png` | MDI webfont (Apache 2.0), rasterized at 17px via fontbm | Umbrella (U=85), tide high (H=72), tide low (L=76) | 8-bit grayscale 256x256 |
| `heart-icon.fnt/.png` | Garmin Connect Icons (sunpazed/garmin-iconfonts), rasterized at 27px via fontbm | Heart outline (h=104) | 8-bit grayscale 256x256 |
| `clock-SairaCondensed-Bold-40.fnt/.png` | Google Fonts (SIL OFL), rasterized at 40px | Digits 0-9, colon | Default clock font |
| `clock-Rajdhani-Bold-40.fnt/.png` | Google Fonts (SIL OFL), rasterized at 40px | Digits 0-9, colon | Alternative clock font (via ClockFont setting) |

**Heart icon size testing**: Tested sizes 18-30px from garmin-connect-icons.ttf. Best results at 27px (winner), 24px, 28px, 21px. Even sizes tend to rasterize cleaner due to font em-size alignment. Alternatives can be regenerated by changing `--font-size` in the pipeline command.

### 5.2a MDI Webfont Codepoints

Source: `materialdesignicons-webfont.ttf` from Templarian/MaterialDesign-Webfont (Apache 2.0)
Saved at: `/tmp/materialdesignicons-webfont.ttf`

| Icon | MDI name | Hex codepoint | Decimal | Mapped to ASCII |
|------|----------|---------------|---------|-----------------|
| Umbrella | umbrella-outline | F054B | 984395 | U (85) |
| Tide high | waves-arrow-up | F185B | 989275 | H (72) |
| Tide low | (not in MDI) | — | — | L (76) — needs flip or alternative |

### 5.2b Weather Icons Glyph Mapping (Erik Flowers, rasterized at 17px)

29 glyphs total. Unicode codepoints from Weather Icons TTF, remapped to ASCII in .fnt file:

Day glyphs (A-V, ASCII 65-86):
```
0xF00D (wi-day-sunny)              → A (65)
0xF002 (wi-day-cloudy)             → B (66)  — also used for C
0xF002 (wi-day-cloudy)             → C (67)
0xF013 (wi-cloudy)                 → D (68)
0xF014 (wi-fog)                    → E (69)
0xF01E (wi-thunderstorm)           → F (70)
0xF01C (wi-sprinkle)               → G (71)
0xF019 (wi-rain)                   → H (72)
0xF01A (wi-showers)                → I (73)
0xF01B (wi-snow)                   → J (74)
0xF017 (wi-rain-mix)               → K (75)
0xF01D (wi-storm-showers)          → L (76)
0xF0B5 (wi-sleet)                  → M (77)
0xF062 (wi-smoke)                  → N (78)
0xF0B6 (wi-day-haze)               → O (79)
0xF063 (wi-dust)                   → P (80)
0xF011 (wi-cloudy-gusts)           → Q (81)
0xF056 (wi-tornado)                → R (82)
0xF073 (wi-hurricane)              → S (83)
0xF076 (wi-snowflake-cold)         → T (84)
0xF072 (wi-hot)                    → U (85)
0xF021 (wi-windy)                  → V (86)
```

Night glyphs (a-g, ASCII 97-103):
```
0xF02E (wi-night-clear)            → a (97)
0xF086 (wi-night-alt-cloudy)       → b (98)
0xF028 (wi-night-alt-rain)         → c (99)
0xF029 (wi-night-alt-showers)      → d (100)
0xF02A (wi-night-alt-thunderstorm) → e (101)
0xF02C (wi-night-alt-snow)         → f (102)
0xF022 (wi-night-alt-cloudy-gusts) → g (103)
```

### 5.3 Icon Sources by Category

| Category | Source | Status |
|----------|--------|--------|
| Weather conditions (29) | Erik Flowers Weather Icons, rasterized at 17px (day A-V, night a-g) | ✅ Wired |
| Heart | Garmin Connect Icons (sunpazed/garmin-iconfonts), rasterized at 27px, char `h` | ✅ Wired |
| Notifications | Crystal Face crystal-icons.fnt, char `5` | ✅ Wired |
| Sunrise/sunset | Crystal Face crystal-icons.fnt, chars `>` / `?` | ✅ Wired |
| Bluetooth | Segment34mkII seg34-icons.fnt, char `L` | ✅ Wired |
| Moon phases (28) | Erik Flowers Weather Icons, rasterized at 24px | ✅ Wired |
| Wind direction | Procedural `dc.fillPolygon()` — swallow-tail arrow rotated to exact degree | ✅ Wired |
| Umbrella | MDI surfer-icons.fnt, char `U` (rasterized with our pipeline) | ✅ Wired |
| Tide high | MDI surfer-icons.fnt, char `H` (waves-arrow-up) | ✅ Wired |
| Tide low | MDI surfer-icons.fnt, char `L` (wave-arrow-down) | ✅ Wired |
| Battery | Code-drawn fill bar (18x10 rectangle + proportional fill) | ✅ Wired |

### 5.4 Code Patterns

**drawTextAligned helper**: Compensates for font top padding so Y = top pixel of visible content:
```java
private function drawTextAligned(dc, x, y, font, text, justify) {
    var fontHeight = dc.getFontHeight(font);
    var ascent = Graphics.getFontAscent(font);
    var topPadding = fontHeight - ascent;
    dc.drawText(x, y - topPadding, font, text, justify);
}
```

**Icon methods**: Each icon has its own `drawIcon*()` method. Font-based icons use `drawTextAligned()`. Procedural icons (wind arrow) use `dc.fillPolygon()`.

**Composite components**: Reusable UI units (text + icon) take `(dc, x, y, data)`.
- Text-first: `x` = anchor between text and icon
- Icon-first: `x` = left edge

**Layout constants**: All pixel coordinates are `private static const` at the top of `SurferWatchFaceView`.

---

## 6. OWM Weather Condition Code → Weather Icons Mapping

Uses Erik Flowers Weather Icons rasterized at 17px. 29 glyphs total: 22 day (A-V) + 7 night (a-g).
Night variants are selected when current time is before sunrise or after sunset.

Based on the official erikflowers OWM mapping (https://erikflowers.github.io/weather-icons/api-list.html):

```
Day glyphs (A-V):
  A = wi-day-sunny (clear, 800)
  B = wi-day-cloudy (few/scattered clouds, 801-802) — night: b
  C = wi-day-cloudy (same as B, used for 801-802) — night: b
  D = wi-cloudy (overcast, 804) — same day/night
  E = wi-fog (741)
  F = wi-thunderstorm (200-232) — night: e
  G = wi-sprinkle (300, 301, 321, 500) — night: d
  H = wi-rain (302-314, 501-504) — night: c
  I = wi-showers (520-522, 701 mist) — night: d
  J = wi-snow (600, 601, 621, 622) — night: f
  K = wi-rain-mix (511, 611-620)
  L = wi-storm-showers (531, 901)
  M = wi-sleet (602)
  N = wi-smoke (711)
  O = wi-day-haze (721)
  P = wi-dust (731, 761, 762)
  Q = wi-cloudy-gusts (771, 803) — night: g
  R = wi-tornado (781, 900)
  S = wi-hurricane (902)
  T = wi-snowflake-cold (903)
  U = wi-hot (904)
  V = wi-windy (905)

Night glyphs (a-g):
  a = wi-night-clear (800 at night)
  b = wi-night-alt-cloudy (801-802 at night)
  c = wi-night-alt-rain (302-314, 501-504 at night)
  d = wi-night-alt-showers (300-321, 500, 520-522, 701 at night)
  e = wi-night-alt-thunderstorm (200-232 at night)
  f = wi-night-alt-snow (600-622 at night)
  g = wi-night-alt-cloudy-gusts (771, 803 at night)
```

---

## 7. Moon Phase Mapping (28 phases)

Moon phase is computed locally via synodic period in `DataManager.computeMoonPhase()`. The 0.0–1.0 float is mapped to 28 glyphs from Erik Flowers Weather Icons, rasterized at 24px.

```
Mapping: Math.round(moonPhase * 28) % 28 → ASCII char (48 + index)
Index 0  (char '0') = new moon
Index 1  (char '1') = waxing crescent 1
Index 2  (char '2') = waxing crescent 2
...
Index 7  (char '7') = first quarter
...
Index 14 (char '>') = full moon
...
Index 21 (char 'E') = last quarter
...
Index 27 (char 'K') = waning crescent 6
```

Source codepoints: `0xF095` (wi-moon-new) through `0xF0B0` (wi-moon-waning-crescent-6), remapped to ASCII 48-75 in the .fnt file.

Note: `Math.round()` is used instead of truncation to avoid the new moon glyph appearing for too wide a range. Illumination % is NOT displayed (removed — overlaps with moon icon at this size).

---

## 8. App Settings (settings.xml settingConfig types)

Valid `settingConfig` types in Connect IQ: `alphaNumeric`, `numeric`, `list`, `boolean`, `date`. There is NO `float` type.

| Property | properties.xml type | settingConfig type | Notes |
|----------|--------------------|--------------------|-------|
| `OWMApiKey` | `string` | `alphaNumeric` | Free-text string input |
| `StormGlassApiKey` | `string` | `alphaNumeric` | Free-text string input |
| `HomeLat` | `string` | `alphaNumeric` | Property must be `string` (not `float`) because `alphaNumeric` is only valid for string properties. Parse to float in code via `toFloat()`. |
| `HomeLng` | `string` | `alphaNumeric` | Same as HomeLat |
| `ClockFont` | `number` | `list` | 0 = Saira Condensed Bold (default), 1 = Rajdhani Bold |

---

## 9. Permissions Required (manifest.xml)

```xml
<iq:uses-permission id="Communications"/>
<iq:uses-permission id="Positioning"/>
<iq:uses-permission id="SensorHistory"/>
<iq:uses-permission id="Background"/>
```

The `Background` permission is sufficient. No `<iq:background>` manifest entry is needed.

### Background Annotations

The following classes MUST be annotated with `(:background)` so they are compiled into the background process:

| Class | Why |
|-------|-----|
| `SurferWatchFaceApp` | Contains `getServiceDelegate()` which runs in background |
| `SurferWatchFaceDelegate` | The ServiceDelegate itself |
| `WeatherService` | Called from ServiceDelegate |
| `TideService` | Called from ServiceDelegate |

`getServiceDelegate()` method itself must also be annotated `(:background)` and returns `[System.ServiceDelegate]`:
```java
(:background)
function getServiceDelegate() as [System.ServiceDelegate] {
    return [new SurferWatchFaceDelegate()];
}
```

**IMPORTANT**: On the Instinct 2X (API 3.4), `ServiceDelegate` lives under `Toybox.System`, NOT `Toybox.Background`. The delegate class extends `System.ServiceDelegate`:
```java
(:background)
class SurferWatchFaceDelegate extends System.ServiceDelegate {
    ...
}
```
