# Streetbound — Driving Lab

## Archived Atlas Coast world and physics review

The latest [Atlas Coast editable map](worlds/atlas-coast.world.json), [overview](worlds/atlas-coast-overview.svg), [level-design plan](docs/ATLAS_COAST_PLAN.md) and [Godot paved-junction world loader](worlds/world_loader.gd) are preserved in the repository for later use. They do **not** replace the existing Driving Lab / proving ground. See the [actual Streetbound source and physics audit](docs/PHYSICS_AUDIT.md) for targeted corrections, measured limitations, road-scale compatibility, and the streaming work required before using the large map in gameplay.


A focused Godot 4 top-down simcade prototype. One reusable car, a finite proving ground, live tuning and replaceable placeholder sound. No progression, garage, dealerships or open-world systems.

## Pause menu — toolkit integration

Press **Escape** to pause driving. The central menu uses the **Game-Dev-Toolkit Functional UI v2 Pause Menu** template with **Resume**, **Settings**, and **Quit**. Escape in Settings returns to Pause; Escape from Pause resumes. Buttons remain operable while the vehicle, world, camera and gameplay are paused.

**Settings** uses the matching toolkit Settings layout, wired to real controls: sound on/off, master audio volume (0–100%), and car-follow camera orientation. Changes are saved to `user://streetbound_pause_settings.cfg` separately from the existing key/controller bindings (`user://controls.cfg`). F1 tuning and V mute remain available during gameplay.

Source layout and settings modules are archived in `assets/ui/` and `addons/gdt/`; the adapted controller is `scripts/ui/pause_menu.gd`. These use toolkit action IDs (`game.resume`, `nav.settings`, `game.quit`, etc.), connected to Streetbound's actual pause/game state and audio/camera rather than decorative mock buttons. The toolkit's original "Main menu" button is deliberately mapped to **Quit**, because Streetbound currently starts directly in the Driving Lab, without a separate main-menu scene.

Test with `tests/pause_menu_test.gd` (also run by CI). The existing driving and rendering-rate tests still run unchanged.

## Play

On this computer, double-click **Launch.cmd** to play using the installed Godot. Alternatively, open `project.godot` in **Godot 4.3 or later** and press **F5** to run the project. Built and tested with **Godot 4.6.3** on Windows. No addons or downloads are required.

| Action | Keyboard | Controller default |
|---|---|---|
| Throttle | W | Right trigger |
| Brake / reverse | S | Left trigger |
| Steering | A / D | Left stick |
| Handbrake | Space | A / bottom face button |
| Reset to launch | R | Y / top face button |
| North-up / car-follow camera | C | Right shoulder |
| Live tuning and rebinding | F1 | Bind in tuning panel |
| Automatic / manual | M | Bind in tuning panel |
| Shift down / up | Q / E | D-pad down / up |
| Mute | V | Bind in tuning panel |

Hold S to brake, then keep holding briefly at rest to reverse. W brakes out of reverse before driving forward. Start with gentle steering; lift before a corner, tap Space with steering to release the rear, then countersteer and feed throttle back in. The automatic transmission is the default. Manual shifting is already usable through the separate transmission module.

F1 opens a scrollable live tuning panel. Click an action and press a key, gamepad button or move an axis. Esc cancels. Keyboard and controller bindings are saved separately per action to `user://controls.cfg`; rebinding one preserves the other. Trigger inputs are analog. Any connected controller can use the defaults. **F1 handling changes are saved automatically** to `user://streetbound_vehicle_tuning.cfg` and reloaded on the next launch, including drivetrain selection. The stock `resources/sport_coupe.tres` remains unchanged. Use **Restore stock vehicle tuning** at the top of F1 to clear your saved override; R continues to reset only the car's position.

The default coupe uses **assisted racing handling**: tire grip 1.65, cornering stiffness 100,000 N/rad, rear stiffness ratio 1.30, rear grip balance 1.22, and steering range 44° at low speed / 14° at high speed. Steering assistance helps settled tires turn beyond the simulation's tire envelope. Extra lateral grip applies a bounded force opposing sideways motion; it scrubs energy rather than rotating the full-speed velocity vector toward the nose. Service braking preserves cornering grip and boosts steering for easier brake-and-turn inputs. Strong return-to-center remains enabled. F1 exposes **Arcade steering assist**, **Arcade cornering strength**, **Brake turning boost**, and the existing tire and steering settings. Settings live in `resources/sport_coupe.tres`. Setting arcade assistance to zero restores the axle-only model. Assistance weakens on loose surfaces and fades out with large slip angles, handbrake tire slip or driven-wheel spin.

