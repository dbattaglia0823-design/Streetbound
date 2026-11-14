# Generic CC0 vehicle-engine recordings

These six small WAV files are **real-recording-derived loops**, made by
[domasx2 on OpenGameArt](https://opengameart.org/content/racing-car-engine-sound-loops)
from a public-domain car-engine recording. The author explicitly says the
six loops differ **only in pitch**, and confirmed in the comments that an
earlier incompatible sample was replaced with a public-domain one.

- License: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
- Original page: https://opengameart.org/content/racing-car-engine-sound-loops
- Redistributable mirror: https://github.com/yashimosh/border-run
- Mirror provenance: https://github.com/yashimosh/border-run/blob/main/CREDITS.md
- Files: `loop_0.wav`, `loop_1_0.wav`, `loop_2_0.wav`,
  `loop_3_0.wav`, `loop_4_0.wav`, `loop_5_0.wav`

The files are byte-identical Git blobs to the mirror at import time.

## Runtime usage

`scripts/audio/generic_recorded_engine.gd` plays them as a low-level
acoustic texture with six-way equal-power RPM crossfades. It activates only
for combustion cars with **no model or family recorded_texture**. It never
replaces a specific engine family/vehicle recording, never plays for EVs,
and does not change engine physics. The reference mix anchors are *blend
positions*, not measured recording RPM.

These files do **not** constitute six real RPM/load recordings or six
different engines. Do not identify them as Audi RS3 five-cylinder, V8,
rotary, etc. The actual engine-family synthesis and existing separately
licensed recordings supply the car's main acoustic identity. Replace this
generic bed with correctly recorded five-cylinder, rotary, V10, etc.
material as it becomes available.

For original high-quality Freesound sources reviewed for future per-family
sample banks, see `docs/FREE_ENGINE_RECORDING_SOURCES.md`.
