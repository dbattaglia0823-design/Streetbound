---
name: racing-ai-audit
description: Use to inspect race or traffic AI path-following, overtaking, obstacle avoidance, stuck handling and vehicle control in driving games.
---

# Racing / traffic AI audit

1. Map the **existing** path representation (waypoints, splines, lane graph, or custom), physics controller, steering logic and race/traffic state. Do not guess filenames.
2. Distinguish high-level route/lane decisions from local obstacle avoidance and low-level throttle, brake and steering.
3. Instrument deterministic cases: straight, sharp curve, lane merge, blocked lane, leading vehicle braking, passing, start/finish and rejoining the route.
4. Check physics units, simulation tick, velocity/acceleration, turn radius, lookahead and curvature-aware target speed.
5. Validate path continuity, progress monotonicity, waypoint handoff, stuck recovery, off-road mistakes and unintended reversals.
6. Check closing speed, safe following/avoidance distance, corner grip and braking; avoid frame-dependent cooldowns and sudden route-target jumps.
7. Add focused tests; compare before/after traces at representative frame rates and verify gameplay on target device when possible.
8. Keep game-specific physics, tuning and AI code in its own repository. Promote only evidenced general lessons into the shared knowledge vault.

Do not replace an entire driving model merely to fix an isolated route bug.
