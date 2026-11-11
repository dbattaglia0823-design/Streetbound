# Public-domain recorded engine texture integration

## What is actually included

This upgrade incorporates **10 original-source CC0 engine audio clips** (one loop-edited sound for each Streetbound engine-family slot). The sounds are **recordings or processed recordings of real engines**, not genuine make/model captures. Every one of the game's 88 cars plays a small amount of its family-matched recording alongside the existing distinct synthesized four-band power / four-band coast engine. That preserves RPM and load correctness while replacing some of the artificial harmonic tone with natural captured turbulence.

**This is not a licensed recording of a Bugatti Chiron, Ferrari F40, or any other specific model.** Do not describe the samples as OEM or aftermarket exhaust recordings from those exact models. Family matching is a game-audio approximation. A later professionally acquired per-car pack at `assets/audio/engines/<car-id>/recorded_texture.ogg` takes precedence without changing code.

## Source provenance

The importer at `tools/prepare_cc0_engine_beds.py` pins both the **Git commit** and the **Git object SHA-1 for every source audio blob**. Downloaded source content must match its hash or the import fails. Nothing is scraped from YouTube. The prep script resamples to 22.05k mono, trims, softly crossfades the loop seam, and normalizes the audio before making compact Vorbis assets. Its `RECORDING_MANIFEST.json` retains source IDs, hash, processed size, peak, RMS and loop seam measurement.

| Engine sound slot | Recording source | License rationale |
|---|---|---|
| I3 / I4 / I6 / V6 | Automobility `creative_engine`, `copper_engine`, `iron_engine`, `stone_engine` | [FoundationGames/Automobility audio credits](https://github.com/FoundationGames/Automobility#credit-audio) explicitly say underlying engine samples were sourced from Freesound and licensed CC0 |
| Cross-plane V8 | `sounds/engine.wav`, [buntine/CarEngines](https://github.com/buntine/CarEngines) | That repository has a root [CC0 1.0 license](https://github.com/buntine/CarEngines/blob/master/LICENSE); the included engine file is used by their sample-playback demo |
| Flat-plane V8 / V10 / W16 | `loop_3_0.wav`, `loop_5_0.wav`, `loop_4_0.wav`, [yashimosh/border-run](https://github.com/yashimosh/border-run/blob/main/CREDITS.md) | Credits explicitly identify source as [domasx2's CC0 racing car loops on OpenGameArt](https://opengameart.org/content/racing-car-engine-sound-loops), edited from a public-domain car recording. **The three loops are pitch variations of one recording**, not three vehicle-specific recordings |
| V12 / W12 | Automobility `diamond_engine`, `gold_engine` | Same CC0 audio provenance as above |

Author attribution is not legally required for CC0 but original projects and creators are credited above. Source claims were reviewed on November 10, 2026.

## Engine-family mapping

The destination asset paths are:

```
assets/audio/engines/<i3|i4|i6|v6|v8_cross|v8_flat|v10|v12|w12|w16>/recorded_texture.ogg
```

The sample bank first probes the precise vehicle ID (for future upgrades), then the broad acoustic family. The standard synthesized engine and all turbo/shift/tire/road/boost audio stay intact. The captured layer follows actual vehicle RPM and throttle, and obeys mute and global engine volume. Recordings are only loaded on vehicle selection or config changes; they aren't redownloaded or decoded every frame.

The CC0 recordings are not suitable as **eight distinct steady-state RPM load/coast loops**. Consequently they are deliberately mixed as low-volume texture—not substituted into the 8-loop system. An exact vehicle's appropriately captured power and coast loops can still be added separately using the existing `power_idle.ogg` through `coast_high.ogg` sample-bank slots.

## Sound-review deliverable and limitations

The importer also produces `engine_audition.wav` containing all ten source beds separated by 250ms silence, ordered as the table above. The import workflow uploads it as a GitHub Actions artifact, together with the per-family RMS and peak manifest. This enables **actual in-ear listening and feedback**. CI headless tests can validate that the sounds load, are non-silent, loop and react to throttle and mute; they cannot judge whether a particular car is convincingly realistic in speakers/headphones.

### Rebuild procedure

Run `python3 tools/prepare_cc0_engine_beds.py` from the repository root with `ffmpeg` and `curl` available. It will regenerate the ten OGG files plus the QC manifest. All input bytes are verified against their original Git blob hashes. Only import recordings with verified commercial redistribution permission; avoid substituting copyrighted films or YouTube audio.

The audio remains a work in progress. These recordings are an improvement in organic texture, but the next major authenticity step is to gather **cleared matched engine load/coast RPM stems recorded from the exact game cars**.
