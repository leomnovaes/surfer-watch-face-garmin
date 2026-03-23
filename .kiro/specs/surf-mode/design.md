# Surf Mode — Design Document

## Overview

Surf Mode adds an alternate watch face layout to the existing Surfer Watch Face, optimized for surfers actively in the water. The user toggles between Shore Mode (default) and Surf Mode via a Connect IQ setting. In Surf Mode, the 176x176 MIP display replaces fitness/weather data with ocean-specific data: interpolated tide height, swell conditions, water temperature, solar intensity, and surf-spot wind — all sourced from a user-configured surf spot location rather than current GPS.

No new source files are created. All changes are additions and branches within the existing `SurferWatchFaceView.mc`, `DataManager.mc`, `SurferWatchFaceDelegate.mc`, and resource files (`properties.xml`, `settings.xml`, `strings.xml`).

---

## Architecture

### High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Settings (Garmin Connect app)                                  │
│  SurfMode=0|1, SurfSpotLat, SurfSpotLng, CopyGPSToSurfSpot     │
└──────────────────────────┬──────────────────────────────────────┘
                           │ onSettingsChanged()
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│  SurferWatchFaceApp.mc                                           │
│  • onSettingsChanged(): detect mode change, reload correct cache │
│  • onBackgroundData(): route surf_ data when SurfMode=1          │
└──────────────────────────┬───────────────────────────────────────┘
                           │
          ┌────────────────┴────────────────┐
          ▼                                 ▼
┌──────────────────┐              ┌──────────────────────────┐
│  DataManager.mc  │              │  SurferWatchFaceDelegate  │
│  (foreground)    │              │  (background process)     │
│                  │              │                            │
│  New fields:     │              │  onTemporalEvent():        │
│  • swellHeight   │              │  if SurfMode=1:            │
│  • swellPeriod   │              │    lat/lng = SurfSpotLat/Lng│
│  • swellDirection│              │    fetch tide → chain swell │
│  • surfWindSpeed │              │    (StormGlass /weather)    │
│  • surfWindDeg   │              │  else:                     │
│  • waterTemp     │              │    lat/lng = GPS/Home       │
│  • solarIntensity│              │    fetch weather → tide     │
│  • interpTideHt  │              │    (existing flow)          │
│  • bottomToggle  │              └──────────────────────────┘
│                  │
│  Methods:        │
│  • interpolateTideHeight()      │
│  • onSwellData()                │
│  • loadSurfCache()              │
│  • loadShoreCache()             │
│  • checkCopyGPS()               │
└──────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────┐
│  SurferWatchFaceView.mc (foreground, onUpdate)                   │
│                                                                  │
│  onUpdate():                                                     │
│    surfMode = Properties.getValue("SurfMode")                    │
│    if surfMode == 1:                                             │
│      drawHrCircle_Surf(dc, dm)   // tide height + solar arc     │
│      drawTopSection_Surf(dc, dm) // battery, water temp, tide   │
│      drawDividers(dc)                                            │
│      drawMiddleSection_Surf(dc, dm) // wind, time, moon         │
│      if bottomToggle == "swell":                                 │
│        drawSwellSection(dc, dm)                                  │
│      else:                                                       │
│        drawTideCurve(dc, dm)                                     │
│    else:                                                         │
│      (existing shore mode rendering)                             │
└──────────────────────────────────────────────────────────────────┘
```

### Request Chaining in Surf Mode

When `SurfMode=1`, the background delegate chains StormGlass calls:

```
onTemporalEvent()
  ├─ if OWM needed (WeatherSource=1, shore mode): WeatherService.fetch() → onWeatherComplete()
  │    └─ if tide needed: TideService.fetch() → onTideComplete() → Background.exit()
  │
  └─ if SurfMode=1:
       ├─ if tide needed: TideService.fetch(surfSpotLat, surfSpotLng) → onTideComplete()
       │    └─ if swell needed: SwellService.fetch(surfSpotLat, surfSpotLng) → onSwellComplete()
       │         └─ Background.exit({tides, swell})
       └─ if only swell needed: SwellService.fetch() → onSwellComplete() → Background.exit({swell})
