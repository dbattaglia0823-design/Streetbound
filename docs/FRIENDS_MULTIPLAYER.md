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

## Low-latency free-roam synchronization

The game remains **player hosted** (no always-on game server) and retains the exact same 120 Hz vehicle physics for local and hosted drivers. Multiplayer protocol **v3** is required on both ends because the authoritative snapshot RPC now includes a sequence number; old v2 builds are refused at admission.

- **Local input prediction:** each participant drives immediately on their own machine. The client schedules changed controls at **60 Hz** (previously 30 Hz), and periodically resends held commands at **10 Hz**, safely inside the host's 450 ms stale-command brake. This reduces command batching without transmitting redundant packets sixty times a second when the player holds steady.
- **Authoritative snapshots:** the player-host simulates guest physics and sends sequenced world state at **30 Hz** (previously 15 Hz), using unreliable ordered ENet packets. Old/out-of-order snapshots are dropped instead of rolling back peers. Remote players' cars still cannot override the host's vehicle physics or economy.
- **Remote-car visuals:** clients buffer up to seven received snapshots and interpolate positions, headings, steering and velocity with an RTT-variance-informed **50–125 ms visual delay**. Missing packets trigger at most **60 ms** of velocity-based *visual* extrapolation; stale cars freeze rather than continuing to drive through scenery. This intentionally smooths other drivers while the local driver's controls remain immediate.
- **Client reconciliation:** the local client ignores small position errors (up to 20 game units), gently corrects medium errors at a frame-rate-independent rate, and immediately accepts major resyncs (>700 game units). The server stays authoritative.
- **Real connection indicator:** the in-game overlay reads actual ENet **RTT**, **RTT variation**, and **reliable-packet-loss** statistics for the connection. The hosting player sees the largest observed RTT among their connected guests; a guest sees their RTT to the host. **Reliable loss is not total UDP input/snapshot loss**, and RTT variation is not a precise one-way jitter measurement. Until ENet has samples, the overlay says *measuring*, not a fictitious 0 ms.

At 60 Hz, one input scheduling interval is ~16.7 ms (was ~33.3 ms). At 30 Hz, snapshots are spaced ~33.3 ms (was ~66.7 ms). These are **application update intervals, not internet ping or guaranteed latency reductions**. The number displayed in-game depends on route distance, Wi-Fi congestion, CPU stalls, buffering, and ISP/VPN routing.

### Getting the lowest practical ping

Use **wired Ethernet**, or a strong and uncongested 5/6 GHz Wi-Fi connection, on the local LAN for best results. Choose as host a player with low, stable RTT to the others and a responsive PC. For friends at another house using Tailscale, check `tailscale status` or `tailscale ping <friend-device>`: a **direct UDP** connection typically has lower latency than a DERP/peer relay. Tailscale documentation: [Connection types](https://tailscale.com/docs/reference/connection-types). Router forwarding is optional for a reachable direct public-IP host, but the in-game private invite remains mandatory.

CI test `tests/online_network_smoothing_test.gd` validates interpolation math, timestamp buffering, jump limits, stale freezing, angle wraparound, and transmission intervals. `tests/online_friend_connection_probe.gd` reads actual measured ENet RTT on a separate guest process. Real two-house RTT, packet loss under congestion, and perceptual smoothness need hands-on sessions; localhost CI does **not** establish zero ping or any promised cross-house RTT.

## Implementation and test coverage

- `scripts/network/online_session.gd`: host-owned roster, version handshake, validated invite admission, 4-player capacity, car model selections, and disconnect cleanup.
- `scripts/network/lan_discovery.gd`: opt-in UDP 28164 LAN discoverability. The client broadcasts a fixed discovery query, accepts bounded JSON replies only for the same game protocol, builds join addresses from actual packet-source IPs, and never uses an untrusted advertised IP for the ENet destination.
- `scripts/ui/title_menu.gd`: separate LAN host/browser/join page and existing private Direct Friends Invite page.
- `scripts/network/online_world.gd`: host-simulated guest vehicle physics using normal driving commands, state snapshots and interpolation. Competitive races, synchronized upgrades and vehicle-to-vehicle collision/damage are **not networked** yet.
- `tests/lan_discovery_probe.gd`: two separate actual Godot processes host and discover via UDP loopback, join using the session invitation and validate roster and cleanup.
- `tests/title_navigation_test.gd` and existing `tests/online_friend_connection_probe.gd` validate the game menus and private ENet admission. CI runs these under Godot 4.6.3, and the existing broader world/physics suite also tests 4.4.1.

**Testing boundaries:** A successful loopback test is not a real two-computer LAN/WAN playtest. Wi-Fi isolation, Windows firewall prompts, Tailscale access rules, multi-interface routing and internet latency still require hands-on testing. No server has been deployed or subscribed to on the user's behalf.
