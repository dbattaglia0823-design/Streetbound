# Driving-only racing and crime: implementation roadmap

Streetbound is a **driving-first** open-world racing/crime game. There is no
player-controlled on-foot movement or combat. Police may win only by physically
containing the car for a verified duration or disabling the vehicle. Reset
during a wanted pursuit is a bust, not a teleport escape.

## First vertical slice: experimental single-player pursuit

- A reusable per-vehicle integrity model responds to actual
  `VehicleController2D.crash_contact` signals. Light contacts and repeated
  contacts within a 0.25-second impact window do not stack damage.
- Engine power stays **100% through 20% integrity**. Below 20% health,
  drive force declines smoothly by at most 20% while the engine can still
  run; at exactly 0% the engine is disabled. Tire friction, braking, catalog
  specs, and the established 120 Hz driving model are unaffected.
- Bounded grey smoke begins at damaged hood condition (below 60%), increases
  gradually as integrity falls, stays in world space as the car moves, and
  dissipates after repair. It uses actual selected vehicle visual bounds,
  adds no new particle textures, and is not on-foot gameplay.
- Vehicle integrity and fuel are tracked per equipped car and persisted in a
  separate resources save. A position reset **does not** refill or repair it.
- Park at a garage, including authored garage markers, and press **K** to
  restore **100% condition for free**, even when the balance is $0.
- At an authored gas station (`fuel` marker), press **K** to repair only up to
  **50% condition** for a small fee ($25 base + $4 per restored point).
  Cars already above 50% receive no repair from the gas station.
- Gas stations also sell fuel/EV charging: press **J** while parked, or use
  the station's **F** interaction. Fuel consumption scales with movement
  and throttle and is independent of nitrous; an empty tank disables drive
  power but retains steering and braking.
- The top-right HUD displays small original vector engine and fuel icons,
  each with a circular condition ring and low/critical colors.
- If the car is disabled or out of fuel outside a police chase, **K** offers
  a capped-price emergency tow to the starting area, with at least 35% engine
  integrity and 8% fuel. It never gives full repair/refill. Police impounds
  use the same low-condition recovery, so garage repairs remain meaningful.
- Starting a street race triggers the first single-player pursuit prototype.
  **F7** also starts a test pursuit in debug builds.
- Police use actual vehicle bodies and the current directional road route
  planner plus the existing physically constrained AI racing driver; no
  acceleration cheats, scripted instant capture or teleport pursuit.
- A three-cruiser containment pattern must surround a nearly stationary
  driver trying to escape for four seconds before a bust is allowed.
- A disabled car while wanted, or resetting during a chase, also causes a
  busted result. Busts recover the vehicle and charge an affordable impound
  fine. Escapes occur after prolonged loss of police contact.
- The new prototype is disabled for multiplayer, split-screen driving and
  custom test drives to avoid partially synchronized damage and rewards.

## Vehicle-only driving contracts — first playable framework

- The World Builder can author `contract` pickup markers and
  `contract_dropoff` destinations. Configure the contract kind and link a
  destination via the native marker editor; the browser editor accepts the
  same fields in marker JSON (`contract_kind`, `destination_marker_id`).
- Three initial mission types: **courier** (legal $550), **smuggling**
  (wanted 1, $950) and **getaway** (wanted 2, $1,350). Other XP and underground
  reputation rewards come from fixed game rules, never arbitrary map values.
- To create a job, place a dropoff on an accessible road, then place a
  contract pickup at least 100 metres away. Select the dropoff in the
  contract marker editor. Jobs require a connected road route and are not
  automatically populated at nonexistent buildings.
- While parked at the job marker, press **F** to accept. Navigate to the
  destination and stop within 12 metres before the timer expires. Police
  jobs require evading the pursuit before payout.
- Box-in arrests, vehicle resets, vehicle changes, disabling the engine
  or running out of fuel, race participation, and expired timers cancel the
  contract without payment. Jobs can also be abandoned from the HUD.
- Completed jobs award cash and driver/car XP through the existing
  ownership save, with persistent one-time run claims, event completion
  counts, and underground reputation. Duplicate run tokens never pay twice.
- These are **single-player, map-authored activities**. The current
  bundled map is not automatically given new contract markers, and store
  robberies/advanced criminal missions are not yet implemented. The
  existing race, garage, gas station and vehicle damage systems are kept.
- Before merging, validate Godot import, contract reward/authoring tests,
  and in-game pickup, arrival, pursuit loss, box-in and dropoff UX.

## Contract givers and robbery jobs — first authoring implementation

- Add `contract_contact` in the map builder for a visible roadside person.
  Each character can offer **up to 8 configurable jobs**. The contact is
  visible in-world and on the minimap/pause map, which also supports waypoint
  routing to the contact. Interactions occur through the stationary vehicle
  by pressing **F**; the player never moves on foot.
