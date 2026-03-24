# Requirements Document — Surf Mode

## Introduction

Surf Mode is an alternate watch face layout optimized for surfers actively in the water. The user manually switches between Shore Mode (default, existing layout) and Surf Mode via a setting. In Surf Mode, the watch face replaces fitness-oriented and general-weather data with ocean-specific data: current tide height, swell conditions, water temperature, solar intensity, and wind — all sourced from a user-configured surf spot location rather than current GPS.

## Glossary

- **Watch_Face**: The SurferWatchFaceView rendering engine that draws all content on the 176x176 MIP display
- **DataManager**: The singleton that holds all cached data consumed by the Watch_Face during rendering
- **ServiceDelegate**: The background process (SurferWatchFaceDelegate) that makes all HTTP requests via onTemporalEvent()
- **Shore_Mode**: The default watch face layout displaying time, weather, tide, HR, stress, notifications, bluetooth, date, sunrise/sunset, precipitation
- **Surf_Mode**: The alternate watch face layout optimized for in-water use, displaying time, tide height, swell, wind, water temperature, solar intensity, moon phase
- **Surf_Spot**: A fixed geographic location (latitude/longitude) configured by the user, used as the data source location for all ocean data in Surf_Mode
- **Subscreen_Circle**: The 62x62 pixel circular cutout at top-right of the display (center 144,31, radius 31)
- **Swell_Data**: Hourly ocean swell forecast from Open-Meteo Marine API, including swellHeight, swellPeriod, and swellDirection. Stored as three flat arrays in Application.Storage.
- **Tide_Curve**: A graphical representation of today's tide extremes plotted as a filled curve with a dithered "now" marker and triangle indicator
- **Bottom_Toggle**: The mechanism by which the user performs a double wrist gesture (two raises within a time window) in Surf_Mode to switch the bottom section between Swell_Data view and Tide_Curve view
- **CopyGPS_Action**: A boolean setting that, when toggled ON, copies current GPS coordinates to SurfSpotLat/SurfSpotLng and auto-resets to OFF
- **Solar_Intensity**: A 0-100% value from SensorHistory.getSolarIntensityHistory() representing current solar radiation
- **Water_Temperature**: An approximate water temperature reading from SensorHistory.getTemperatureHistory() (body temperature sensor, approximate when submerged)

---

## Requirements

### Requirement 1: Surf Mode Setting

**User Story:** As a surfer, I want to switch between shore mode and surf mode via a setting, so that I can see ocean-optimized data when I'm heading into the water.

#### Acceptance Criteria

1. THE Watch_Face SHALL expose a `SurfMode` setting as a list with two values: 0 (Shore) and 1 (Surf)
2. THE Watch_Face SHALL default the `SurfMode` setting to 0 (Shore)
3. WHEN `SurfMode` is set to 0, THE Watch_Face SHALL render the Shore_Mode layout
4. WHEN `SurfMode` is set to 1, THE Watch_Face SHALL render the Surf_Mode layout
5. WHEN the user changes the `SurfMode` setting, THE Watch_Face SHALL immediately re-render using the selected mode's layout on the next onUpdate() call

---

### Requirement 2: Surf Spot Location Configuration

**User Story:** As a surfer, I want to configure a fixed surf spot location, so that tide, swell, and wind data are fetched for the spot I'm surfing rather than my current GPS position.

#### Acceptance Criteria

1. THE Watch_Face SHALL expose `SurfSpotLat` and `SurfSpotLng` settings as alphaNumeric string inputs, parsed to float in code
2. THE Watch_Face SHALL default `SurfSpotLat` and `SurfSpotLng` to "0.0"
3. THE Watch_Face SHALL expose a `CopyGPSToSurfSpot` setting as a boolean toggle, defaulting to false
4. WHEN `CopyGPSToSurfSpot` is toggled ON and a valid GPS position is available, THE DataManager SHALL copy the current GPS latitude to `SurfSpotLat` and the current GPS longitude to `SurfSpotLng` via Application.Properties.setValue()
5. WHEN `CopyGPSToSurfSpot` has copied coordinates, THE DataManager SHALL reset `CopyGPSToSurfSpot` to false via Application.Properties.setValue()
6. THE Watch_Face SHALL treat `SurfSpotLat`/`SurfSpotLng` values of "0.0" or empty string as "not configured" and display "--" for all Surf_Mode location-dependent fields
7. WHILE `SurfMode` is set to 1, THE ServiceDelegate SHALL use `SurfSpotLat`/`SurfSpotLng` as the coordinates for all location-dependent API requests (tide, swell, wind)
8. WHILE `SurfMode` is set to 0, THE ServiceDelegate SHALL use current GPS or HomeLat/HomeLng as the coordinates for all location-dependent API requests

