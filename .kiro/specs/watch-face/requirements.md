# Watch Face Requirements

## Overview
A surfer-focused watch face for the Garmin Instinct 2X Solar displaying time, fitness metrics, ocean conditions, and weather in a single always-visible layout.

---

## 1. Display Layout

### 1.1 Heart Rate Circle
- The system SHALL display heart rate (BPM) inside a filled white circle in the top-right area of the screen
- The system SHALL display a heart icon above the BPM value inside the circle
- The circle SHALL be positioned to align with the physical solar sensor ring on the watch bezel

### 1.2 Top Section
- The system SHALL display battery percentage and a dynamic battery icon on the first row
- The battery icon SHALL visually reflect charge level (full, high, medium, low, critical)
- The system SHALL display notification count and a notification icon on the second row
- The system SHALL display tide information on the third row:
  - Left column: a directional icon (↑ for next high tide, ↓ for next low tide) and the time of the next tide event
  - Right column: predicted height of the next tide event in meters or feet (MLLW datum, per device unit setting)

### 1.3 Middle Section
- The system SHALL display three columns:
  - Left: next sunrise or sunset time with a directional icon (↑ sunrise, ↓ sunset)
  - Center: current time in large font
  - Right: moon phase icon, AM/PM indicator, and seconds (hidden by default)

### 1.4 Date Row
- The system SHALL display the current date as: `DayOfWeek Mon DD` (e.g., `Wed Mar 18`)
- The system SHALL display a Bluetooth connectivity icon to the left of the date