```

Note: Swell data is fetched from the same StormGlass `/v2/weather/point` endpoint but with different params. It is implemented as a new `fetchSwell()` method on the existing `TideService` class (or a thin wrapper), not a separate service class, to minimize background memory usage.

---

## Components and Interfaces

### Modified Files

| File | Changes |
|------|---------|
| `SurferWatchFaceView.mc` | Add surf-mode branch in `onUpdate()`, new `drawHrCircle_Surf()`, `drawTopSection_Surf()`, `drawMiddleSection_Surf()`, `drawSwellSection()`, `drawTideCurve()`, `garminConditionToSurfWindGlyph()` |
| `DataManager.mc` | Add surf data fields, `interpolateTideHeight()`, `onSwellData()`, `loadSurfCache()`, `loadShoreCache()`, `checkCopyGPS()`, `updateSurfSensors()` |
| `SurferWatchFaceDelegate.mc` | Add surf-mode coordinate selection, swell fetch chaining, `surf_` prefixed storage writes |
| `TideService.mc` | Add `fetchSwell()` method for StormGlass weather endpoint |
| `SurferWatchFaceApp.mc` | Route `swell` key from `onBackgroundData()`, detect mode change in `onSettingsChanged()` |
| `resources/settings/properties.xml` | Add `SurfMode`, `SurfSpotLat`, `SurfSpotLng`, `CopyGPSToSurfSpot` |
| `resources/settings/settings.xml` | Add setting UI entries for new properties |
| `resources/strings/strings.xml` | Add string resources for new setting labels |

### No New Files

All logic lives in existing source files. No new `.mc` files, no new font files, no new bitmap resources.

---

## Screen Layout — Surf Mode

### ASCII Diagram (176x176, 2-color MIP)

```
┌─────────────────────────────────────┐  y=0
│  [BAT%] [BAT_ICON]    ┌──────────┐  │  y=2   ROW 1: Battery (same as shore)
│  [WATER_TEMP °C/°F]   │  ↑↓      │  │  y=25  ROW 2: Water temp (replaces BT+notif)
│  [↑↓][TIDE_TIME] [HT] │ [1.2m]   │  │  y=48  ROW 3: Next tide (same as shore)
├────────────────────────│          │──│  y=68  DIVIDER
│ [→]     [HH:MM]  [🌙] │  ☀arc   │  │  y=76  MIDDLE: Wind arrow (replaces sun)
│ [12kn]  [large] [AMPM]└──────────┘  │         Wind speed below arrow
│                 [secs]               │
├──────────────────────────────────────│  y=114 (no date row — removed)
│                                      │
│  BOTTOM SECTION (toggleable):        │
│                                      │
│  [SWELL VIEW]  or  [TIDE CURVE]      │
│  ┌──────┬──────┬──────┐              │  y=120
│  │ 1.5m │ 12s  │  ↗   │  SWELL      │  Swell ht, period, direction
│  │height│period│ dir  │              │  y=148
│  └──────┴──────┴──────┘              │
│                                      │
│  ── OR ──                            │
│                                      │
│  ┌──────────────────────┐            │  y=114
│  │  ╱╲      ╱╲          │  TIDE      │  Polyline from tideExtremes
│  │ ╱  ╲    ╱  ╲    │now │  CURVE     │  "now" vertical marker
│  │╱    ╲──╱    ╲───│────│            │  H/L labels on Y axis
│  └──────────────────────┘            │  y=170
│                                      │
└──────────────────────────────────────┘  y=176
```

### Subscreen Circle (Surf Mode)

In surf mode, the subscreen circle (center 144,31, radius 31) displays:
- **Center number**: Interpolated current tide height (e.g., "1.2m" or "3.9ft"), replacing heart rate BPM
- **Top icon**: Tide direction arrow (↑ rising / ↓ falling), replacing heart icon
- **Arc gauge**: Solar intensity 0-100%, replacing stress arc. Same arc geometry (45° to 135° clockwise, 6px wide)

### Layout Constants (new/modified)

```monkeyc
// --- Surf Mode: Subscreen circle content ---
private static const SURF_TIDE_ARROW_X = 144;
private static const SURF_TIDE_ARROW_Y = 14;
private static const SURF_TIDE_TEXT_X = 144;
private static const SURF_TIDE_TEXT_Y = 34;

