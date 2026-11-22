# Play with friends — temporary LAN and internet sessions

**No always-on game computer or deployed Streetbound service is required.** A player hosts while playing and their game becomes the session authority. When the host exits, the session ends. Up to four total drivers can play together in free-roam Morrow Coast.

The implementation is Godot ENet over UDP. Two different connection methods share the same vehicle physics, admission and synchronized free-roam systems.

## Friends on the same Wi-Fi or wired local network

1. Everyone runs the same Streetbound version. Select **Multiplayer → Find / Host LAN Game**.
2. Host: enter your driver name, then choose **Host LAN Game**. Your computer starts hosting UDP **28163** and responds to UDP **28164** discovery queries only while your game is open.
3. Friends: select **Find LAN Games**, choose the host from the list, and select **Join Selected LAN Game**. A same-subnet UDP broadcast finds compatible hosts; the received packet's IP is used for joining instead of asking players for an address.
4. To end the game, the host leaves to the main menu. LAN advertising and the game session stop.

**Privacy:** LAN advertising is deliberately **opt-in**. It publishes the temporary session's invitation credential in responses to LAN discovery queries, so any device able to query the host on that local network may see and join the game. It does not publish rooms to the internet. **Do not use discoverable LAN hosting on an untrusted shared or public Wi-Fi.** For stricter invitation-only LAN sessions, use the Direct Friends Invite option below, and share the invite privately instead.

LAN scans may not cross multiple VLANs, guest Wi-Fi/client isolation, corporate firewall segments, or a VPN tunnel. Allow the app through your OS firewall (UDP 28163 for ENet; UDP 28164 for discovery). No internet router port forwarding is required for players already on the same LAN.

## Friends at another house — no always-on computer

The existing **Multiplayer → Play With Friends (Online)** supports player-to-player joining when the host is reachable.

**Recommended for private internet sessions without router port forwarding: Tailscale**, or a similar trusted virtual-LAN app. Tailscale can securely connect your computers or share a particular host device with friends over the internet without opening a home-router port; its service supplies the connection coordination/relay infrastructure, and only the actual players' machines must be on while playing.

