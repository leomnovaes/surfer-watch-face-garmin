# Surf Mode — Design Document

## Overview

Surf Mode adds an alternate watch face layout to the existing Surfer Watch Face, optimized for surfers actively in the water. The user toggles between Shore Mode (default) and Surf Mode via a Connect IQ setting. In Surf Mode, the 176x176 MIP display replaces fitness/weather data with ocean-specific data: interpolated tide height, swell conditions, water temperature, solar intensity, and surf-spot wind — all sourced from a user-configured surf spot location rather than current GPS.

One new source file was created: `OpenMeteoService.mc` for all Open-Meteo API calls (swell, weather, surf wind). All other changes are additions and branches within existing files.

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

When `SurfMode=1`, the background delegate chains API calls:

```
onTemporalEvent()
  ├─ if Shore mode (SurfMode=0):
  │    ├─ if OWM needed (WeatherSource=1): WeatherService.fetch() → onShoreWeatherDone()
  │    │    └─ if tide needed: TideService.fetch() → onTideComplete() → Background.exit()
  │    └─ if only tide needed: TideService.fetch() → onTideComplete() → Background.exit()
  │
  └─ if Surf mode (SurfMode=1):
       ├─ Open-Meteo swell (always): TideService.fetchSwell() → onSwellDone()
       │    └─ if tide needed: TideService.fetch(SG) → onTideComplete()
       │         └─ if wind needed (OWM key set): WeatherService.fetch() → onWindDone()
       │              └─ Background.exit({swell, tides, weather})
       └─ if -403 at any point: stop chain, exit with partial results
```

Data sources per mode:
- **Swell**: Open-Meteo Marine API (free, no key, ~1.2KB response, fetched every temporal event)
- **Tide**: StormGlass tide extremes (1 call/day, backup key on 402)
- **Wind (surf)**: OWM 2.5 for surf spot coordinates → only windSpeed/windDeg extracted
- **Wind (shore)**: OWM 2.5 or Garmin built-in for GPS coordinates → full weather fields

Note: Surf mode wind uses separate DataManager fields (`surfWindSpeed`, `surfWindDeg`) to avoid cross-contaminating shore weather data. The delegate's `onWindDone()` callback only extracts wind fields when in surf mode.

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
// --- Surf mode: swell data (from Open-Meteo Marine API, hourly forecast) ---
var swellHeight as Float or Null;       // meters (current hour from forecast array)
var swellPeriod as Float or Null;       // seconds (current hour from forecast array)
var swellDirection as Number or Null;   // degrees (0=N, meteorological, current hour)

// --- Surf mode: wind data (from OWM 2.5 for surf spot, separate from shore) ---
var surfWindSpeed as Float or Null;     // m/s or mph from OWM (depends on units param)
var surfWindDeg as Number or Null;      // degrees from OWM

// --- Surf mode: sensor data ---
var waterTemp as Float or Null;         // Celsius (from SensorHistory.getTemperatureHistory)
var solarIntensity as Number or Null;   // 0-100 (from System.getSystemStats().solarIntensity)

// --- Surf mode: interpolated tide ---
var interpTideHeight as Float or Null;  // meters, cosine-interpolated each onUpdate()

