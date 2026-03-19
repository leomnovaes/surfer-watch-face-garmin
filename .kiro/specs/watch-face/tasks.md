# Watch Face Tasks

## Status Legend
- [ ] Not started
- [x] Complete
- [-] In progress

---

## Phase 1 — Project Scaffold & Static Layout

### Task 1: Clean up scaffolded project
- [x] Delete `resources/layouts/layout.xml` (not used — rendering is code-driven)
- [x] Remove `setLayout()` call from `SurferWatchFaceView.onLayout()`
- [x] Rename source files to match `structure.md` naming conventions
- [x] Verify project still builds after cleanup
- Satisfies: design §2.1

### Task 2: Add required permissions to manifest
- [x] Add `Communications` permission to `manifest.xml`
- [x] Add `Positioning` permission to `manifest.xml`
- [x] Add `SensorHistory` permission to `manifest.xml`
- [x] Add `Background` permission to `manifest.xml`
- [x] Add `:background` annotation to `SurferWatchFaceDelegate`, `WeatherService`, and `TideService` classes in source
- [x] Verify build succeeds
- Satisfies: design §8, requirements §2.1–2.4

### Task 3: Add app settings to properties.xml
- [x] Add `OWMApiKey` (string) property
- [x] Add `StormGlassApiKey` (string) property
- [x] Add `HomeLat` (float) property with default 0.0
- [x] Add `HomeLng` (float) property with default 0.0
- [x] Add corresponding entries to `settings.xml` for Garmin Connect UI
- Satisfies: requirements §3.1

### Task 4: Implement static background and canvas clear
- [x] Implement `SurferWatchFaceBackground.draw()` to fill canvas black
- [x] Implement `SurferWatchFaceView.onUpdate()` skeleton that clears screen and calls section helpers
- [x] Verify black screen renders in simulator
- Satisfies: requirements §5.1, design §1.1

### Task 5: Draw static placeholder — top section
- [x] Implement `drawTopSection(dc)` with hardcoded placeholder values
  - Row 1: "75%" + battery icon placeholder (rectangle outline)
  - Row 2: "3" + notification icon placeholder
  - Row 3: "↑ 14:32" + "1.8m" tide placeholders
- [x] Verify layout matches reference-design.png positions
- Satisfies: requirements §1.2, design §1.3

### Task 6: Draw static placeholder — heart rate circle
- [x] Implement `drawHrCircle(dc)` with hardcoded placeholder values
  - Filled white circle at x=148, y=52, r=22
  - Heart symbol (text "♥") centered above BPM
  - "72" BPM placeholder
- [x] Verify circle renders correctly in simulator
- Satisfies: requirements §1.1, design §1.3

### Task 7: Draw static placeholder — middle section
- [x] Implement `drawMiddleSection(dc)` with hardcoded placeholder values
  - Left: sunrise icon placeholder + "06:12"
  - Center: "10:49" in FONT_LARGE, centered at x=88
  - Right: moon icon placeholder + "78%" + "AM"
  - Seconds hidden (not drawn)
- [x] Verify time is centered and readable
- Satisfies: requirements §1.3, design §1.3

### Task 8: Draw static placeholder — date row and dividers
- [x] Implement `drawDateRow(dc)` with hardcoded "Wed Mar 18"
- [x] Draw bluetooth icon placeholder left of date
- [x] Draw three horizontal divider lines per design §1.3
- Satisfies: requirements §1.4, design §1.3

### Task 9: Draw static placeholder — weather widget
- [x] Implement `drawWeatherWidget(dc)` with hardcoded placeholder values
  - Col 1: weather icon placeholder + "18°C"
  - Col 2: wind arrow placeholder + "13 km/h"
  - Col 3: umbrella icon placeholder + "76%"
- Satisfies: requirements §1.5, design §1.3

### Task 10: Pixel-tune full static layout
- [ ] Run in simulator, compare against reference-design.png
- [ ] Adjust coordinates until layout matches reference
- [ ] Verify no content is clipped by semi-octagon corners
- Satisfies: design §1.1, §1.2

---

## Phase 2 — Live Watch Sensor Data

