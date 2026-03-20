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
- [x] Layout tuned iteratively throughout icon implementation
- [x] All icons now rendered with real fonts — no text placeholders remain
- [x] Coordinates adjusted during each icon wiring task
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
- [x] Moon phase computed locally (synodic period), always available — defaults to new moon glyph if null
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

### Icons currently wired:
| Icon | Source | Font | Char | Status |
|------|--------|------|------|--------|
| Weather conditions (17) | Crystal Face weather-icons | WeatherIcons | A-I, a-h | ✅ Wired |
| Heart | Segment34mkII (outline) | Seg34Icons | h | ✅ Wired |
| Bluetooth | Segment34mkII | Seg34Icons | L | ✅ Wired |
| Notifications | Crystal Face crystal-icons | CrystalIcons | 5 | ✅ Wired |
| Sunrise/Sunset | Crystal Face crystal-icons | CrystalIcons | > / ? | ✅ Wired |
| Moon phases (8) | Segment34mkII | MoonIcons | 0-7 | ✅ Wired |
| Wind direction | Procedural `dc.fillPolygon()` | — | — | ✅ Wired |
| Umbrella | MDI webfont (rasterized) | SurferIcons | U (85) | ✅ Wired |
| Tide high | MDI waves-arrow-up (rasterized) | SurferIcons | H (72) | ✅ Wired |
| Tide low | MDI wave-arrow-down (rasterized) | SurferIcons | L (76) | ✅ Wired |
| Battery | Code-drawn fill bar | — | — | ✅ Wired |

### Icons with no remaining placeholders — all icons are now real.

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
- [x] Verify all icons render correctly in simulator

### Task 29: Wire Segment34 moon phases into view
- [x] Copy Segment34mkII moon.fnt/.png into `resources/fonts/`
- [x] Add font resource to `resources/fonts/fonts.xml`
- [x] Update `drawIconMoon()` to select from 8 phase glyphs (chars 0-7) based on `DataManager.moonPhase`
- [x] Map moonPhase (0.0–1.0) to 8 phases: 0=new, 1=wax crescent, 2=first quarter, 3=wax gibbous, 4=full, 5=wan gibbous, 6=last quarter, 7=wan crescent
- [x] Remove moon illumination % text (overlaps with moon icon at this size)
- [x] Verify moon icon changes in simulator

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
- [x] Established rasterization pipeline: fontbm 17px AA → ImageMagick alpha extract → 8-bit grayscale
- [x] Tested 9 variants (sizes 14-20px, AA/mono, spacing/padding combos) on simulator
- [x] Key finding: PNG must be 8-bit grayscale with `alphaChnl=1` to match Crystal Face format
- [x] Key finding: RGBA output causes bold/fat lines — Garmin renderer misinterprets channels
- [x] Rasterized umbrella-outline from MDI webfont TTF (F054B → char U=85)
- [x] Wired into `drawIconUmbrella()` using surferIconsFont
- [x] Verified in simulator
- Note: Pipeline documented in design §5.1. Reusable for any future icon rasterization.

### Task 32: Wire tide icons from MDI webfont
- [x] Rasterize `waves-arrow-up` (F185B, 2 waves + 2 arrows) for high tide using proven pipeline
- [x] Rasterize `wave-arrow-down` (F1CB0, 1 wave + 1 arrow) for low tide
- [x] Add both to surfer-icons.fnt/.png (H=72 high, L=76 low)
- [x] Update `drawIconTide()` to use surferIconsFont
- [x] Verify in simulator
- Note: MDI has no `waves-arrow-down` (plural). Using mismatched pair intentionally — 2 waves for high tide (more water), 1 wave for low tide (less water) — works as visual metaphor.

### Task 32b: Implement code-drawn battery icon
- [x] Replace `[=]` text placeholder with code-drawn battery: outline rectangle (18x10) + fill bar proportional to % + terminal nub
- [x] `drawIconBattery(dc, x, y)` takes position params — moveable unit, replaceable with font icon later
- [x] Tuned size to match other icons (18x10 body + 2x4 terminal)
- [x] Verified in simulator

### Task 33*: Add night weather condition variants
- [x] Crystal Face weather-icons already includes night variants (a-h) — no rasterization needed
- [x] Update `owmToWeatherGlyph()` to accept `isNight` flag
- [x] Check if current time is before sunrise or after sunset to determine night
- [x] Night mapping: clear→f, cloudy→h, thunderstorm→e, showers→c, rain→b, snow→d, fog→h, overcast/tornado→same
- [ ] Verify night icons render correctly in simulator

### Task 34: Validate tide time and height accuracy
- [x] Investigated StormGlass datum — switched to MLLW to match Surfline
- [x] Investigated timezone parsing — Garmin forum confirmed `Gregorian.moment()` interprets input as UTC, original code was correct
- [x] Compared tide times/heights against Surfline for nearby stations — values are in expected range
- [x] Documented: different stations/models produce 30-60min time and 0.3-0.5m height differences (normal)
- Note: Reverted timezone adjustment that was introducing error. Original `parseISOToUnix()` was correct all along.