---

### Requirement 3: Surf Mode Subscreen Circle

**User Story:** As a surfer, I want to see current tide height and solar intensity in the subscreen circle, so that I can quickly glance at the most critical ocean data.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the current tide height (in meters or feet per device unit setting) as the number inside the Subscreen_Circle, replacing heart rate
2. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display a tide direction arrow icon inside the Subscreen_Circle, replacing the heart icon
3. THE tide direction arrow SHALL point up for a rising tide (next event is high) and down for a falling tide (next event is low)
4. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display Solar_Intensity as a 0-100% arc gauge around the Subscreen_Circle, replacing the stress arc
5. THE Watch_Face SHALL read Solar_Intensity from SensorHistory.getSolarIntensityHistory() with a period of 1 sample
6. IF Solar_Intensity data is unavailable, THEN THE Watch_Face SHALL display an empty arc (0% fill)
7. IF tide height data is unavailable, THEN THE Watch_Face SHALL display "--" inside the Subscreen_Circle

---

### Requirement 4: Surf Mode Top Section

**User Story:** As a surfer, I want to see battery, water temperature, and next tide event in the top section, so that I have essential status info while in the water.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display battery percentage and battery icon on Row 1, identical to Shore_Mode
2. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display Water_Temperature on Row 2, replacing the notification count, notification icon, and bluetooth icon
3. THE Watch_Face SHALL read Water_Temperature from SensorHistory.getTemperatureHistory() with a period of 1 sample
4. THE Watch_Face SHALL display Water_Temperature in °C or °F based on the device unit setting (UNIT_METRIC → °C, UNIT_STATUTE → °F, converting from Celsius by multiplying by 1.8 and adding 32)
5. IF Water_Temperature data is unavailable, THEN THE Watch_Face SHALL display "--" on Row 2
6. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the next tide event time and height on Row 3, identical to Shore_Mode

---

### Requirement 5: Surf Mode Middle Section

**User Story:** As a surfer, I want to see wind direction and speed in the middle section instead of sunrise/sunset, so that I can assess wind conditions while surfing.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display a wind direction arrow and wind speed in the left column of the middle section, replacing sunrise/sunset
2. THE wind direction arrow SHALL be rendered using the existing drawWindArrow() method, centered in the left column icon position
3. THE wind speed text SHALL be displayed below the arrow, formatted per the WindSpeedUnit setting
4. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the current time in the center column using the same font and position as Shore_Mode
5. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the moon phase icon, AM/PM indicator, and seconds (on wrist raise) in the right column, identical to Shore_Mode
6. IF wind data is unavailable in Surf_Mode, THEN THE Watch_Face SHALL display "--" for wind speed and omit the wind arrow

---

### Requirement 6: Surf Mode Bottom Section — Swell View

**User Story:** As a surfer, I want to see swell height, period, and direction at a glance, so that I can assess wave conditions without leaving the water.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1 and the Bottom_Toggle state is "swell", THE Watch_Face SHALL display Swell_Data in the bottom section, replacing the date row and weather widget
2. THE Watch_Face SHALL display swell height in meters or feet (per device unit setting), swell period in seconds, and swell direction as a directional arrow
3. THE Watch_Face SHALL arrange the three swell data points in a three-column layout matching the weather widget column positions
4. IF Swell_Data is unavailable, THEN THE Watch_Face SHALL display "--" for all three swell fields

---

### Requirement 7: Surf Mode Bottom Section — Tide Curve View