// --- Surf mode: UI state ---
var bottomToggleState as Number;        // 0 = swell view, 1 = tide curve view
```

### New Application.Storage Keys

Surf mode uses `"surf_"` prefixed keys to keep caches separate:

| Key | Type | Description |
|-----|------|-------------|
| `"surf_tideHeights"` | Array | Tide heights for surf spot (flat array, meters) |
| `"surf_tideTimes"` | Array | Tide event times for surf spot (flat array, unix timestamps) |
| `"surf_tideTypes"` | Array | Tide event types for surf spot (flat array, 1=high 0=low) |
| `"surf_tideFetchedDay"` | String | "YYYY-MM-DD" of last surf tide fetch |
| `"surf_tideFetchLat"` | Float | Lat used for last surf tide fetch |
| `"surf_tideFetchLng"` | Float | Lng used for last surf tide fetch |
| `"surf_tideDataExpired"` | Boolean | Whether surf tide data needs refresh |
| `"surf_swellHeights"` | Array | 24h hourly swell heights (meters) from Open-Meteo |
| `"surf_swellPeriods"` | Array | 24h hourly swell periods (seconds) from Open-Meteo |
| `"surf_swellDirections"` | Array | 24h hourly swell directions (degrees) from Open-Meteo |
| `"sgLastResponseCode"` | Number | Last StormGlass HTTP response code |

Shore mode uses unprefixed keys (`"tideHeights"`, `"tideTimes"`, `"tideTypes"`, `"tideFetchedDay"`, etc.).

Note: Surf wind (`surfWindSpeed`, `surfWindDeg`) is not persisted to Storage — it's fetched live from OWM every temporal event and held only in DataManager memory.

### New Settings (properties.xml + settings.xml)

| Property | Type | Default | settingConfig | Description |
|----------|------|---------|---------------|-------------|
| `SurfMode` | number | 0 | list (0=Shore, 1=Surf) | Active display mode |
| `SurfSpotLat` | string | "0.0" | alphaNumeric | Surf spot latitude |
| `SurfSpotLng` | string | "0.0" | alphaNumeric | Surf spot longitude |
| `CopyGPSToSurfSpot` | boolean | false | boolean | One-shot GPS copy trigger |

### Open-Meteo Marine API (Swell)

```
GET https://marine-api.open-meteo.com/v1/marine
  ?latitude={surfSpotLat}
  &longitude={surfSpotLng}
  &hourly=swell_wave_height,swell_wave_period,swell_wave_direction
  &forecast_days=1
```

No API key required. No rate limit.

**Response structure**:
```json
{
  "hourly": {
    "time": ["2024-03-18T00:00", "2024-03-18T01:00", ...],
    "swell_wave_height": [1.5, 1.4, ...],
    "swell_wave_period": [12.3, 12.1, ...],
    "swell_wave_direction": [245.0, 243.0, ...]
  }
}
```

Response is ~1.2KB for 24 hours — fits comfortably in background memory (~28KB).

### Swell Response Parsing (in background)

```
1. Parse response["hourly"] dictionary
2. Extract flat arrays: swell_wave_height, swell_wave_period, swell_wave_direction
3. Pass arrays directly via callback (no per-entry parsing needed)
4. Delegate stores arrays in Application.Storage (surf_swellHeights, surf_swellPeriods, surf_swellDirections)
5. Extract current hour's entry for immediate display in Background.exit() result
6. DataManager.updateSwellFromForecast() picks current hour on each onUpdate()
```

### Surf Mode Wind (OWM 2.5)

Wind in surf mode is fetched from OWM 2.5 Current Weather using surf spot coordinates. The delegate's `onWindDone()` callback extracts only `windSpeed` and `windDeg` — it does NOT store temperature, condition, sunrise, or sunset to avoid polluting shore weather fields.

Wind is stored in separate DataManager fields: `surfWindSpeed` and `surfWindDeg`.

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
  tideHeights = Storage.getValue("surf_tideHeights")
  tideTimes = Storage.getValue("surf_tideTimes")
  tideTypes = Storage.getValue("surf_tideTypes")
  tideFetchedDay = Storage.getValue("surf_tideFetchedDay")

loadShoreCache():
  tideHeights = Storage.getValue("tideHeights")
  tideTimes = Storage.getValue("tideTimes")
  tideTypes = Storage.getValue("tideTypes")
  tideFetchedDay = Storage.getValue("tideFetchedDay")
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
   var stats = System.getSystemStats()
   if stats has :solarIntensity and stats.solarIntensity != null:
     solarIntensity = stats.solarIntensity.toNumber()  // 0-100
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

In `onTemporalEvent()`, coordinates are selected based on mode:

```
surfMode = Properties.getValue("SurfMode")
if surfMode == 1:
  surfLat = Properties.getValue("SurfSpotLat")
  surfLng = Properties.getValue("SurfSpotLng")
  if surfLat != null and surfLng != null:
    lat = surfLat.toFloat()
    lng = surfLng.toFloat()
    if lat == 0.0 and lng == 0.0:
      // Not configured — skip all surf fetches
      Background.exit(null); return
  // Use surf spot coordinates for swell (Open-Meteo), tide (SG), and wind (OWM)