- Place a `contract_dropoff` marker for the escape/delivery destination.
  For robberies, add a separate `robbery_target` marker at the store,
  bank, warehouse or other building and at least 100 metres from the
  contact and the dropoff. Both legs need drivable road navigation.
- Configure jobs in the native map builder's **Edit Selected Marker** panel
  or the browser map editor's **Contract Giver — Mission Configuration**
  inspector. The job editor supports title, kind (courier, smuggling,
  getaway or robbery), difficulty, target, destination, wanted level,
  timer, driver/car XP, cash, underground reputation, repeatability,
  minimum driver level and minimum criminal reputation.
- Each contract has a stable ID. On the map, selecting the person opens a
  vehicle-only contract board showing the available options, their
  payouts and locked requirements.
- **Robbery loop:** accept a job from the person, drive to the specified
  building, stop and wait in the car for the off-screen crew for 7 seconds,
  then escape an actual police pursuit and reach the configured dropoff
  while stopped. Arrest, engine failure, expired timer, resetting or
  abandoning the vehicle contract cancels its payout.
- Author-defined cash, XP, reputation and heat are strictly bounded, and
  the economy verifies the bounds again before paying. Saved one-time
  jobs cannot pay repeatedly, while repeatable contracts record run
  counts and anti-duplicate tokens. Older single-job `contract` markers
  remain valid.
- No generic person AI, weapons, pedestrian controls or accessible
  interiors have been added. Contact artwork is an original lightweight
  overhead marker and does not block collision or traffic.
- The new features are on the draft PR until the complete CI and
  in-game route/interaction/escape playtests pass.

## Dedicated contact screen — in-game job selection

- Press **F** at a stationary roadside contract contact to open a separate
  responsive, full-screen **Contract Contact** screen. It replaces the generic
  map-marker/fast-travel popup for contacts while leaving the existing
  fast-travel menu unchanged. Press **Escape** or Close to return to driving.
- The contact screen shows their authored name, role, biography and greeting
  alongside an original portrait monogram. Four default personalities
  (**street fixer**, **contract broker**, **garage connection**, **local insider**)
  have distinct accents, greetings and dialogue. Map creators may override the
  role, greeting and biography for individually named contacts.
- The left column lists each available job with its type, difficulty and
  progress status. The selected right-hand briefing gives a mission description,
  cash, driver/car XP, criminal reputation, wanted level, timer, required
  driver level and underground reputation, and repeatability.
- Completion indicators come from the existing persistent
  `completed_driving_contracts` save, keyed by the world, contact and stable
  offer ID. One-time finished jobs appear **COMPLETED** and cannot be accepted;
  repeatable jobs show **N COMPLETE** and remain available; unmet progression
  requirements show **LOCKED**.
- The map builder (native and browser) now has fields for contact role,
  greeting, biography and each contract's mission briefing. Empty fields
  keep the built-in personality/briefing defaults, ensuring older maps and
  saves display correctly. Text sizes are validated on import.
- The board consumes the existing contract runtime and economy API; it
  never calculates or pays rewards itself. Successful acceptance closes
  the board and releases world pause. Failed acceptance shows an error
  without discarding the selected contract.
- Validate `tests/contact_contract_screen_test.gd` plus the
  browser `contract-contacts.test.mjs` round-trip tests before merging.
  Verify mouse, keyboard, viewport scaling and contact-specific layouts
  visually in a real driving session.

## Map Builder usability — contract & race authoring

- **Native contact editor:** Identity and dialogue now have their own tab,
  separate from contract configuration. Job tabs expose a list of up to eight
  contracts, safe *new/duplicate/delete/reorder* commands, a difficulty preset,
  mission objectives, rewards, wanted level and progression requirements.
  Duplicating a job issues a fresh stable ID (it never reuses the original
  completion history); changing a title or order preserves existing job IDs.
- **Browser contact editor:** displays a live mission summary, descriptive
  marker-link validation messages, job count, duplicate and ordering controls,
  difficulty presets, arrival tolerance and crew wait controls. Invalid
  destination links are surfaced before export; the full world schema
  remains authoritative on save/import.
- **Gameplay customization:** the robbery crew wait defaults to 7 seconds but
  can be authored between **3–30 seconds**. A job's delivery/robbery stop
  radius defaults to 12 m and can be set to **6–30 m**. The mission runtime
  actually honors these settings, and both native Godot and browser world
  validation enforce the same bounds. Older maps keep their old defaults.
- **Browser race editor:** an always-accessible collapsible *Races & Events*
  panel edits existing races' name, category, difficulty, laps (circuits),
  time limit, checkpoint/start radii, solo cash/driver/car XP, first-win
  cash/driver/car XP, required driver/car level, repeatability and
  prerequisite event links. All changes pass the existing world normalization
  rules; cyclic/missing prerequisites and out-of-bounds rewards are rejected.
  Race IDs, route checkpoints, starting grids and opponent pools are retained.