**User Story:** As a surfer, I want to see a visual tide curve for today, so that I can understand the tide pattern and where I am in the cycle.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1 and the Bottom_Toggle state is "tide curve", THE Watch_Face SHALL display a Tide_Curve graph in the bottom section
2. THE Tide_Curve SHALL plot today's tide extremes from the tideExtremes array as a curve spanning the full width of the bottom section
3. THE Tide_Curve SHALL display a vertical "now" marker at the position corresponding to the current time within the day
4. THE Tide_Curve SHALL label the high and low tide heights on the Y axis
5. IF tide extreme data is unavailable, THEN THE Watch_Face SHALL display "--" in the bottom section instead of the Tide_Curve

---

### Requirement 8: Bottom Section Toggle via Double Wrist Gesture

**User Story:** As a surfer, I want to toggle between swell info and tide curve by raising my wrist twice quickly, so that I can switch views without navigating menus (watch faces cannot receive button input).

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL detect a double wrist gesture (two wrist raises within a configurable time window) via `onExitSleep()` timing
2. WHEN a double wrist gesture is detected in Surf_Mode, THE Watch_Face SHALL toggle the Bottom_Toggle state between "swell" (0) and "tide curve" (1)
3. WHEN the Bottom_Toggle state changes, THE Watch_Face SHALL request a UI update to re-render the bottom section
4. THE Watch_Face SHALL default the Bottom_Toggle state to 0 ("swell") when Surf_Mode is activated
5. THE Watch_Face SHALL use a 4-second detection window for double wrist gesture
6. NOTE: Watch faces cannot receive button input (no onSelect, no BehaviorDelegate). The double wrist gesture is the only available toggle mechanism.

---

### Requirement 9: Swell Data Fetching

**User Story:** As a surfer, I want swell data fetched automatically from Open-Meteo Marine API, so that I always have current wave conditions without manual intervention or API keys.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE ServiceDelegate SHALL fetch Swell_Data from the Open-Meteo Marine API: `GET https://marine-api.open-meteo.com/v1/marine?latitude={lat}&longitude={lon}&hourly=swell_wave_height,swell_wave_period,swell_wave_direction&forecast_days=1`
2. THE ServiceDelegate SHALL use the `SurfSpotLat`/`SurfSpotLng` coordinates for the swell request
3. THE ServiceDelegate SHALL request a 24-hour hourly forecast (forecast_days=1) for swell data
4. THE ServiceDelegate SHALL store the full 24-hour hourly forecast as three flat arrays (heights, periods, directions) in Application.Storage
5. THE DataManager SHALL pick the current hour's entry from the stored forecast arrays on each onUpdate() call, so the display advances through the forecast over time
6. THE ServiceDelegate SHALL fetch fresh swell data on every background temporal event (Open-Meteo is free with no quota)
7. THE DataManager SHALL persist swell forecast arrays to Application.Storage with `surf_` prefixed keys (`surf_swellHeights`, `surf_swellPeriods`, `surf_swellDirections`)
8. IF the Open-Meteo API returns an error, THEN THE ServiceDelegate SHALL skip the swell fetch and retain previously cached data
9. THE Open-Meteo Marine API requires no API key — zero configuration needed for swell data

---

### Requirement 10: Separate Cache for Surf Mode

**User Story:** As a surfer, I want shore mode and surf mode data cached separately, so that switching modes doesn't cause stale or incorrect data to display.

#### Acceptance Criteria

1. THE DataManager SHALL use "surf_" prefixed keys in Application.Storage for all Surf_Mode cached data (tide extremes, swell data, fetch timestamps, fetch coordinates)
2. THE DataManager SHALL use unprefixed keys in Application.Storage for all Shore_Mode cached data, preserving the existing cache structure
3. WHEN `SurfMode` changes from 0 to 1, THE DataManager SHALL load Surf_Mode cached data from "surf_" prefixed storage keys
4. WHEN `SurfMode` changes from 1 to 0, THE DataManager SHALL load Shore_Mode cached data from unprefixed storage keys
5. THE ServiceDelegate SHALL write fetch metadata (tideFetchedDay, tideFetchLat, tideFetchLng, swellFetchedDay) to "surf_" prefixed keys when fetching for Surf_Mode, and to unprefixed keys when fetching for Shore_Mode

---

### Requirement 11: Surf Mode API Quota Management

