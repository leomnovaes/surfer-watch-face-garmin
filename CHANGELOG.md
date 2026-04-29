# Changelog

## v1.1.0

### New Features
- **Always Show Seconds** — new setting to keep seconds visible in low-power mode (uses per-second partial updates). Off by default to save battery.
- **Configurable Arc Gauge** — choose what the arc around the subscreen circle displays, independently for shore and surf modes. Options: Stress (shore default), Solar Intensity (surf default), Body Battery, or Disabled.
- **Surf Bottom View Configuration** — choose the default bottom section in surf mode (Swell or Tide Curve) and enable/disable the double wrist gesture toggle. Lock your preferred view before paddling out.

### Improved
- Sunrise/sunset accuracy upgraded to ±1 minute (SunCalc Julian date algorithm with equation of time and atmospheric refraction)
- Sunrise/sunset no longer overwritten by local computation when API provides values (OWM/Open-Meteo)
- Architecture refactored to Crystal Face pattern — App class has zero DataManager references, freeing background memory
- Background events always trigger foreground refresh (fixes Garmin mode sunrise/sunset not updating)
- Background delegate reads GPS and Bluetooth directly from OS APIs
- GPS reads moved from per-tick to event-driven
- Moon phase computation moved from per-tick to event-driven
- Weather glyph mappers consolidated into single function (saves 360 bytes code)
- All Storage keys shortened to 2-3 characters
- Storage version gating prevents stale key bloat on updates
- Dead code removed: unused font files, unused sensor fields, debug prints
- Single clock font loaded at a time with live reload on settings change

### Changed
- Removed Home Latitude / Home Longitude settings (GPS from watch is sufficient)

### Memory
- Peak memory: 59.4KB (was 59.5KB pre-refactor) — added 4 features while maintaining same footprint
- Code: 32263 bytes, Data: 9519 bytes

## v1.0.3

### Fixed
- Sunrise/sunset times now accurate to ±1 minute (was ±5 min). Upgraded from simplified solar position to SunCalc Julian date algorithm with equation of time correction and atmospheric refraction.
- Sunrise/sunset no longer overwritten by local computation when API provides values (OWM/Open-Meteo). Only Garmin weather source computes locally.

### Changed
- Architecture refactored to Crystal Face pattern: App class has zero DataManager references, freeing background memory for tide JSON parsing
- Single clock font loaded at a time (saves ~4KB). Live reload on settings change — no app restart needed.
- Removed Home Latitude / Home Longitude settings (GPS position from watch is sufficient)

### Improved
- Peak foreground memory reduced from 59.7KB to ~58.2KB (1.5KB more headroom)
- GPS reads moved from per-tick to event-driven (every 5 min on background events)
- Moon phase computation moved from per-tick to event-driven
- Background delegate reads GPS and Bluetooth directly from OS APIs instead of relaying through Storage
- All Storage keys shortened to 2-3 characters to reduce data memory
- Storage version gating: stale keys from previous versions automatically cleared on update
- Removed debug println from background process (was consuming memory via string allocation)
- Removed dead code: persistTideData(), unused WeatherService fields, unused font files

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


## v1.0.2

### Fixed
- Wind and swell arrows now correctly point in the TRAVEL direction (tip = where it's heading, tail = where it comes from). Was pointing in the FROM direction for N/S angles.


### Fixed
- Precipitation probability now consistent across all weather sources — always reads from DataManager, no direct Garmin API access in the view
- OWM mode populates precipitation from Garmin built-in (OWM 2.5 doesn't include pop)
- Switching weather source shows "--" for all fields until new source responds (was showing stale pop from previous source)

### Changed
- Weather source tradeoffs documented in README and store description (Open-Meteo model-based vs OWM station observations)
- Surf mode temperature now shows 1 decimal place (8.8°C instead of 8°C)
- Ocean surface temperature option added (Open-Meteo Marine, hourly, works offline)
- Settings reordered for better UX
- Launcher icon 62x62 PNG (was 24x24 SVG causing scaling warnings)
- Store cover image updated to 500x500 with Surfer Watch branding
