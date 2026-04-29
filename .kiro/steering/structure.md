# Project Structure

## Directory Layout
```
surfer-watch-face-instinct-2x-solar/
├── .kiro/
│   ├── steering/          ← persistent project context (always read by Kiro)
│   │   ├── product.md
│   │   ├── tech.md
│   │   └── structure.md
│   └── specs/
│       ├── watch-face/    ← spec for the shore mode watch face feature
│       │   ├── requirements.md
│       │   ├── design.md
│       │   └── tasks.md
│       └── surf-mode/     ← spec for the surf mode feature
│           ├── requirements.md
│           ├── design.md
│           └── tasks.md
├── source/                ← all Monkey C source files (.mc)
│   ├── SurferWatchFaceApp.mc       ← app entry point, thin shell: registers background, writes Storage flags, NO DataManager references
│   ├── SurferWatchFaceView.mc      ← main view, owns DataManager, onUpdate() rendering + Storage flag handling
│   ├── SurferWatchFaceBackground.mc← background drawable
│   ├── SurferWatchFaceDelegate.mc  ← Background.ServiceDelegate, makes all HTTP requests, reads GPS/BT directly from OS
│   ├── DataManager.mc              ← business logic: holds cached data, processes background flags, computes sunrise/sunset/moon
│   ├── WeatherService.mc           ← OWM HTTP request logic (called from ServiceDelegate)
│   ├── OpenMeteoService.mc         ← Open-Meteo API calls: swell, weather, surf wind
│   └── TideService.mc              ← StormGlass tide HTTP request logic (called from ServiceDelegate)
├── resources/
│   ├── drawables/         ← bitmap icons (.bmp, 1-bit monochrome)
│   ├── layouts/           ← (unused — rendering is code-driven)
│   ├── settings/          ← properties.xml (API keys, user prefs)
│   └── strings/           ← strings.xml (app name)
├── manifest.xml           ← app metadata, target device, permissions
└── monkey.jungle          ← build config
```

## Naming Conventions
- Files: PascalCase matching the class they contain
- Classes: PascalCase
- Functions: camelCase
- Variables: camelCase
- Constants: UPPER_SNAKE_CASE
- Resource IDs: camelCase in XML

## Key Architectural Decisions
- `SurferWatchFaceView` owns all rendering AND DataManager — single `onUpdate()` draws everything
- DataManager is created via lazy init on the first `onUpdate()` tick (not in `onLayout()` — font loading uses too much stack)
- App class (`SurferWatchFaceApp`) has ZERO references to DataManager — Crystal Face pattern
- App writes to `Application.Storage` flags on background events and settings changes; View reads flags in `onUpdate()`
- ALL HTTP requests run in `SurferWatchFaceDelegate` (Background.ServiceDelegate) via `onTemporalEvent()` — this is a hard platform requirement for watch faces
- Background delegate reads GPS directly via `Position.getInfo()` and BT via `System.getDeviceSettings()` — no Storage relay needed
- Background fires at most every 5 minutes; refresh rate limits (OWM 5min, StormGlass daily) enforced via timestamps in `Application.Storage`
- Data flows: background → `Background.exit(data)` → `onBackgroundData(data)` → Storage flags → View `onUpdate()` → DataManager → renders
- GPS is read event-driven (on background events and init), not per-tick
- Sunrise/sunset: API-provided for OWM/Open-Meteo, computed locally (SunCalc algorithm) for Garmin mode only
- Moon phase computed on background events and settings changes, not per-tick
- Single clock font loaded at a time; live reload on settings change
- All Storage keys use 2-3 char short names (full reference in DataManager.mc comment block)
- Storage version gating: on startup, View checks `"av"` key and calls `clearValues()` on mismatch to prevent stale key bloat
- All drawing uses absolute pixel coordinates based on the 176x176 grid
- Screen layout constants defined at top of `SurferWatchFaceView.mc`

## Spec-Driven Rules
- Never modify source files directly to change behavior — update the spec first
- `tasks.md` is the single source of truth for what has been built and what remains
- Each task maps to one or more acceptance criteria in `requirements.md`
- Placeholder values are used until a feature is fully implemented per its task
- Any change to features, behavior, data sources, refresh rates, or user-facing functionality must also update `README.md` to keep user documentation in sync

## Release Checklist (for every user-facing change)
After any code change that affects behavior or visuals:
1. Update spec files (requirements.md, design.md, tasks.md) to reflect the change
2. Update `README.md` (features, user guide, data refresh table, etc.)
3. Update `store-description.txt` if the change affects the store listing
4. Regenerate `screenshot.png` (user takes new simulator screenshot)
5. Regenerate `screenshot-annotated.png` (run `annotate.py` with the new screenshot)
6. Regenerate `store-cover.png` (run `generate-cover.py` with the new screenshot)
7. Add entry to `CHANGELOG.md` describing the change
8. Build new `.iq` package via `Monkey C: Export Project`
9. Upload to Connect IQ developer dashboard (new package + updated assets if visuals changed)

## Session Continuity
- Before ending any session, mark completed tasks `[x]` and in-progress tasks `[-]` in `tasks.md`
- At the start of a new session, read `tasks.md` to find the last completed task and resume from the next one
- The steering files (this file, `product.md`, `tech.md`) provide all context needed to resume without conversation history