else:
  lat = Storage.getValue("lastKnownLat")
  lng = Storage.getValue("lastKnownLng")
  // Use GPS/Home coordinates for weather (OWM/Garmin) and tide (SG)
```

### Surf Mode Wind Source

In surf mode, wind data comes from OWM 2.5 Current Weather for the surf spot coordinates. The delegate's `onWindDone()` callback extracts only `windSpeed` and `windDeg` from the OWM response and stores them in `surfWindSpeed`/`surfWindDeg` — separate from shore mode's `windSpeed`/`windDeg`.

The wind arrow is drawn using the existing `drawWindArrow()` method with `dm.surfWindDeg`. The arrow tip points in the TRAVEL direction (where wind/swell is heading), and the swallow tail indicates the origin. Wind speed is normalized to m/s and converted per the `WindSpeedUnit` setting, using the same logic as shore mode.

For the swell direction arrow in the bottom section, the same `drawWindArrow()` is reused with `swellDirection` degrees from the Open-Meteo forecast. Same convention: tip = travel direction, tail = origin.

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

### Double Wrist Gesture Toggle (onExitSleep timing)

Watch faces cannot receive button input (no onSelect, no BehaviorDelegate). The toggle mechanism uses `onExitSleep()` timing to detect a double wrist raise:

```monkeyc
// In SurferWatchFaceView.mc:
private var lastWristRaiseTime as Number = 0;