// --- Surf Mode: Top section Row 2 (water temp) ---
private static const SURF_WTEMP_X = 42;
private static const SURF_WTEMP_Y = TOP_ROW2_Y;  // y=25, same row as BT+notif in shore

// --- Surf Mode: Middle section left column (wind) ---
// Reuses MID_LEFT_X=22, MID_ICON_Y=76, MID_TEXT_Y=94

// --- Surf Mode: Bottom section (swell view) ---
private static const SURF_BOTTOM_Y = 120;
private static const SURF_BOTTOM_ICON_Y = SURF_BOTTOM_Y;
private static const SURF_BOTTOM_TEXT_Y = SURF_BOTTOM_Y + 18;
// Reuses WX_COL1_X=42, WX_COL2_X=88, WX_COL3_X=134

// --- Surf Mode: Bottom section (tide curve) ---
private static const TIDE_CURVE_TOP_Y = 114;
private static const TIDE_CURVE_BOTTOM_Y = 170;
private static const TIDE_CURVE_LEFT_X = 12;
private static const TIDE_CURVE_RIGHT_X = 164;
private static const TIDE_CURVE_NOW_MARKER_WIDTH = 1;
```

---

## Data Models

### New DataManager Fields

```monkeyc
// --- Surf mode: swell data (from StormGlass /v2/weather/point) ---
var swellHeight as Float or Null;       // meters
var swellPeriod as Float or Null;       // seconds
var swellDirection as Number or Null;   // degrees (0=N, meteorological)
var surfWindSpeed as Float or Null;     // m/s from StormGlass
var surfWindDeg as Number or Null;      // degrees from StormGlass
var swellFetchedDay as String or Null;  // "YYYY-MM-DD" UTC

// --- Surf mode: sensor data ---
var waterTemp as Float or Null;         // Celsius (from SensorHistory.getTemperatureHistory)
var solarIntensity as Number or Null;   // 0-100 (from SensorHistory.getSolarIntensityHistory)

// --- Surf mode: interpolated tide ---
var interpTideHeight as Float or Null;  // meters, computed each onUpdate()

// --- Surf mode: UI state ---
var bottomToggleState as Number;        // 0 = swell view, 1 = tide curve view
```

### New Application.Storage Keys

Surf mode uses `"surf_"` prefixed keys to keep caches separate:

| Key | Type | Description |
|-----|------|-------------|
| `"surf_tideExtremes"` | Array | Tide extremes for surf spot |
| `"surf_tideFetchedDay"` | String | "YYYY-MM-DD" of last surf tide fetch |
| `"surf_tideFetchLat"` | Float | Lat used for last surf tide fetch |
| `"surf_tideFetchLng"` | Float | Lng used for last surf tide fetch |
| `"surf_swellHeight"` | Float | Cached swell height (m) |
| `"surf_swellPeriod"` | Float | Cached swell period (s) |
| `"surf_swellDirection"` | Number | Cached swell direction (deg) |
| `"surf_windSpeed"` | Float | Cached surf wind speed (m/s) |
| `"surf_windDeg"` | Number | Cached surf wind direction (deg) |
| `"surf_swellFetchedDay"` | String | "YYYY-MM-DD" of last swell fetch |
| `"surf_stormGlassQuotaExhausted"` | Boolean | Quota flag for surf requests |

Shore mode continues using unprefixed keys (`"tideExtremes"`, `"tideFetchedDay"`, etc.) — no changes to existing cache.

### New Settings (properties.xml + settings.xml)

| Property | Type | Default | settingConfig | Description |
|----------|------|---------|---------------|-------------|
| `SurfMode` | number | 0 | list (0=Shore, 1=Surf) | Active display mode |
| `SurfSpotLat` | string | "0.0" | alphaNumeric | Surf spot latitude |
| `SurfSpotLng` | string | "0.0" | alphaNumeric | Surf spot longitude |
| `CopyGPSToSurfSpot` | boolean | false | boolean | One-shot GPS copy trigger |

### StormGlass Weather/Swell Endpoint

```
GET https://api.stormglass.io/v2/weather/point
  ?lat={surfSpotLat}
  &lng={surfSpotLng}
  &params=swellHeight,swellPeriod,swellDirection,windSpeed,windDirection
  &start={startOfDayUTC}
  &end={endOfDayUTC}
