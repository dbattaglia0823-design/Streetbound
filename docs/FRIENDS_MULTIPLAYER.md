# Play with friends — temporary LAN and internet sessions

**No always-on game computer or deployed Streetbound service is required.** A player hosts while playing and their game becomes the session authority. When the host exits, the session ends. Up to four total drivers can play together in free roam on the bundled world or a published Map Builder world.

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

The protocol was **v6** for the Ashford circuit and is now **v7** with street sprints; older builds are intentionally rejected because they do not understand the authoritative event choice and circuit gate state. Remote friends still use the existing private invitation/LAN/Tailscale setup and need no permanent server. Circuit and drag modes share the same lobby/event controller, so only one event can run at a time. The Larkspur street sprint now has a narrow-road safe grid and route validation under v7 (see below).

Tests include `tests/online_friend_circuit_rules_test.gd` (closed-course gates, reverse crossings, skipped gates, safe 2–4-car width, v6 protocol) and `tests/online_friend_circuit_world_probe.gd` (actual two-process full-game circuit selection, authorized readiness, countdown, guest input release and host-only DNF results). Both are automated localhost checks; real cross-house playtesting and track fairness observations remain outstanding.

## Synchronized Larkspur street sprints (protocol v7)

The existing player-hosted friend lobby now supports the **actual Larkspur Street Sprint** as well as Ashford quarter-mile and full circuit. Drive to the Larkspur race start in a private LAN/direct/Tailscale session. The host offers a friend race; 1–3 friends who park at the marker can select **JOIN / READY**, then the host starts the shared 4.5-second countdown. Everyone remains in the same free-roam world with their own existing car.

Because Larkspur is a narrow directed public-street route, racers stage in a **single-file grid** along the real road centerline, separated by 9 m rather than occupying opposing lanes or sidewalks. The host validates every forward physical checkpoint crossing in order along the existing street navigation, including the actual finish. Jumping ahead to the finish, reversing, crossing a gate outside the 10 m radius, implausible position jumps, and leaving the marked route for 3 seconds cannot produce a valid finish. A 300-second limit assigns DNF to unfinished cars. Route/braking guidance and host-synchronized rankings are available to every driver.

This is still **practice only** until real-network result validation: no cash, XP, wagers, parts or career-save modifications. The separate single-player Larkspur sprint and authored racing HUDs remain disabled online, while all solo race progression is unchanged. Protocol **v7** rejects older builds that cannot understand the replicated street grid poses.

Automated coverage: `tests/online_friend_street_rules_test.gd` verifies the directional gates, shortcuts and narrow single-file start grid; `tests/online_friend_street_world_probe.gd` checks the full game with a host and guest over real loopback ENet. A **real two-house latency and fairness playtest** is still required before enabling persistent multiplayer career rewards.

## Shared friend-race progression and session rewards (protocol v8)

All synchronized race types (Ashford drag, full Ashford Circuit, Larkspur street sprint, and published Map Builder races) contribute to **one shared leaderboard for the current hosted session**. When every participating driver has either completed the host-verified physical route or received DNF, the host settles the race exactly once and sends the results and standings to every friend. Each validated finisher receives **10 / 7 / 5 / 3 friend race points** in finishing order (first through fourth). DNFs receive zero. The HUD shows the gained points and session standings; the host also tracks races, wins, podiums, DNFs and personal-best times per race type.

These points are **session-scoped rewards**, not spendable career currency. A race result is only eligible after the host's official validated finish, not from a client message or a race merely being started; duplicate results and repeat network messages cannot award the same run twice. The scoreboard follows authorized reconnects within the live hosting session. The host remains the authority; this does not add user accounts, backend rankings or an independent anti-cheat service.

**Introduced in protocol v10:** Cash, driver/car XP and upgrade-item prizes are now credited to the local career after a host-validated finish. See the persistent rewards section below. Wagers and permanent career event completion/achievements remain separate; friend session standings still reset when the host leaves.

Protocol **v8** introduced replicated session standings; **v9** additionally binds each race to its compiled map and event ID. Older clients must update. Automated `tests/online_friend_standings_test.gd` covers finish order points, repeated-result defense, DNF, session personal bests and rejection of invalid contestants; the existing two-process friend race regressions cover host/guest result replication.