function onExitSleep() as Void {
    isSleeping = false;
    var surfMode = Application.Properties.getValue("SurfMode");
    if (surfMode != null && surfMode == 1) {
        var now = Time.now().value();
        var diff = now - lastWristRaiseTime;
        if (lastWristRaiseTime > 0 && diff < 10) {
            // Double raise detected — toggle bottom view
            var dm = getApp().getDataManager();
            if (dm != null) {
                dm.bottomToggleState = (dm.bottomToggleState == 0) ? 1 : 0;
            }
            lastWristRaiseTime = 0;
        } else {
            lastWristRaiseTime = now;
        }
    }
    WatchUi.requestUpdate();
}
```

The 4-second window balances intentional activation with comfort — a natural double-raise takes 2-4 seconds.

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

### Property 8: Double Wrist Gesture Toggle Behavior Based on Mode

*For any* double wrist gesture (two `onExitSleep()` calls within the detection window), when `SurfMode=1` the `bottomToggleState` should flip (0→1 or 1→0), and when `SurfMode=0` no toggle should occur.

**Validates: Requirements 8.1, 8.2**

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
| SurfSpotLat/Lng = "0.0" or empty | Display "--" for all location-dependent surf fields. Skip all surf fetches. |
| Open-Meteo swell API returns non-200 | Skip swell parsing, retain cached swell forecast arrays. Chain continues to tide. |
| Open-Meteo swell response missing `"hourly"` | Return null from swell parsing. Display "--" for swell fields. |
| StormGlass tide API returns 402 (quota) | Immediately retry with backup key in the same cycle. If backup also fails, skip tide. |
| StormGlass tide API returns non-200 (not 402) | Skip tide, retain cached data. Do NOT try backup (avoid exhausting both keys). |
| StormGlass response returns -403 | Background memory exhausted. Stop chain immediately, exit with partial results. |
| OWM wind API returns non-200 | Skip wind, display "--" for wind in surf mode. |
| No OWM API key configured | Skip wind fetch entirely. Display "--" for wind. |
| SensorHistory.getTemperatureHistory unavailable | `waterTemp = null`, display "--". |
| System.getSystemStats().solarIntensity unavailable | `solarIntensity = null`, display 0% arc (empty). |
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

---

## Phase 3 — Open-Meteo Weather Source & Offline Wind

### Overview

Add Open-Meteo as a third weather source option (alongside Garmin built-in and OWM). This enables:
1. Zero-config weather updates for shore mode (no API key needed)
2. Hourly wind forecast for surf mode offline use (advances through stored array when phone disconnects)
3. Precipitation probability from Open-Meteo (replaces Garmin built-in when Open-Meteo selected)

### WeatherSource Setting Change

Current: `WeatherSource` list with 2 values (0=Garmin, 1=OWM)
New: `WeatherSource` list with 3 values (0=Garmin, 1=Open-Meteo, 2=OWM)

Note: OWM moves from value 1 to value 2. This is a breaking change for users who had OWM selected — they'll need to re-select it. Acceptable since the watch face is pre-release.

### Updated Request Chaining

```
onTemporalEvent()
  ├─ Shore mode (SurfMode=0):
  │    ├─ WeatherSource=0 (Garmin): no weather fetch, only tide if needed
  │    ├─ WeatherSource=1 (Open-Meteo): OpenMeteoService.fetchCurrent() → onShoreWeatherDone()
  │    │    └─ if tide needed: TideService.fetch() → onTideComplete() → exit
  │    └─ WeatherSource=2 (OWM): WeatherService.fetch() → onShoreWeatherDone()
  │         └─ if tide needed: TideService.fetch() → onTideComplete() → exit
  │
  └─ Surf mode (SurfMode=1):
       ├─ Open-Meteo swell (always): TideService.fetchSwell() → onSwellDone()
       │    └─ if tide needed: TideService.fetch(SG) → onTideComplete()
       │         ├─ WeatherSource=0 (Garmin): no wind fetch → exit
       │         ├─ WeatherSource=1 (Open-Meteo): OpenMeteoService.fetchSurfWind() → onSurfWindDone()
       │         │    └─ exit (stores 24h hourly wind arrays)
       │         └─ WeatherSource=2 (OWM): WeatherService.fetch() → onWindDone()
       │              └─ exit (stores current wind only)
       └─ if -403 at any point: stop chain, exit with partial results
```

### Open-Meteo API Endpoints

**Shore mode (current weather):**
```
GET https://api.open-meteo.com/v1/forecast
  ?latitude={lat}&longitude={lon}
  &current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation_probability,is_day
  &daily=sunrise,sunset
  &timezone=auto
  &forecast_days=1
  &wind_speed_unit=ms
```
Response: ~670 bytes. Contains current snapshot + today's sunrise/sunset.

**Surf mode (hourly wind forecast):**
```
GET https://api.open-meteo.com/v1/forecast
  ?latitude={lat}&longitude={lon}
  &hourly=wind_speed_10m,wind_direction_10m
  &forecast_days=1
  &timezone=auto
  &wind_speed_unit=ms
```
Response: ~986 bytes. Contains 24 hourly wind entries.

Both use `wind_speed_unit=ms` to get m/s directly — matches our internal normalization (all wind speeds stored as m/s, converted at display time per WindSpeedUnit setting).

### New Service: OpenMeteoService

A new class in `WeatherService.mc` (or a separate file — TBD based on background memory). Annotated with `:background`.

```monkeyc
(:background)
class OpenMeteoService {
    private var _callback as Method;

    function initialize(callback as Method) {
        _callback = callback;
    }

    // Shore mode: fetch current weather + sunrise/sunset
    function fetchCurrent(lat as Float, lon as Float) as Void { ... }