Releasing the handbrake preserves rear tire slip and the existing travel direction. Rear contact relaxes over a nominal 0.9 seconds on asphalt; excess drive torque can spin the released wheels, reduce usable thrust/lateral grip and prolong recovery. Lifting helps the tires settle sooner. Steering and grip aids return only as contact and slip settle, so releasing Space cannot act as a free direction-change boost. There is no imposed speed penalty or launch cooldown: losses come from braking, tire scrub and untransmitted wheel torque. The normalized wheelspin estimate also affects RPM, tire audio and marks. F1 exposes **Rear tire recovery / seconds** and **Wheelspin settling rate**; the HUD displays spin and rear contact. This remains a simplified simcade tire model, not a full wheel/clutch simulation.

## Proving ground

Launch north along the long straight. The circuit continues clockwise through high-speed sweepers into a technical section and hairpin, then back to the start. The gate east of the launch joins a circular skidpad. The gravel bed lies north of the skidpad, reached across the grass. Grass surrounds the road. Guardrails, two standalone impact-test barriers and a distant perimeter provide collision tests. R always returns to the launch. Road labels, brake markers, painted curbs and persistent bounded skid marks aid orientation.


### Persistent F1 tune

All 19 live-handling sliders and the FWD/RWD/AWD selector save automatically to a versioned Godot ConfigFile. Changes are grouped during slider dragging (350 ms) to avoid excess disk writes, and pending changes are flushed when the F1 menu closes or the game quits. The save is stored locally in `user://streetbound_vehicle_tuning.cfg`—separate from `user://controls.cfg` and pause/audio settings—so it survives restarts without altering the original vehicle Resource. Opening the menu shows the saved values, and `Restore stock vehicle tuning` restores the current car and deletes the saved override. Invalid or out-of-range profile values are ignored. Automated coverage is in `tests/tuning_persistence_test.gd`.

## Imperial dashboard and tuning readouts

Streetbound displays driving speed in **MPH** (including the main speedometer and longitudinal/lateral telemetry). Visible vehicle specifications and live tuning captions use **pounds (lb)** for weight, **pound-feet (lb-ft)** for engine torque, **horsepower (hp)** for power, and **pounds-force (lbf)** for brakes and tire stiffness. Adjusting tuning sliders still updates the correct underlying vehicle configuration; the displayed numbers are converted from metric. Units are handled in `scripts/ui/imperial_units.gd` and validated by `tests/imperial_display_test.gd`.

The **simulation remains in SI units**, including metres/second, kg, Nm, kW and Newtons. This preserves the calibrated drivetrain, physics values, saved vehicle resources and regression-test trajectories while showing the driver imperial measurements.

## Architecture and units

`scenes/vehicle.tscn` is reusable; visuals live below `Art` and do not drive physics. The supplied PNG points down, so its Sprite is rotated 180 degrees around its center. The body points up at rotation zero. Collision dimensions approximate the car body rather than the PNG's transparent padding. Mipmaps preserve the supplied art at driving scale.

| Module | Responsibility / extension seam |
|---|---|
| `scripts/vehicle/vehicle_config.gd` | Exported Resource specs; duplicate per vehicle or derive upgraded Resources |
| `resources/sport_coupe.tres` | Starting coupe and normalized RPM torque curve |
| `scripts/vehicle/vehicle_controller.gd` | Fixed-step longitudinal forces, axle slip forces, grip budget, yaw, reverse and swept impacts |
| `scripts/vehicle/transmission.gd` | Automatic policy, manual commands, RPM coupling, shift interruption and shift signal |
| `scripts/input/controls.gd` | InputMap defaults and persistent key / controller rebinding |
| `scripts/world/proving_ground.gd` | Finite track, barriers, surface query and bounded tire marks |
| `scripts/camera/driving_camera.gd` | Smooth lookahead, zoom and orientation |
| `scripts/audio/vehicle_audio.gd` | Replaceable engine, tire and shift streams; procedural placeholders and impact sound |
| `scripts/ui/driving_hud.gd` | Speed, gear, RPM, surface, slip, specs and live tuning |