### Task 11: Implement DataManager skeleton
- [x] Create `DataManager.mc` with all fields from design §2.2
- [x] Implement `initialize()` — loads persisted tide data from `Application.Storage`
- [x] Implement `updateSensorData()` reading HR, battery, notifications, BT status, GPS
- [x] In `updateSensorData()`: write `lastKnownLat`, `lastKnownLng`, `bluetoothConnected` to `Application.Storage` so background process can read them
- [x] Implement `onWeatherData(data)` — receives parsed OWM data from background, stores fields
- [x] Implement `onTideData(data)` — receives parsed tide array from background, persists to storage
- [x] Wire `updateSensorData()` call into `onUpdate()`
- Satisfies: requirements §2.1, design §2.2, §4.5

### Task 12: Wire live time and date
- [x] Replace hardcoded time in `drawMiddleSection()` with `System.getClockTime()`
- [x] Respect `is24Hour` device setting
- [x] Replace hardcoded date in `drawDateRow()` with current date from `Gregorian.info(Time.now(), Time.FORMAT_SHORT)`
- Satisfies: requirements §2.1

### Task 13: Wire live battery
- [x] Replace hardcoded battery % with `DataManager.battery`
- [x] Implement battery icon selection logic (5 levels) using rectangle placeholders
- Satisfies: requirements §1.2, §2.1

### Task 14: Wire live heart rate
- [x] Replace hardcoded BPM with `DataManager.heartRate`
- [x] Display `--` when `heartRate == null`
- Satisfies: requirements §1.1, §2.1

### Task 15: Wire live notifications and Bluetooth
- [x] Replace hardcoded notification count with `DataManager.notificationCount`
- [x] Show/hide bluetooth icon based on `DataManager.bluetoothConnected`
- Satisfies: requirements §1.2, §1.4, §2.1

---

## Phase 3 — Location

### Task 16: Implement GPS / location fallback
- [x] In `DataManager.updateSensorData()`: read GPS via `Position.getInfo()`
- [x] If GPS unavailable, fall back to `HomeLat`/`HomeLng` from app properties (treat `0.0` as not set)
- [x] Write `lastKnownLat`, `lastKnownLng` to both DataManager fields and `Application.Storage`
- [x] Display `--` for all location-dependent fields when no valid location available
- Satisfies: requirements §2.2, design §4.5

---

## Phase 4 — Weather (OWM)

### Task 17: Implement ServiceDelegate and WeatherService
- [x] Create `SurferWatchFaceDelegate.mc` extending `Background.ServiceDelegate`
- [x] Implement `onTemporalEvent()` — reads refresh timestamps from `Application.Storage`, decides what to fetch, chains requests per design §2.4
- [x] Implement `WeatherService.fetch(lat, lon, apiKey, units)` — builds OWM URL, makes request, parses response into a Dictionary
- [x] In OWM callback: if StormGlass refresh also needed, chain into `TideService.fetch()`; otherwise call `Background.exit({:weather => weatherDict})`
- [x] Register temporal event in `SurferWatchFaceApp.initialize()`: `Background.registerForTemporalEvent(new Time.Duration(5 * 60))`
- [x] Implement `SurferWatchFaceView.onBackgroundData(data)` — routes `:weather` key to `DataManager.onWeatherData()`, `:tides` key to `DataManager.onTideData()`
- Satisfies: requirements §2.3, design §2.3, §2.4, §3

### Task 18: Implement OWM refresh logic in ServiceDelegate
- [x] In `onTemporalEvent()`: check `owmFetchedAt` and distance from `owmFetchLat/Lon` vs current position
- [x] Implement `distanceBetween()` Haversine helper in ServiceDelegate
- [x] Guard: skip if `bluetoothConnected == false` (read from `Application.Storage`)
- [x] On successful fetch: write `owmFetchedAt`, `owmFetchLat`, `owmFetchLon` to `Application.Storage`
- Satisfies: requirements §2.3, design §4.1, §4.5

### Task 19: Wire live weather data to view
- [x] Replace weather condition placeholder with icon mapped from `weatherConditionId` (design §6)
- [x] Replace temperature placeholder with `DataManager.temperature` + unit suffix (°C or °F)
- [x] Replace wind placeholder with `DataManager.windSpeed` converted per design §4.4 + direction arrow (from `windDeg`)
- [x] Replace precipitation placeholder with `DataManager.precipPop * 100`%
- [x] Display `--` for all fields when OWM data is null or stale (>2h)
- Satisfies: requirements §1.5, §2.3

### Task 20: Wire live sunrise/sunset to view
- [x] Compare `DataManager.sunrise` and `DataManager.sunset` to current time
- [x] Display the next upcoming event with correct icon (↑ sunrise, ↓ sunset)
- [x] Display `--` when OWM data unavailable
- Satisfies: requirements §1.3, §2.3

