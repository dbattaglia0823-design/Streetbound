# Streetbound — Vehicle sound design and clip references

## What ships

All **88** currently catalogued playable cars receive explicit, original audio character data from `data/player_vehicle_catalog.json`:

- Engine type (I3, I4, I6, V6, cross-plane V8, flat-plane V8, V10, V12, W12, W16)
- Tuned exhaust intensity and roughness
- Turbo, supercharger, or naturally aspirated induction
- Optional turbo flutter character, where a turbo pressure model exists

These sound profiles are artistic characterizations; models with unspecified years/trims are not promised exact OEM engine specifications.

The primary engine and event sounds remain **original procedural audio**, not copied from reference videos. The generator creates eight seamless power/coast RPM layers per engine signature. An additional quiet layer now uses ten publicly CC0-labeled, processed recordings (one per broad acoustic family), with explicit provenance and QA in [CC0_RECORDED_ENGINE_TEXTURES.md](CC0_RECORDED_ENGINE_TEXTURES.md). These are **not** verified captures of the exact Streetbound models. CPU-light AudioStreamPlayer layers crossfade by actual RPM and throttle. Separate intake, gearbox, turbo/blower, blow-off, flutter, impact and exhaust-pop streams respond to live simulated driving telemetry. Existing asphalt/loose-surface tire samples are unchanged. Engine-synthesis results are cached and bounded by the finite catalog/profile configurations.

`scripts/audio/vehicle_audio.gd` has optional `AudioStream` overrides for the idle, low, mid and high RPM samples, and for shift, blow-off, flutter and pop effects. To use genuine field recordings, provide cleared/licensed, loop-edited assets in those export fields. Do not import copyrighted video audio without permission. Native Godot imported .ogg and .wav loops can replace synthesis while retaining the timing, RPM and physics envelopes. For dynamic projects that construct the vehicle audio node in code, set the exported fields on the node before it enters the scene tree.

## Reference listening / tuning notes (do not copy audio)

| Real-world reference | Sonic detail used for the synthesized profiles | Source |
| --- | --- | --- |
| BMW G80 M3, catless downpipe | Straight-six midrange growl, turbo airflow audible on acceleration, tighter shift interruptions | [ARM Motorsports downpipes comparison (recorded)](https://www.youtube.com/watch?v=T0gKWq-fynE) |
| Ferrari F40 twin-turbo V8 | Aggressive lightweight exhaust, high turbo whistle, air discharge and overrun character | [Car & Driver F40 road test](https://www.caranddriver.com/reviews/a32983963/tested-1991-ferrari-f40/), [F40 sound recording](https://www.youtube.com/watch?v=UBj_o8rTTpQ) |
| Bugatti Chiron W16 | Deep bass, dense multi-bank combustion character, turbine whistle versus exhaust growl | [Chiron hill climb audio observations](https://www.motorauthority.com/news/1110853_bugatti-chiron-hill-climb-run-is-alive-with-the-sound-of-turbo-spools) |
| Corvette C8 Z06 flat-plane V8 | Very different high-RPM pitch/bright harmonic rasp than a traditional cross-plane V8; no turbo discharge | [Road & Track Z06 engine sound](https://www.roadandtrack.com/news/a38056934/2023-chevrolet-corvette-z06-sound/) |
| Ford Mustang GT with modified exhaust | Low cross-plane V8 rumble and stronger aftermarket exhaust note; no turbo flutter unless equipped with a real turbo | [2024 Mustang H-pipe/straight-pipe comparison](https://www.youtube.com/watch?v=zGWi9oOVBW0) |
| Ferrari 488 GTB | Turbo V8 note, with more suppressed exhaust volume than a naturally aspirated 458 | [Ferrari 488 sound comparison](https://www.autospies.com/news/index.aspx?submissionid=85451) |

Wikimedia Commons lists a [Ferrari F40 engine audio recording](https://commons.wikimedia.org/wiki/File:Ferrari_F40_-_engine_and_exhaust_sound_(YouTube_yfF5gtwxBzY).opus) as CC BY 3.0, **but its license review was still pending when checked (November 2026)**. It is therefore **not bundled**; review the source rights before reuse. If cleared for redistribution, include author, source, full license link and a description of edits in your game credits and `docs`.

## Audio triggers

- **Engine RPM and load:** continuous, pitch tracking follows actual gearbox RPM; rising throttle increases exhaust and intake. Smooth layer weights prevent snapping between engine samples.
- **Gear shifts:** short transient torque-cut and shift sound; real boost can also trigger an air release.
- **Turbo:** spool audibility tracks `vehicle.boost_psi / config.boost_max_psi`. Blow-off or flutter can occur on pressure release after throttle lift or shifting, subject to cooldown. There is no blow-off at zero boost.
- **Supercharger:** rotor whine increases with RPM and throttle but does **not** create turbo BOV/flutter.
- **N/A engines:** no artificial boost or turbo sounds.
- **Exhaust overrun:** occasional pops after high-load throttle lift or high-RPM shifts on aggressive tuned profiles; rate limited.
- **Exhaust upgrade:** adds rasp/aggression to the actual equipped car; removing the part restores stock sound.
- **Mute and master volume:** existing V key and pause/settings remain authoritative for all audio streams.
- **Surface:** distinct tire and road sound clips remain triggered by real tire slip and road conditions.

## Further work

For truly recorded, vehicle-accurate RPM soundtracks, obtain properly licensed sample packs with clean steady-state idle / low / medium / high-RPM load and coast loops, plus separate compressor, BOV and pop effects. Recordings should have their background noise, clips and loop seams professionally edited and loudness-normalized. Unlike using raw video audio, that produces clear repeatable content and reliable game-export licensing.