- **Native race editor:** already provides a mature tabbed race form
  (race settings, enemy vehicles, career progression and multiplayer
  payouts). It remains the preferred tool for designing new routes and
  arranging race-specific starting grids.
- Testing: `node --test map-editor/tests/*.test.mjs` includes the new
  `event-authoring.test.mjs` and `tests/driving_contracts_test.gd`
  exercises native job duplication/reordering, schema and mission knobs.
  Do not merge without latest-head Godot and browser test results.

## Wanted-level police pursuit intelligence — driving-only

- **Responsive rather than numerous:** Wanted level 1 deploys **one** cruiser,
  level 2 **two**, level 3 **three**, and levels 4–5 at most **four**. There
  are no endless scripted reinforcements or proximity-based vehicle respawns.
- **Off-screen, non-ambush spawns:** dispatch selects open asphalt lanes
  **125–245 metres** from the player, behind or well to the side of their
  actual movement direction. It rejects occupied locations, camera-visible
  positions and candidates within 45 metres of another responder. Police
  never materialize directly in the predicted forward travel corridor. If no
  safe lane exists, dispatch keeps the wanted alert and retries every three
  seconds for up to 18 seconds rather than spawning an ambush or failing a
  robbery; the alert expires if there is still no safe response route.
- **Physically realistic difficulty:** all cruisers use the existing
  `VehicleController2D` and shared route driver. Increased wanted tiers
  modestly increase throttle requests, ordinary speed targets, vision range
  and search persistence, with no RPM/HP/grip/top-speed multipliers,
  snap-turning, rubber-banding, teleports or arbitrarily short stopping
  distances.
- **Coordinated tactics:** responders have pursuer/interceptor/flank roles.
  Interceptors extrapolate the most recently **visible** suspect velocity
  for at most a couple seconds, never consult the player's chosen GPS target.
  At wanted 3+, nearby officers slow down and drive toward three
  120°-spaced containment positions. Arrest still requires real police
  vehicles within 8 metres surrounding a nearly stationary car for four
  continuous seconds. The target positions alone are never an instant bust.
- **Roadblocks (wanted 4–5):** one officer may be diverted onto an actual
  connected asphalt lane 90–170 metres ahead of the *last observed* travel
  direction, where it must physically drive and brake to hold position.
  This is an assignment for an already existing vehicle, **not** a new car
  spawned on the player's route. If the graph has no legal position or the
  officer cannot drive there in time, no artificial roadblock appears.
- **Last-sighting searches:** only an unobstructed line of sight from a
  nearby cruiser refreshes suspect coordinates. After 2.5 seconds without
  contact, officers search the last known location and nearby possible
  roads, never the hidden player's true position. Timers vary from
  **11 seconds at level 1** to **24 seconds at level 5**. An actual sighting
  resumes pursuit; evading the full search clears wanted status.
- **Disabled vehicle fairness:** vehicle disablement triggers arrest only
  when a cruiser actually sees the player and reaches within 24 metres.
  Vehicle resets during pursuit still count as busts; no free
  reset-to-escape exploit. Vehicle-only robbery and race outcomes continue
  to use the existing `busted`/`escaped` signals and wanted state.
- **Coverage and limitations:** deterministic tests validate tier limits,
  safe spawn angles/distance/separation, roadblock legality, bounded
  interception, triangular containment and search/reacquisition.
  `tests/police_tactics_test.gd` runs in Godot 4.6.3 CI. This does not add
  realistic police model art, dispatch radio, new precincts or multiplayer
  synchronization; live driving, weather, map-coverage and collision
  playtests are still required before merging.

## Next phases (not yet implemented)

1. Expand the initial map-authored courier/getaway/smuggling contracts
   into vehicle-only robbery pickup jobs and richer delivery objectives;
   author real contract locations on each production map.
2. More reliable police interception, collision-safe spawning, coordinated
   roadblocks, line-of-sight searches, tactical escalation and wanted heat.
3. Career/underground reputation, mission contract payouts and failure rules
   with saved progression and explicit anti-duplicate reward tokens.
4. Polish vehicle damage visuals, physical gas station placement and repair
   UI, plus realistic vehicle-specific consumption tuning and persistent
   damage integration with future career saves.
5. Host-authoritative multiplayer police, shared pursuits, damage and contract
   payouts, with reconnect and split-screen validation.

## Validation

Run the standalone test after normal import:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/driving_crime_foundation_test.gd
godot --headless --path . --script res://tests/police_tactics_test.gd
godot --headless --path . --script res://tests/vehicle_fuel_gauges_test.gd
godot --headless --path . --script res://tests/vehicle_service_integration_test.gd
godot --headless --path . --script res://tests/driving_contracts_test.gd
godot --headless --path . --script res://tests/contact_contract_screen_test.gd
```

Also run the repository-wide validation workflow and visually inspect pursuit
spawn points, garage repair affordances, cop collision and disabled-car
recovery. Headless assertions do not establish pursuit AI fairness or
playability. Do not treat this prototype as a complete police or crime system.