## Any published Map Builder world (protocol v9)

Multiplayer no longer depends on launching the bundled Morrow Coast map. Publish a Map Builder world through the existing production publication process, include the published world in the **same Streetbound build on every computer**, then host or join through the existing LAN/private invitation menus. Every admitted player enters the selected published game world with the same multiplayer car physics, interpolated remote traffic, reconnect handling and temporary lobby.

**Map verification happens before a guest is admitted:** the host compares the selected world ID and SHA-256 digest of the **compiled world archive** with the client's supplied identity. A different published map, an older bake with the same name, or a mismatched set of mapped roads/races is rejected with a map-mismatch message. Protocol v9 is required on both computers. A full-file hash verifies identical packaged data; it is not an authenticated account/anti-cheat attestation.

**Published races are discovered automatically:** the shared race controller reads the already validated `editor_races` nodes on that world and registers each event by the Map Builder's stable `race-...` ID. It uses the author's start positions/formation, closed circuit or point-to-point/sprint navigation, physical direction-aware checkpoints, checkpoint radius, lap count, race time limit and title. 2–4 players join/ready at the physical start. The host owns all race movement, progress, official results and session-point awards. Multiple placed races can be chosen by driving near the desired starting marker; the selected ID is sent to every peer, never a guest-provided route. Existing Ashford/Larkspur events continue to work only on the original world.

A published map with **no race events** still supports online free roam. The Map Builder's development-only **Test Drive** remains local and is intentionally excluded from multiplayer. Maps must be **published and packaged into both installations**; this work does **not** stream or download unknown custom maps to friends, transfer draft files, or allow mid-session map switching. Every player must have the same build. For a changed map, publish a new build and start a fresh lobby.

**Session scoring across map replacements:** the shared 10/7/5/3 finish-point scoreboard remains temporary to the hosted session. Personal bests are distinguished by published world ID, archive hash and race ID, so different race courses cannot overwrite one another. Career cash, XP and item drops are now separately saved under protocol v10 and later; wagers, achievements and a long-term friend leaderboard are not implemented.

Automated coverage includes `tests/online_map_race_rules_test.gd` (map hash mismatch, authored circuits/sprints, starting grid, per-event results) and `tests/online_published_world_probe.gd` (two separate Godot processes in the fully published Map Builder world, joining the same ENet session and host-validating an authored sprint). These are localhost runs, not proof of same-house or different-house latency.

## Persistent cash, driver/car XP and garage parts (introduced in protocol v10)

**Friend races now pay career rewards after host-confirmed results.** In any private 2–4-player lobby, a validated finish of an Ashford drag, Ashford circuit, Larkspur sprint, or **published Map Builder** circuit/sprint earns the local driver **cash**, **driver XP**, **XP for the car they staged with**, and a chance at one actual garage upgrade part. The existing 10/7/5/3 session-points standings continue unchanged. Results and prizes are visible in the friend-race overlay; the normal balance, XP HUD and garage inventory update from the existing VehicleOwnership save model.

The standard first-to-fourth payouts are:

| Place | Drag cash | Driver XP | Car XP | Upgrade item chance |
|---|---:|---:|---:|---:|
| 1st | $1,800 | 780 | 560 | 100% |
| 2nd | $1,100 | 490 | 360 | 70% |
| 3rd | $700 | 310 | 220 | 40% |
| 4th | $400 | 190 | 130 | 20% |

For unmodified races, circuit rewards are multiplied by **1.25** and street sprint rewards by **1.10**, rounded to the nearest integer. Map authors can now explicitly override these defaults on a race-by-race basis; solo race rewards remain separate. Upgrade items use the existing race-category loot pool, seeded deterministically by the hosted run and raced car, with rarity limited by car level. If the player's inventory has reached the 2,500-item limit, no additional part is generated. Cash and XP still apply up to existing progression caps.

### Configuring Map Builder multiplayer prizes in the race editor

Open **Map Builder → select or place a race → Edit Race... → Multiplayer Rewards**, inside the same existing race settings window. The **Set Multiplayer Rewards...** button under Race Setup's solo reward fields opens that tab directly. Check **Use custom multiplayer prizes for this race** and set:

