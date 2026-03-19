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
- Next sunrise/sunset time and direction icon — via OWM API
- Weather condition icon and temperature — via OWM API
- Wind direction and speed — via OWM API
- Precipitation chance — via OWM API
- Moon phase icon and illumination % — calculated
- Seconds display (hidden by default, revealed on wrist gesture to save battery)
- AM/PM indicator
- Secondary view via double-wrist gesture (future)

## Design Principles
- Design is locked first as a spec; code is generated to match the spec
- Placeholders are used for data not yet wired up — no layout changes when data is added
- 2-color MIP display constraint: black and white only, no gradients
- Minimal battery impact: avoid unnecessary redraws, lazy-load external data
- Location-aware: GPS/last known position used for all location-dependent data
