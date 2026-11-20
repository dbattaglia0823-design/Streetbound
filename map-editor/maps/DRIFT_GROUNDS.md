# Drift Grounds — compact drifting practice map

**World:** `drift-grounds.world.json` • **820 × 700 metres** • editable custom map

This map is separate from **Compact Boroughs** and the main **Morrow Coast**
world. It is a purpose-built facility with drivable connected pavement, not
a city map with a few corners renamed for drifting.

### Practice areas

- **Dual-ring skidpad** (northwest): an outer 80 m-radius practice loop,
  a smaller 42 m-radius donut loop, and a connector between them. An
  outside guardrail leaves the access route open.
- **Technical S transitions** (northeast): alternating curves and a
  tighter direction change. Its entrance comes directly from the skidpad,
  and its exit joins the main track.
- **Tandem circuit** (southern half): a continuous 24 m-wide sweeping
  loop with an east-hand bend, broad return, and an optional **infield
  reverse-transitions** route. A separate access/pit lane completes the
  network.

Scenery is concentrated in a tuning garage, service paddock, spectator
parking, tire storage, floodlights, and planted buffer areas instead of
obstructing the drifting line. Five **solid path-based guardrails** protect
selected corners and exits, with room to recover from a slide.

### Sessions

The course includes three editable race events:

1. **Tandem Outer Loop** — two-lap circuit driving route
2. **Technical Drift Transitions** — point-to-point time trial
3. **Skidpad Control Session** — skidpad time trial

These use Streetbound's existing circuit and time-trial systems. **They do
not introduce a dedicated drift angle, clipping-zone, or drift-score
mechanic.** Such a scoring system would be separate gameplay work.

There is one valid player spawn on the connecting access road. No
authored traffic-spawn markers are placed in this training facility; this
does not itself override other runtime traffic spawning systems.

### Opening and testing

**Native in-game editor:** choose **Drift Grounds** next to **Compact
Boroughs**. The starter is copied into the editable user map library
on first use. Existing modifications to the saved copy are never replaced.
Use **F6 / Test Drive** to drive it, and **Ctrl+S** to keep changes.

**Browser Map Builder:** click **Drift Grounds** in the header. Export the
editable JSON for use in the native editor.

The active PLAY world remains Morrow Coast. If desired, publishing Drift
Grounds later uses the existing **Build Game World...** control, which
requires a saved map and backs up the previous game selection.

### Regressions

```sh
python3 -m unittest discover -s tests -p drift_grounds_map_test.py -v
node --test map-editor/tests/drift-grounds.test.mjs
godot --headless --path . --script res://tests/drift_grounds_native_test.gd
```