- **First-place cash:** $0–$20,000.
- **First-place driver XP:** 0–5,000.
- **First-place vehicle XP:** 0–5,000.
- **First-place upgrade drop chance:** 0–100%.

A live preview shows the **1st–4th place** cash, XP and part odds. The first-place amounts are exact; 2nd–4th scale individually using the existing finishing-position ratios. Part odds scale from the specified first-place chance using 70%, 40% and 20% for lower places. A zero amount disables that specific reward; a zero drop chance disables upgrade parts for that race.

**Unchecking the override leaves that race on the standard multiplayer payouts**, including existing published maps and Morrow Coast's built-in events. Existing solo rewards, career first-win bonuses and event unlock requirements are unchanged. Save Race Settings, then **Save to Game / publish** the edited map; distribute the **same compiled map build** to every participant. Players cannot edit prizes mid-session, and multiplayer money/XP uses locally validated map settings rather than guest-supplied RPC amounts. Invalid, non-integer, missing or out-of-cap custom prizes are rejected by the native editor, browser import and production world baker.

**Eligibility and duplicate protection:** The lobby host is still the sole authority for finish timing and every ordered directional checkpoint; clients cannot submit a winning result or a payout amount. Before settlement, **all** participants must be finished or DNF. Only finishers are rewarded; DNFs, forfeits, spectators, aborted races, and unfinished runs earn nothing. The host transmits one settled result to everyone, and each participant independently calculates their fixed rewards and atomically writes their own save. A distinct random 192-bit lobby ID and a monotonically increasing host race ID are saved in `multiplayer_claims`, so replicated result packets, reconnections and app restarts cannot pay the same run twice. A missing/invalid save fails closed, returning a visible error rather than silently granting a reward.

**Trust boundary:** This is a private, player-hosted game, **not a tamper-proof online economy**. A malicious host can falsify their own authoritative results, or players can edit their local save; the host cannot become an independently trusted anti-cheat referee without a dedicated trusted service and account identities. Play paid multiplayer with trusted friends. This feature does not provide a global leaderboard, authenticated accounts, wagers, currency exchange, or automatic map downloads.

**Delivery limits:** A guest must receive the host's final reliable results packet before leaving the session to save their prize. A disconnected guest who forfeits is DNF and receives no prize. A host closing the lobby before sending a completed result can prevent the guest receiving it; there is no backend mailbox or delayed offline claim system. Godot localhost tests do not substitute for real two-house playtesting.

Tests: `tests/online_friend_rewards_test.gd` verifies fixed caps, result eligibility, part drops, per-car XP, save/reload and replay protection. `tests/online_friend_rewards_world_probe.gd` launches two real Godot ENet processes with **separate user-data directories** in a published Map Builder world to exercise final result delivery and independent host/guest career saves. This test injects terminal records after real staging/countdown to isolate the payout path; the preexisting drag, circuit, and street tests validate physical finishes and shortcut checks.

## Low-latency free-roam synchronization

The game remains **player hosted** (no always-on game server) and retains the exact same 120 Hz vehicle physics for local and hosted drivers. Multiplayer protocol **v11** is required on both ends. Admission checks the exact compiled world archive SHA-256 and map ID in addition to the protocol, private invite and reconnect credential; an admitted friend also receives the unique lobby ID required for durable payouts. Older builds are refused.

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
- `scripts/network/online_world.gd`: host-simulated guest vehicle physics using normal driving commands, state snapshots and interpolation. Built-in and Map Builder-authored sprint/circuit races use host-authoritative `online_friend_race.gd`; synchronized upgrades and vehicle-to-vehicle collision/damage are **not networked** yet.
- `tests/lan_discovery_probe.gd`: two separate actual Godot processes host and discover via UDP loopback, join using the session invitation and validate roster and cleanup.
- `tests/title_navigation_test.gd` and existing `tests/online_friend_connection_probe.gd` validate the game menus and private ENet admission. CI runs these under Godot 4.6.3, and the existing broader world/physics suite also tests 4.4.1.

**Testing boundaries:** A successful loopback test is not a real two-computer LAN/WAN playtest. Wi-Fi isolation, Windows firewall prompts, Tailscale access rules, multi-interface routing and internet latency still require hands-on testing. No server has been deployed or subscribed to on the user's behalf.
