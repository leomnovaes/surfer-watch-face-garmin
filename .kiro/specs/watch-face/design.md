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
│  [NOTIF_COUNT] [BELL] │  ♥       │  │  y=24
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
- Center: x=146, y=33
- Radius: 35px
- Drawn as filled white circle, then heart icon + BPM text on top in black
- Heart icon and BPM use `TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER` for centering within the circle

**Top Section** (left side of screen, y=2 to ~y=70)
- Row spacing: 23px between rows
- Row 1 (battery): y=2
  - Battery %: right-justified to x=81 (anchor), font=FONT_XTINY
  - Battery icon: left-justified from x=85
- Row 2 (notifications): y=25
  - Notification count: right-justified to x=81 (anchor), font=FONT_XTINY
  - Notification icon: left-justified from x=85
- Row 3 (tide): y=48
  - Tide direction icon: x=1, left-justified
  - Next tide time: x=1 + iconWidth + 4, font=FONT_XTINY
  - Tide height: right-justified to x=101, font=FONT_XTINY

**Middle Section** (y=76 to y=94)
- Left column (sun): center-justified on x=26
  - Sun icon: y=78, centered
  - Sun time + a/p suffix: y=96, centered
- Center column (time): x=88 (center)
  - Time: font=FONT_NUMBER_HOT, center + vcenter justified
- Right column: 2x2 grid
  - Left edge x=128, right edge x=168
  - Top row y=78, bottom row y=96
  - Top-left: moon phase icon (from Segment34mkII moon font, chars 0-7)
  - Top-right: empty (illumination % removed — overlaps with moon icon at this size)
  - Bottom-left: am/pm, left-justified
  - Bottom-right: seconds (visible for layout, hidden by default in Task 38)

**Divider Lines** (single line)
- Top divider: drawLine(x=8, y=68, x=160, y=68) — right side clipped to avoid HR circle area

**Date Row** (y=112)
- Bluetooth icon: x=TOP_COL1_X (aligned with tide icon), y=112
- Date string: x=88, y=112, font=FONT_XTINY, center-justified
- Note: bluetooth icon placement may move to top section row 2 in a future revision

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
var precipPop as Float or Null             // 0.0–1.0
var moonPhase as Float or Null             // 0.0–1.0
var owmFetchedAt as Number or Null         // Unix timestamp of last successful fetch

// Cached tide data (from StormGlass, received via onBackgroundData)
var tideExtremes as Array or Null          // array of {height, time (unix), type}
var tideFetchedDay as String or Null       // "YYYY-MM-DD" UTC of last fetch

// Computed from tideExtremes on each onUpdate()
var nextTideTime as Number or Null         // Unix timestamp
var nextTideType as String or Null         // "high" or "low"
var currentTideHeight as Float or Null     // interpolated meters

