# Driving-only racing and crime: implementation roadmap

Streetbound is a **driving-first** open-world racing/crime game. There is no
player-controlled on-foot movement or combat. Police may win only by physically
containing the car for a verified duration or disabling the vehicle. Reset
during a wanted pursuit is a bust, not a teleport escape.

## First vertical slice: experimental single-player pursuit

- A reusable per-vehicle integrity model responds to actual
  `VehicleController2D.crash_contact` signals. Light contacts and repeated
  contacts within a 0.25-second impact window do not stack damage.
- Damage lowers *available driving force* without changing catalog specs,
  tire friction, braking, or the established 120 Hz handling model.
- Damage is scoped to equipped car IDs for the active session; it is not yet
  persisted, and a position reset **does not heal** a vehicle.
- Park at the existing garage or an authored garage/fuel marker and press **K**
  to pay for repairs. An unaffordable repair does not change car state.
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

## Next phases (not yet implemented)

1. Activity definitions and map-builder editing for getaway, robbery,
   delivery, impound, repair and police-station markers with stable world IDs.
2. More reliable police interception, collision-safe spawning, coordinated
   roadblocks, line-of-sight searches, tactical escalation and wanted heat.
3. Career/underground reputation, mission contract payouts and failure rules
   with saved progression and explicit anti-duplicate reward tokens.
4. Improved damage effects, persistent per-car damage, paid towing,
   repair UI, and non-police disabling/recovery.
5. Host-authoritative multiplayer police, shared pursuits, damage and contract
   payouts, with reconnect and split-screen validation.

## Validation

Run the standalone test after normal import:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/driving_crime_foundation_test.gd
```

Also run the repository-wide validation workflow and visually inspect pursuit
spawn points, garage repair affordances, cop collision and disabled-car
recovery. Headless assertions do not establish pursuit AI fairness or
playability. Do not treat this prototype as a complete police or crime system.
