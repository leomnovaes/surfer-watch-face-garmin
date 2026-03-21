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

**OpenWeatherMap 2.5 (optional, WeatherSource=1)**
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
- Request 48h window (start of today UTC to end of tomorrow UTC)
- Rate limit: max 1 request per calendar day; refresh also triggered if GPS moves >50km
- Free tier: 10 calls/day — persist response to `Application.Storage`

### API Keys
- Stored in Connect IQ app settings (configurable via Garmin Connect mobile app)
- Properties: `OWMApiKey`, `StormGlassApiKey`, `HomeLat`, `HomeLng`
- Never hardcoded in source

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
