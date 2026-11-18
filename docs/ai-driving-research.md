# Streetbound AI driving: audit and research notes (November 2026)

## Existing architecture — keep it

- **Street and traffic routes:** `road_route_planner.gd` uses shortest legal directed traffic-lane connections, while `traffic_flow.gd` keeps ambient cars on road and junction geometry with physical collisions, stopping/yielding, player sensing, and offscreen stuck recovery.
- **Race geometry:** `race_line_builder.gd` keeps street opponents in asphalt-bounded lanes and gives circuits wider apex options.
- **Speed profile:** `race_navigation.gd` samples local curvature, derives limits from tire/surface grip, and back-propagates available braking distance.
- **Controls:** `race_ai_driver.gd` outputs normal throttle/brake/steer commands to `VehicleController2D`, with no AI-only engine, grip, or velocity boosts.
- **Passing:** `race_traffic_overtaking.gd` scans actual ambient bodies and racers, predicts crossing traffic, checks lateral corridor occupancy/pavement, and caps speed if a pass is unsafe.

## This pass

The race controller's global nearest-route projection could choose the wrong branch of a figure-eight or crossing road, ignoring its already-tracked last station. Its `_point_at` function linearly searched the full route for every lookahead sample. The companion PR changes those to progress-aware projection with off-route fallback and binary waypoint sampling. No changes to AI grip, horsepower, tire physics, or racing payouts.

## External references and practical fit

1. **F1TENTH Planning / Pure Pursuit / Stanley**  
   https://f1tenth-planning.readthedocs.io/en/latest/control/pure_pursuit.html  
   https://github.com/f1tenth/f1tenth_planning  
   Reference algorithms for speed-dependent steering lookahead, curvature-aware speed limits and alternative tracking controllers. Best used to design an **A/B test** against Streetbound's existing heading-error steering, not copied wholesale. Existing `race_navigation.gd` already models a braking speed envelope.

2. **Raceline Studio (MIT licensed)**  
   https://github.com/a2ngerer/raceline-studio  
   Editor for minimum-curvature/minimum-time racelines and physics-limited speed profiles with CSV exports. A promising **offline tool for closed circuits**. It accepts ROS occupancy maps (`map.yaml` + image), so Streetbound would need an export/coordinate conversion layer. Its optimised lines should never be applied unchanged to city streets: our directed lanes, junction rules and pavement clearance remain authoritative.

3. **OpenStreetMap Racer, Godot 4**  
   https://github.com/egore/openstreetmap-racer  
   Similar road-graph traffic architecture: rolling multisegment road commitments, body-position projection onto paths, lookahead pursuit, lane offset and near/far detail policies. Useful ideas for Streetbound's ambient-traffic performance and junction stability; it is a **3D project**, not a ready-to-use Streetbound 2D replacement.

4. **Godot NavigationAgent2D / RVO**  
   https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html  
   Provides generic navigation and local reciprocal-velocity avoidance. This is a good research path for future **pedestrians/roaming non-vehicle agents**, but a safe velocity alone does not account for a car's steering angle, tire grip and braking distance. Keep Streetbound's directed vehicle route graph and real vehicle controller for racing.

5. **Godot Steering AI Framework**  
   https://github.com/GDQuest/godot-steering-ai-framework  
   Seek/arrive/pursue/follow/avoid building blocks; useful educational reference for blended behaviors. Its older Godot APIs require compatibility review before adopting into Godot 4.6.3.

## Next safe experiments (do not turn on by default)

1. Add deterministic driving telemetry: route cross-track error (RMS/max), successful route/finish rate, lap time, collisions, offroad time, wheelspin, repeated steering reversals, time blocked by traffic, and per-frame AI CPU budget. Test city sprint, authored circuit, drag, overlapping/intersecting roads, and collision recovery across low/medium/high grip and different vehicle sizes.
2. With the same scenario seeds, compare the existing controller against speed-dependent Pure Pursuit steering and a Stanley-style cross-track correction. Preserve all physical vehicle limits, braking envelope, and difficulty settings; adopt only if finish rate and collisions improve without worse corner cutting.
3. Improve traffic overtaking conservatively with time-to-collision, closing-speed-dependent acceptance gaps, continuity of chosen passing side, and safe exit back to the legal racing line. Test oncoming traffic, crossing vehicles, player alongside and short/curved pavement corridors.
4. Investigate coarse/fine route sampling and route-segment caches if profiler shows `_nearest_station`, `station_at`, or surface checks dominate frame time. Do not pre-optimize at the cost of recovering from actual collisions.
5. If adding offline optimised circuit lines, validate `surface_at()` across car width and test whole laps before accepting new geometry.

## Key acceptance rule

Racing AI must finish legal routes while remaining competitive using the **same car physics** as the player. Faster laps obtained by teleporting, boosting power/grip, ignoring collisions, or cutting across undriveable terrain are regressions.
