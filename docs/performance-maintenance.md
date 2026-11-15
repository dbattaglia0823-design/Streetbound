# Streetbound: performance and loading maintenance

This project uses Godot 4.4.1 and 4.6.3 in CI. Performance work must
preserve driving physics (60 Hz), predictable map streaming, accurate
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
