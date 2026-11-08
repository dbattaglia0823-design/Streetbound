# Streetbound — top-down open-world driving

Godot 4.4.1 driving prototype and saved 22,000 x 18,000 World Forge Atlas Coast world. The existing Top-Down Porsche GT3 RS Blueprint.png remains unchanged and is used as a temporary visual car model.

## Open and drive

1. Open this repository in Godot 4.4.1; import assets and run the main scene (F5).
2. W / Up accelerates, S / Down brakes then reverses, A/D or Left/Right steer, Space applies handbrake, R resets to the Westhaven garage, F3 toggles map markers.
3. The camera follows the driver car and the HUD displays speed in km/h, heading direction and surface.

## Preserved Atlas Coast assets

- worlds/atlas-coast.world.json: exact original World Forge v2 document, with 132 roads, 32 terrain regions, seven race venues, coastline, organic cities, 11 dealerships, garages, dirt tracks, highways and fuel stops.
- worlds/atlas-coast-overview.svg: standalone planning illustration of the region.
- worlds/world_loader.gd: verbatim junction-aware Godot 4 adapter that renders terrain, roads, at-grade crossings, props and basic collision geometry.
- docs/ATLAS_COAST_PLAN.md: layout and replacement-asset handoff.
- Source snapshot: https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/825780debc1e760239297d9bf661c4ab3bde546c/web/map-builder . Import the saved JSON into World Forge to continue editing; Streetbound does not contain the browser editor.

This map is a layout foundation, not a completed game. It uses vector and solid scenery placeholders. Intersections are all assumed to be at-grade; highway overpasses, ramp rules, traffic AI and navigation are not implemented. The game currently loads the full map without chunk streaming, so mobile performance is NOT guaranteed.

## Physics analysis and first implementation

The original Streetbound repository contained only its Porsche PNG and a .gitattributes file, and therefore had no car physics or application code to audit. This change creates the first driving implementation in scripts/car_controller.gd, rather than claiming to tune nonexistent physics.

- CharacterBody2D uses floating collision mode and move_and_slide() for solid obstacles.
- Testable advance_physics(delta, drive, steer, handbrake) is separate from keyboard input; this allows AI, controller or touch integration later.
- World pixels are converted to metric units with an explicit pixels_per_meter parameter. Acceleration is limited by engine power and vehicle mass, with rolling resistance and aerodynamic drag.
- Brake input first decelerates then engages reverse. Steering has finite response, reduced range at high speed, wheelbase-dependent turn rate and an acceleration-limited yaw cap.
- Body direction and momentum are separated to permit lateral slip and handbrake drifts. Surface grip varies between asphalt, track, dirt, gravel, grass and beach.
- Texture height determines sprite scale, with editable heading offset and collision dimensions. The PNG may need artwork cropping or transparency checks before release.

Known omissions: no real suspension/tire model, transmissions and gears, engine RPM, ABS, torque distribution, sound, touchscreen UI, saving, traffic, dealers, races or proper world streaming. Road widths and the camera must be validated relative to the car model during gameplay. A single car controller is a foundation, not verified GT3 RS telemetry or real-world vehicle physics.

## Testing and priorities

GitHub Actions imports the project with Godot 4.4.1 and runs tests/driving_physics_smoke.gd covering forward acceleration, speed limits, braking, reverse, speed-based steering, surface grip, reset, and saved map junction integrity.

Next steps: playtest steering feel and braking distance; add physics telemetry and car definitions; implement spatial indexing and streaming before mobile deployment; replace map placeholders with original shadow-free assets; then implement garage, dealership, upgrades and race logic.