Physics uses metres, seconds, kilograms, newtons, Nm and kW. Only the controller converts motion to world pixels at **20 px/m**. The physics rate is **120 Hz**, independent of rendering; Godot physics interpolation smooths vehicle and camera transforms. A CharacterBody2D and swept `move_and_collide` give deterministic, tunable impacts with restitution, tangential sliding and energy loss. This choice follows [Godot's character-body collision model](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html).

The two-axle model saturates lateral forces by surface grip and axle load, reducing the available grip on driven wheels under torque. Front saturation gives understeer; rear grip balance and handbrake allow oversteer. Steering includes input smoothing, a speed-sensitive tire envelope and adjustable countersteer assistance. Releasing steering activates an overdamped self-aligning spring that returns the wheels to zero, with stronger centering at speed and no countersteer-assist offset. The default return strength is 18/s; F1 exposes **Return-to-center strength** independently of **Steering response**. Low-speed kinematic blending avoids unstable parking-speed slip calculations. This is intentionally assisted simcade handling, rather than a full suspension or tire-temperature simulation.

Mass, torque curve, torque and power limits, drivetrain traction, gear/final-drive ratios, wheel radius, grip, axle balance, steering, brake force, drag and rolling resistance all feed the controller. Per-instance Resource duplication isolates tuning and supports future upgrades without changing shared stock data. AI can set `external_input = true` and supply `command = Vector4(throttle, brake, steer, handbrake)`. A future streamed world can implement the same `surface_at(world_position)` query. Racing, traffic and garage systems can reference the vehicle without coupling to its artwork or input source.

The engine and tire sounds remain replaceable placeholders. Tire audio uses original, pre-baked four-second loops: filtered rubber resonances and a subtly wandering squeal on asphalt, with granular scrub on loose surfaces. Its peak playback gain defaults to -27 dB (about 12 dB below the previous mix), with quiet mild cornering, smooth onset/release and surface crossfades. Assign looping recordings to `engine_stream`, `tire_stream` and `loose_tire_stream`, and a one-shot to `shift_stream` in an audio scene to replace them. `tire_volume_db` controls the tire mix independently. RPM changes engine pitch; load changes volume; slip, handbrake, wheelspin, speed and surface control tire noise. Shift and impact signals trigger one-shots. Use V to mute. `tools/bake_tire_audio.py` can regenerate the original synthesized tire assets offline; no per-drift synthesis is required.

Tire marks use a separate `TireMarks2D` GPU instance pool, capped at 1,800 quads. Each sample overwrites two ring-buffer slots without rebuilding the static ground drawing, copying history arrays or allocating per-mark nodes. `tests/drift_benchmark.gd` renders a saturated-pool drift stress test and checks that the ground drawing is built only once. Run it with Godot's `--script res://tests/drift_benchmark.gd --fixed-fps 60`; add `-- --silent` to isolate audio. Timings are actual wall-clock milliseconds with VSync disabled, not the simulated fixed frame duration.

## Validation

Run `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1` from this folder. Pass `-Godot 'C:\path\to\godot.exe'` if Godot is installed elsewhere. The runner imports the project, rejects error logs, checks the actual controller against real Godot collision geometry, and compares a repeatable acceleration/steering/drift trace at **30, 60 and 144 render FPS**, keeping physics at 120 Hz. Full-scene tests cover the live input path, camera toggle, manual shift, audio players, tuning panel and saved key/controller rebinding. Test user data stays inside ignored `.runtime/`.

Test coverage: launch and upshift; stop before reversing; reverse and reverse steering; low-speed turns; high-speed turns and bounded slip; handbrake drift and recovery; grass acceleration versus asphalt; gravel detection; swept barrier impact; reset; power Resource response; FWD/RWD/AWD traction response; rendering-rate consistency. Results and logs are generated locally and excluded from version control.

`tests/arcade_tune_test.gd` additionally compares turn-in at 3, 12, 30 and 42 m/s against the previous grip-racing setup, verifies extra turning under braking, checks that grass remains less grippy, and confirms that steering at rest and straight-line braking do not rotate the car.

`tests/handbrake_recovery_test.gd` checks momentum continuity on release, persistent rear slip, torque-induced wheelspin, faster contact recovery when lifting, eventual recovery and reset. A repeatable right-angle corner checks that clean steering exits sooner than a handbrake turn or repeated handbrake taps under the same entry speed, engine and steering policy. This is a regression scenario for the release exploit, not a guarantee of optimal balance on every future track.

The tests establish repeatability and regression bounds, not a substitute for personal handling preference. A physical controller and the subjective sound mix still benefit from a hands-on pass. No AI traffic, networking, multi-body crash simulation, suspension, tire heat or streamed world is included in this milestone.
