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
- [x] Set `currentTideHeight` to the predicted height of the next tide event (not interpolated)
- [x] If no future events found (all in past), write `tideDataExpired=true` to `Application.Storage` to trigger background refresh
- [x] Call from `onUpdate()` each tick
- Note: Originally interpolated current height between extremes. Changed to show next event's predicted height — more useful for surfers planning around tide events.
- Satisfies: requirements §1.2, design §2.2, §4.2

### Task 26: Wire live tide data to view
- [x] Replace tide direction placeholder with icon based on `nextTideType`
- [x] Replace tide time placeholder with formatted `nextTideTime` (includes a/p in 12hr mode)
- [x] Replace tide height placeholder with next event's predicted height converted per design §4.4 ("X m" or "X ft")
- [x] Display `--` when tide data unavailable
- Note: `formatUnixTime()` now includes a/p suffix in 12hr mode. Tide height shows the predicted height of the next event, not interpolated current height.
- Satisfies: requirements §1.2, §2.4

---

## Phase 6 — Icons

### Approach (revised after research)
- **BMFont rasterization** is the standard community approach for icon fonts on Garmin
- **Crystal Face** (warmsound/crystal-face, GPL v3) is the reference implementation — uses Erik Flowers Weather Icons + custom crystal icons
- **fontbm cannot match BMFont quality** — different rasterizer (FreeType2 vs Windows GDI) produces half-pixel offset and different anti-aliasing
- **Current approach**: use Crystal Face's pre-rasterized .fnt/.png files directly where available (SIL OFL for weather icons, custom pixel-art for crystal icons)
- **Missing icons** need to be sourced from other community fonts or rasterized once we solve the quality gap

### Icons currently wired (from Crystal Face):
| Icon | Source | Font | Char | Status |
|------|--------|------|------|--------|
| Weather conditions (17) | Crystal Face weather-icons | WeatherIcons | A-I, a-h | ✅ Wired |
| Heart | Crystal Face crystal-icons | CrystalIcons | 3 | ✅ Wired |
| Bluetooth | Crystal Face crystal-icons | CrystalIcons | 8 | ✅ Replaced by Segment34 `L` |
| Notifications | Crystal Face crystal-icons | CrystalIcons | 5 | ✅ Wired |
| Sunrise | Crystal Face crystal-icons | CrystalIcons | > | ✅ Wired |
| Sunset | Crystal Face crystal-icons | CrystalIcons | ? | ✅ Wired |

### Icons still needed (text placeholders):
| Icon | Status | Approach |
|------|--------|----------|
| Umbrella/precipitation | Procedural (temporary) | Task 31b: rasterize from Material Design SVG to font glyph |
| Tide high/low | [^]/[v] placeholder | Task 32: rasterize from Material Design SVG (`waves-arrow-up/down`) |
| Wind direction | ✅ Procedural polygon | Done — `dc.fillPolygon()` rotated to exact degree |
| Battery | Code-drawn | Keep as-is |

### Community icon font sources discovered:
| Repo | Font file | Glyphs | Notes |
|------|-----------|--------|-------|
| warmsound/crystal-face | crystal-icons-small.fnt/.png | 17 (heart, BT, notif, sunrise, sunset, temp, etc.) | ✅ In use. GPL v3 code, custom pixel-art icons at 20px |
| warmsound/crystal-face | weather-icons.fnt/.png | 17 weather conditions (A-I day, a-h night) | ✅ In use. Erik Flowers SIL OFL, BMFont rasterized |
| ludw/Segment34mkII | icons.fnt/.png | 22 (alarm, battery x2, DND, BT on/off, heart, move bar levels, etc.) | Quality looks great. Has outline heart, simple BT |
| ludw/Segment34mkII | moon.fnt/.png | 9 moon phases (chars 0-8) | Detailed moon phases, quality looks great |
| bombsimon/garmin-seaside | weather-icons-16.fnt/.png | 12 weather glyphs (a-l) | Uses Garmin Weather.CONDITION_* mapping, 16px |
| SarahBass/Data-Heavy-Garmin-Watchface | weatherhoro.fnt/.png | 56 glyphs | Large set — weather + possibly horoscope + arrows + more |
| bsyrowik/BCTides | sine.png (various sizes) | Sine wave bitmap | Not a font — individual PNG bitmaps for tide visualization |

### Segment34mkII icon mapping (confirmed by visual inspection):
```
Icons font:
  0 = Arrow UP (N)
  1 = Arrow UP-RIGHT (NE)
  2 = Arrow RIGHT (E)
  3 = Arrow DOWN-RIGHT (SE)
  4 = Arrow DOWN (S)
  5 = Arrow DOWN-LEFT (SW)
  6 = Arrow LEFT (W)
  7 = Arrow UP-LEFT (NW)
  A = Alarm
  B = Battery variant 1
  C = Battery variant 2
  D = DND (Do Not Disturb)
  H = Heart (filled)
  h = Heart (outline)
  L = Bluetooth connected
  M = Bluetooth disconnected
  N-R = Move bar levels 1-5
  S = Unknown

Moon font:
  0 = New moon (dark)
  1 = Waxing crescent (illuminated from right)
  2 = First quarter
  3 = Waxing gibbous
  4 = Full moon
  5 = Waning gibbous
  6 = Last quarter
  7 = Waning crescent
  8 = Death Star (easter egg, not usable)
```

