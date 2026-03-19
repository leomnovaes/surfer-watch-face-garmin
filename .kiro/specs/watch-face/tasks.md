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

### Task 27: Convert Garmin icons font to BMFont format
- [ ] Convert `garmin-connect-icons.ttf` using `fontbm` at 15px with glyphs: heart (0x6d), bluetooth (0x56), speech-bubble (0xC2)
- [ ] Also generate at 12px and 18px for size options during pixel tuning
- [ ] Place output `.fnt` + `.png` files in `resources/fonts/`
- [ ] Add font resource entry to `resources/fonts/fonts.xml` (create file if needed)
- [ ] Verify font loads in simulator without errors

### Task 28: Convert Weather Icons font to BMFont format
- [ ] Identify unicode codes for all needed glyphs:
  - Weather conditions (7): clear, clouds, rain, drizzle, thunderstorm, snow, fog
  - Sunrise/sunset (2): wi-sunrise, wi-sunset
  - Umbrella (1): wi-umbrella
  - Wind directions (8): wi-wind towards-N/NE/E/SE/S/SW/W/NW
  - Moon phases (16): select 16 evenly-spaced phases from the 28 available
- [ ] Convert `weathericons-regular-webfont.ttf` using `fontbm` at 15px with only the needed glyphs
- [ ] Also generate at 12px and 18px for size options
- [ ] Place output `.fnt` + `.png` files in `resources/fonts/`
- [ ] Add font resource entry to `resources/fonts/fonts.xml`
- [ ] Verify font loads in simulator without errors

### Task 29: Wire Garmin icon font into view
- [ ] Load Garmin icon font resource in `SurferWatchFaceView`
- [ ] Update `drawIconHeart()` to use font glyph instead of text placeholder
- [ ] Update `drawIconBluetooth()` to use font glyph
- [ ] Update `drawIconNotification()` to use speech-bubble font glyph
- [ ] Verify all three icons render correctly in simulator

### Task 30: Wire Weather Icons font — weather conditions
- [ ] Load Weather Icons font resource in `SurferWatchFaceView`
- [ ] Update `drawIconWeather()` to select glyph based on `DataManager.weatherConditionId` using OWM code mapping (design §6)
- [ ] Verify weather condition icon changes based on live OWM data

### Task 31: Wire Weather Icons font — sunrise/sunset
- [ ] Update `drawIconSun()` to use wi-sunrise / wi-sunset glyphs
- [ ] Verify icons render correctly in simulator

### Task 32: Wire Weather Icons font — wind direction
- [ ] Update `drawIconWind()` to select from 8 directional glyphs based on `DataManager.windDeg`
- [ ] Map degree ranges to cardinal directions (0=N, 45=NE, 90=E, etc.)
- [ ] Verify wind direction icon changes based on live OWM data

### Task 33: Wire Weather Icons font — moon phases
- [ ] Update `drawIconMoon()` to select from 16 phase glyphs based on `DataManager.moonPhase`
- [ ] Map moonPhase (0.0–1.0) to 16 evenly-spaced glyph indices
- [ ] Verify moon icon changes based on calculated phase

### Task 34: Wire Weather Icons font — umbrella
- [ ] Update `drawIconUmbrella()` to use wi-umbrella glyph
- [ ] Verify icon renders correctly in simulator

### Task 35: Tide direction icons
- [ ] Decide on tide high/low icon approach (wave+arrow, simple arrow, or other)
- [ ] If using Weather Icons: identify suitable glyphs
- [ ] If custom: create simple code-drawn icons or find suitable font glyphs
- [ ] Update `drawIconTide()` to use chosen icons
- [ ] Verify icons render correctly in simulator

### Task 36*: Add night weather condition variants (deferred)
- [ ]* Identify night variant glyphs from Weather Icons (wi-night-clear, wi-night-alt-cloudy, etc.)
- [ ]* Add night glyphs to the Weather Icons BMFont conversion
- [ ]* Update `drawIconWeather()` to check if current time is between sunset and sunrise
- [ ]* If nighttime, use night variant glyph instead of day variant

---

## Phase 7 — Polish & Sideload

### Task 37: Implement seconds reveal (placeholder gesture)
- [ ] Add seconds field to `drawMiddleSection()`, hidden by default
- [ ] Add a settings property `ShowSeconds` (boolean) as temporary toggle until gesture is implemented
- Satisfies: requirements §4.2

### Task 38: Pixel-tune full layout with real icons
- [ ] Run in simulator with all icons rendered
- [ ] Adjust font sizes (12/15/18px) for best visual balance
- [ ] Adjust coordinates until layout matches reference
- [ ] Verify no content is clipped by semi-octagon corners
- Satisfies: design §1.1, §1.2

### Task 39: Sideload to physical watch
- [ ] Build `.prg` file via `Monkey C: Build for Device`
- [ ] Copy to watch via USB: `GARMIN/APPS/`
- [ ] Validate all fields render correctly on real hardware
- [ ] Validate MIP display (confirm no color artifacts)
- Satisfies: requirements §5.1

### Task 40: Final layout tuning on device
- [ ] Compare physical watch rendering against reference-design.png
- [ ] Adjust font sizes, spacing, divider positions as needed
- [ ] Add dividing lines if needed for readability
- Satisfies: design §1.3
