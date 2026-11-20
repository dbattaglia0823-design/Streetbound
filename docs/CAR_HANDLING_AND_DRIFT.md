# Racing and drift handling — car/upgrade dependent

The real `VehicleController2D` still owns **one 120 Hz bicycle/axle tire simulation**. There are no fake velocity snaps, free steering impulses at rest, forced drift animations, or control-mode switches. Grip, weight, drivetrain, wheelspin, road surface, steering, rear tire saturation, and yaw inertia remain authoritative.

## Stock cars

`PlayerVehicleCatalog.make_configuration` uses the existing real/estimated roster specifications and adjusts three bounded, new handling values by vehicle type, mass and drive layout:

- `high_speed_stability` — a subtle tire-envelope/steering contact aid at speed;
- `drift_control` — sustained slide/driver-countersteer confidence while the rear tires are already slipping;
- `handbrake_rotation_boost` — moving rear-wheel-lock yaw response, with a small **one-time engagement pulse** and a sustained steering-dependent torque.

Light RWD/compact cars are more willing to rotate. Heavy SUVs and AWD hypercars have less natural low-speed rotation but remain usable. All stock vehicle models now have a better handbrake-rear-grip baseline and slightly longer slip recovery to allow an intentional moving 180°.

The pulse requires the **handbrake edge, rolling speed, and steering**. It does nothing for a parked vehicle, preserves service-brake priority when all pedals are held, and cannot make the chassis move sideways on its own.

## Upgrades and trade-offs

The same existing 120 upgrade templates and persistent equipped IDs remain. No extra slot, save migration, or free items are added.

- **Grip tires + Grip suspension:** high-speed stability, cornering stiffness and tire grip. They take faster turns more tightly, *within* front/rear contact limits, with weaker assistance on grass and while sliding.
- **Balanced, Precision and All-Round options:** smaller high-speed stability increases rather than another dominant grip build.
- **Drift tires + Drift suspension:** more slide retention, controllable countersteering, extra yaw authority, and improved initiation of an intentional handbrake turn. Drift rear-grip balance remains lower than Grip builds.
- **Drag tires:** launch-oriented only. No new lateral cornering bonus.
- Engine power/torque, driven axle, mass, tire grip and other vehicle properties still affect how easily wheelspin breaks the tires free.

The physical high-speed stability boost is deliberately limited (up to ~12% extra front lateral force and ~6.5% rear force at the maximum tune). It fades below ~12 m/s, on low-grip surfaces, when wheelspin rises, or when handbrake/slip is present. It does not force the car onto a road rail. Drift-only assistance also fades when the tires are settled.

Parts apply **flat, bounded normalized increments** to `high_speed_stability` and `drift_control`; `handbrake_rotation_boost` remains a bounded multiplicative stat. The live pause-menu upgrade handler already computes the delta of all numeric properties between the two complete stock-derived loadouts, so hot-swapping these fields changes the current running car immediately without resetting it.

## Verification and tuning

The dedicated test compares the **same real controller** with different upgrade loadouts on a 120 Hz steering trace. It checks three differently sized/driven cars, stock moving handbrake 180°s, high-speed cornering, drift hold, and no steering movement at rest. A separate CI job exercises pre-existing parked-brake conflicts and the entire 120-template catalog on Godot 4.4.1/4.6.3.

The small **Drift Grounds** map is a useful manual driving target but is not required by the handling change. It has no special grip script; the car and upgrades provide the difference.

### Design limits

This is a deliberately forgiving arcade/track model, not an individual-four-wheel tire model. There is still no dedicated differential simulation, suspension load transfer, tire temperature, ABS or automatic drift-score measurement. Refine balance after hands-on driving with multiple car classes and keyboard/touch controls.