### SarahBass WeatherHoro — visual inspection:
Mostly numbers and zodiac signs. Weather icons present but lower quality than Crystal Face.
Notable: 108 (l) = sunrise, 110 (n) = sunset.
Not useful for our remaining needs.

### Summary of available icons for remaining needs:
| Need | Best source | Format | Notes |
|------|-----------|--------|-------|
| Wind direction (8) | Segment34mkII icons.fnt | Pre-rasterized .fnt/.png | Chars 0-7, 8 directional arrows. Fallback option if procedural polygon doesn't work. |
| Moon phases (8) | Segment34mkII moon.fnt | Pre-rasterized .fnt/.png | Chars 0-7 (skip char 8 Death Star). Quality looks great. |
| Umbrella/precipitation | Templarian/MaterialDesign-SVG | SVG (needs rasterization) | `umbrella-outline.svg`. Apache 2.0 license. |
| Tide high/low | Templarian/MaterialDesign-SVG | SVG (needs rasterization) | `waves-arrow-up.svg`, `waves-arrow-down.svg`. Apache 2.0 license. |
| Wind direction (procedural) | Custom code | `dc.fillPolygon()` | Triangle with swallow tail, rotated to exact wind degree. Primary approach. |

### Rasterization approach for custom icons (established):
The proven pipeline for rasterizing SVG icons to Garmin BMFont format:
1. Source: Material Design Icons webfont TTF (`materialdesignicons-webfont.ttf`, Apache 2.0)
2. Rasterize: `fontbm --font-file <ttf> --font-size 17 --chars <decimal_codepoints> --spacing-horiz 1 --spacing-vert 1 --padding-up 0 --padding-right 0 --padding-down 0 --padding-left 0 --texture-size 256x256 --output <name>`
3. Convert: `magick <name>_0.png -alpha extract -type grayscale -depth 8 <final>.png`
4. Edit .fnt: remap high unicode char IDs to ASCII, set `alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0`, fix filename
5. Result: 8-bit grayscale 256x256 PNG matching Crystal Face format

Key findings from rasterization testing:
- **PNG must be 8-bit grayscale** (not RGBA) — Garmin renderer reads grayscale value as alpha
- **Channel flags must be** `alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0` — matches Crystal Face
- **RGBA output causes bold/fat lines** — gray AA pixels get thresholded to white on MIP display
- **fontbm native AA at 17px** produces best results — matches Crystal Face target size
- **19px is a viable alternative** if more detail is needed
- **Monochrome** gives thinnest lines but loses detail compared to properly formatted grayscale AA
- **Gemini 2x supersample approach failed** — downscale destroyed glyph detail
- **Spacing/padding variations** made no visible difference at these sizes

### Task 27: Set up Crystal Face icons
- [x] Copy Crystal Face weather-icons .fnt/.png into `resources/fonts/`
- [x] Copy Crystal Face crystal-icons .fnt/.png into `resources/fonts/`
- [x] Update `resources/fonts/fonts.xml`
- [x] Verify fonts load in simulator

### Task 28: Wire Crystal Face icons into view
- [x] Wire weather condition icon (drawIconWeather with OWM code mapping)
- [x] Wire heart, bluetooth, notification icons
- [x] Wire sunrise/sunset icons
- [ ] Verify all icons render correctly in simulator (user check needed)

### Task 29: Wire Segment34 moon phases into view
- [x] Copy Segment34mkII moon.fnt/.png into `resources/fonts/`
- [x] Add font resource to `resources/fonts/fonts.xml`
- [x] Update `drawIconMoon()` to select from 8 phase glyphs (chars 0-7) based on `DataManager.moonPhase`
- [x] Map moonPhase (0.0–1.0) to 8 phases: 0=new, 1=wax crescent, 2=first quarter, 3=wax gibbous, 4=full, 5=wan gibbous, 6=last quarter, 7=wan crescent
- [x] Remove moon illumination % text (overlaps with moon icon at this size)
- [ ] Verify moon icon changes in simulator

### Task 29b: Swap bluetooth icon to Segment34 simple version
- [x] Copy Segment34mkII icons.fnt/.png into `resources/fonts/`
- [x] Add font resource to `resources/fonts/fonts.xml`
- [x] Update `drawIconBluetooth()` to use Segment34 char `L` (connected) instead of Crystal Face char `8`
- [ ] Optionally: show Segment34 char `M` (disconnected) when BT is off, or hide icon entirely (current behavior)
- [x] Verify bluetooth icon renders correctly in simulator
- Note: Segment34 has a simple bluetooth rune without background circle. Crystal Face's version had a filled circle background.
- Note: .fnt file needed fixes — original referenced `icons.png` (renamed to `seg34-icons.png`) and had incorrect `scaleW=246` (actual texture is 377px wide).