Headers:
  Authorization: {StormGlassApiKey}
```

**Response structure** (simplified):
```json
{
  "hours": [
    {
      "time": "2024-03-18T00:00:00+00:00",
      "swellHeight": { "sg": 1.5 },
      "swellPeriod": { "sg": 12.3 },
      "swellDirection": { "sg": 245.0 },
      "windSpeed": { "sg": 5.2 },
      "windDirection": { "sg": 180.0 }
    },
    ...
  ]
}
```

Each param has a `"sg"` (StormGlass) source key. The delegate extracts the `"sg"` value from the hourly entry closest to `now`.

### Swell Response Parsing (in background)

```
1. Parse response["hours"] array
2. For each entry, parse ISO time to unix timestamp
3. Find entry with minimum |entryTime - now|
4. Extract: swellHeight.sg, swellPeriod.sg, swellDirection.sg, windSpeed.sg, windDirection.sg
5. Package as Dictionary: {swellHeight, swellPeriod, swellDirection, windSpeed, windDeg}
6. Return via Background.exit({..., swell: swellDict})
```

---

## Detailed Method Designs

### DataManager.interpolateTideHeight()

Called from `onUpdate()` when `SurfMode=1`. Computes current tide height by cosine interpolation between the two surrounding tide extremes.

```
Algorithm:
1. If tideExtremes is null or empty → interpTideHeight = null; return
2. now = Time.now().value()
3. Walk tideExtremes to find:
   - prevEvent: last event where time <= now
   - nextEvent: first event where time > now
4. If only nextEvent exists (before first event of day):
   interpTideHeight = nextEvent.height; return
5. If only prevEvent exists (after last event of day):
   interpTideHeight = prevEvent.height; return
6. Both exist:
   t = (now - prevEvent.time) / (nextEvent.time - prevEvent.time)  // 0.0 to 1.0
   // Cosine interpolation (smooth curve between extremes):
   interpTideHeight = prevEvent.height + (nextEvent.height - prevEvent.height) * (1 - cos(t * π)) / 2
```

Why cosine interpolation: Tides follow a roughly sinusoidal pattern between extremes. Linear interpolation would create sharp corners at high/low points. Cosine interpolation naturally produces the S-curve shape that matches real tide behavior, using only `Math.cos()` which is available in Monkey C.

### DataManager.checkCopyGPS()

Called from `updateSensorData()`. Implements the one-shot GPS copy:

```
1. copyGPS = Properties.getValue("CopyGPSToSurfSpot")
2. If copyGPS != true → return
3. If lastKnownLat == null or lastKnownLng == null → return
4. Properties.setValue("SurfSpotLat", lastKnownLat.toString())
5. Properties.setValue("SurfSpotLng", lastKnownLng.toString())
6. Properties.setValue("CopyGPSToSurfSpot", false)
```

### DataManager.loadSurfCache() / loadShoreCache()

Called when mode changes (detected in `onSettingsChanged()` or on startup):

```
loadSurfCache():
  tideExtremes = Storage.getValue("surf_tideExtremes")
  tideFetchedDay = Storage.getValue("surf_tideFetchedDay")
  swellHeight = Storage.getValue("surf_swellHeight")
  swellPeriod = Storage.getValue("surf_swellPeriod")
  swellDirection = Storage.getValue("surf_swellDirection")
  surfWindSpeed = Storage.getValue("surf_windSpeed")
  surfWindDeg = Storage.getValue("surf_windDeg")
  swellFetchedDay = Storage.getValue("surf_swellFetchedDay")