**User Story:** As a surfer, I want the watch face to manage API calls efficiently, so that I don't exhaust my StormGlass daily quota when using surf mode.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE ServiceDelegate SHALL make at most 1 StormGlass API call per day for tide extremes (swell and wind use Open-Meteo or OWM which have no daily quota concern)
2. THE ServiceDelegate SHALL chain requests based on WeatherSource: Open-Meteo swell → StormGlass tide → wind source (Open-Meteo hourly / OWM current / none for Garmin)
3. THE ServiceDelegate SHALL support a backup StormGlass API key (`StormGlassBackupApiKey` setting) for tide fetches
4. WHEN the primary StormGlass key returns HTTP 402 (quota exhausted), THE ServiceDelegate SHALL set a `sgUseBackup` flag in Application.Storage and use the backup key on the next background cycle
5. THE `sgUseBackup` flag SHALL be cleared on a successful tide fetch
6. IF any request in the chain returns -403 (background memory exhausted), THE ServiceDelegate SHALL stop the chain immediately and exit with whatever partial results have been accumulated
7. Open-Meteo swell and weather fetches have no quota limit and are fetched on every background temporal event
8. OWM wind fetches for surf mode have no daily limit (free tier: 1M calls/month)

---

### Requirement 12: Surf Mode Wind Data Source (Legacy OWM)

**User Story:** As a surfer using OWM, I want wind data in surf mode to come from OWM for the surf spot, so that wind readings are live and match the location I'm surfing.

Note: This requirement describes the OWM (WeatherSource=2) behavior. Open-Meteo wind behavior is in Requirement 18. Garmin behavior is in Requirement 20.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1 and `WeatherSource` is set to 2 (OWM), THE ServiceDelegate SHALL fetch wind data from OWM 2.5 Current Weather API using the surf spot coordinates (`SurfSpotLat`/`SurfSpotLng`)
2. WHILE `SurfMode` is set to 1 and `WeatherSource` is set to 2, THE ServiceDelegate SHALL extract only wind speed and wind direction from the OWM response — temperature, condition, sunrise, and sunset SHALL NOT be stored (surf mode does not display shore weather fields)
3. WHILE `SurfMode` is set to 1, THE DataManager SHALL store surf wind data in separate fields (`surfWindSpeed`, `surfWindDeg`) that do not overwrite shore wind fields (`windSpeed`, `windDeg`)
4. WHILE `SurfMode` is set to 0, THE DataManager SHALL source wind data from the existing weather source (Garmin built-in, Open-Meteo, or OWM), unchanged from current behavior
5. THE wind speed unit conversion in surf mode SHALL follow the same logic as shore mode (normalize to m/s, then convert per `WindSpeedUnit` setting)
6. IF no OWM API key is configured and `WeatherSource` is 2, THE ServiceDelegate SHALL skip the wind fetch and display "--" for wind in surf mode

---

### Requirement 13: Surf Mode Removed Elements

**User Story:** As a surfer, I want non-essential shore data hidden in surf mode, so that the display is uncluttered and focused on ocean conditions.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the notification count and notification icon from the display
2. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the bluetooth icon from the display
3. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the date row from the display
4. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the weather condition icon and temperature from the display
5. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the sunrise/sunset icon and time from the display
6. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL omit the precipitation icon and percentage from the display
7. WHILE `SurfMode` is set to 1 and the Bottom_Toggle state is "swell", THE Watch_Face SHALL display the next sunrise or sunset event for the surf spot in the date row position, computed locally from SurfSpotLat/SurfSpotLng using the solar position algorithm
8. WHILE `SurfMode` is set to 1 and the Bottom_Toggle state is "tide curve", THE Watch_Face SHALL omit the sunrise/sunset row (the space is used by tide event time labels)

---

### Requirement 14: Tide Height Interpolation

**User Story:** As a surfer, I want to see the current estimated tide height, so that I know the water level right now rather than just the next event's height.

#### Acceptance Criteria

1. THE DataManager SHALL compute an interpolated current tide height from the tideExtremes array by finding the two surrounding events (previous and next) and linearly interpolating based on the current time
2. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the interpolated current tide height in the Subscreen_Circle
3. IF only one surrounding tide event is available (e.g., before the first event of the day), THEN THE DataManager SHALL use the nearest event's height as the current height
4. THE DataManager SHALL update the interpolated tide height on each onUpdate() call


---

## Phase 3 — Open-Meteo Weather Source & Offline Wind

### Requirement 15: Three-Tier Weather Source Setting

