# Streetbound Native Map Editor — migration status

## Native editing in Godot (developer builds)

Launch Streetbound from its local Godot project in debug/development mode, drive
in Morrow Coast, and press **F6**. The game pauses while you edit. **F6 / Test
Drive** restores your original vehicle and camera. The native editor is not
installed in release builds, cannot be opened while split-screen is active,
and does not create a second game world.

The center of the editor is **the real Godot map**, including animated art and
the actual pavement, collision surfaces and traffic simulation. The highlighted
pink intersection polygons come from the playable archive; cyan lane directions
and orange intersection turn connectors come from the same
`traffic_network.gd` built for the running traffic AI.

- **Inspect:** Click any real road, junction or placed scenery object. Baked
  procedural objects can be inspected, but **not arbitrarily rewritten**.
- **Road Anchor:** Click an authored road control point and drag it. A connected
  endpoint on another compatible road moves with it, in the same undo step.
  Existing source road IDs are preserved. Grid snapping is 1 metre by default;
  use **GRID 1m** to toggle it. Dangerous 350m moves, out-of-bounds coordinates
  and zero-length resulting road segments are rejected.
- **Move Asset:** Move an *authored* scenery object. Generated trees, protected
  game structures and procedural city buildings remain read-only until a
  stable replacement/adoption workflow is supported.
- **HOUSE / SHOP / TREE / ROCK:** Place a new source-authored object using a
  supported existing game atlas type. Its size and collision are rebuilt by the
  production generator, not guessed by an editor-only physics system.
- **Rotate / Delete / Undo / Redo / Discard:** Operate on source drafts. Only
  ordinary authored props may be deleted (not adopted or protected gameplay
  structures). Ctrl+Z and Ctrl+Y also navigate history.
- **Right/middle drag or WASD/arrows:** Pan. **Mouse wheel:** zoom.
  **CENTER ON CAR:** return focus to the original vehicle.

**Draft preview versus playable geometry:** Bright yellow control points/lines
and green asset footprints are **unbaked edits**. Live road, collision,
intersection and traffic data are still the previous baked state until you
click Apply to Game and Reload World. The native editor does not invent a
separate intersection or traffic solver.

## Safe Apply to Game

The native editor uses the **same authoritative local backend** as the browser
Map Builder: `tools/map_editor_server.py`. It writes only the World Forge v2
authoring source, invokes `tools/build_morrow_coast.py`, and verifies the
rebuilt, versioned `streetbound.streamed-world` output.

1. Have **Python 3** installed on the development PC. Select **START BACKEND**
   in F6 to launch the local-only service *without opening a browser*. If
   Python is not on PATH, use `map-editor/Start Native Map Backend.cmd` in the
   repository checkout and leave its terminal open.
2. Edit the map and select **APPLY TO GAME**. The native client checks the
   locally loaded baked world SHA, the local server's world SHA and the exact
   authored source snapshot before sending the edit using the local token.
3. The backend validates the revision and source, rebuilds road geometry,
   intersections, traffic inputs, collisions and spatial indices, and either
   commits all three files or **restores the source, world and overview** on
   failure. Changes by another editor/rebuilder cause a conflict rather than
   an overwrite.
4. On success select **RELOAD WORLD**. This reloads the real Godot game scene
   and reopens the editor at the same camera location, with freshly rebuilt
   junctions, pavement, traffic and assets. The car is re-created for this
   explicit reload; Test Drive without reloading preserves the original car.

The affected versioned files are
`map-editor/maps/morrow-coast.edits.world.json`,
`worlds/morrow-coast.world.json`, and
`worlds/morrow-coast-overview.svg`. Commit those generated changes to Git
after verifying them. **Never paste the authoring file over the baked world.**

Source edits during Apply are locked. If the backend is unavailable or the
loaded source and backend source disagree, no files are modified. Restart
Godot to import the latest source before trying again.

The browser Map Builder remains functional and may still be used, but don't
edit the same document in both clients simultaneously.

## Current limitations and remaining transition

This is a genuine editing-and-rebuild milestone, **not yet feature parity with
the entire browser editor**. Source road anchor movement and source-authored
scenery are supported. Protected/procedural scenery conversion, adding new road
branches and junction design, region painting, full asset browsing and complex
multi-object operations still require the browser editor. These should be
migrated after validation of the source-identity and rollback workflow. The
Python builder stays authoritative; only the UI is being replaced.

## Verification

- `node --test map-editor/tests/*.test.mjs` — browser geometry and source
  editor regressions.
- `python tests/native_map_bridge_contract_test.py` — native-to-local backend
  status/token/revision authorization; stale apply; failed rebuild rollback of
  source, playable map and overview; successful apply.
- Godot `tests/native_world_editor_test.gd` — real map/traffic inspection,
  editor cameras, streaming and Test Drive restoration.
- Godot `tests/native_map_authoring_test.gd` — real source anchors,
  connected endpoints, authored scenery, undo/redo and draft isolation.
- GitHub Actions runs these on Godot 4.4.1 and 4.6.3.

The current local backend stays bound to `127.0.0.1` and requires a matching
origin plus session token for writes. It does not expose a public network API.