loadShoreCache():
  tideExtremes = Storage.getValue("tideExtremes")
  tideFetchedDay = Storage.getValue("tideFetchedDay")
  // Weather fields loaded via existing loadWeatherData()
```

### DataManager.updateSurfSensors()

Called from `onUpdate()` when `SurfMode=1`. Reads surf-specific sensor data:

```
1. Water temperature:
   if SensorHistory has :getTemperatureHistory
     iter = SensorHistory.getTemperatureHistory({:period => 1})
     sample = iter.next()
     if sample != null and sample.data != null:
       waterTemp = sample.data.toFloat()  // Celsius
     else: waterTemp = null
   else: waterTemp = null

2. Solar intensity:
   if SensorHistory has :getSolarIntensityHistory
     iter = SensorHistory.getSolarIntensityHistory({:period => 1})
     sample = iter.next()
     if sample != null and sample.data != null:
       solarIntensity = sample.data.toNumber()  // 0-100
     else: solarIntensity = null
   else: solarIntensity = null
```

### SurferWatchFaceView.drawTideCurve(dc, dm)

Draws a tide curve in the bottom section (y=114 to y=170, x=12 to x=164).

```
Algorithm:
1. If tideExtremes is null or size < 2 → draw "--" centered; return
2. Determine time range: startTime = start of today UTC, endTime = end of today UTC
3. Filter tideExtremes to events within [startTime, endTime]
4. If filtered < 2 → draw "--"; return
5. Compute Y range: minHeight = min(all heights), maxHeight = max(all heights)
   Add 5% padding to both ends
6. For each pixel column x from TIDE_CURVE_LEFT_X to TIDE_CURVE_RIGHT_X:
   a. Map x to time: t = startTime + (x - LEFT_X) / (RIGHT_X - LEFT_X) * (endTime - startTime)
   b. Find surrounding events (prev, next) for time t
   c. Cosine-interpolate height at time t (same algorithm as interpolateTideHeight)
   d. Map height to y: y = BOTTOM_Y - (height - minHeight) / (maxHeight - minHeight) * (BOTTOM_Y - TOP_Y)
   e. Draw pixel at (x, y) — dc.drawPoint(x, y)
7. Draw "now" marker:
   nowX = LEFT_X + (now - startTime) / (endTime - startTime) * (RIGHT_X - LEFT_X)
   dc.drawLine(nowX, TOP_Y, nowX, BOTTOM_Y)  // vertical line
8. Label H/L on Y axis:
   Draw maxHeight value at (LEFT_X-2, TOP_Y) right-justified
   Draw minHeight value at (LEFT_X-2, BOTTOM_Y) right-justified
```

### SurferWatchFaceView.drawSwellSection(dc, dm)

Three-column layout matching weather widget positions:

```
Col 1 (x=42): Swell height
  Icon: wave glyph from surfer-icons font (reuse "H" tide-high glyph)
  Text: height in m or ft (e.g., "1.5m" or "4.9ft")

Col 2 (x=88): Swell period
  Icon: text "s" or clock glyph
  Text: period in seconds (e.g., "12s")

Col 3 (x=134): Swell direction
  Icon: wind arrow rotated to swellDirection degrees (reuse drawWindArrow)
  Text: compass label (e.g., "SW")
```

### SurferWatchFaceDelegate — Surf Mode Coordinate Selection

In `onTemporalEvent()`, after reading GPS from Storage:

```
surfMode = Properties.getValue("SurfMode")
if surfMode == 1:
  surfLat = Properties.getValue("SurfSpotLat")
  surfLng = Properties.getValue("SurfSpotLng")
  if surfLat != null and surfLng != null:
    lat = surfLat.toFloat()
    lng = surfLng.toFloat()
    if lat == 0.0 and lng == 0.0:
      // Not configured — skip surf fetches
      Background.exit(null); return
  // Use surf spot coordinates for tide + swell
  // Still use GPS coordinates for OWM weather if WeatherSource=1
