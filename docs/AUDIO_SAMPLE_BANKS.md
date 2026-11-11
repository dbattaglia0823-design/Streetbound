# Streetbound vehicle audio: 88-car mastering and licensed recordings

Streetbound now ships 88 art-directed vehicle profiles, original synthesized RPM and effects audio, **plus ten CC0 recorded engine texture loops** with source hashes and a reproducible processing manifest. These are acoustic-family recordings, not authenticated make/model-specific audio. See [CC0 recorded source and license audit](CC0_RECORDED_ENGINE_TEXTURES.md). No source audio from YouTube has been copied.

## Playable changes

1. **Power vs engine braking:** Eight per-car RPM loops (idle, low, mid, high, each under load and on overrun). At zero throttle the mixer transitions into the softer engine-braking set; it does not cut engine volume to silence.
2. **Real driver telemetry:** The gearbox RPM sets engine pitch. Throttle controls power/coast crossfade and intake. Vehicle speed determines wind, road and driveline/gear noise. Asphalt and loose surfaces have different rolling and tire textures.
3. **Mechanical events:** Initial ignition and car-swap ignition, upshift cut, manual downshift rev blip, high-RPM rev-limiter intervention, occasional overrun exhaust pops on performance cars, collision and curb-contact transients.
4. **Forced induction:** Turbo spool, compressor flutter and BOV remain dependent on actual modeled turbo pressure. The supercharged Camaro ZL1 uses a supercharger whine instead. Naturally aspirated cars do not receive compressor sounds.
5. **Individual character:** All 88 entries specify an acoustic resonance (dark to bright), intake prominence, driveline prominence, idle lope, overrun frequency and boost audibility in addition to engine layout, tuning aggression and flutter intensity. These are gameplay sound presets, not exact manufacturer recordings.
6. **Garage:** Installing performance exhaust parts raises their engine's acoustic intensity and roughness; unequipping returns to stock. Audio reconfigures whenever a vehicle's actual config changes. V mute and settings master volume continue to work.

The synthesized source loops are generated on **car selection**, not in the frame-by-frame audio callback, and are cached by engine family, RPM band, power/coast mode, and selected tone.

## Upgrading to vehicle-accurate RPM recordings

Place loop-edited, properly licensed .ogg or .wav files under:

```
assets/audio/engines/<car-id>/
  power_idle.ogg
  power_low.ogg
  power_mid.ogg
  power_high.ogg
  coast_idle.ogg
  coast_low.ogg
  coast_mid.ogg
  coast_high.ogg
  shift.ogg
  blowoff.ogg
  flutter.ogg
  pop.ogg
  ignition.ogg
  shutdown.ogg
  downshift.ogg
  limiter.ogg
  curb.ogg
```

Examples:

- `assets/audio/engines/ford-mustang/power_low.ogg`
- `assets/audio/engines/bmw-m3/coast_high.ogg`
- `assets/audio/engines/ferrari-f40/flutter.ogg`

Explicitly configured `AudioStream` overrides take precedence. Otherwise the importer looks for **per-car files first**, then shared family files. The bundled CC0 `recorded_texture.ogg` loops add a separate low-volume real-recording bed; they do **not** replace any missing power/coast RPM stem, which continues to be generated procedurally. Adding cleared per-car `recorded_texture.ogg` will override its shared family layer.

**Processing requirements:** Record each engine at stable RPM under load and on engine braking, reduce background wind/other car noise, loudness-match clips, find click-free loop points, enable OGG loop support or set the WAV loop end in Godot, and verify that playback pitch still follows the reference RPM. Do not use multi-second accelerating rev recordings as fixed-RPM loops without extracting and editing stable intervals.

**Rights:** Use real field clips only when you can verify commercial redistribution rights. Store a source URL, author, license, retrieval date and edits in `docs/VEHICLE_AUDIO_REFERENCES.md`. If using CC BY, include the exact attribution in the game's credits; check CC BY-SA terms before distributing derivatives.

### Additional sources reviewed (not bundled)

- [muted.io Performance Cars](https://muted.io/performance-cars/) — 68 field recordings, advertised CC0, but requires a separate Ko-fi download.
- [Soundza: Car Engine, Gear Shift & Hum Loops](https://soundza.com/packs/car-engine-gear-shift-and-hum-loops) — CC0, some recordings, some synthesis; separately downloadable zip.
- [Soundza: Vehicle Sound Effects](https://soundza.com/packs/tarmac-cars-trucks-sirens-and-race-engines) — broader CC0 road/vehicle recordings.
- [Vehicle SFX Free (itch.io)](https://heyheythere.itch.io/vehicle-sfx-free) — CC BY 4.0; synthesized sounds, attribution required.

These links are for reference and potential future licensing/asset import, not proof that individual recordings were audited for model fidelity.

## Tests and performance

`tests/fleet_audio_mastering_test.gd` covers every authored profile, the two distinct load/coast sample sets, loop caching, wind/road speed dynamics, up/downshift behavior, actual limiter, muted effects, curb hits and car switching. `tests/engine_turbo_audio_test.gd` still validates the previous turbo/boost/flutter system.

Per-car sample assets and per-family fallbacks are checked **only when selecting a new vehicle**. Neither the mixer nor the physics loop downloads media or generates per-sample PCM at runtime. This keeps performance predictable even with 88 vehicles in the dealership.
