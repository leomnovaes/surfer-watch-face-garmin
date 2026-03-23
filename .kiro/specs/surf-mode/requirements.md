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
- **Swell_Data**: Hourly ocean swell forecast from StormGlass weather endpoint, including swellHeight, swellPeriod, and swellDirection
- **Tide_Curve**: A graphical representation of today's tide extremes plotted as a curve with a "now" marker
- **Bottom_Toggle**: The mechanism by which the user presses the START/STOP button (onSelect) in Surf_Mode to switch the bottom section between Swell_Data view and Tide_Curve view
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

### Requirement 8: Bottom Section Toggle via Button Press

**User Story:** As a surfer, I want to press the START/STOP button to toggle between swell info and tide curve, so that I can switch views without navigating menus.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL intercept the onSelect() event (START/STOP button single press) and return true
2. WHEN onSelect() is intercepted in Surf_Mode, THE Watch_Face SHALL toggle the Bottom_Toggle state between "swell" and "tide curve"
3. WHEN the Bottom_Toggle state changes, THE Watch_Face SHALL request a UI update to re-render the bottom section
4. THE Watch_Face SHALL default the Bottom_Toggle state to "swell" when Surf_Mode is activated
5. WHILE `SurfMode` is set to 0, THE Watch_Face SHALL return false from onSelect(), preserving default Garmin behavior (opens activity list)

---

### Requirement 9: Swell Data Fetching

**User Story:** As a surfer, I want swell data fetched automatically from StormGlass, so that I always have current wave conditions without manual intervention.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE ServiceDelegate SHALL fetch Swell_Data from the StormGlass weather endpoint: `GET https://api.stormglass.io/v2/weather/point?lat={lat}&lng={lng}&params=swellHeight,swellPeriod,swellDirection&start={unix}&end={unix}`
2. THE ServiceDelegate SHALL use the `SurfSpotLat`/`SurfSpotLng` coordinates for the swell request
3. THE ServiceDelegate SHALL request a 24-hour window (start of current day UTC to end of current day UTC) for swell data
4. THE ServiceDelegate SHALL extract the hourly entry closest to the current time from the response for display
5. THE ServiceDelegate SHALL refresh Swell_Data at most once per calendar day (same refresh logic as tide: new day or first fetch)
6. THE DataManager SHALL persist Swell_Data to Application.Storage with a "surf_" prefixed key to keep it separate from Shore_Mode cache
7. IF the StormGlass API returns an error or quota is exhausted, THEN THE ServiceDelegate SHALL skip the swell fetch and retain previously cached data

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

**User Story:** As a surfer, I want the watch face to manage StormGlass API calls efficiently, so that I don't exhaust my daily quota when using surf mode.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE ServiceDelegate SHALL make at most 2 StormGlass API calls per day: 1 for tide extremes and 1 for Swell_Data
2. THE ServiceDelegate SHALL chain the swell fetch after the tide fetch within a single onTemporalEvent() cycle, following the existing request chaining pattern
3. THE ServiceDelegate SHALL track swell fetch timestamps separately from tide fetch timestamps in Application.Storage
4. THE ServiceDelegate SHALL respect the existing StormGlass quota exhaustion guard (stormGlassQuotaExhausted flag) for both tide and swell requests
5. IF the combined tide + swell requests would exceed the daily quota (10 calls/day free tier), THEN THE ServiceDelegate SHALL prioritize the tide fetch over the swell fetch

---

### Requirement 12: Surf Mode Wind Data Source

**User Story:** As a surfer, I want wind data in surf mode to come from the StormGlass weather endpoint for the surf spot, so that wind readings match the location I'm surfing.

#### Acceptance Criteria

1. WHILE `SurfMode` is set to 1, THE DataManager SHALL source wind speed and wind direction from the StormGlass weather response (same API call as Swell_Data), using the windSpeed and windDirection fields
2. WHILE `SurfMode` is set to 1, THE DataManager SHALL store surf wind data in "surf_" prefixed Application.Storage keys
3. WHILE `SurfMode` is set to 0, THE DataManager SHALL source wind data from the existing weather source (Garmin built-in or OWM), unchanged from current behavior

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

---

### Requirement 14: Tide Height Interpolation

**User Story:** As a surfer, I want to see the current estimated tide height, so that I know the water level right now rather than just the next event's height.

#### Acceptance Criteria

1. THE DataManager SHALL compute an interpolated current tide height from the tideExtremes array by finding the two surrounding events (previous and next) and linearly interpolating based on the current time
2. WHILE `SurfMode` is set to 1, THE Watch_Face SHALL display the interpolated current tide height in the Subscreen_Circle
3. IF only one surrounding tide event is available (e.g., before the first event of the day), THEN THE DataManager SHALL use the nearest event's height as the current height
4. THE DataManager SHALL update the interpolated tide height on each onUpdate() call