**User Story:** As a user, I want to choose between Garmin built-in, Open-Meteo, or OpenWeatherMap as my weather source, so that I can pick the best balance of convenience, accuracy, and features for my needs.

#### Acceptance Criteria

1. THE Watch_Face SHALL change the `WeatherSource` setting from a 2-value list to a 3-value list: 0 = Garmin (default), 1 = Open-Meteo, 2 = OpenWeatherMap
2. THE Watch_Face SHALL update the setting UI labels and string resources to reflect the three options
3. WHEN `WeatherSource` is set to 0 (Garmin), THE Watch_Face SHALL behave identically to the current Garmin built-in mode — no background HTTP for weather, reads from `Weather.getCurrentConditions()`, computes sunrise/sunset locally
4. WHEN `WeatherSource` is set to 1 (Open-Meteo), THE ServiceDelegate SHALL fetch weather from the Open-Meteo Forecast API (no API key required)
5. WHEN `WeatherSource` is set to 2 (OWM), THE ServiceDelegate SHALL fetch weather from OWM 2.5 Current Weather API (requires `OWMApiKey`)
6. WHEN the user changes `WeatherSource`, THE DataManager SHALL clear all weather fields to prevent condition code mismatch between mappers (existing `clearWeatherData()` behavior)
7. THE existing `OWMApiKey` setting SHALL remain — it is only required when `WeatherSource` = 2 (OWM)

---

### Requirement 16: Open-Meteo Weather for Shore Mode

**User Story:** As a user, I want Open-Meteo as a weather source that requires no API key, so that I can get more frequent weather updates than Garmin built-in without signing up for anything.

#### Acceptance Criteria

1. WHEN `WeatherSource` is set to 1 (Open-Meteo) and `SurfMode` is 0 (Shore), THE ServiceDelegate SHALL fetch current weather from: `GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation_probability,is_day&daily=sunrise,sunset&timezone=auto&forecast_days=1&wind_speed_unit=ms`
2. THE ServiceDelegate SHALL use current GPS or HomeLat/HomeLng coordinates for the request
3. THE ServiceDelegate SHALL parse the response and extract: `current.temperature_2m`, `current.weather_code`, `current.wind_speed_10m`, `current.wind_direction_10m`, `current.precipitation_probability`, `current.is_day`, `daily.sunrise[0]`, `daily.sunset[0]`
4. THE ServiceDelegate SHALL convert sunrise/sunset from ISO 8601 local time strings to Unix timestamps
5. THE DataManager SHALL store the weather code as `weatherConditionId` (WMO code, not OWM code)
6. THE Watch_Face SHALL use a new `wmoToWeatherGlyph()` mapper to convert WMO codes to icon glyphs when `WeatherSource` = 1
7. THE Watch_Face SHALL use the `is_day` field from Open-Meteo to determine day/night icon variants (instead of comparing current time to sunrise/sunset)
8. THE Watch_Face SHALL display precipitation probability from the Open-Meteo response when `WeatherSource` = 1, replacing the Garmin built-in `precipitationChance`
9. THE Open-Meteo response is ~670 bytes for current-only — fits comfortably in background memory
10. THE ServiceDelegate SHALL fetch Open-Meteo weather on every background temporal event (no time/distance gating — same as current OWM behavior)

---

### Requirement 17: WMO Weather Code Mapping

**User Story:** As a user using Open-Meteo, I want weather condition icons that accurately represent the current conditions, even though WMO codes are less granular than OWM codes.

#### Acceptance Criteria

1. THE Watch_Face SHALL implement a `wmoToWeatherGlyph(code, isNight)` function mapping WMO codes to the existing Erik Flowers weather icon glyphs
2. THE mapping SHALL cover all WMO codes: 0 (clear), 1-3 (partly cloudy to overcast), 45/48 (fog/rime fog), 51/53/55 (drizzle), 56/57 (freezing drizzle), 61/63/65 (rain), 66/67 (freezing rain), 71/73/75 (snow), 77 (snow grains), 80/81/82 (rain showers), 85/86 (snow showers), 95 (thunderstorm), 96/99 (thunderstorm with hail)
3. THE mapping SHALL support day/night variants for clear, partly cloudy, drizzle, rain, showers, snow, and thunderstorm conditions
4. THE following OWM-only conditions SHALL NOT have WMO equivalents and are documented as unavailable when using Open-Meteo: smoke, haze, dust/sand, squalls, tornado, tropical storm, hurricane, cold, hot, windy
5. FOR any unrecognized WMO code, THE mapper SHALL fall back to the clear sky glyph