### 1.5 Weather Widget
- The system SHALL display three columns:
  - Left: weather condition icon (mapped from `current.weather[0].id`) and temperature below it (°C or °F per device setting)
  - Center: wind direction arrow icon (derived from `current.wind_deg`) and wind speed below it (km/h or mph per device setting, converted from OWM's m/s)
  - Right: umbrella icon and precipitation chance % below it (from `Toybox.Weather.getCurrentConditions().precipitationChance` — Garmin built-in current weather, not OWM, because OWM hourly/daily data is excluded from the API call to fit within background memory limits)

---

## 2. Data Sources

### 2.1 Watch Sensors
- The system SHALL read heart rate from the watch's optical HR sensor via `Activity.getActivityInfo().currentHeartRate`
- The system SHALL read battery level from `System.getSystemStats().battery`
- The system SHALL read notification count from `System.getDeviceSettings().notificationCount`
- The system SHALL read Bluetooth status from `System.getDeviceSettings().phoneConnected`
- The system SHALL read current time and date from `System.getClockTime()`
- The system SHALL respect the device's 12/24-hour setting via `System.getDeviceSettings().is24Hour`
- The system SHALL respect the device's metric/imperial unit setting via `System.getDeviceSettings().distanceUnits`

### 2.2 Location
- The system SHALL obtain the device's last known GPS position via `Position.getInfo()`
- When no location is available, the system SHALL display `--` for all location-dependent fields
- The system SHALL store the last known position for use in API refresh decisions

### 2.3 OpenWeatherMap One Call API 3.0
- Endpoint: `GET https://api.openweathermap.org/data/3.0/onecall`
- Required parameters: `lat`, `lon`, `appid`, `units` (`metric` or `imperial` based on device setting), `exclude=minutely,hourly,daily,alerts`
- The system SHALL extract from the response:
  - `current.temp` — temperature
  - `current.weather[0].id` — weather condition code (mapped to icon)
  - `current.wind_speed` — wind speed
  - `current.wind_deg` — wind direction in degrees (converted to cardinal/arrow)
  - `current.sunrise` and `current.sunset` — Unix timestamps, compared to now to determine next event
- Fields NOT sourced from OWM (excluded to fit in background memory ~28KB):
  - Precipitation: sourced from `Toybox.Weather.getCurrentConditions().precipitationChance` (Garmin built-in current weather)
  - Moon phase: calculated locally from current date using synodic period in `DataManager.computeMoonPhase()`
- The system SHALL refresh OWM data when phone connection is available AND at least one of:
  - At least 30 minutes have elapsed since the last successful fetch
  - The GPS position has changed by more than 5km since the last fetch
- The system SHALL NOT call OWM more than once per 30 minutes under any circumstances
- The system SHALL cache the last successful OWM response in memory
- When OWM data is unavailable or stale (>2 hours old), the system SHALL display `--` for affected fields

### 2.4 StormGlass Tide Extremes API
- Endpoint: `GET https://api.stormglass.io/v2/tide/extremes/point`
- Required parameters: `lat`, `lng` (note: `lng` not `lon`), `start` (Unix UTC), `end` (Unix UTC), `datum=MLLW`
- Auth: `Authorization` header with API key
- Datum: `MLLW` (Mean Lower Low Water) — heights are always positive and match what tide websites and surfers expect. Default MSL datum produces small values around 0 which are confusing.
- The system SHALL request a 48-hour window (`start` = start of current day UTC, `end` = end of next day UTC) to cover midnight transitions
- The response contains an array of `{ height: float, time: string (UTC ISO), type: "high"|"low" }`
- The system SHALL determine "next tide" by finding the first event in the array where `time` is after current time
- The system SHALL display the predicted height of the next tide event (not interpolated current height — more useful for surfers planning around tide events)
- The system SHALL refresh StormGlass data when ALL of the following are true:
  - A phone connection is available
  - The cached data is from a previous calendar day (UTC)
  - OR the GPS position has changed by more than 50km since the last fetch
  - OR the cache is empty (first run)
- The system SHALL NOT call StormGlass more than once per calendar day under normal conditions
- The system SHALL persist the StormGlass response to `Application.Storage` so it survives watch face restarts
- When StormGlass data is unavailable, the system SHALL display `--` for tide fields

### 2.5 Moon Phase
- The system SHALL compute moon phase locally from the current date using the synodic period (29.53058867 days) relative to a known new moon epoch (Jan 6, 2000 18:14 UTC)
- The result is a 0.0–1.0 float matching OWM convention: 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter
- The system SHALL map the float to one of 28 phases for icon selection (using Erik Flowers Weather Icons moon glyphs)
- Moon phase is always available (computed locally, no API dependency)
- Moon illumination % is NOT displayed (removed — overlaps with moon icon at this size)

---

## 3. Configuration

### 3.1 App Settings (via Garmin Connect mobile app)
- The system SHALL expose the following configurable properties via Connect IQ app settings:
  - `OWMApiKey` (string) — OpenWeatherMap API key
  - `StormGlassApiKey` (string) — StormGlass API key
  - `HomeLat` (string, optional) — fallback latitude if GPS unavailable (stored as string, parsed to float in code)
  - `HomeLng` (string, optional) — fallback longitude if GPS unavailable (stored as string, parsed to float in code)
- The system SHALL use `HomeLat`/`HomeLng` as the location source when GPS position is unavailable
- The system SHALL treat `HomeLat`/`HomeLng` values of `0.0` or empty string as "not configured" and display `--` for location-dependent fields
- API keys SHALL NOT be hardcoded in source

---

## 4. Behavior

### 4.1 Update Rate
- The system SHALL redraw the watch face at most once per second via `onUpdate()`
- The system SHALL use a background timer to trigger API refresh checks, not `onUpdate()`

### 4.2 Seconds Display
- The system SHALL hide the seconds field by default
- The system SHALL reveal the seconds field when the user performs a wrist-raise gesture (deferred — placeholder shown until gesture is implemented)

### 4.3 Secondary View (Future)
- The system SHALL support a secondary view accessible via double-wrist gesture
- This requirement is deferred — placeholder architecture only in current implementation

### 4.4 Placeholders
- Any field not yet wired to a live data source SHALL display a static placeholder value
- Placeholder values SHALL occupy the same position, font, and size as the final live value

---

## 5. Constraints

### 5.1 Display
- The system SHALL only use black (0x000000) and white (0xFFFFFF) for all rendering
- The system SHALL render all content within the 176x176 pixel canvas

### 5.2 Performance
- The system SHALL not perform blocking operations in `onUpdate()`
- The system SHALL cache all external API responses in memory
- The system SHALL persist StormGlass data to `Application.Storage`

### 5.3 API Rate Limits
- OWM: maximum 1 request per 30 minutes (free tier: 1000/day)
- StormGlass: maximum 1 request per calendar day (free tier: 10/day)
- The system SHALL track `meta.requestCount` and `meta.dailyQuota` from StormGlass responses and cease requests if quota is exhausted