### Task 21: Wire live moon phase to view
- [x] Map `DataManager.moonPhase` to icon using design §7 mapping
- [x] Calculate illumination % using `Math.round(Math.sin(moonPhase * Math.PI) * 100)`
- [ ] Display `--` when OWM data unavailable
- Satisfies: requirements §1.3, §2.5

---

## Phase 5 — Tide (StormGlass)

### Task 22: Implement TideService in ServiceDelegate
- [x] Implement `TideService.fetch(lat, lng, apiKey)` — builds StormGlass URL with 48h window, sets `Authorization` header
- [x] Parse response array, convert ISO time strings to Unix timestamps
- [x] Check `meta.requestCount` vs `meta.dailyQuota`; if exhausted, write `stormGlassQuotaExhausted=true` to `Application.Storage`
- [x] Package tide result and include in `Background.exit()` payload alongside weather data
- Satisfies: requirements §2.4, design §2.4

### Task 23: Implement tide persistence
- [x] Implement `DataManager.persistTideData()` saving array + fetch day to `Application.Storage`
- [x] Implement `DataManager.loadTideData()` restoring from `Application.Storage` on startup
- [x] Call `loadTideData()` from `DataManager.initialize()`
- Satisfies: requirements §2.4, §5.2

### Task 24: Implement StormGlass refresh logic in ServiceDelegate
- [x] In `onTemporalEvent()`: check `tideFetchedDay` vs today UTC, and distance from `tideFetchLat/Lng` vs `lastKnownLat/Lng`
- [x] Guard: skip if `stormGlassQuotaExhausted == true` in `Application.Storage`
- [x] On successful fetch: write `tideFetchedDay`, `tideFetchLat`, `tideFetchLng` to `Application.Storage`
- Satisfies: requirements §2.4, design §4.2, §4.5

### Task 25: Implement computeNextTide()
- [x] Walk `tideExtremes` array to find first event where `time > now`
- [x] Set `DataManager.nextTideTime`, `nextTideType`
- [x] Interpolate `currentTideHeight` between previous and next extreme
- [x] If no future events found (all in past), write `tideDataExpired=true` to `Application.Storage` to trigger background refresh
- [x] Call from `onUpdate()` each tick
- Satisfies: requirements §1.2, design §2.2, §4.2

### Task 26: Wire live tide data to view
- [x] Replace tide direction placeholder with icon based on `nextTideType`
- [x] Replace tide time placeholder with formatted `nextTideTime`
- [x] Replace tide height placeholder with `currentTideHeight` converted per design §4.4 ("X m" or "X ft")
- [x] Display `--` when tide data unavailable
- Satisfies: requirements §1.2, §2.4

---

## Phase 6 — Icons

### Approach (revised after research)
- **BMFont rasterization** is the standard community approach for icon fonts on Garmin
- **Crystal Face** (warmsound/crystal-face) is the reference implementation — uses Erik Flowers Weather Icons rasterized via BMFont with proven settings
- **Proven BMFont settings**: fontSize=-17, aa=2, useHinting=1, useSmoothing=1, padding=0,0,0,0, spacing=1,1, outWidth=256, outHeight=256, outBitDepth=8, alphaChnl=1, format=png
- **Grid-aligned sizes** (power of 2 divisors of em-size) produce best results: 16px, 32px for em=512/2048 fonts
- **Anti-aliasing ON** (aa=2) produces better results than monochrome — Garmin's 1-bit renderer thresholds the gray pixels

### Task 27: Validate re-rasterization approach
- [ ] Re-rasterize a few Erik Flowers Weather Icons glyphs using Crystal Face's BMFont settings (fontSize=-17, aa=2, hinting=1, smoothing=1, padding=0, spacing=1,1, 256x256, 8-bit)
- [ ] Compare output visually with Crystal Face's pre-rasterized `weather-icons-20.fnt`/`weather-icons-20_0.png`
- [ ] If results match: proceed with re-rasterization for our full glyph set
- [ ] If results differ: use Crystal Face files directly (GPL license) and supplement missing glyphs

### Task 28: Generate final Weather Icons font
- [ ] Using validated BMFont settings, rasterize Erik Flowers Weather Icons TTF with all needed glyphs:
  - Weather conditions (21): per design §6 OWM mapping
  - Sunrise/sunset (2): wi-sunrise (0xF051), wi-sunset (0xF052)
  - Umbrella (1): wi-umbrella (0xF084)
  - Moon phases (16): per design §7