// Device/sensor data (updated each onUpdate())
var heartRate as Number or Null
var battery as Number                      // 0–100
var notificationCount as Number
var bluetoothConnected as Boolean
var lastKnownLat as Float or Null
var lastKnownLng as Float or Null
```

**Key methods:**
- `initialize()` — loads persisted tide data from `Application.Storage`
- `updateSensorData()` — called from `onUpdate()`, reads HR, battery, notifications, BT, GPS; writes lat/lng to `Application.Storage` for background process
- `onWeatherData(data as Dictionary)` — receives parsed OWM fields from `onBackgroundData()`, stores in fields, updates `owmFetchedAt`
- `onTideData(data as Array)` — receives parsed tide array from `onBackgroundData()`, stores and persists
- `computeNextTide()` — walks `tideExtremes` to find next event after now, interpolates current height
- `persistTideData()` — saves `tideExtremes` and `tideFetchedDay` to `Application.Storage`
- `loadTideData()` — restores from `Application.Storage` on startup

### 2.3 WeatherService

Runs inside `SurferWatchFaceDelegate` (background process). Returns a parsed Dictionary to the delegate.

- `fetch(lat, lon, apiKey, units)` — builds OWM One Call 3.0 URL, calls `Communications.makeWebRequest()`
- Callback parses response JSON, extracts only the fields we need, returns Dictionary:
  `{:temp, :conditionId, :windSpeed, :windDeg, :sunrise, :sunset, :pop, :moonPhase}`
- On error: returns null, delegate skips packaging weather data

### 2.4 TideService

Runs inside `SurferWatchFaceDelegate` (background process). Returns a parsed Array to the delegate.

- `fetch(lat, lng, apiKey)` — builds StormGlass URL with 48h window, sets `Authorization` header, calls `Communications.makeWebRequest()`
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
2. `now - owmFetchedAt >= 30 * 60` (30 minutes elapsed)
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

### 5.1 Approach: BMFont Icon Fonts (revised)

Icons are rendered via `drawText()` using BMFont-rasterized icon fonts. The proven community approach:

**BMFont settings** (from Crystal Face / warmsound):
```
fontName=Weather Icons
fontSize=-17          # negative = match pixel height
aa=2                  # 2x supersampling
useSmoothing=1
useHinting=1
renderFromOutline=0
useClearType=0
padding=0,0,0,0
spacing=1,1
outWidth=256
outHeight=256
outBitDepth=8         # grayscale
alphaChnl=1
textureFormat=png
```
Note: This config is for BMFont (Windows only). fontbm (cross-platform) uses FreeType2 which produces different rasterization — slightly different anti-aliasing and half-pixel baseline offset. For identical results, use BMFont on Windows.

**fontbm workaround to match BMFont aa=2 output** (render at 2x, downscale):
```bash
# 1. Generate at 2x size (34px for target 17px)
fontbm --font-file weathericons.ttf --font-size 34 --chars <chars> \
  --data-format txt --spacing-horiz 2 --spacing-vert 2 \
  --padding-up 0 --padding-right 0 --padding-down 0 --padding-left 0 \
  --texture-size 512x512 --output crystal_2x

# 2. Downscale and convert to 8-bit grayscale (requires ImageMagick)
magick crystal_2x_0.png -filter Mitchell -resize 256x256 \
  -alpha extract -type grayscale -depth 8 crystal_final.png