1. Both host and friends install and connect a compatible virtual-LAN app; ensure they are authorized to communicate. For Tailscale, share the host device or authorize friends in your tailnet. See [Tailscale's game server guide](https://tailscale.com/docs/use-cases/personal-or-at-home-use/share-private-game-server).
2. The host opens **Play With Friends (Online)**, sets their driver name and **the host's Tailscale IPv4 address** (usually in the `100.x.x.x` range) in the *reachable IP/hostname* field, leaves UDP port **28163**, and selects **Host Friend Session**.
3. In the game, the host clicks **Copy Invite** and sends the long `SB1-` code privately to friends.
4. Each friend opens the same online menu, pastes the code, and selects **Join Friend Session**. ENet traffic goes over the private network; no dedicated Streetbound machine or game-hosting subscription is necessary.
5. The host's game is the authority and must remain open *for the play session only*. Leaving closes the session. If Tailscale is stopped or connectivity is blocked, the game disconnects.

**Without a VPN**, internet hosting may work if the host uses a public reachable address and forwards the chosen ENet **UDP** port (default 28163) on their router/firewall. This can fail with carrier-grade NAT or restrictive networks. There is no Steam/EOS relay integration, automatic NAT traversal, matchmaker, or authentication service in Streetbound yet. A code on its own cannot make an unreachable home computer reachable from another house.

## Existing private invitation controls

A host chooses their reachable IP or hostname and port. The game generates a random 192-bit per-session secret and packages the host address, port and secret into a `SB1-` invitation. The host checks possession of the current secret **before** admitting a guest. The in-world host can **Copy Invite**, **New Code** (invalidates earlier invitations for future joins), and **Lock/Unlock Lobby** (blocks or allows new arrivals without kicking current drivers).

The protocol is not end-to-end encrypted and codes are bearer credentials. Do not broadcast a private invitation over insecure public networks. For LAN discovery, the credential is knowingly shared on the local subnet; for Direct Friends invites it remains private unless the host shares it. This does not establish verified player accounts or prevent a malicious recipient from re-sharing a code.

## Recover from an interrupted connection

Since **multiplayer protocol v4** (retained in v6), a guest can recover from a short internet/Wi-Fi interruption without reloading the driving world or replacing their car. The host remains the authority; no always-on game computer, central server, or router change is introduced.

- At initial admission, the host generates a **separate random 192-bit personal resume token** for each guest. It stays in memory for this session and is not displayed in the invite code, roster, or LAN advertisement. A shared lobby invite is **not enough** to claim another player's reconnecting seat.
- If the host detects a lost guest, it reserves the player's occupied slot and **the exact existing physics car** for **35 seconds**. It immediately cancels stale throttle/nitrous commands. Friends who remain in the session see that driver's name labeled **reconnecting**.
- The guest automatically retries the prior address/port every **5 seconds**, for up to **30 seconds**. During recovery the driving scene stays loaded and local driving input is temporarily suspended. A successful resume uses the personal token, rebinds the old host-owned car to the new ENet peer ID, restores the selected vehicle, resets client interpolation history, resynchronizes authoritative position and resumes normal input.
- An authenticated reconnect is permitted even if the host has subsequently **locked the lobby or rotated the shared invite**, but only while the player's reservation remains valid. New players must still pass the normal invitation/lock/capacity checks. Expired seats and tokens are purged.
- If recovery fails or the original host has quit, the guest returns to the title screen with a disconnection status. **Host migration is not included.** This does not change NAT traversal, packet travel time, or how different-house sessions are established.

**Limits:** The 35-second reservation also temporarily occupies a slot after an ordinary disconnect/exit, until it expires. Reconnection only succeeds if the host keeps the same session alive and remains reachable. The token is not an account identity, does not persist across game restarts, and cannot provide end-to-end encryption.

Tests include `tests/online_reconnect_world_probe.gd` (real two-process Godot host/guest gameplay, locked/rotated lobby and exact car preservation) and `tests/online_reconnect_impairment_test.gd` (deterministic, **synthetic** snapshot-arrival profiles for **30, 80 and 150 ms RTT** with jitter and packet drops). These do not substitute for real LAN/WAN outage and packet-capture tests.

## Friend-to-friend Ashford quarter-mile racing (protocol v6)

This is the first playable **multiplayer racing event** in the existing 2–4 driver player-hosted Morrow Coast free-roam session. It uses the **actual Ashford Drag Strip** course; no always-on server, account, matchmaking service, or separate world is needed.

1. Everyone joins the same temporary LAN/direct/Tailscale friend session with the **same protocol v6 game build**.
2. Drive to the **Ashford Drag Strip** starting circle. The host parks near the start and selects **NEW FRIEND RACE** in the in-world *ASHFORD / FRIENDS QUARTER MILE* overlay.
3. Other drivers park within 35 metres of the starting circle, slow down, and select **JOIN / READY**. The host validates the actual server-simulated position, connection and speed before marking them ready. Players not racing can remain in free roam.
4. When at least two drivers have opted in and are staged, the host chooses **START RACE**. The host places the existing vehicles in two, three or four separate real-world lanes at Ashford's start and starts a 4.5-second shared countdown. Client visuals align to the host-owned grid; steering/throttle are held until **GREEN**.
5. Race to the physical **402.336 m** finish line. The player host alone validates positions, forward line crossings, lane bounds, suspicious position jumps and a 180-second run limit. Results show ordered finish times (millisecond precision from host clock) and DNF/forfeit status. Results are pushed to all connected racers and spectators.

**Practice-only in this initial implementation.** Friend races do **not** earn cash, XP, wager payouts, parts, or career/race progress. The existing solo Ashford AI race is temporarily disabled during online sessions to avoid overlapping prompts or unsynchronized rewards. No vehicle-to-vehicle collision/damage is added in this PR. The Ashford Circuit is also now supported (see the next section); other solo race types remain unsynchronized.

The host may cancel an event, and a guest may forfeit during a run. Disconnecting during a run causes a **DNF**, even if the player reconnects to the same car shortly afterward; this prevents reconnecting to reset the race timer or gain a free restart. The separate reconnect system continues to preserve the driver's ordinary free-roam vehicle. Results reset after a short display interval, allowing the host to open another event.

**Security and fairness:** Remote clients cannot submit finish positions, elapsed times, money changes or winner choices. Host-authenticated readiness/forfeits are the only guest race RPCs. The host can still cheat because this is peer-hosted; a central anti-cheat service and independent timing arbiter are intentionally outside the temporary friends-only scope. A physical LAN/WAN playtest is needed to validate countdown alignment under real packet delay (the UI compensates approximately using measured RTT).

Dedicated tests: `tests/online_friend_drag_rules_test.gd` covers lane layouts, direction-aware finish geometry, impossible jumps, DNF exclusion and deterministic ranking. `tests/online_friend_drag_world_probe.gd` launches two real full-game processes and checks authorized readiness, staged host-owned vehicles, countdown, guest input release, and synchronized host-only practice results.

## Synchronized Ashford Grand Circuit laps (protocol v6)

Besides the original quarter-mile friends race, a host can now start a **2–4 player full-lap Ashford Circuit practice race**. Drive to the existing Ashford Grand Circuit start marker with friends, stop within 35 metres, and the host selects **NEW FRIEND RACE**. The game chooses the event based on the host's physical location. Participating friends select **JOIN / READY**; the host checks actual server-simulated position and speed before **START RACE**. Up to four existing cars line up across the 14-metre circuit width, with client input frozen until the shared 4.5-second green.

Unlike a shortcut-prone lap projection, the host requires **sequential directional physical checkpoint crossings** along the existing closed circuit racing line. Checkpoints are spaced about 110 m apart. A racer cannot claim a lap by jumping directly to the finish, crossing gates backward, driving far outside the racing line, sending client timestamps, or repeatedly touching the same marker. The host evaluates every car with its authoritative physics; time limit is 480 seconds, then outstanding drivers receive DNF. Actual results and DNF status are replicated to the lobby; practice laps do not award cash, XP, parts, or career progress.

A circuit route/braking guide appears while racing. The solo Ashford drag, circuit, Larkspur sprint, and authored event prompts and menu entries are disabled during player-hosted multiplayer to prevent **unsynchronized local races and career rewards**. The single-player experience is unchanged.

The protocol is **v6**, so everyone must update; older v5 builds are intentionally rejected because they do not understand the authoritative event choice and circuit gate state. Remote friends still use the existing private invitation/LAN/Tailscale setup and need no permanent server. Circuit and drag modes share the same lobby/event controller, so only one event can run at a time. The Larkspur street sprint is **not** a shared multiplayer event yet; its narrower road requires a separate safe grid and route validation pass.

Tests include `tests/online_friend_circuit_rules_test.gd` (closed-course gates, reverse crossings, skipped gates, safe 2–4-car width, v6 protocol) and `tests/online_friend_circuit_world_probe.gd` (actual two-process full-game circuit selection, authorized readiness, countdown, guest input release and host-only DNF results). Both are automated localhost checks; real cross-house playtesting and track fairness observations remain outstanding.

## Low-latency free-roam synchronization

The game remains **player hosted** (no always-on game server) and retains the exact same 120 Hz vehicle physics for local and hosted drivers. Multiplayer protocol **v6** is required on both ends because the admission and world RPCs now also include the friend race controller, alongside resume credentials and sequenced snapshots; old v2/v3/v4/v5 builds are refused at admission.

- **Local input prediction:** each participant drives immediately on their own machine. The client schedules changed controls at **60 Hz** (previously 30 Hz), and periodically resends held commands at **10 Hz**, safely inside the host's 450 ms stale-command brake. This reduces command batching without transmitting redundant packets sixty times a second when the player holds steady.
- **Authoritative snapshots:** the player-host simulates guest physics and sends sequenced world state at **30 Hz** (previously 15 Hz), using unreliable ordered ENet packets. Old/out-of-order snapshots are dropped instead of rolling back peers. Remote players' cars still cannot override the host's vehicle physics or economy.
- **Remote-car visuals:** clients buffer up to seven received snapshots and interpolate positions, headings, steering and velocity with an RTT-variance-informed **50–125 ms visual delay**. Missing packets trigger at most **60 ms** of velocity-based *visual* extrapolation; stale cars freeze rather than continuing to drive through scenery. This intentionally smooths other drivers while the local driver's controls remain immediate.
- **Client reconciliation:** the local client ignores small position errors (up to 20 game units), gently corrects medium errors at a frame-rate-independent rate, and immediately accepts major resyncs (>700 game units). The server stays authoritative.
- **Real connection indicator:** the in-game overlay reads actual ENet **RTT**, **RTT variation**, and **reliable-packet-loss** statistics for the connection. The hosting player sees the largest observed RTT among their connected guests; a guest sees their RTT to the host. **Reliable loss is not total UDP input/snapshot loss**, and RTT variation is not a precise one-way jitter measurement. Until ENet has samples, the overlay says *measuring*, not a fictitious 0 ms.

At 60 Hz, one input scheduling interval is ~16.7 ms (was ~33.3 ms). At 30 Hz, snapshots are spaced ~33.3 ms (was ~66.7 ms). These are **application update intervals, not internet ping or guaranteed latency reductions**. The number displayed in-game depends on route distance, Wi-Fi congestion, CPU stalls, buffering, and ISP/VPN routing.

### Getting the lowest practical ping

Use **wired Ethernet**, or a strong and uncongested 5/6 GHz Wi-Fi connection, on the local LAN for best results. Choose as host a player with low, stable RTT to the others and a responsive PC. For friends at another house using Tailscale, check `tailscale status` or `tailscale ping <friend-device>`: a **direct UDP** connection typically has lower latency than a DERP/peer relay. Tailscale documentation: [Connection types](https://tailscale.com/docs/reference/connection-types). Router forwarding is optional for a reachable direct public-IP host, but the in-game private invite remains mandatory.

CI test `tests/online_network_smoothing_test.gd` validates interpolation math, timestamp buffering, RTT-corrected local targets, jump limits, stale freezing, angle wraparound, and transmission intervals. `tests/online_friend_connection_probe.gd` reads actual measured ENet RTT on a separate guest process. `tests/online_realtime_world_probe.gd` launches two full Morrow Coast game sessions over real ENet loopback and checks the sequenced snapshots, bounded buffer, and live RTT display. The focused `.github/workflows/multiplayer-latency-validation.yml` runs these alongside the existing full regression. Real two-house RTT, packet loss under congestion, and perceptual smoothness need hands-on sessions; localhost CI does **not** establish zero ping or any promised cross-house RTT.

## Implementation and test coverage

- `scripts/network/online_session.gd`: host-owned roster, version handshake, validated invite and resume-token admission, 4-player capacity, reserved/recovered car identity, and disconnect expiry.
- `scripts/network/lan_discovery.gd`: opt-in UDP 28164 LAN discoverability. The client broadcasts a fixed discovery query, accepts bounded JSON replies only for the same game protocol, builds join addresses from actual packet-source IPs, and never uses an untrusted advertised IP for the ENet destination.
- `scripts/ui/title_menu.gd`: separate LAN host/browser/join page and existing private Direct Friends Invite page.
- `scripts/network/online_world.gd`: host-simulated guest vehicle physics using normal driving commands, state snapshots and interpolation. Friend drag and Ashford Circuit events are synchronized through `online_friend_race.gd`; other competitive races, synchronized upgrades and vehicle-to-vehicle collision/damage are **not networked** yet.
- `tests/lan_discovery_probe.gd`: two separate actual Godot processes host and discover via UDP loopback, join using the session invitation and validate roster and cleanup.
- `tests/title_navigation_test.gd` and existing `tests/online_friend_connection_probe.gd` validate the game menus and private ENet admission. CI runs these under Godot 4.6.3, and the existing broader world/physics suite also tests 4.4.1.

**Testing boundaries:** A successful loopback test is not a real two-computer LAN/WAN playtest. Wi-Fi isolation, Windows firewall prompts, Tailscale access rules, multi-interface routing and internet latency still require hands-on testing. No server has been deployed or subscribed to on the user's behalf.