- [ ] Place output `.fnt` + `.png` in `resources/fonts/`
- [ ] Add font resource entry to `resources/fonts/fonts.xml`
- [ ] Verify font loads in simulator without errors

### Task 29: Generate final general icons font
- [ ] Compare Crystal Face crystal-icons-small (custom pixel-art) vs Font Awesome re-rasterized with proven BMFont settings for: heart, bluetooth, notification/bell
- [ ] Choose better-looking option
- [ ] Place output `.fnt` + `.png` in `resources/fonts/`
- [ ] Add font resource entry to `resources/fonts/fonts.xml`
- [ ] Verify font loads in simulator without errors

### Task 30: Wire weather condition icons into view
- [ ] Load Weather Icons font resource in `SurferWatchFaceView`
- [ ] Update `drawIconWeather()` to select glyph based on `DataManager.weatherConditionId` using OWM code mapping (design §6)
- [ ] Verify weather condition icon changes based on live OWM data in simulator

### Task 31: Wire sunrise/sunset icons into view
- [ ] Update `drawIconSun()` to use wi-sunrise / wi-sunset glyphs from Weather Icons font
- [ ] Verify icons render correctly in simulator

### Task 32: Wire heart, bluetooth, notification icons into view
- [ ] Update `drawIconHeart()`, `drawIconBluetooth()`, `drawIconNotification()` to use chosen font glyphs
- [ ] Verify all three icons render correctly in simulator

### Task 33: Wire moon phase icons into view
- [ ] Update `drawIconMoon()` to select from 16 phase glyphs based on `DataManager.moonPhase`
- [ ] Map moonPhase (0.0–1.0) to 16 evenly-spaced glyph indices per design §7
- [ ] Verify moon icon changes based on calculated phase in simulator

### Task 34: Wire umbrella icon into view
- [ ] Update `drawIconUmbrella()` to use wi-umbrella glyph from Weather Icons font
- [ ] Verify icon renders correctly in simulator

### Task 35: Implement wind direction arrow (procedural polygon)
- [ ] Implement `drawWindArrow(dc, x, y, degrees)` using `dc.fillPolygon()` — triangle with swallow tail
- [ ] Calculate polygon vertices rotated to wind direction from `DataManager.windDeg`
- [ ] Replace wind icon placeholder with procedural arrow
- [ ] Verify arrow rotates correctly based on live OWM wind data in simulator

### Task 36: Implement tide direction icons
- [ ] Search community fonts (sunpazed/garmin-iconfonts, mondrian) for tide high/low wave glyphs
- [ ] Typical mapping: high tide = wave+up arrow, low tide = wave+down arrow
- [ ] If found: rasterize with proven BMFont settings and add to font resources
- [ ] If not found: draw procedurally or use simple up/down arrow text
- [ ] Wire into `drawIconTide()` and verify in simulator

### Task 37*: Add night weather condition variants (deferred)
- [ ]* Identify night variant glyphs from Weather Icons (wi-night-clear, wi-night-alt-cloudy, etc.)
- [ ]* Add night glyphs to the Weather Icons BMFont conversion
- [ ]* Update `drawIconWeather()` to check if current time is between sunset and sunrise
- [ ]* If nighttime, use night variant glyph instead of day variant

---

## Phase 7 — Polish & Sideload

### Task 38: Implement seconds reveal (placeholder gesture)
- [ ] Add seconds field to `drawMiddleSection()`, hidden by default
- [ ] Add a settings property `ShowSeconds` (boolean) as temporary toggle until gesture is implemented
- Satisfies: requirements §4.2

### Task 39: Pixel-tune full layout with real icons
- [ ] Run in simulator with all icons rendered
- [ ] Adjust icon font sizes if needed (regenerate at different px)
- [ ] Adjust coordinates until layout matches reference
- [ ] Verify no content is clipped by semi-octagon corners
- Satisfies: design §1.1, §1.2

### Task 40: Sideload to physical watch
- [ ] Build `.prg` file via `Monkey C: Build for Device`
- [ ] Copy to watch via USB: `GARMIN/APPS/`
- [ ] Validate all fields render correctly on real hardware
- [ ] Validate MIP display (confirm no color artifacts)
- Satisfies: requirements §5.1

### Task 41: Final layout tuning on device
- [ ] Compare physical watch rendering against reference-design.png
- [ ] Adjust font sizes, spacing, divider positions as needed
- [ ] Add dividing lines if needed for readability
- Satisfies: design §1.3
