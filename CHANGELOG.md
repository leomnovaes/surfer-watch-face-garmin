# Changelog

## v1.1.0 (unreleased)

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
- Removed dead `precipPop` field from DataManager
- Fixed `owmFetchedAt` dual-source: DataManager reads from Storage (single source of truth)
- Fixed notification icon described as "bell" — it's a speech bubble
- Fixed Bluetooth icon documented in date row — it's in the notification row

## v1.0.0

Initial release. Surfer-focused watch face for Garmin Instinct 2X Solar with tide, weather, wind, moon phase, heart rate, stress arc, and more.
