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
godot --headless --path . --script res://tests/vehicle_fuel_gauges_test.gd
godot --headless --path . --script res://tests/vehicle_service_integration_test.gd
godot --headless --path . --script res://tests/driving_contracts_test.gd
godot --headless --path . --script res://tests/contact_contract_screen_test.gd
```

Also run the repository-wide validation workflow and visually inspect pursuit
spawn points, garage repair affordances, cop collision and disabled-car
recovery. Headless assertions do not establish pursuit AI fairness or
playability. Do not treat this prototype as a complete police or crime system.
