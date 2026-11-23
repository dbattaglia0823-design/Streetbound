# Playing Streetbound on macOS

Streetbound uses the same Godot 4.6.3 gameplay, world, saves, vehicle stats and
controls on Windows and macOS. The macOS export is a **Universal 2** application
for both Apple Silicon (arm64) and Intel (x86_64); no Windows VM, Wine or
always-on server is required.

## Download a Mac build

1. In this repository open **Actions → Streetbound macOS universal build**.
2. Select a successful run for the branch/commit you want. On demand, use
   **Run workflow**. macOS releases are not automatically published to Releases.
3. Under **Artifacts**, download **Streetbound-macOS-universal**.
   GitHub wraps the artifact in its own ZIP. Extract it, then extract
   `Streetbound-macOS-universal.zip` to get `Streetbound.app`.
4. Move `Streetbound.app` to Applications (optional) and double-click it.

The CI package is **ad-hoc signed, not Apple Developer ID-signed or notarized**.
A downloaded build may be blocked by macOS Gatekeeper. To open a build you
trust, try Control-clicking Streetbound.app → Open. If macOS offers
**Open Anyway**, find it in System Settings → Privacy & Security. You may
need to attempt to open the app once before this setting appears. Do not
disable Gatekeeper globally. A notarized public release requires an Apple
Developer ID and a separate signing/notarization pipeline.

## Play directly from the project

Install [Godot 4.6.3](https://godotengine.org/download/archive/4.6.3-stable/)
for macOS, open `project.godot`, and press **F5**. This requires no export
templates. To create an app yourself: in Godot install **4.6.3 export
templates**, use **Project → Export → macOS**, and export a `.app` or
`.zip`. For a distributable release, change the export preset to use your
own Developer ID and notarization credentials; do not commit credentials.

## Controls and multiplayer

- Keyboard: **W/S** accelerate/brake; **A/D** steer; **Space** handbrake;
  **Q/E** downshift/upshift; **M** auto/manual; **Escape** pause/settings.
- Controllers: use a compatible gamepad. Button and axis mappings are
  remappable under **Pause → Settings → Controls**; macOS controller support
  depends on the device and macOS version.
- LAN friends: choose **Multiplayer → Find / Host LAN Game**. macOS may
  prompt for **Local Network** access; allow it. If discovery fails, verify
  that both machines are on the same subnet, the Mac firewall permits
  Streetbound incoming traffic, and UDP **28164** (discovery) and **28163**
  (default game host port) are available.
- Friends at another house: use the game's private invitation and a reachable
  UDP endpoint or compatible virtual LAN. The host must be running the game.
  The Mac build adds no relay, cloud server or NAT traversal service.

## Build and verification

`.github/workflows/macos-build.yml` runs on a macOS host using the project's
pinned Godot **4.6.3**, imports the project, runs the existing title,
startup and input tests, exports the app, checks its arm64 and x86_64 binary
slices and code signature, performs a headless launch of the exported bundle,
then publishes a ZIP artifact. The file include filter explicitly packs
`*.json` and `*.txt` because Morrow Coast, the vehicle catalog and other
game data are read with `FileAccess` rather than Godot's `load()`.

The headless tests and automated launch do **not** prove frame pacing,
controller compatibility, fullscreen behavior, audio or real LAN connectivity.
Before calling a Mac build fully playtested, drive the real world on an Apple
Silicon Mac and an Intel Mac, check pause/settings/saves, and join a Windows
or Mac friend over LAN. Keep any problems in the PR rather than treating a
successful export as equivalent to interactive validation.