---

## Phase 7 — Polish & Sideload

### Task 38: Implement seconds reveal on wrist gesture
- [x] Track sleep state via `onEnterSleep()` / `onExitSleep()` callbacks
- [x] Show seconds only when awake (wrist raise gesture active)
- [x] Hide seconds when sleeping (wrist at rest) to save battery
- [x] Removed ShowSeconds settings property — behavior is automatic via gesture
- [x] Fixed weather icon defaulting to sunny when no data — now hides icon entirely
- Satisfies: requirements §4.2

### Task 39: Pixel-tune full layout with real icons
- [x] All icons rendered with real fonts — no text placeholders remain
- [x] Layout coordinates tuned iteratively throughout development
- [x] Bluetooth moved to notification row (row 2, left side)
- [x] Date format: uppercase month, centered
- [x] Custom clock font (Saira Condensed Bold 40px default, Rajdhani Bold 40px alternative)
- [x] Code cleanup: removed unused constants, optimized getApp()/getDataManager() calls
- Satisfies: design §1.1, §1.2

### Task 42: Add stress arc indicator to HR circle
- [x] Read stress via `SensorHistory.getStressHistory({:period=>1})` — returns 0-100, available since API 3.3
- [x] Add `stress` field to DataManager, update in `updateSensorData()`
- [x] Confirmed sub-screen geometry: center=(144,31), radius=31 (from simulator.json, Y tuned)
- [x] Draw arc around HR circle using `dc.setPenWidth()` + `dc.drawArc()`
- [x] Arc spans from 2 o'clock (60°) to 10 o'clock (120°) = 300° total, going clockwise through the bottom
- [x] Frame: 1px black border on inner and outer edge, end caps at start/end
- [x] At 0% stress: arc frame visible, fill is white (blends with circle)
- [x] At 100% stress: arc fill is black (filled clockwise from 2 o'clock to 10 o'clock)
- [x] When stress data unavailable (null): show as 0% (fully white arc)
- [x] Arc is always visible (not gated by sleep state)
- [x] Refactored into `drawStressArc()`, `drawHrHeart()`, `drawHrText()` with tweakable position constants
- [x] Wired to real stress data from DataManager
- Note: Heart at (144,14), BPM text at (144,34), arc width 6px. Positions are `private static const` for easy tuning.
- Note: Arc angles adjusted to 2:30 (45°) to 9:30 (135°) = 270° to clear filled heart icon.
- Note: Arc borders 2px thick, end caps adjusted (capInnerR+1) to prevent inward overflow.

### Task 43b: Fix weather, moon, heart, wind bugs from real-watch testing
- [x] Weather: replaced Crystal Face 17-glyph set with full Erik Flowers 29-glyph set (fontbm 17px, 256x256 texture)
- [x] Weather: full OWM mapping with day (A-V) and night (a-g) variants — now has pure rain, thunderstorm, fog, etc.
- [x] Moon: replaced Segment34 8-phase with Erik Flowers 28-phase at 24px, Math.round() instead of truncate
- [x] Heart: replaced Segment34 outline with Garmin Connect Icons outline at 27px (tested 18-30px, 27px won)
- [x] Wind: negated rotation angle to fix clockwise/counter-clockwise mirror
- [x] Stress arc: 2px borders, end cap inner radius +1 to prevent overflow
- Key finding: Instinct 2X max font texture size is 256x256 — 512x512 causes garbled rendering
- Key finding: BMFont via Wine doesn't support negative fontSize (Wine GDI limitation) — fontbm direct is our pipeline
- Key finding: Downscale methods (2x render → shift → downscale) add too much AA noise vs fontbm direct

### Task 44: Tune wind arrow rendering
- [x] Extracted arrow params as constants: WIND_ARROW_SIZE, WIND_ARROW_WIDTH, WIND_ARROW_NOTCH, WIND_ARROW_Y_OFFSET
- [x] Tuned to size=9, width=0.8, notch=0.5 (bigger, wider, shallower tail than original 7/0.6/0.4)
- [x] Fixed comments to accurately describe what each constant controls

### Task 43: Experiment with clock fonts
- [x] Researched and tested: Bebas Neue, Barlow Condensed Bold, Rajdhani Bold, Saira Condensed Bold, Oswald
- [x] Rasterized at 40px using proven pipeline — matched FONT_NUMBER_HOT height
- [x] Compared all on watch face via screenshots
- [x] Finalists: Saira Condensed Bold (best fit, minimal layout change) and Rajdhani Bold (most stylish, needs layout tweaks)
- [x] Wired Saira as default clock font, Rajdhani as alternative
- [x] Added `ClockFont` setting (list: 0=Saira, 1=Rajdhani) to swap via Garmin Connect app
- [x] Date format: month now uppercase (e.g., "Wed MAR 19")
- [x] Code cleanup: removed all unused icon placeholder constants, optimized `getApp()`/`getDataManager()` to single call in `onUpdate()` passed to all section methods
- Note: Font TTFs from Google Fonts (SIL OFL). Rasterized at 40px to match HOT digit height.

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
