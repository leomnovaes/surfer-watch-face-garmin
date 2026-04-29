# Product Overview

## What
A custom Garmin watch face for the Instinct 2X Solar, designed for surfers and outdoor athletes who need at-a-glance access to time, environmental, and ocean conditions.

## Target User
Surfers and outdoor athletes who wear the Garmin Instinct 2X Solar and want a single watch face that surfaces the most relevant data for their lifestyle — tide conditions, weather, wind, and standard fitness metrics — without needing to navigate menus.

## Key Features
- Current time (large, always visible)
- Date and day of week
- Heart rate (live from watch sensor)
- Battery level with dynamic icon
- Notification count
- Bluetooth connectivity status
- Next tide time and direction (high/low), current tide height — via StormGlass API
- Next sunrise/sunset time and direction icon — via OWM API, Open-Meteo API, or local SunCalc computation (Garmin mode)
- Weather condition icon and temperature — via Garmin built-in (default), Open-Meteo (no key), or OWM API
- Wind direction and speed — via Garmin built-in, Open-Meteo, or OWM API
- Precipitation chance — via DataManager (Garmin built-in, Open-Meteo API, or Garmin fallback for OWM)
- Moon phase icon — computed locally from synodic period (28 phases)
- Seconds display (hidden by default, revealed on wrist gesture to save battery, or always-on via setting)
- AM/PM indicator
- Surf mode: swell height/period/direction (Open-Meteo Marine API, free), tide curve graph, interpolated tide height, water temperature, configurable arc gauge (solar/stress/body battery/disabled), surf spot wind (Open-Meteo hourly forecast or OWM current)
- Double wrist gesture toggles surf mode bottom section between swell view and tide curve (configurable: default view + toggle enable/disable)

## Design Principles
- Design is locked first as a spec; code is generated to match the spec
- Placeholders are used for data not yet wired up — no layout changes when data is added
- 2-color MIP display constraint: black and white only, no gradients
- Minimal battery impact: avoid unnecessary redraws, lazy-load external data
- Location-aware: GPS/last known position used for all location-dependent data
