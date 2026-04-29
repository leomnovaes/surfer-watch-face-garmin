# Technology Stack

## Target Device
- Garmin Instinct 2X Solar
- Screen: 176x176px, semi-octagon shape
- Display: Memory-In-Pixel (MIP), 2 colors (black = 0x000000, white = 0xFFFFFF)
- Connect IQ API Level: 3.4
- Device ID: `instinct2x`
- Memory: ~65KB heap (tight — keep allocations minimal)
- Sub-screen: circular cutout at top-right, canvas position x=113 y=1 62x62px, center=(144,31) radius=31 (from simulator.json, Y tuned to fit)

## Language
- Monkey C (Garmin's proprietary language)
- Java-like syntax: classes, methods, inheritance
- Weakly typed with optional type annotations
- No generics, limited standard library

## SDK
- Connect IQ SDK 9.1.0
- Installed at: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/`
- minApiLevel: 3.4.0

## Development Environment
- macOS
- VS Code with official Garmin Monkey C extension
- Java 17 (Corretto) required by SDK
- Simulator: ConnectIQ.app (launch before running via F5)
- Run via F5 in VS Code to build and deploy to simulator

## External APIs

### Weather Sources (tiered)
The watch face supports two weather sources, configurable via `WeatherSource` setting:

**Garmin Built-in (default, WeatherSource=0)**
- Reads from `Weather.getCurrentConditions()` in the main process — no background HTTP needed
- Fields: temperature, condition (Garmin codes 0-53), windSpeed, windBearing, precipitationChance
- Sunrise/sunset computed locally via solar position algorithm (Weather.getSunrise requires CIQ 4.1, we target 3.4)
- Updates: cached by OS, refreshed ~hourly via phone connection

**Open-Meteo Weather (optional, WeatherSource=1)**
- Shore mode endpoint: `GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation_probability,is_day&daily=sunrise,sunset&timezone=auto&forecast_days=1&wind_speed_unit=ms`
- Surf mode wind endpoint: `GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&hourly=wind_speed_10m,wind_direction_10m&forecast_days=1&timezone=auto&wind_speed_unit=ms`
- Auth: none (free, no API key, <10K calls/day for non-commercial)
- Shore mode: current snapshot (~670 bytes) with temp, WMO weather code, wind, precip probability, is_day, sunrise/sunset
- Surf mode: 24h hourly wind forecast (~986 bytes), stored as flat arrays, advances offline
- WMO weather codes (0-99): fewer conditions than OWM (~20 vs ~50), no smoke/haze/dust/tornado/tropical storm
- Wind always returned in m/s (wind_speed_unit=ms)
- Sunrise/sunset returned as ISO local time strings, converted to Unix via utc_offset_seconds
- Models: auto-selects best for location (GEM 2.5km for Canada, HRRR 3km for US, etc.)

**OpenWeatherMap 2.5 (optional, WeatherSource=2)**
- Endpoint: `GET https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={key}&units={metric|imperial}`
- Returns: current weather in a single compact response
- Fields used: `main.temp`, `weather[0].id`, `wind.speed`, `wind.deg`, `sys.sunrise`, `sys.sunset`
- Rate limit: fetches on every background temporal event (~every 5 min). Free tier: 1M calls/month, no credit card
- OWM 3.0 API keys also work with 2.5 — same account, no extra setup

### StormGlass Tide Extremes API
- Endpoint: `GET https://api.stormglass.io/v2/tide/extremes/point?lat={lat}&lng={lng}&start={unix}&end={unix}&datum=MLLW`
- Auth: `Authorization: {api_key}` header
- Note: uses `lng` not `lon`
- Datum: `MLLW` (Mean Lower Low Water) — heights are always positive and match tide websites. Default MSL gives small values around 0 which are confusing.
- Returns: array of `{ height: float, time: string (UTC ISO), type: "high"|"low" }`
- Request 72h window (local midnight today to midnight+3 days via Time.today() + 72h)
- Rate limit: max 1 request per calendar day; refresh also triggered if GPS moves >50km or tide data expired
- Free tier: 10 calls/day — persist response to `Application.Storage`
- Backup key: `StormGlassBackupApiKey` setting, immediate retry on 402 in the same background cycle. TideService handles retry internally.

### Open-Meteo Marine API (surf mode swell)
- Endpoint: `GET https://marine-api.open-meteo.com/v1/marine?latitude={lat}&longitude={lon}&hourly=swell_wave_height,swell_wave_period,swell_wave_direction&forecast_days=1`
- Auth: none (free, no API key, no quota)
- Returns: `{hourly: {time: [...], swell_wave_height: [...], swell_wave_period: [...], swell_wave_direction: [...]}}`
- Response size: ~1.2KB for 24 hours — fits in background memory (~28KB)
- Fetched on every background temporal event in surf mode (no gating needed)
- Stored as 3 flat arrays in Application.Storage: `surf_swellHeights`, `surf_swellPeriods`, `surf_swellDirections`
- DataManager picks current hour's entry on each onUpdate() via `updateSwellFromForecast()`

### API Keys
- Stored in Connect IQ app settings (configurable via Garmin Connect mobile app)
- Properties: `OWMApiKey`, `StormGlassApiKey`, `StormGlassBackupApiKey`, `HomeLat`, `HomeLng`
- Surf mode properties: `SurfSpotLat`, `SurfSpotLng`, `CopyGPSToSurfSpot`
- Never hardcoded in source
- Open-Meteo requires no key

## Key Garmin APIs Used
- `WatchUi.WatchFace` — base class for watch faces
- `Graphics.Dc` — drawing context for all rendering
- `System.getClockTime()` — current time
- `System.getDeviceSettings()` — 12/24hr, units (metric/imperial)
- `Activity.getActivityInfo()` — heart rate
- `System.getSystemStats()` — battery
- `Communications.makeWebRequest()` — HTTP calls to OWM and StormGlass (background only)
- `Position.getInfo()` — GPS / last known location
- `Background.registerForTemporalEvent()` — schedules background process
- `Application.Storage` — persistent key-value store shared between main and background

## Monkey C Patterns

### Singleton via getApp()
Monkey C has no static classes. The singleton pattern is:
```java
// In SurferWatchFaceApp.mc
var dataManager as DataManager;
function getDataManager() as DataManager { return dataManager; }

// Access anywhere via:
var dm = (Application.getApp() as SurferWatchFaceApp).getDataManager();
```

### HTTP Requests — Background Service Delegate (CRITICAL)
Watch faces CANNOT call `Communications.makeWebRequest()` from the main process.
All HTTP calls MUST run inside a `Background.ServiceDelegate` via `onTemporalEvent()`.

Architecture:
1. Main app registers for temporal events: `Background.registerForTemporalEvent(new Time.Duration(5 * 60))`
2. System fires `ServiceDelegate.onTemporalEvent()` at most every 5 minutes
3. `ServiceDelegate` makes HTTP requests, packages results, calls `Background.exit(data)`
4. Main app receives data via `AppBase.onBackgroundData(data)` (on the App class, NOT the View)
5. Main app stores data in `Application.Storage` and updates DataManager

This means:
- `WeatherService` and `TideService` live in `ServiceDelegate.mc`, not in the main process
- All classes/functions used in the background MUST be annotated with `:background`
- Minimum refresh interval is 5 minutes (system enforced)
- OWM 5-minute and StormGlass daily limits are enforced by storing last-fetch timestamps in `Application.Storage`
- Background process has its own memory budget (~28KB on Instinct 2X) — keep response parsing minimal

### App Settings (Connect IQ Configurable Properties)
Settings are configured by the user via the Garmin Connect mobile app and synced to the watch.

Three files work together:
- `resources/settings/properties.xml` — defines property IDs, types, and default values
- `resources/settings/settings.xml` — defines the UI shown in Garmin Connect app
- In code: `Application.Properties.getValue("PropertyId")` reads current value

Example `settings.xml` entry:
```xml
<setting propertyKey="@Properties.OWMApiKey" title="@Strings.owm_api_key_title">
    <settingConfig type="alphaNumeric"/>
</setting>
```

Note: `settingConfig type` is `alphaNumeric` (camelCase). In code, read with `Application.Properties.getValue("OWMApiKey")` (API 3.4+).

Valid `settingConfig` types: `alphaNumeric`, `numeric`, `list`, `boolean`, `date`. There is NO `float` type. For decimal number inputs (e.g., GPS coordinates), use `alphaNumeric` and parse to float in code via `toFloat()`.

### Application.Storage
Key-value persistent storage that survives watch face restarts and watch reboots.
- `Application.Storage.setValue("key", value)` — stores any Monkey C object
- `Application.Storage.getValue("key")` — retrieves stored value (returns null if not set)
- Used for: StormGlass tide cache, last fetch timestamps, last fetch coordinates
- **Key naming**: Use 2-3 character short keys to save memory (string keys are stored in flash). Full key reference is in the comment block at the top of `DataManager.mc`.
- **Version gating**: On startup, View checks `Storage.getValue("av")` against current version. On mismatch, `Storage.clearValues()` wipes stale keys from previous builds. Bump the version number whenever Storage keys change.
- Storage persists across app updates — stale keys from old versions waste memory if not cleared.

### Timer vs Background
- `Timer.Timer` — runs in main process, cannot make HTTP requests, fine for UI refresh triggers
- `Background.ServiceDelegate` — runs in background process, can make HTTP requests, fires at most every 5 min

## Icon Strategy

### Approach
Icons use a custom bitmap font (`.fnt` + `.png`) generated from the **Weather Icons** open-source font (MIT/SIL OFL licensed, by Erik Flowers). This is the standard approach used by experienced Garmin developers — one font resource, color-tintable in code, memory efficient.

### Font Files
- `resources/fonts/weather-icons.fnt` + `weather-icons_0.png` — generated at 15px from `weathericons-regular-webfont.ttf` using `fontbm`. Contains 18 glyphs so far (weather conditions + some directional arrows). Moon phases and remaining glyphs still to be added (Tasks 28-35).
- `resources/fonts/crystal-icons.fnt/png` and `weather-icons-24.fnt/png` — reference files only, not used in the app.

### Icon Source Font
- `tools/weathericons.ttf` — Weather Icons TTF (gitignored, local only)
- `tools/garmin-connect-icons.ttf` — Garmin Connect icon font (gitignored, local only)
- `tools/fontbm` — BMFont-compatible converter for macOS (gitignored, local only)
- Tools folder: `/Volumes/workplace/Garmin/surfer-watch-face-instinct-2x-solar/tools/`

### What Uses Fonts vs Code
- **Font glyphs (weather-icons.fnt):** weather conditions, moon phases, tide arrows, sunrise/sunset, wind direction, umbrella
- **Drawn in code (like battery):** heart (HR circle), bluetooth icon, notification icon
- **BMP files in `resources/drawables/`:** generated earlier from Weather Icons TTF — will be removed once font wiring is complete in Tasks 29-35

### Weather Icons Unicode Codepoints Used
- `0xf00d` clear/sunny, `0xf013` cloudy, `0xf019` rain, `0xf01c` drizzle
- `0xf01e` thunderstorm, `0xf01b` snow, `0xf014` fog
- `0xf051` sunrise, `0xf052` sunset
- `0xf0b1` wind direction arrow (rotated in code)
- `0xf084` umbrella
- Moon phases: `0xf095` (new) through `0xf0b0` (waning crescent-6), 8 phases selected

## Drawing Approach
- All rendering done programmatically via `dc` (drawing context) in `onUpdate()`
- No XML layout files — full pixel control needed for this design
- Icons rendered via custom icon font (BMFont format) through `drawText()` — NOT bitmaps
  - Memory efficient: one font file vs many bitmap files
  - CPU efficient: font rendering is hardware-optimized
  - Alignment: icons and text both go through `drawText()`, so they share the same padding and align naturally at the same Y coordinate
- All text and icon rendering goes through a `drawTextAligned()` helper that compensates for font top padding, ensuring the Y coordinate = top pixel of visible content
- System fonts: FONT_XTINY, FONT_TINY, FONT_SMALL, FONT_MEDIUM, FONT_LARGE
- Layout coordinates are `private static const` at the top of `SurferWatchFaceView`
- Each icon has its own `drawIcon*()` method; composite UI units (icon + text) have their own `draw*()` methods that take `(dc, x, y, data)` for reusability

## Constraints
- No colors other than black and white
- Watch face `onUpdate()` called at most once per second — keep it fast
- External API calls must be async (background service or timer-based)
- API data cached locally — don't call on every update tick

## Sensor Gating Rules (CRITICAL — memory safety)

On the ~65KB heap, reading unused sensors causes OOM. Every sensor read MUST be gated by the settings that control whether it's displayed. Never read a sensor unconditionally — always check the mode and relevant setting first.

**Rule: only read a sensor if the current mode + settings will display its value.**

### Sensor → Setting → Mode mapping

| Sensor | API | Shore Mode | Surf Mode | Gate condition |
|--------|-----|-----------|-----------|----------------|
| Heart Rate | `Activity.getActivityInfo()` | Subscreen (default) | Not displayed | Shore only, when ShoreSubscreen needs it |
| Stress | `SensorHistory.getStressHistory()` | Arc (default) | Arc (optional) | ShoreArc=0 OR SurfArc=1 |
| Body Battery | `SensorHistory.getBodyBatteryHistory()` | Arc (optional) | Arc (optional) | ShoreArc=2 OR SurfArc=2 |
| Solar Intensity | `System.getSystemStats().solarIntensity` | Arc (optional) | Arc (default) | ShoreArc=1 OR SurfArc=0 |
| Water Temp | `SensorHistory.getTemperatureHistory()` | Not displayed | Top section (default) | Surf only, when SurfTempSource=0 |
| Altitude | `SensorHistory.getElevationHistory()` | Subscreen (optional) | Not displayed | Shore only, when ShoreSubscreen=2 |
| Steps | `ActivityMonitor.getInfo().steps` | Subscreen (optional) | Not displayed | Shore only, when ShoreSubscreen=3 |
| Battery | `System.getSystemStats().battery` | Always | Always | No gate — always needed |
| GPS | `Position.getInfo()` | Always | Always | No gate — always needed |
| Notifications | `System.getDeviceSettings()` | Always | Not displayed | Read with battery (same call) |

### SensorHistory OOM constraint
`SensorHistory` iterators allocate heap memory. Only ONE SensorHistory iterator should be active per tick. The arc settings (Stress vs Body Battery) are mutually exclusive, so only one runs. Altitude and Steps are also mutually exclusive (different ShoreSubscreen values). Never read two SensorHistory sensors in the same tick.

### When adding a new sensor or setting
1. Add the sensor to this table
2. Add the gate condition
3. Implement the gate in `updateSensorData()` or `updateSurfSensors()`
4. If it uses SensorHistory, put the read in its own private function (isolates iterator from main stack)
5. Test with all setting combinations to verify no OOM

## Monkey C Compiler & Code Size Best Practices

### Compiler Optimization
- The default optimization level is **-O2** (release) — no need to set it explicitly
- SDK 4.1.4+ compiler performs constant folding, constant substitution, and branch elimination automatically
- Manual constant inlining is unnecessary — use `private static const` for readability
- Higher levels (-O3) are not documented as providing additional benefits

### What costs code memory
- Each class, module, enum, and function has fixed overhead even if unused
- `switch/case`: more expensive than `if/else` chains
- Dictionaries: huge overhead for both code and data — avoid for lookup tables
- Array initialization with named constants: generates more code than literal values
- Fully qualified names (`$.Foo.Bar.Baz`): generates more code than short names (`Bar.Baz`)
- Without `-O2`: `private static const` declarations and expressions like `const FOO = 1+1` generate extra bytecode
- With `-O2`: the compiler handles constant folding and substitution — use `private static const` freely for readability

### What costs data memory
- Each class field (var) costs ~8-16 bytes regardless of whether it holds a value
- `Application.Storage.setValue()` writes to flash — never call per tick
- `Application.Properties.getValue()` reads from in-memory settings — safe per tick
- `SensorHistory` iterators allocate heap memory temporarily — only one at a time
- Custom fonts on CIQ 3.x load into app heap; on CIQ 4.x+ they use a separate graphics pool
- Font memory correlates with file size — keep .fnt/.png files small, remove unused glyphs

### What does NOT cost significant memory
- Comments (stripped at compile time)
- Inline literal numbers vs named constants (similar cost with `-O2`)
- `Application.Properties.getValue()` calls (in-memory, no I/O)

## Background/Foreground Architecture (CRITICAL)

### The Problem
The App class (`AppBase`) is `:background` annotated — it runs in BOTH foreground and background processes. Any class referenced by the App's fields or methods gets pulled into the background process, consuming its limited memory (~28KB on Instinct 2X).

**Rule: The App class MUST NOT reference foreground-only classes (DataManager, View) in its fields or method bodies.**

If the App has `var dataManager as DataManager`, the entire DataManager class (all fields, all method signatures) gets compiled into the background process even though the background never uses it.

### Correct Pattern (Crystal Face reference)
```
App (:background, thin shell):
  - getServiceDelegate() → returns ServiceDelegate
  - onBackgroundData(data) → writes to Application.Storage, calls requestUpdate()
  - getInitialView() → creates View (no foreground class stored as field)
  - onSettingsChanged() → writes flag to Storage, calls requestUpdate()
  - NO DataManager field, NO View field, NO foreground method calls

View (NOT :background):
  - onUpdate() → checks Storage flags, loads data if changed, renders
  - Owns DataManager or handles data directly
  - All foreground logic lives here

ServiceDelegate (:background):
  - onTemporalEvent() → reads from Storage/Properties, fetches APIs
  - Writes results to Application.Storage
  - Calls Background.exit() with minimal payload
  - NO foreground class references
```

### Background Memory Budget
- Instinct 2/2X: 28,488 bytes total for background process
- Code + AppBase + globals consume ~21KB, leaving ~7KB for API responses
- OWM/Open-Meteo weather fetch consumes ~3KB, leaving ~4KB for tide
- Tide fetch (StormGlass) needs ~3.5KB+ for JSON parsing — fits with ~4KB free
- **NEVER use `System.println()` with string concatenation in background** — temporary string allocations consume the free memory needed for API responses. This was confirmed to cause -403 OOM.
- If swell + tide don't fit, the tide response returns -403 (NETWORK_RESPONSE_OUT_OF_MEMORY)
- Every new property, string, or setting increases compiled app size and reduces background free memory

### When adding new features
1. Check background memory impact: add debug prints (`System.getSystemStats().freeMemory`) in `onTemporalEvent()`
2. Ensure the App class doesn't gain new foreground class references
3. If background memory is tight, consider splitting API chains across separate temporal events
4. Test on Instinct 2X simulator — it has the tightest memory budget