# 3. Fix .fnt file: divide all x/y/width/height/xoffset/yoffset by 2,
#    change size to 17, scaleW/scaleH to 256
```

**Crystal Face Weather Icons glyph mapping** (unicode → ASCII character):
```
61441 (wi-day-cloudy)             → A (65)
61442 (wi-day-cloudy-gusts)       → B (66)
61445 (wi-day-lightning)          → C (67)
61448 (wi-day-rain)               → D (68)
61449 (wi-day-showers)            → E (69)
61450 (wi-day-snow)               → F (70)
61452 (wi-day-sunny-overcast)     → G (71)
61453 (wi-day-sunny)              → H (72)
61459 (wi-cloudy)                 → I (73)
61475 (wi-night-alt-cloudy-gusts) → a (97)
61477 (wi-night-alt-rain)         → b (98)
61480 (wi-night-alt-showers)      → c (99)
61481 (wi-night-alt-snow)         → d (100)
61482 (wi-night-alt-thunderstorm) → e (101)
61486 (wi-night-clear)            → f (102)
61569 (wi-tornado)                → g (103)
61574 (wi-night-alt-cloudy)       → h (104)
```

**Grid-aligned sizes**: for best pixel alignment, use sizes that are power-of-2 divisors of the font's em-size:
- Font Awesome (em=512): ideal at 16px, 32px
- Weather Icons (em=2048): ideal at 16px, 32px
- Anti-aliasing ON produces better results than monochrome — Garmin's 1-bit renderer thresholds gray pixels

**Reference implementation**: Crystal Face (warmsound/crystal-face, GPL v3) has pre-rasterized Weather Icons and custom crystal icons that serve as quality benchmark.

**Icon sources by category**:
| Category | Source | Approach |
|----------|--------|----------|
| Weather conditions (21) | Erik Flowers Weather Icons TTF | BMFont rasterize with proven settings |
| Sunrise/sunset (2) | Erik Flowers Weather Icons TTF | BMFont rasterize |
| Umbrella (1) | Erik Flowers Weather Icons TTF | BMFont rasterize |
| Moon phases (16) | Erik Flowers Weather Icons TTF | BMFont rasterize |
| Heart, Bluetooth, Bell (3) | Font Awesome Solid/Brands TTF OR Crystal Face crystal-icons | Compare both, choose better |
| Wind direction (8) | Procedural polygon | `dc.fillPolygon()` — triangle with swallow tail, rotated to wind degree |
| Tide high/low (2) | Community fonts (sunpazed, mondrian) | Search for wave+arrow glyphs, fallback to procedural |
| Battery | Code-drawn | Keep current fill-bar approach |

### 5.2 Font Sources

Two separate icon font files:

**Garmin Icons** (`garmin-connect-icons.ttf` → `garmin-icons.fnt`):
| Role | Glyph name | Unicode |
|------|-----------|---------|
| Heart (HR circle) | heart | 0x6D |
| Bluetooth | bluetooth | 0x56 |
| Notification | speech-bubble | 0xC2 |

**Weather Icons** (`weathericons-regular-webfont.ttf` → `weather-icons.fnt`):

Weather conditions (OWM code → glyph, from erikflowers OWM mapping):
| OWM codes | Glyph name | Unicode |
|-----------|-----------|---------|
| 200-202, 230-232 | wi-thunderstorm | 0xF01E |
| 210-212, 221 | wi-lightning | 0xF016 |
| 300, 301, 321, 500 | wi-sprinkle | 0xF01C |
| 302, 311, 312, 314, 501-504 | wi-rain | 0xF019 |
| 310, 511, 611-616, 620 | wi-rain-mix | 0xF017 |
| 313, 520-522 | wi-showers | 0xF01A |
| 531, 901 | wi-storm-showers | 0xF01D |
| 600, 601, 621, 622 | wi-snow | 0xF01B |
| 602 | wi-sleet | 0xF0B5 |
| 711 | wi-smoke | 0xF062 |
| 721 | wi-day-haze | 0xF0B6 |
| 731, 761, 762 | wi-dust | 0xF063 |
| 741 | wi-fog | 0xF014 |
| 771, 801-803 | wi-cloudy-gusts | 0xF011 |
| 781, 900 | wi-tornado | 0xF056 |
| 800 | wi-day-sunny | 0xF00D |
| 804 | wi-cloudy | 0xF013 |
| 902 | wi-hurricane | 0xF073 |
| 903 | wi-snowflake-cold | 0xF076 |
| 904 | wi-hot | 0xF072 |
| 905 | wi-windy | 0xF021 |

Other Weather Icons:
| Role | Glyph name | Unicode |
|------|-----------|---------|
| Sunrise | wi-sunrise | 0xF051 |
| Sunset | wi-sunset | 0xF052 |
| Umbrella | wi-umbrella | 0xF084 |
| Wind (generic) | wi-strong-wind | 0xF050 |

Moon phases (16 evenly-spaced from 28 available):
| Phase | Glyph name | Unicode |
|-------|-----------|---------|
| New moon | wi-moon-new | 0xF095 |
| Waxing crescent 2 | wi-moon-waxing-crescent-2 | 0xF097 |
| Waxing crescent 4 | wi-moon-waxing-crescent-4 | 0xF099 |
| Waxing crescent 6 | wi-moon-waxing-crescent-6 | 0xF09B |
| First quarter | wi-moon-first-quarter | 0xF09C |
| Waxing gibbous 2 | wi-moon-waxing-gibbous-2 | 0xF09E |
| Waxing gibbous 4 | wi-moon-waxing-gibbous-4 | 0xF0A0 |
| Waxing gibbous 6 | wi-moon-waxing-gibbous-6 | 0xF0A2 |
| Full moon | wi-moon-full | 0xF0A3 |
| Waning gibbous 2 | wi-moon-waning-gibbous-2 | 0xF0A5 |
| Waning gibbous 4 | wi-moon-waning-gibbous-4 | 0xF0A7 |
| Waning gibbous 6 | wi-moon-waning-gibbous-6 | 0xF0A9 |
| Third quarter | wi-moon-third-quarter | 0xF0AA |
| Waning crescent 2 | wi-moon-waning-crescent-2 | 0xF0AC |
| Waning crescent 4 | wi-moon-waning-crescent-4 | 0xF0AE |
| Waning crescent 6 | wi-moon-waning-crescent-6 | 0xF0B0 |

**Not using icon fonts:**
- Battery — code-drawn (fill bar proportional to %)
- Wind direction arrows — deferred (Task 32), using cardinal text labels ("N", "NE", etc.) for now
- Tide direction — TBD (Task 35)

### 5.3 Code Patterns

**drawTextAligned helper**: All text and icon rendering goes through `drawTextAligned()` which compensates for the font's built-in top padding. This ensures the Y coordinate passed is where the visible pixels actually start:
```java
private function drawTextAligned(dc, x, y, font, text, justify) {
    var fontHeight = dc.getFontHeight(font);
    var ascent = Graphics.getFontAscent(font);
    var topPadding = fontHeight - ascent;
    dc.drawText(x, y - topPadding, font, text, justify);
}
```

**Icon methods**: Each icon has its own `drawIcon*()` method that calls `drawTextAligned()` with the icon placeholder constant. When the icon font is ready, only the constant value and font reference change — no call sites need updating:
```java
private function drawIconBattery(dc, x, y) {
    drawTextAligned(dc, x, y, Graphics.FONT_XTINY, IC_BATTERY, TEXT_JUSTIFY_LEFT);
}
```

**Composite components**: Reusable UI units (text + icon or icon + text) are encapsulated in methods that take `(dc, x, y, data)` so they can be placed anywhere by changing the position constants.

Anchoring rule for composite components:
- **Text-first** (text left, icon right): `x` = anchor point between text and icon. Text is `TEXT_JUSTIFY_RIGHT` to `x - SPACER`, icon is `TEXT_JUSTIFY_LEFT` from `x`.
- **Icon-first** (icon left, text right): `x` = left edge. Icon is `TEXT_JUSTIFY_LEFT` from `x`, text is `TEXT_JUSTIFY_LEFT` from `x + iconWidth + SPACER`.

Examples:
```java
// Text-first: "75%" [=]  — x anchors the boundary
private function drawBatteryWithPercent(dc, x, y, percent) {
    drawTextAligned(dc, x - SPACER, y, FONT_XTINY, percent + "%", TEXT_JUSTIFY_RIGHT);
    drawIconBattery(dc, x, y);
}

