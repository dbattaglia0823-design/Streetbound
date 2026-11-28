# Streetbound: performance and loading maintenance

This project uses Godot 4.4.1 and 4.6.3 in CI. Performance work must
preserve driving physics (120 Hz), predictable map streaming, accurate
vehicle assets, and deterministic navigation.

## Existing budgets and safeguards

- Morrow Coast streams at most one new gameplay chunk per render frame
  (`scripts/world/morrow_coast.gd`); map mirrors stream a few per frame.
  Do not turn these into synchronous neighborhood-wide builds.
- The driving minimap has its own 244x244 SubViewport. It stops GPU
  updates when hidden by the atlas, pause menu or tuning UI.
- The high-resolution 960x880 pause map is allocated on the *first*
  pause, and is disabled on resume or when another menu is shown.
- The garage builds owned vehicle cards on demand and reuses those cards
  until its inventory changes. The proving ground still allows all cars.
- The pause Cars browser initially creates up to 18 rows; further rows
  append near the bottom of scrolling or when the player selects Show More.
  Search and price sorting always query the complete catalog.
- Menu car images load lazily in bounded per-frame batches. Keep image
  decoding and GPU readback outside hot gameplay loops.

## Validation procedure

1. Compare cold-import startup, warm startup, first pause, second pause,
   first garage open, and first Cars-tab open *separately*. Record median
   times and p95 frame time across repeated runs on target Windows hardware.
2. In Godot Debugger > Profiler and Monitors, check frame time, physics
   frame time, draw calls, object/node count, texture memory, and spikes.
   Use Streetbound's F7 world diagnostic panel for streamed chunk timings
   and runtime rendering counters.
3. Run `tests/game_startup_smoke_test.gd`,
   `tests/pause_dashboard_layout_test.gd`,
   `tests/player_vehicle_roster_test.gd`,
   `tests/drive_in_garage_test.gd`,
   `tests/circular_minimap_mask_test.gd`, and the full GitHub CI.
4. Recheck performance when adding lots of new car images, animated
   scenery, traffic vehicles, race event cards, or menu transitions.
   Prefer capped batches, visibility-based updates, pooled short-lived
   effects, and one source of truth for catalog data. Add an allocation
   regression for each new large menu.
5. Do not lower the physics tick rate or simplify collision precision
   without physics regression tests and actual profiling evidence.
   Do not offload SceneTree mutation to worker threads.

## Official Godot references

- General optimization and measurement:
  https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html
- CPU and SceneTree node costs:
  https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html
- SubViewport update modes:
  https://docs.godotengine.org/en/stable/classes/class_subviewport.html
- Background resources (never call threaded_get before LOAD_LOADED):
  https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html
- Low-level Servers (only after profiling demonstrates a bottleneck):
  https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html


## Six-phase gameplay performance pass

- **Startup:** The title no longer directly preloads the full gameplay script. Clicking Play launches a worker to read, SHA-256 hash and parse the selected archive, audit it and perform the existing road width, bridge and mountain data preparation. The game scene is requested through ResourceLoader's threaded API. The title displays preparation stages and elapsed time. Only a matching path and byte hash can consume the prepared data once; direct scene launches, mismatches and published fallbacks retain the original synchronous path. SceneTree creation, texture uploads, traffic network construction and remaining gameplay initialization still run on the main thread. In-game debug Map Builder keeps its lightweight entry point but defers interface construction, source loading and asset scans until opened. No persistent geometry cache is introduced.
- **Streaming:** Speed-dependent lookahead is bounded to the existing dormant ring. Optional speculative builds respect frame time; required collision-bearing chunks are never delayed by this optimization. Cursor Test Drive builds the actual spawn cell before adding the vehicle. Existing cache radius and 120 Hz physics are unchanged.
- **Traffic:** Reuse identical route lookahead samples for every candidate vehicle and cache player/racer group membership only during each physics tick. The optional optimized AI setting extends already-cached obstruction scans from 100/120 ms to 160/180 ms only for remote invisible agents outside race, recovery and nearby human/racer conditions. Braking, lane integration, crossing priority and collisions still update at the original physics rate. No vehicle pooling or reduced player/race simulation tick rate.
- **Rendering:** Stop hidden map view and overlay processing, with an optional minimap refresh cap. Share base textures across sprite regions, deduplicate wet-road reflection vehicles, and clear stale wet reflections when rain stops. Defaults preserve full scenery shadows, full rain density and every-frame minimap rendering. Instanced vegetation, generalized geometry batching and particle pooling remain profiling-driven follow-up work.
- **Settings:** Settings > Graphics offers high-quality, balanced and performance presets plus FPS cap, vsync, minimap refresh, solo ambient density, rain visuals, scenery shadows, adaptive streaming, optimized remote AI and the F7 overlay. Presets are opt-in; race density and online density remain unaffected. No render-resolution scaler is introduced. Settings are saved with the existing pause settings store.
- **Diagnostics and benchmark:** F7 reports wall-clock startup stages, 95th-percentile frame time and slowest-1%-mean FPS over a bounded 1,200-frame sample. `tests/game_performance_benchmark.gd` records first/repeat startup, initial neighborhood and wet throttle workload, first/repeat pause, peak draw calls/texture memory and chunk counters. Run `godot --path . --script res://tests/game_performance_benchmark.gd` in an isolated test profile using a real display for FPS; the manual regression workflow also produces a headless report for CPU/load comparisons. Headless fixed-fps throughput is not hardware gameplay FPS. First-in-process startup is not a guaranteed cold disk cache. No absolute timing threshold is imposed on shared runners. Existing startup/title/settings tests cover the new contracts. Sustained high-speed, dense-city, nighttime, police and race workload baselines still require profiling and repeatable scenario fixtures. CI, GPU visual confirmation and target hardware comparisons are pending.
