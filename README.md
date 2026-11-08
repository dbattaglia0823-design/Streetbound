# Streetbound — Driving Lab

A focused Godot 4 top-down simcade prototype. One reusable car, a finite proving ground, live tuning and replaceable placeholder sound. No progression, garage, dealerships or open-world systems.

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

F1 opens a scrollable live tuning panel. Click an action and press a key, gamepad button or move an axis. Esc cancels. Keyboard and controller bindings are saved separately per action to `user://controls.cfg`; rebinding one preserves the other. Trigger inputs are analog. Any connected controller can use the defaults. Handling edits affect the current car for this session; edit the Resource to make a permanent setup.

The default coupe is now a **grip-focused racing build**: tire grip 1.65, cornering stiffness 100,000 N/rad, rear stiffness ratio 1.30, rear grip balance 1.22, and steering range 36° at low speed / 11° at high speed (further limited by tire capacity). This improves cornering bite and rear stability under power while retaining the strong steering return. F1 exposes tire grip, front/rear tire response, rear grip balance and high-speed steering for further tuning. Racing settings live in `resources/sport_coupe.tres`; the generic Resource defaults remain available for future vehicle types. The racing comparison tests check reduced slip, tighter turns, quick direction changes, lift-off and braking while cornering against the previous setup.

## Proving ground

Launch north along the long straight. The circuit continues clockwise through high-speed sweepers into a technical section and hairpin, then back to the start. The gate east of the launch joins a circular skidpad. The gravel bed lies north of the skidpad, reached across the grass. Grass surrounds the road. Guardrails, two standalone impact-test barriers and a distant perimeter provide collision tests. R always returns to the launch. Road labels, brake markers, painted curbs and persistent bounded skid marks aid orientation.

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

The procedural engine/tire sounds are audible placeholders. Assign looping recordings to `engine_stream` and `tire_stream`, and a one-shot to `shift_stream` in an audio scene to replace them. RPM changes engine pitch; load changes volume; slip, handbrake, speed and surface control tire noise. Shift and impact signals trigger one-shots. Use V to mute.

Tire marks use a separate `TireMarks2D` GPU instance pool, capped at 1,800 quads. Each sample overwrites two ring-buffer slots without rebuilding the static ground drawing, copying history arrays or allocating per-mark nodes. `tests/drift_benchmark.gd` renders a saturated-pool drift stress test and checks that the ground drawing is built only once. Run it with Godot's `--script res://tests/drift_benchmark.gd --fixed-fps 60`; add `-- --silent` to isolate audio. Timings are actual wall-clock milliseconds with VSync disabled, not the simulated fixed frame duration.

## Validation

Run `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1` from this folder. Pass `-Godot 'C:\path\to\godot.exe'` if Godot is installed elsewhere. The runner imports the project, rejects error logs, checks the actual controller against real Godot collision geometry, and compares a repeatable acceleration/steering/drift trace at **30, 60 and 144 render FPS**, keeping physics at 120 Hz. Full-scene tests cover the live input path, camera toggle, manual shift, audio players, tuning panel and saved key/controller rebinding. Test user data stays inside ignored `.runtime/`.

Test coverage: launch and upshift; stop before reversing; reverse and reverse steering; low-speed turns; high-speed turns and bounded slip; handbrake drift and recovery; grass acceleration versus asphalt; gravel detection; swept barrier impact; reset; power Resource response; FWD/RWD/AWD traction response; rendering-rate consistency. Results and logs are generated locally and excluded from version control.

The tests establish repeatability and regression bounds, not a substitute for personal handling preference. A physical controller and the subjective sound mix still benefit from a hands-on pass. No AI traffic, networking, multi-body crash simulation, suspension, tire heat or streamed world is included in this milestone.