// Icon-first: [^] 14:32  — x is the left edge
private function drawTideInfo(dc, x, y, isHigh, time, height) {
    drawIconTide(dc, x, y, isHigh);
    drawTextAligned(dc, x + iconWidth + SPACER, y, FONT_XTINY, time, TEXT_JUSTIFY_LEFT);
}
```

**Layout constants**: All pixel coordinates are `private static const` at the top of `SurferWatchFaceView`, grouped by section. Adjusting layout = changing constants only.

---

## 6. OWM Weather Condition Code → Weather Icons Mapping

Uses the official erikflowers OWM mapping (https://erikflowers.github.io/weather-icons/api-list.html):

```
200-202, 230-232  → wi-thunderstorm (0xF01E)
210-212, 221      → wi-lightning (0xF016)
300, 301, 321     → wi-sprinkle (0xF01C)
302, 311, 312, 314→ wi-rain (0xF019)
310, 511          → wi-rain-mix (0xF017)
313, 520-522      → wi-showers (0xF01A)
500               → wi-sprinkle (0xF01C)
501-504           → wi-rain (0xF019)
531               → wi-storm-showers (0xF01D)
600, 601, 621, 622→ wi-snow (0xF01B)
602               → wi-sleet (0xF0B5)
611-616, 620      → wi-rain-mix (0xF017)
701 (mist)        → wi-showers (0xF01A)
711               → wi-smoke (0xF062)
721               → wi-day-haze (0xF0B6)
731, 761, 762     → wi-dust (0xF063)
741               → wi-fog (0xF014)
771               → wi-cloudy-gusts (0xF011)
781               → wi-tornado (0xF056)
800               → wi-day-sunny (0xF00D)
801-803           → wi-cloudy-gusts (0xF011)
804               → wi-cloudy (0xF013)
900               → wi-tornado (0xF056)
901               → wi-storm-showers (0xF01D)
902               → wi-hurricane (0xF073)
903               → wi-snowflake-cold (0xF076)
904               → wi-hot (0xF072)
905               → wi-windy (0xF021)
```

---

## 7. Moon Phase Mapping (16 phases)

```
phase == 0.0 or >= 0.96875     → wi-moon-new (0xF095)
0.0 < phase < 0.0625           → wi-moon-new (0xF095)
0.0625 <= phase < 0.125        → wi-moon-waxing-crescent-2 (0xF097)
0.125 <= phase < 0.1875        → wi-moon-waxing-crescent-4 (0xF099)
0.1875 <= phase < 0.25         → wi-moon-waxing-crescent-6 (0xF09B)
phase == 0.25                  → wi-moon-first-quarter (0xF09C)
0.25 < phase < 0.3125          → wi-moon-first-quarter (0xF09C)
0.3125 <= phase < 0.375        → wi-moon-waxing-gibbous-2 (0xF09E)
0.375 <= phase < 0.4375        → wi-moon-waxing-gibbous-4 (0xF0A0)
0.4375 <= phase < 0.5          → wi-moon-waxing-gibbous-6 (0xF0A2)
phase == 0.5                   → wi-moon-full (0xF0A3)
0.5 < phase < 0.5625           → wi-moon-full (0xF0A3)
0.5625 <= phase < 0.625        → wi-moon-waning-gibbous-2 (0xF0A5)
0.625 <= phase < 0.6875        → wi-moon-waning-gibbous-4 (0xF0A7)
0.6875 <= phase < 0.75         → wi-moon-waning-gibbous-6 (0xF0A9)
phase == 0.75                  → wi-moon-third-quarter (0xF0AA)
0.75 < phase < 0.8125          → wi-moon-third-quarter (0xF0AA)
0.8125 <= phase < 0.875        → wi-moon-waning-crescent-2 (0xF0AC)
0.875 <= phase < 0.9375        → wi-moon-waning-crescent-4 (0xF0AE)
0.9375 <= phase < 0.96875      → wi-moon-waning-crescent-6 (0xF0B0)
```

Illumination %: `Math.round(Math.sin(moonPhase * Math.PI) * 100)`

---

## 8. App Settings (settings.xml settingConfig types)

Valid `settingConfig` types in Connect IQ: `alphaNumeric`, `numeric`, `list`, `boolean`, `date`. There is NO `float` type.

| Property | properties.xml type | settingConfig type | Notes |
|----------|--------------------|--------------------|-------|
| `OWMApiKey` | `string` | `alphaNumeric` | Free-text string input |
| `StormGlassApiKey` | `string` | `alphaNumeric` | Free-text string input |
| `HomeLat` | `string` | `alphaNumeric` | Property must be `string` (not `float`) because `alphaNumeric` is only valid for string properties. Parse to float in code via `toFloat()`. |
| `HomeLng` | `string` | `alphaNumeric` | Same as HomeLat |

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
