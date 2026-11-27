# Streetbound upgrade architecture — 120 specialized parts

## Live equipment system

Streetbound has **six live equipment slots**: Engine, Turbo, Transmission,
Tires, Suspension and Nitrous. The only equipment menu is the pause-accessible
Quick Upgrades overlay (`scripts/ui/quick_upgrades_overlay.gd`).

The canonical catalog (`data/upgrade_parts.json`, schema version 4) has
**120 fixed-stat templates**: four distinct specialties per slot at each of
Common, Uncommon, Rare, Epic and Legendary. The car-level gates remain
10 / 20 / 30 / 40 / 50. Existing part IDs are preserved; equipped old parts
use the rebalanced stats the next time their car configuration is rebuilt.

The design takes inspiration from the *idea* of specialized builds and
race-earned progression, without copying any other game's part names, visuals
or performance numbers. Matching a part to the event and vehicle should be
more valuable than always choosing a single dominant stat line.

| Slot | Four distinct upgrade specialties |
| --- | --- |
| Engine | Street (balanced), Torque (low-end), High RPM (top-end), Lightweight (lower mass) |
| Turbo | Spool (response), Balanced, Peak (top-end), Midrange (torque) |
| Transmission | Street (fast shifts), Launch (short gearing), Top Speed (tall gearing), Track (mixed) |
| Tires | Grip (maximum road grip), Drift (controlled slide), All-Round (stable mixed use), Drag (asphalt launch) |
| Suspension | Grip (corner stiffness), Drift (steering angle), Balanced (stability), Precision (turn-in) |
| Nitrous | Sprint (peak torque), Balanced, Endurance (capacity), Rapid Refill (short cooldown) |

### New physics attributes

- `mass_kg` allows Lightweight Engine parts to reduce actual sprung vehicle
  mass, changing acceleration and corner response instead of only changing a
  rating. The engine has less peak horsepower than the high-power specialties.
- `launch_grip_bonus` increases **driven-wheel longitudinal traction only on
  asphalt**, fading continuously to zero by 28 m/s (~101 km/h). Drag tires do
  **not** gain lateral grip, braking grip or extra traction on grass. Existing
  vehicles default to zero and keep their prior driving physics.
- Launch transmissions gain substantially more final drive but risk reaching
  redline sooner. Tall-gear sets reduce final drive and can improve maximum
  speed only on gear-limited builds. No hidden top-speed multiplier is added.
- Turbo boost pressure remains bounded by the vehicle's real boost cap;
  its separately listed power and torque bonuses determine peak output.
  Spool response and induction audio still use actual boosted physics.
- Nitrous recharge values are **absolute seconds**, not percentage bonuses.
  Rapid Refill is tuned for repeated short bursts, not the largest burst.

A specialist may still underperform on a particular car, track or driving
style. Formula and catalog tests validate meaningful trade-offs; final
time-trial balance should be measured using multiple vehicle classes.

## Reward source tags and future rotating races

Every template has stable `reward_sources` tags describing the future event
families where it belongs: `street`, `circuit`, `drag`, `drift`,
`highway`, `sprint`, `technical`, and `endurance`. The associated
`role` text describes why the part is useful. These tags are *planned
reward eligibility*, **not a claim that the tagged races exist now**.

`UpgradeParts.reward_template(race_id, car_level, event_type = "")` now
accepts an optional event type; when supplied, the award is restricted to
templates with the matching source tag and `race_drop_enabled=true`.
Unknown event types and empty eligible pools return no part rather than a
reward from the wrong event. Existing callers omit event_type and continue to
use the original deterministic general reward pool.

**Current availability:** The original 30 templates remain earnable through
existing races. The other **90 templates are catalog-only** and cannot be
awarded by the current race loop. This preserves progression and avoids
handing new parts out at random before event-specific loot is implemented.
The UI can preview all 120, but it only equips owned item UIDs.

**Later race-rotation feature (not yet active):**
1. Give authored races a stable event family, unique race ID, and rotation
   group; include event IDs on any intentionally exclusive rewards.
2. Rotate active races via a persisted calendar/rotation seed rather than
   the wall clock alone, and show locked or next-up events in the race UI.
3. Construct per-event weighted loot pools from part IDs and source tags,
   filter by eligible rarity/unlock rules, and ensure a configured fallback
   within the **same** event rather than silently switching reward pools.
4. Make reward claiming rotation-instance-aware so a race can return without
   granting duplicate rewards for the same appearance. Preserve owned parts,
   saves, and deterministic checks across rotations.
5. Surface expected reward families and rarity restrictions before entry,
   and add simulation tests for availability, drop fairness and lockouts.

Race rotation is deliberately not implemented in this change; the event
definitions and ownership claim history need a coordinated migration first.

## Save compatibility and testing

The removed ECU, Intake, Exhaust and Brakes categories remain unavailable.
All surviving 90 template IDs still resolve, and 30 new IDs are added without
changing the shape of existing inventory entries or per-car loadouts. Save
migration still ignores unknown IDs, preserves valid inventory and loadouts,
and retains unique part ID counters.

The upgrade catalog, role comparisons, event-tag filtering, asphalt-only
launch traction, mass changes, live hot-swaps and save migrations are checked
by the existing Godot test scripts and GitHub workflows.


## Black market (robbery phase 5)

The normal six race slots and 120 loot templates are unchanged. Four purchase-only slots (chassis, bumpers, protection, cargo) have basic (60 rep) and advanced (250 rep) parts. Purchases use canonical cash prices and unique saved inventory UIDs; installation uses reputation instead of vehicle XP and normal single-item-per-car ownership rules. Black-market UI buttons are in the existing upgrade overlay and purchases/swaps require a stationary vehicle in free roam without heat, an active race or a contract. Chassis increases max HP with a mass penalty; bumpers reduce incoming impact damage with a mass penalty; engine shielding reduces critical-health running power loss but cannot drive at zero HP; cargo storage reduces simulated cargo mass and increases cargo capacity. Normalized damage percentage is preserved when chassis changes. No tire durability, cargo damage or impact-source attribution system is introduced, so reinforced tires, cargo armor and outgoing damage bonuses are deferred. All figures are gameplay tuning, not real specifications. Tests cover purchases, rep gates, slot separation, health/mass modifiers and insufficient funds. Godot CI and live UI/handling verification pending.
