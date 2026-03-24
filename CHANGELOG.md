# Changelog

## v2.0.0 (unreleased)

### Added
- Surf mode: alternate watch face layout for in-water use, toggled via settings
- Subscreen circle: interpolated tide height + solar intensity arc + tide direction icon (replaces HR + stress)
- Water temperature from watch body temp sensor
- Swell data: height, period, direction from Open-Meteo Marine API (free, no key, 24h hourly forecast)
- Tide curve graph with filled area, dithered "now" marker, triangle indicator, time labels
- Double wrist gesture toggles between swell view and tide curve in surf mode
- Surf spot location settings: manual lat/lng entry + one-tap GPS copy
- StormGlass backup API key setting with automatic failover on 402
- Surfing, thermometer, timer-sand icons rasterized from Material Design Icons
- Open-Meteo Marine API integration (free, unlimited, ~1.2KB response)
- Separate surf/shore wind fields (surfWindSpeed/surfWindDeg vs windSpeed/windDeg)
- Background chain for surf mode: Open-Meteo swell → StormGlass tide → OWM wind
- -403 detection stops background chain immediately (memory exhausted safety)
- Open-Meteo Weather API as third weather source (no key, WMO codes, hourly wind forecast for surf offline)
- 3-tier weather source setting: Garmin (default), Open-Meteo (no key), OpenWeatherMap (needs key)
- WMO weather code mapper for Open-Meteo conditions
- Precipitation probability from Open-Meteo when selected as source
- Surf mode hourly wind forecast (Open-Meteo): 24h array, advances offline when phone disconnects

### Changed
- Swell data source: StormGlass weather → Open-Meteo Marine (free, no quota)
- StormGlass now used only for tide extremes (1 call/day)
- Swell stored as 3 flat arrays in Application.Storage, advances hourly via updateSwellFromForecast()
- Surf mode OWM call extracts only wind — does not pollute shore weather fields

### Fixed
- Weather icon mapping: 5 community-validated overrides for misleading Erik Flowers mappings
- Background memory: flat array storage instead of nested dictionaries

## v1.1.0

### Added
- Tiered weather source: Garmin built-in (default, zero config) or OpenWeatherMap (optional)
- WeatherSource setting in Garmin Connect app
- Local sunrise/sunset computation for Garmin weather mode (CIQ 3.4 compatible)
- Garmin condition code mapper (54 weather conditions → icon glyphs)
- Wind speed unit setting: Auto, km/h, knots, mph, m/s
- Wind speed now shows 1 decimal digit (e.g., "11.4" instead of "11kph")
- CHANGELOG.md for version tracking
- Release checklist in steering files

### Changed
- OWM switched from 3.0 One Call to 2.5 Current Weather (no credit card needed, 1M calls/month free)
- OWM weather fetches on every background event (removed time/distance guards, simplified logic)
- Immediate background fetch attempted on face start (falls back to 5-min if system enforces minimum)
- Background re-registers at 5-min interval after each data receipt
- Wind arrow: size 9→7, y-offset 7→5 (slightly smaller and higher)
- Weather data cleared on source switch to prevent condition code mismatch

### Fixed
- Re-rasterized weather-icons font: 3 glyphs (B/day-cloudy, f/night-snow, g/night-cloudy-gusts) had wrong codepoints from manual .fnt remapping
- Override 5 misleading Erik Flowers OWM icon mappings (community-validated): 803 broken clouds→cloudy, 701 mist→fog, 602 heavy snow→snow, 531 ragged showers→showers, 611-612 sleet→sleet icon
- Removed dead `precipPop` field from DataManager
- Fixed `owmFetchedAt` dual-source: DataManager reads from Storage (single source of truth)
- Fixed notification icon described as "bell" — it's a speech bubble
- Fixed Bluetooth icon documented in date row — it's in the notification row

## v1.0.0

Initial release. Surfer-focused watch face for Garmin Instinct 2X Solar with tide, weather, wind, moon phase, heart rate, stress arc, and more.