```

### Garmin Condition Code to Surf Wind Icon Mapping

In surf mode, wind data comes from StormGlass (degrees + m/s), not from a weather condition code. The wind arrow is drawn using the existing `drawWindArrow()` method with `surfWindDeg`. No condition-code-to-icon mapping is needed for surf wind — it's a direct degree value.

For the swell direction arrow in the bottom section, the same `drawWindArrow()` is reused with `swellDirection` degrees.

### SurferWatchFaceView.onUpdate() — Mode Branch

```monkeyc
function onUpdate(dc as Dc) as Void {
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
    dc.clear();
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

    var dm = getApp().getDataManager();
    if (dm == null) { return; }

    var surfMode = Application.Properties.getValue("SurfMode");

    if (surfMode != null && surfMode == 1) {
        // Surf mode
        dm.updateSensorData();
        dm.checkCopyGPS();
        dm.updateSurfSensors();
        dm.computeNextTide();
        dm.interpolateTideHeight();
        dm.computeMoonPhase();

        drawHrCircle_Surf(dc, dm);
        drawTopSection_Surf(dc, dm);
        drawDividers(dc);
        drawMiddleSection_Surf(dc, dm);
        if (dm.bottomToggleState == 0) {
            drawSwellSection(dc, dm);
        } else {
            drawTideCurve(dc, dm);
        }
    } else {
        // Shore mode (existing)
        dm.updateSensorData();
        dm.computeMoonPhase();
        dm.computeNextTide();
        // ... existing shore rendering ...
    }
}
```

### Button Press Handling (onSelect toggle)

The `SurferWatchFaceApp.getInitialView()` currently returns `[new SurferWatchFaceView()]`. To handle button presses, it must also return a `BehaviorDelegate`:

```monkeyc
// In SurferWatchFaceApp.mc:
function getInitialView() as [Views] or [Views, InputDelegates] {
    dataManager = new DataManager();
    return [new SurferWatchFaceView(), new SurferWatchFaceBehaviorDelegate()];
}
```

Wait — we said no new files. The behavior delegate can be a simple inner approach, but Monkey C doesn't support inner classes. Instead, we add `onSelect` handling to the existing view via `WatchFace` behavior. Actually, `WatchUi.WatchFace` doesn't receive `onSelect` directly. We need a `WatchUi.BehaviorDelegate` returned alongside the view.

Since we want no new files, we add the `BehaviorDelegate` class to the bottom of `SurferWatchFaceView.mc`:

```monkeyc
class SurferWatchFaceBehaviorDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            var dm = getApp().getDataManager();
            if (dm != null) {
                dm.bottomToggleState = (dm.bottomToggleState == 0) ? 1 : 0;
                WatchUi.requestUpdate();
            }
            return true;
        }
        return false;  // Shore mode: default Garmin behavior
    }
}
```

This class lives in `SurferWatchFaceView.mc` alongside the view class.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: CopyGPS Round Trip

*For any* valid GPS coordinate pair (lat, lng) where lat ∈ [-90, 90] and lng ∈ [-180, 180], when `CopyGPSToSurfSpot` is set to true and `lastKnownLat`/`lastKnownLng` hold those coordinates, after calling `checkCopyGPS()`, `Properties.getValue("SurfSpotLat").toFloat()` should equal lat, `Properties.getValue("SurfSpotLng").toFloat()` should equal lng, and `Properties.getValue("CopyGPSToSurfSpot")` should be false.

**Validates: Requirements 2.4, 2.5**

### Property 2: Mode Determines API Coordinates

*For any* SurfMode value (0 or 1), any surf spot coordinate pair, and any GPS/Home coordinate pair: when `SurfMode=1`, the coordinates passed to StormGlass API calls should equal the surf spot coordinates; when `SurfMode=0`, the coordinates should equal the GPS/Home coordinates.

**Validates: Requirements 2.7, 2.8**

### Property 3: Tide Direction Arrow Matches Next Tide Type

*For any* tide extremes array where a next tide event exists, the tide direction arrow should point up (rising) when `nextTideType` is "high" and down (falling) when `nextTideType` is "low".

**Validates: Requirements 3.3**

### Property 4: Water Temperature Unit Conversion

*For any* temperature value in Celsius, when device units are UNIT_METRIC the displayed value should equal the Celsius value rounded to integer with "°C" suffix; when device units are UNIT_STATUTE the displayed value should equal `(celsius * 1.8 + 32)` rounded to integer with "°F" suffix.

**Validates: Requirements 4.4**

### Property 5: Swell Height Unit Conversion

*For any* swell height value in meters, when device units are UNIT_METRIC the displayed value should be formatted as meters (e.g., "1.5m"); when device units are UNIT_STATUTE the displayed value should equal `meters * 3.281` formatted as feet (e.g., "4.9ft").

**Validates: Requirements 6.2**

### Property 6: Tide Interpolation Correctness

*For any* tide extremes array with at least two events and *for any* time t between two consecutive events (prevEvent, nextEvent), the interpolated tide height should satisfy: (a) it is between prevEvent.height and nextEvent.height (inclusive), and (b) when t equals prevEvent.time, the result equals prevEvent.height, and when t equals nextEvent.time, the result equals nextEvent.height.

**Validates: Requirements 14.1, 7.2**

### Property 7: Now Marker Time-to-X Mapping

*For any* time t within [startOfDay, endOfDay], the "now" marker X position should equal `LEFT_X + (t - startOfDay) / (endOfDay - startOfDay) * (RIGHT_X - LEFT_X)`, producing a linear mapping from time to horizontal pixel position.

**Validates: Requirements 7.3**

### Property 8: onSelect Behavior Based on Mode

*For any* call to `onSelect()`, when `SurfMode=1` the method should return true, and when `SurfMode=0` the method should return false.

**Validates: Requirements 8.1, 8.5**

### Property 9: Bottom Toggle Round Trip

*For any* initial `bottomToggleState` value (0 or 1), calling the toggle action twice should restore the original state. Equivalently, toggling is an involution: `toggle(toggle(state)) == state`.

**Validates: Requirements 8.2**

### Property 10: Closest Hourly Entry Selection

*For any* array of hourly swell entries with timestamps and *for any* target time `now`, the selected entry should have the minimum absolute time difference `|entry.time - now|` among all entries in the array.

**Validates: Requirements 9.4**

### Property 11: Cache Key Isolation by Mode

*For any* data persisted by DataManager, when `SurfMode=1` all Application.Storage keys for tide, swell, wind, and fetch metadata should be prefixed with `"surf_"`; when `SurfMode=0` the same categories of data should use unprefixed keys. No surf-mode write should overwrite a shore-mode key and vice versa.

**Validates: Requirements 9.6, 10.1, 10.2, 10.5, 11.3, 12.2**

### Property 12: Cache Round Trip on Mode Switch

*For any* set of surf-mode cached data (tide extremes, swell, wind), storing it while in `SurfMode=1`, switching to `SurfMode=0` (which loads shore cache), then switching back to `SurfMode=1` should restore the original surf-mode data from `"surf_"` prefixed storage keys.

**Validates: Requirements 10.3, 10.4**

### Property 13: StormGlass Daily Call Limit in Surf Mode

*For any* sequence of `onTemporalEvent()` invocations on the same calendar day while `SurfMode=1`, the total number of StormGlass API calls (tide + swell combined) should be at most 2.

**Validates: Requirements 11.1, 9.5**

### Property 14: Swell Request 24-Hour Window

*For any* day, the swell fetch request's `start` parameter should equal the start of that day in UTC (midnight) and the `end` parameter should equal `start + 86400` (24 hours later).

**Validates: Requirements 9.3**

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| SurfSpotLat/Lng = "0.0" or empty | Display "--" for all location-dependent surf fields. Skip StormGlass fetches. |
| StormGlass swell API returns non-200 | Skip swell parsing, retain cached swell data. Log nothing (no logging API on watch). |
| StormGlass quota exhausted (`requestCount >= dailyQuota`) | Set `surf_stormGlassQuotaExhausted = true`. Skip both tide and swell fetches until new calendar day. |
| StormGlass swell response missing `"hours"` array | Return null from swell parsing. Display "--" for swell fields. |
| StormGlass swell entry missing `"sg"` key | Skip that entry, try next closest hour. If no valid entries, return null. |
| SensorHistory.getTemperatureHistory unavailable | `waterTemp = null`, display "--". |
| SensorHistory.getSolarIntensityHistory unavailable | `solarIntensity = null`, display 0% arc (empty). |
| Tide extremes array empty or null in surf mode | `interpTideHeight = null`, display "--" in subscreen. Tide curve shows "--". |
| Only one tide extreme available (before first or after last event) | Use nearest event's height directly (no interpolation). |
| No phone connection (BT disconnected) | Skip all background fetches (existing guard). Render from cached data. |
| CopyGPSToSurfSpot toggled but no GPS fix | Do nothing, leave CopyGPSToSurfSpot as true. Will retry on next `updateSensorData()` call when GPS becomes available. |
| Mode switch while background fetch in progress | Background writes to keys based on mode at fetch time. If mode changed mid-flight, data lands in the correct prefixed/unprefixed keys based on the mode that initiated the fetch. On next `onSettingsChanged()`, the correct cache is loaded. |

---

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests for comprehensive coverage.

**Unit tests** cover:
- Specific examples: known tide extreme arrays with expected interpolation results
- Edge cases: empty tide arrays, single-event arrays, null sensor data, "0.0" surf spot coordinates
- Integration points: `onBackgroundData()` routing swell data, `onSettingsChanged()` cache switching
- Error conditions: malformed StormGlass responses, missing `"sg"` keys, quota exhaustion

**Property-based tests** cover:
- Universal properties across all valid inputs (Properties 1-14 above)
- Each property test runs minimum 100 iterations with randomized inputs
- Generators produce: random GPS coordinates, random tide extreme arrays, random swell response arrays, random timestamps

### Property-Based Testing Library

**Library**: Since Monkey C has no PBT library and tests would need to run outside the watch, property tests will be written as **pseudocode specifications** in the design and implemented as parameterized unit tests with randomized inputs using Monkey C's `Test` module (SDK test harness). Each test generates 100+ random inputs in a loop.

Alternative: For complex properties (interpolation, cache isolation), extract pure logic into testable functions and test with a JUnit-based harness via the SDK's Java test bridge, using **jqwik** (Java PBT library) for true property-based testing.

### Test Tagging

Each property-based test must include a comment referencing the design property:

```monkeyc
// Feature: surf-mode, Property 6: Tide interpolation correctness
// For any tide extremes array with at least two events and for any time t
// between two consecutive events, the interpolated height is between the
// surrounding heights and equals the exact height at event times.
(:test)
function testTideInterpolationCorrectness(logger as Logger) as Boolean {
    // 100 iterations with random tide arrays and timestamps
    ...
}
```

### Key Test Scenarios

| Property | Generator | Oracle |
|----------|-----------|--------|
| P1: CopyGPS | Random lat ∈ [-90,90], lng ∈ [-180,180] | SurfSpotLat/Lng match, flag reset |
| P2: Mode coordinates | Random mode (0/1), random coords | Correct coord set passed to API |
| P6: Tide interpolation | Random 2-6 extremes, random t between them | Height ∈ [min,max] of surrounding pair; exact at endpoints |
| P9: Toggle round trip | Random initial state (0/1) | toggle(toggle(s)) == s |
| P10: Closest entry | Random hourly array (1-24 entries), random now | Selected entry minimizes |time - now| |
| P11: Cache isolation | Random data, random mode | Keys prefixed correctly per mode |
| P14: 24h window | Random date | start = midnight UTC, end = start + 86400 |
