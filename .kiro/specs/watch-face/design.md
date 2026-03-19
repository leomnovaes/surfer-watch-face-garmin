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
  - Top-left: moon phase icon
  - Top-right: empty (moon illumination % added in Task 21)
  - Bottom-left: am/pm, left-justified
  - Bottom-right: seconds (visible for layout, hidden by default in Task 28)

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

### 5.1 Approach: Custom Icon Font
All icons are rendered via `drawText()` using a custom icon font (BMFont format). This approach was chosen because:
- **Memory efficient**: one font file holds all icon glyphs, vs individual bitmap files
- **CPU efficient**: font rendering is hardware-optimized on Garmin devices
- **Alignment**: since both text and icons go through `drawText()`, they share the same padding behavior and align naturally at the same Y coordinate — no manual offset needed
- **Color flexible**: icon color can be changed via `dc.setColor()` like any text (not needed for our 1-bit display, but good for portability)

Source font: Font Awesome subset or ftrimboli's Garmin standard icons TTF, converted via `fontbm` (Mac-compatible BMFont alternative) to `.fnt` + `.png` format.

Font resource declared in `resources/fonts/fonts.xml`:
```xml
<fonts>
    <font id="IconFont" filename="icons.fnt" filter="..." />
</fonts>
```

Loaded in code: `var iconFont = WatchUi.loadResource(Rez.Fonts.IconFont);`

### 5.2 Icon Glyph Mapping
Each icon is mapped to a character in the icon font. Until the icon font is created (Task 27), text placeholders are used:

| Icon | Placeholder | Final glyph | Used for |
|------|------------|-------------|----------|
| Battery | `[=]` | TBD | Battery level |
| Notification | `[!]` | TBD | Notification bell |
| Tide High | `[^]` | TBD | Next tide = high (↑) |
| Tide Low | `[v]` | TBD | Next tide = low (↓) |
| Sunrise | `[*]` | TBD | Next event = sunrise |
| Sunset | `[.]` | TBD | Next event = sunset |
| Bluetooth | `[B]` | TBD | Bluetooth connected |
| Moon | `[O]` | TBD | Moon phase |
| Weather | `[~]` | TBD | Weather condition |
| Wind | `[>]` | TBD | Wind direction |
| Umbrella | `[U]` | TBD | Precipitation |
| Heart | `<3` | TBD | Heart rate |

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

## 6. OWM Weather Condition Code Mapping

```
200–232  → ic_weather_thunderstorm
300–321  → ic_weather_drizzle
500–531  → ic_weather_rain
600–622  → ic_weather_snow
700–781  → ic_weather_fog
800      → ic_weather_clear
801–804  → ic_weather_clouds
```

---

## 7. Moon Phase Mapping

```
phase == 0.0 or == 1.0        → ic_moon_new
0.0 < phase < 0.25            → ic_moon_waxing_crescent
phase == 0.25                 → ic_moon_first_quarter
0.25 < phase < 0.5            → ic_moon_waxing_gibbous
phase == 0.5                  → ic_moon_full
0.5 < phase < 0.75            → ic_moon_waning_gibbous
phase == 0.75                 → ic_moon_last_quarter
0.75 < phase < 1.0            → ic_moon_waning_crescent
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
