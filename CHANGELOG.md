# Changelog

## v1.1.0

### New Features
- **Always Show Seconds** — keep seconds visible in low-power mode. Off by default to save battery.
- **Configurable Arc Gauge** — choose what the arc displays per mode: Stress, Solar Intensity, Body Battery, or Disabled.
- **Surf Bottom View Configuration** — choose default bottom section (Swell or Tide Curve) and enable/disable wrist gesture toggle.

### Improved
- Sunrise/sunset accuracy upgraded to ±1 minute (SunCalc algorithm)
- Architecture refactored to Crystal Face pattern for better memory efficiency
- GPS and moon phase moved from per-tick to event-driven
- Weather glyph mappers consolidated into single function
- Storage keys shortened, version gating prevents stale data on updates
- Dead code and unused resources removed

### Changed
- Removed Home Latitude / Home Longitude settings (GPS from watch is sufficient)

## v1.0.2

### Fixed
- Wind and swell arrows now correctly point in the TRAVEL direction
- Precipitation probability consistent across all weather sources
- Switching weather source clears stale data

### Changed
- Surf mode temperature shows 1 decimal place
- Ocean surface temperature option added (Open-Meteo Marine)
- Settings reordered for better UX
- Launcher icon updated to 62x62 PNG

## v1.0.0

Initial public release of Surfer Watch.

### Features
- Shore Mode: time, date, battery, HR, stress arc, tide, sunrise/sunset, weather, wind, precipitation, moon phase, notifications, Bluetooth
- Surf Mode: swell, tide curve, interpolated tide height, wind, water temperature, solar arc, surf sunrise/sunset
- Weather Sources: Garmin built-in, Open-Meteo (no key), OpenWeatherMap 2.5
- Tide data via StormGlass API with backup key support
- Swell + ocean temperature via Open-Meteo Marine API (free)
- Double wrist gesture toggles surf bottom view
- Custom clock font (Saira Condensed / Rajdhani)
- Supported: Instinct 2, Instinct 2X Solar, Instinct 3 Solar 45/50mm
