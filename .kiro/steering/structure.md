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
│       └── watch-face/    ← spec for the watch face feature
│           ├── requirements.md
│           ├── design.md
│           └── tasks.md
├── source/                ← all Monkey C source files (.mc)
│   ├── SurferWatchFaceApp.mc       ← app entry point, registers background, owns DataManager, receives onBackgroundData()
│   ├── SurferWatchFaceView.mc      ← main view, onUpdate() rendering
│   ├── SurferWatchFaceBackground.mc← background drawable
│   ├── SurferWatchFaceDelegate.mc  ← Background.ServiceDelegate, makes all HTTP requests
│   ├── DataManager.mc              ← singleton, holds cached data read by view
│   ├── WeatherService.mc           ← OWM HTTP request logic (called from ServiceDelegate)
│   └── TideService.mc              ← StormGlass HTTP request logic (called from ServiceDelegate)
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
- `SurferWatchFaceView` owns all rendering — single `onUpdate()` draws everything
- `DataManager` is a singleton accessed via `(Application.getApp() as SurferWatchFaceApp).getDataManager()`
- ALL HTTP requests run in `SurferWatchFaceDelegate` (Background.ServiceDelegate) via `onTemporalEvent()` — this is a hard platform requirement for watch faces
- Background fires at most every 5 minutes; refresh rate limits (OWM 30min, StormGlass daily) enforced via timestamps in `Application.Storage`
- Data flows: background → `Background.exit(data)` → `onBackgroundData(data)` → DataManager → `onUpdate()` renders
- All drawing uses absolute pixel coordinates based on the 176x176 grid
- Screen layout constants defined at top of `SurferWatchFaceView.mc` (e.g., `TOP_SECTION_Y = 10`)

## Spec-Driven Rules
- Never modify source files directly to change behavior — update the spec first
- `tasks.md` is the single source of truth for what has been built and what remains
- Each task maps to one or more acceptance criteria in `requirements.md`
- Placeholder values are used until a feature is fully implemented per its task

## Session Continuity
- Before ending any session, mark completed tasks `[x]` and in-progress tasks `[-]` in `tasks.md`
- At the start of a new session, read `tasks.md` to find the last completed task and resume from the next one
- The steering files (this file, `product.md`, `tech.md`) provide all context needed to resume without conversation history