    // Surf mode: fetch 24h hourly wind forecast
    function fetchSurfWind(lat as Float, lon as Float, callback as Method) as Void { ... }
}
```

### WMO Weather Code Mapping

WMO codes (0-99) mapped to existing Erik Flowers glyphs:

| WMO Code | Condition | Day Glyph | Night Glyph |
|----------|-----------|-----------|-------------|
| 0 | Clear sky | A | a |
| 1 | Mainly clear | B | b |
| 2 | Partly cloudy | C | b |
| 3 | Overcast | D | D |
| 45, 48 | Fog, rime fog | E | E |
| 51, 53, 55 | Drizzle (light/mod/dense) | G | d |
| 56, 57 | Freezing drizzle | K | K |
| 61, 63, 65 | Rain (slight/mod/heavy) | H | c |
| 66, 67 | Freezing rain | K | K |
| 71, 73, 75 | Snow (slight/mod/heavy) | J | f |
| 77 | Snow grains | M | M |
| 80, 81, 82 | Rain showers | I | d |
| 85, 86 | Snow showers | J | f |
| 95 | Thunderstorm | F | e |
| 96, 99 | Thunderstorm with hail | F | e |
| Other | Fallback: clear | A | a |

**Conditions NOT available in WMO (OWM-only):**
smoke, haze, dust/sand, squalls, tornado, tropical storm, hurricane, cold, hot, windy.
These are rare/extreme conditions. When using Open-Meteo, these conditions will show as the nearest WMO equivalent or clear fallback.

### Sunrise/Sunset Parsing from Open-Meteo

Open-Meteo returns sunrise/sunset as ISO 8601 local time strings (e.g., `"2026-03-23T07:12"`). These need to be parsed to Unix timestamps for DataManager.

The parsing reuses the existing `parseISOToUnix()` pattern from TideService, but the format is shorter (no seconds, no timezone offset — it's already local time when `timezone=auto` is used).

However, since `Gregorian.moment()` interprets input as UTC, and Open-Meteo returns local time when `timezone=auto`, we need to subtract the UTC offset. Open-Meteo provides `utc_offset_seconds` in the response for this purpose.

### Surf Mode Wind Forecast Storage

When WeatherSource=1 (Open-Meteo) and SurfMode=1:

| Storage Key | Type | Description |
|-------------|------|-------------|
| `surf_windSpeeds` | Array<Float> | 24h hourly wind speeds (m/s) |
| `surf_windDirections` | Array<Number> | 24h hourly wind directions (degrees) |

DataManager reads these arrays via `updateSurfWindFromForecast()` on each `onUpdate()`, picking the current hour's entry — same pattern as `updateSwellFromForecast()`.

When WeatherSource=2 (OWM), surf wind continues to use the current-only `surfWindSpeed`/`surfWindDeg` fields (no forecast array).

### Precipitation Probability by Source

All sources populate `dm.precipProbability`. The view reads only from `dm.precipProbability`.

| WeatherSource | Precip Source | How populated |
|---------------|--------------|---------------|
| 0 (Garmin) | `Weather.getCurrentConditions().precipitationChance` | `updateGarminWeather()` every tick |
| 1 (Open-Meteo) | `current.precipitation_probability` from API response | `onWeatherData()` from background |
| 2 (OWM) | `Weather.getCurrentConditions().precipitationChance` (fallback) | `onWeatherData()` reads Garmin when API has no pop |

### Memory Budget for Surf Mode Chain (Open-Meteo)

Worst case: all three requests in one temporal event cycle.
- Open-Meteo swell: ~1.2KB response
- StormGlass tide: ~1-2KB response (4-6 extremes)
- Open-Meteo wind: ~986 bytes response

Each response is parsed and stored before the next request fires (chained callbacks). The background process only holds one response in memory at a time. Total stored data in Application.Storage grows, but Storage is persistent and doesn't count against background memory.

### Impact on Shore Mode

Shore mode with Open-Meteo (WeatherSource=1) uses `current=` params only — no hourly arrays. The response is ~670 bytes, parsed into the same DataManager fields as OWM (temperature, weatherConditionId, windSpeed, windDeg, sunrise, sunset). The only difference is the condition code mapper used at render time.

Shore mode does NOT store hourly forecast arrays. Wind shows the latest fetched value and goes stale when offline — same behavior as current OWM mode.
