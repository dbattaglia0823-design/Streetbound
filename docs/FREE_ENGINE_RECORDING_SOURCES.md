# Streetbound: free recorded-engine asset shortlist

Reviewed 2026-11-13. These are **source candidates**, not bundled or quality-auditioned
assets. The source pages explicitly show CC0 as of review; preserve original
source/license links and recheck before distributing. Freesound often requires
an account to download full-quality originals. CC0 attribution is optional,
but source credit and provenance are recommended.

| Intended use | Recording / creator | Source URL | Licence | Limitation |
|---|---|---|---|---|
| General starter/rev reference | Car Engine / Kraftaggregat | https://freesound.org/people/Kraftaggregat/sounds/737642/ | CC0 | 15.5s start/rev/stop; isolate stable segments |
| General startup/idle | Car Engine Start, Idle, and Revving / NHumphrey | https://freesound.org/people/NHumphrey/sounds/200973/ | CC0 | 39s, mixed events, loop editing required |
| V8 performance | v8 engine rev.wav / overmedium | https://freesound.org/people/overmedium/sounds/651534/ | CC0 | 8.5s includes idle and throttle blips |
| Twin-turbo V8 | S63 AMG V8 Engine Revs / marcelweiss | https://freesound.org/people/marcelweiss/sounds/505321/ | CC0 | 6.2s stationary rev, not multi-RPM loop pack |
| Turbo release | Turbo Spooling and Blow Off.WAV / EwanPenman11 | https://freesound.org/people/EwanPenman11/sounds/659544/ | CC0 | 5.3s passby; isolate release, remove engine/Doppler |
| Raw engine loops for crossfade prototype | racing car engine sound loops / domasx2 | https://opengameart.org/content/racing-car-engine-sound-loops | CC0 | Six pitch variants of **one** source, not distinct OEM recordings |
| Engine ignition | Car engine start 01 / looneybits | https://opengameart.org/content/car-engine-start-01 | CC0 | Startup one-shot, not continuous RPM bed |
| General exterior idle | Car engine / XiiiSamples | https://freesound.org/people/XiiiSamples/sounds/384107/ | CC0 | 29s; inspect for steady usable windows |

## Integration recipe

Streetbound already resolves per-model, then per-family audio from:
`res://assets/audio/engines/<catalog-id-or-engine-family>/<slot>.wav`
(or `.ogg`, `.mp3`) in `scripts/audio/vehicle_audio_sample_bank.gd`.

Supported **loop** slots: `power_idle`, `power_low`, `power_mid`,
`power_high`, `coast_idle`, `coast_low`, `coast_mid`,
`coast_high`, and `recorded_texture`.

Supported **one-shot** slots: `shift`, `blowoff`, `flutter`, `pop`,
`ignition`, `shutdown`, `downshift`, `limiter`, and `curb`.

1. Download the source original WAV (do **not** rip a streaming preview).
2. Identify stationary RPM regions with limited background noise. A sweeping
   rev is **not** a substitute for four constant-speed RPM loops.
3. Edit per-band loops: remove DC, unwanted crowd/wind, verify source RPM,
   crossfade loop boundaries, and loudness-match. Never force a full
   acceleration recording to loop. Prefer WAV for repeated low-latency voices,
   Ogg for longer ambience.
4. Put a curated clip in its engine-family directory, e.g.
   `assets/audio/engines/v8_cross/power_idle.wav`. Populate only slots
   for which legitimate source material exists. A `recorded_texture` can be
   used as a quiet organic bed if no clean discrete RPM loops are available.
5. Maintain **distinct** families: `i4`, `i5`, `i6`, `v6`,
   `v8_cross`, `v8_flat`, `v10`, `v12`, etc. A V8 recording
   must not be relabeled as an Audi RS3 I5.
6. Test idle, full-load pull, off-throttle decel, upshift, downshift, redline,
   turbo spool/BOV, and a rapid car swap in Godot. Check loop clicking,
   phase/volume beating, pitch boundaries, CPU use, and clipping.

### Current limitations

The new Toolkit-derived mixer uses reference RPM of 1200, 2600, 4200,
and 6400. Do **not** pitch-shift unmeasured recordings as though recorded
at those RPMs; before production, record or estimate original RPM per clip
and use metadata-driven band RPM values. The current sample bank is fixed-slot;
adopting the Toolkit's row-based `bank.json` manifest is preferable once
actual multi-RPM families have been assembled.

No audio binaries are committed in this documentation change. Actual clip
audition, waveform editing, measured RPM tagging, licence snapshots,
headless tests and in-game listening remain to be completed.