---

### Requirement 18: Surf Mode Wind — Open-Meteo Hourly Forecast (Offline)

**User Story:** As a surfer, I want hourly wind forecast data stored on the watch, so that wind readings continue to update even when my phone is disconnected while I'm in the water.

#### Acceptance Criteria

1. WHEN `WeatherSource` is set to 1 (Open-Meteo) and `SurfMode` is 1, THE ServiceDelegate SHALL fetch hourly wind forecast from: `GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&hourly=wind_speed_10m,wind_direction_10m&forecast_days=1&timezone=auto&wind_speed_unit=ms`
2. THE ServiceDelegate SHALL use `SurfSpotLat`/`SurfSpotLng` coordinates for the request
3. THE ServiceDelegate SHALL store the 24-hour hourly wind forecast as two flat arrays (`surf_windSpeeds`, `surf_windDirections`) in Application.Storage
4. THE DataManager SHALL pick the current hour's wind entry from the stored forecast arrays on each onUpdate() call via `updateSurfWindFromForecast()`, so the display advances through the forecast over time (same pattern as swell)
5. THE ServiceDelegate SHALL fetch fresh wind forecast on every background temporal event (Open-Meteo is free)
6. WHEN a fresh fetch succeeds, THE DataManager SHALL use the latest fetched current-hour value; WHEN offline, THE DataManager SHALL advance through the stored forecast array
7. THE Open-Meteo wind-only response is ~986 bytes — fits in background memory alongside swell (~1.2KB) and tide
8. IF the Open-Meteo API returns an error, THEN THE ServiceDelegate SHALL skip the wind fetch and retain previously cached forecast data

---

### Requirement 19: Surf Mode Wind — OWM Behavior (Current Only)

**User Story:** As a surfer using OWM, I want wind data for my surf spot even though it won't update offline, so that I have live wind readings when my phone is connected.

#### Acceptance Criteria

1. WHEN `WeatherSource` is set to 2 (OWM) and `SurfMode` is 1, THE ServiceDelegate SHALL fetch current wind from OWM 2.5 using surf spot coordinates (existing behavior, unchanged)
2. THE DataManager SHALL store OWM surf wind in `surfWindSpeed`/`surfWindDeg` fields (existing behavior)
3. WHEN the phone disconnects, THE wind display SHALL show the last fetched value (stale, does not advance)
4. THE Watch_Face SHALL document that OWM surf wind freezes when offline, while Open-Meteo surf wind advances hourly

---

### Requirement 20: Surf Mode Wind — Garmin Source Behavior

**User Story:** As a surfer using Garmin built-in weather, I understand that Garmin weather is GPS-based and cannot provide wind for a remote surf spot.

#### Acceptance Criteria

1. WHEN `WeatherSource` is set to 0 (Garmin) and `SurfMode` is 1, THE Watch_Face SHALL display "--" for wind speed and omit the wind arrow
2. THE Watch_Face SHALL document that Garmin built-in weather uses the watch's GPS location, not the configured surf spot, so wind data is not available in surf mode with Garmin source

---

### Requirement 21: Surf Mode Background Chain Update

**User Story:** As a surfer, I want the background fetch chain to use the correct weather source for wind data, so that the right API is called based on my settings.

#### Acceptance Criteria

1. WHEN `SurfMode` is 1 and `WeatherSource` is 1 (Open-Meteo), THE ServiceDelegate SHALL chain: Open-Meteo swell → StormGlass tide → Open-Meteo weather (wind forecast)
2. WHEN `SurfMode` is 1 and `WeatherSource` is 2 (OWM), THE ServiceDelegate SHALL chain: Open-Meteo swell → StormGlass tide → OWM wind (current only, existing behavior)
3. WHEN `SurfMode` is 1 and `WeatherSource` is 0 (Garmin), THE ServiceDelegate SHALL chain: Open-Meteo swell → StormGlass tide (no wind fetch)
4. THE -403 memory exhaustion guard SHALL apply to all chain variants — stop immediately and exit with partial results
