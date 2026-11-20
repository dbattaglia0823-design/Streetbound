# Streetbound — 148-car axle handling calibration

Date: 2026-11-20. This is a **gameplay estimation pass**, not an independently
measured OEM center-of-gravity, static weight distribution or brake bias dataset.

## Method

The 98 original cars and 50 additional cars each receive explicit estimated
`front_weight_fraction`, `center_of_gravity_height_m`, and `brake_bias_front`
values in their respective source JSON entry. Estimates are reproducible from
vehicle class, existing curb/running mass, wheelbase, length/overhang,
drivetrain, and the published gas/hybrid/electric powertrain classification.
There are two explicit outlier height adjustments for the Ariel Atom 500 and
Nomad, whose configurations would not be represented well by an ordinary
sports coupe baseline. Bounds enforce plausible gameplay contact behavior.
All values are labeled **estimates** and can be replaced with documented
trim-specific measurements when trustworthy source material becomes available.

- A heavier, high-center-of-gravity SUV transfers relatively more axle load
  when braking than a low hypercar at comparable deceleration.
- Typical FWD cars are front-heavy, RWD sports cars are closer to balanced,
  and AWD profiles depend on their class and drive configuration.
- Brake front bias trends with static front load and center-of-gravity height,
  but remains a gameplay estimate: no ABS or independent wheel lock model.
- The power, torque, mass, wheelbase, gearing, grip, drivetrain, prices and
  other reference specifications remain unchanged.
- Purchased tire, suspension and powertrain upgrades still act after the
  stock `VehicleConfig` is created.

## Verification and scope

`tests/vehicle_realworld_audit_test.gd` verifies every catalog record has
bounded, uniquely varied handling estimates and the config reads those values.
`tests/roster_weight_transfer_calibration_test.gd` creates all 148 real
stock configurations, checks that original reference specs are unchanged,
and runs a live braking simulation for every car, verifying forward load
transfer, summed normal load and finite dynamics. The existing 120 Hz
physics, handbrake, drift and race regression tests run separately.

**Limitations:** no manufacturer/trim-specific measured weight distribution,
CG height, corner weighting, suspension travel, per-wheel tire temperatures,
or ABS are asserted. Adjustments should follow actual hands-on handling tests
and same-seed before/after AI driving benchmarks rather than claims of
precise real-world simulation.