### Task 30: Implement wind direction (procedural polygon)
- [x] Implement `drawWindArrow(dc, x, y, degrees)` using `dc.fillPolygon()` — triangle with swallow tail
- [x] Calculate polygon vertices rotated to exact wind direction from `DataManager.windDeg`
- [x] Replace wind icon placeholder with procedural arrow
- [x] Verify arrow rotates correctly based on live OWM wind data in simulator
- [x] Don't draw arrow when no wind data — show nothing (text below shows "--")
- Note: Procedural approach works well. Arrow is 7px half-height, swallow-tail shape, rotated to exact OWM wind_deg. Segment34 fallback not needed.

### Task 30b: Wind arrow no-data default
- [x] When `windDeg` is null, don't draw any arrow (was defaulting to north which is misleading)
- [x] Verified: wind column shows only "--" text when no weather data

### Task 31: Umbrella icon (procedural, temporary)
- [x] Implemented procedural umbrella using `dc.fillCircle()` dome + line handle + hook
- [x] Replaced `[U]` text placeholder in precipitation column
- [x] Verified in simulator — functional but lower quality than font-based icons
- Note: Procedural umbrella is a stopgap. Task 31b will replace with a proper rasterized icon font glyph.

### Task 31b: Replace procedural umbrella with rasterized icon font glyph
**Goal**: Establish a repeatable rasterization pipeline and find the best fontbm settings for our icons.

**Step 1: Create TTF from SVGs**
- [ ] Use FontForge (CLI) to import Material Design SVGs into a single TTF
- [ ] Map: U=umbrella, H=tide-high, L=tide-low
- [ ] SVGs already in `/tmp/`: `mdi-umbrella-outline.svg`, `mdi-waves-arrow-up.svg`, `mdi-waves-arrow-down.svg`

**Step 2: Round 1 — Generate 9 variants using fontbm**
Test umbrella glyph across different settings. Output to `/tmp/raster-test/`.

| # | Size | AA | Spacing | Padding | Command notes |
|---|------|----|---------|---------|---------------|
| 1 | 17px | native | 1,1 | 0,0,0,0 | Crystal Face baseline |
| 2 | 17px | native | 0,0 | 0,0,0,0 | No spacing |
| 3 | 17px | native | 2,2 | 0,0,0,0 | Extra spacing for AA bleed |
| 4 | 17px | native | 1,1 | 1,1,1,1 | Padding to prevent AA clipping |
| 5 | 16px | native | 1,1 | 0,0,0,0 | Power-of-2 aligned |
| 6 | 15px | native | 1,1 | 0,0,0,0 | Smallest, matches FONT_XTINY |
| 7 | 17px | monochrome | 1,1 | 0,0,0,0 | No AA — sharp pixels |
| 8 | 34→17 | 2x+Mitchell | 2,2 | 0,0,0,0 | Gemini 2x supersample approach |
| 9 | 32→16 | 2x+Mitchell | 2,2 | 0,0,0,0 | Power-of-2 variant of Gemini |

- [ ] Generate all 9 variants
- [ ] Present PNGs to user for visual comparison
- [ ] User picks top 2-3 candidates

**Step 3: Round 2 — Fine-tune winners**
- [ ] Take the best 2-3 from Round 1
- [ ] Tweak spacing/padding/size by ±1px to find optimal
- [ ] Present refined PNGs to user for final pick

**Step 4: Wire winner into project**
- [ ] Copy winning .fnt/.png to `resources/fonts/`
- [ ] Register in `fonts.xml`
- [ ] Update `drawIconUmbrella()` to use font glyph
- [ ] Verify in simulator

### Task 32: Rasterize tide icons from Material Design SVG
- [ ] Use rasterization pipeline from Task 31b
- [ ] Rasterize `waves-arrow-up.svg` and `waves-arrow-down.svg` from Templarian/MaterialDesign-SVG (Apache 2.0, already in `/tmp/`)
- [ ] Add to font resources (can share .fnt/.png with umbrella or separate file)
- [ ] Wire into `drawIconTide()` and verify in simulator

### Task 33*: Add night weather condition variants (deferred)
- [ ]* Crystal Face weather-icons already includes night variants (a-h)
- [ ]* Update `owmToWeatherGlyph()` to check if current time is between sunset and sunrise
- [ ]* If nighttime, use night variant glyph (a-h) instead of day variant (A-I)

### Task 34: Validate tide time and height accuracy
- [ ] Force fresh StormGlass fetch and compare tide time against Surfline for same location
- [ ] Confirm timezone fix: `parseISOToUnix()` correctly converts UTC → unix timestamp using `System.getClockTime().timeZoneOffset`
- [ ] If times are still off by 1h, investigate whether `Gregorian.moment()` already accounts for DST or if double-correction is happening
- [ ] Compare tide height against Surfline (both use MLLW datum) — should be within ~0.3m for nearby stations
- [ ] Document any remaining discrepancies as known limitations (different tide stations/models produce different predictions)
- Note: StormGlass uses nearest tide station which may not match the exact spot Surfline uses. Time and height differences of 30-60min and 0.3-0.5m are normal between nearby stations.

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
