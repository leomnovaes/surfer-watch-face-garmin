# Changelog

## v1.0.0

Initial public release of Surfer Watch.

### Features

**Shore Mode (default)**
- Time with custom font (Saira Condensed Bold or Rajdhani Bold)
- Date, battery, notifications, Bluetooth connectivity
- Heart rate with stress arc gauge
- Next tide time, direction, and predicted height (StormGlass API, MLLW datum)
- Sunrise/sunset with directional icon
- Weather condition icon (day/night variants), temperature
- Wind direction arrow and speed (configurable: km/h, knots, mph, m/s)
- Precipitation chance
- Moon phase (28 phases, computed locally)
- Seconds on wrist raise

**Surf Mode**
- Swell height, period, direction (Open-Meteo Marine API, free, no key)
- Tide curve graph with filled area, dithered "now" marker, time labels
- Interpolated current tide height in subscreen circle
- Wind direction and speed for surf spot
- Water temperature: watch sensor or ocean surface (Open-Meteo Marine, hourly, works offline)
- Solar intensity arc gauge
- Sunrise/sunset for surf spot
- Double wrist gesture (4s window) toggles between swell view and tide curve
- Surf spot location: manual entry or one-tap GPS copy
- Hourly wind forecast advances offline when phone disconnects (Open-Meteo)

**Weather Sources**
- Garmin built-in (default, zero config)
- Open-Meteo (no key needed, WMO codes, precipitation probability)
- OpenWeatherMap 2.5 (needs key, most granular condition icons)

**Data Sources**
- StormGlass API for tide extremes (78h window, backup key with immediate 402 retry)
- Open-Meteo Marine API for swell + ocean surface temperature (free, 24h hourly forecast)
- Open-Meteo Weather API for weather + surf wind forecast (free, no key)
- OpenWeatherMap 2.5 for weather (optional, needs key)
- Garmin built-in for weather, precipitation (default)

**Supported Devices**
- Garmin Instinct 2
- Garmin Instinct 2X Solar
- Garmin Instinct 3 Solar 45/50mm

**Settings**
- Clock Font, Wind Speed Unit, Weather Source
- Display Mode (Shore/Surf), Surf Temperature Source (Watch/Ocean)
- Surf Spot Lat/Lng, Copy GPS to Surf Spot
- OWM API Key, StormGlass API Key + Backup
- Home Lat/Lng
