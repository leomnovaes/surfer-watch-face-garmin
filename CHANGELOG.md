# Changelog

## v1.1.0 (unreleased)

### Changed
- OWM weather refresh interval reduced from 30 minutes to 5 minutes (~288 calls/day, within 1000/day free tier)

### Fixed
- Re-rasterized weather-icons font: 3 glyphs (B/day-cloudy, f/night-snow, g/night-cloudy-gusts) had wrong codepoints baked in during original manual .fnt remapping. Root cause: char ID remapping errors during hand-editing. g was showing a rain icon instead of cloudy-gusts, which caused OWM 803 (broken clouds) to display rain at night.
- Removed dead `precipPop` field from DataManager (was always null)
- Fixed `owmFetchedAt` dual-source: DataManager now reads from Storage (single source of truth)
- Fixed notification icon described as "bell" — it's a speech bubble
- Fixed Bluetooth icon documented in date row — it's in the notification row (top section, row 2)

## v1.0.0

Initial release. Surfer-focused watch face for Garmin Instinct 2X Solar with tide, weather, wind, moon phase, heart rate, stress arc, and more.
