# Friends-only online lobbies — first implementation

Status: developmental, see PR #176 and its CI. Invite-only means a host-generated secret **must** be presented to enter. It does **not** mean cloud matchmaking, user identity verification, automatic NAT traversal, or encrypted gameplay.

## Play with friends

1. All players run the same game version / map. From the title screen select **Multiplayer → Play with Friends (Online)**.
2. Host: set a driver name, a **reachable host IP or DNS name**, and a **UDP port** (default 28163), then choose **HOST FRIEND SESSION**. For tests on the same PC use \`127.0.0.1\`; on a local network use the host's LAN address; for internet play use the host's public IP or reachable DNS name.
3. In the game world, the host clicks **COPY INVITE**. The code contains the chosen host address, port and a fresh 192-bit random admission secret. Send that full code privately to friends; they don't need to type an IP or port separately.
4. A guest chooses a driver name, pastes the invitation into the title screen's invitation field, and selects **JOIN FRIEND SESSION**. Only clients presenting the current valid secret and compatible protocol version can join.
5. Up to four total drivers (one host plus three guests) share free-roam Morrow Coast. Host can click **LOCK LOBBY** to block further arrivals (without removing current friends), **UNLOCK LOBBY** to allow them again, or **NEW CODE** to revoke older invitations. Leaving the session/returning to title revokes that lobby's secret.

**Important network requirement:** This first implementation uses ENet over direct UDP. The host may have to forward the chosen UDP port on their router and allow that port through their firewall for friends outside their LAN. Carrier-grade NAT or restrictive networks may prevent connections entirely. Invite codes bundle connection details but do **not** route traffic around NAT or automatically expose the host. No public lobby directory or relay is deployed in this repository.

**Security limitation:** Invitation possession is the only admission factor; it is not tied to named accounts and the game packets/secret are not end-to-end encrypted. Only share codes with trusted people and avoid hosting on adversarial networks. Rotating a code prevents *future* joins using the old code; it does not kick already connected peers. A lobby lock prevents new joins, not existing sessions. UDP ports can be probed; unadmitted clients receive a rejection and are disconnected.

## Technical notes

- \`scripts/network/online_session.gd\` (autoloader) creates the private lobby using a Godot \`Crypto\` CSPRNG for a 192-bit hex secret. \`SB1-\` invitations are base64url-encoded JSON containing hostname, UDP port and token; the format is **encoding**, not encryption. Admission RPC validates version, name, capacity, lock state and secret on the **host** before adding a player to the roster. Invalid clients cannot create synced cars or send accepted driving inputs.
- \`scripts/network/online_world.gd\` uses host-simulated guest \`VehicleController2D\` physics from clamped commands, guest-side local prediction, 15 Hz state replication and interpolation. Networked remote collision/damage is disabled in this slice.
- \`scripts/ui/title_menu.gd\` hosts or joins using a pasteable invitation. The in-world host toolbar copies/rotates invitations and locks/unlocks the lobby. The pause menu does not pause the host's physics while friends are connected.
- User-specific careers, inventories and upgrades remain local; competitive races, host migration, vehicle collisions, authoritative economic rewards and match results are **not yet networked**.

## Validation

- \`tests/online_friend_session_test.gd\`: host-world smoke, real vehicle spawning, UI flows, invite generation/decoding/rotation, lock controls, pause isolation and cleanup.
- \`tests/online_friend_connection_probe.gd\`: runs separate Godot processes through a real ENet UDP loopback connection. A host shares its ephemeral private invitation with the guest via a temporary test file, which the host removes after testing. Verifies admission, roster, world readiness, model identity and disconnect. Missing/invalid invite paths are rejected.
- Tests are invoked in Godot 4.6.3 CI; broader world tests also execute with Godot 4.4.1. A green run verifies those precise cases only. Two physical computers, LAN/WAN firewalls, high ping/loss, and the full game still need hands-on playtesting.

## Future infrastructure

A seamless short-code experience with no IP/port forwarding requires a **deployed** lobby registration/discovery service and managed NAT traversal/relay (or server-authoritative dedicated game hosting). An external code lookup, user identity and TLS-backed authentication are not included. Do not advertise cloud invite codes or "works behind any router" until a real backend is configured, secured, deployed and tested.


---

## Hosted private rooms (new development milestone, not deployed by default)

Streetbound now contains an **optional headless dedicated-server mode** and short-code room directory. This removes port forwarding **for the players' home networks** when the *server operator* deploys a publicly reachable game machine.

**This code is not an already-running hosted service.** The game ships no public API URL. Without a service operator deploying the backend, use the original **Direct Friends Invite** mode.

### Player flow (after a server operator deploys the service)

1. Open **Multiplayer → Hosted Friend Rooms (Beta)**.
2. Enter a driver name and the operator's **HTTPS room directory URL** (the app remembers this URL). A friend creating a lobby chooses **Create Private Room**.
3. The directory starts a fresh **authoritative Godot room process** and returns a random, unlisted **12-character code**. The creator connects as a normal player; no one runs a UDP server on their own PC.
4. In-world, the creator clicks **Copy Room Code** and shares that code privately with friends.
5. Each friend opens the same Hosted Rooms page, enters the service URL and code, and selects **Join With Room Code**. The directory resolves the code to the publicly reachable game server and a random per-room ENet admission secret.
6. All players connect **outbound** over UDP to the game server. Up to **four human players** can participate; the dedicated server is not counted as a driver. The room expires after two hours, and the creator leaving requests server shutdown (disconnecting the remaining guests).

The original host-as-player ENet **Direct Friends Invite** flow remains available. Hosted room codes are **not** interchangeable with the earlier \`SB1-\` direct invitations.

### Operator deployment

The directory is Python standard library only (\`tools/hosted_rooms.py\`), binds to **127.0.0.1:8090**, starts one isolated headless Godot process per room (\`tools/hosted_room.gd\`), and provides:

| Endpoint | Behavior |
| --- | --- |
| \`POST /rooms\` | Allocate a bounded dedicated room; return code, owner token, server endpoint and admission secret |
| \`GET /rooms/{CODE}\` | Resolve a private bearer code to the room's server address, UDP port and secret |
| \`DELETE /rooms/{CODE}\` | Owner-only shutdown using \`X-Room-Owner\` credential |
| \`GET /health\` | No-credential health check |

Example on a **test VM** with Godot 4.6.3 and the entire imported Streetbound project already installed:

\`\`\`sh
export STREETBOUND_PUBLIC_GAME_HOST=games.example.com
export STREETBOUND_GODOT=/usr/local/bin/godot
export STREETBOUND_GAME_ROOT=/srv/streetbound
export STREETBOUND_API_PORT=8090
export STREETBOUND_PORT_START=28200
export STREETBOUND_PORT_END=28207
export STREETBOUND_MAX_ROOMS=4
python3 tools/hosted_rooms.py
\`\`\`

- Put the loopback HTTP API **behind an HTTPS reverse proxy** (e.g. a TLS-enabled proxy for \`rooms.example.com\` to \`127.0.0.1:8090\`). HTTPS is enforced by the game's client, except when talking to **127.0.0.1/localhost** for local development. Never expose 8090 publicly.
- Open **UDP 28200–28207** on the public game server's firewall, and **TCP 443** for HTTPS; keep HTTP 8090 bound to loopback. Game clients do not forward UDP themselves.
- Ensure the server has sufficient CPU/RAM/storage for up to four isolated Godot worlds and that Godot imports assets once before serving rooms. The room directory uses distinct ephemeral working/data directories per room, and signals readiness only after the Morrow Coast gameplay scene initializes.
- The default cap is four concurrent rooms, room creation is rate-limited per source address (30 seconds) and each room expires after two hours; processes are terminated/reaped on expiry or close. Start/restart of the directory does not recover rooms.
- **Do not put this provisioning endpoint directly on the open internet.** There is *no user account/authenticated room creation, distributed rate limiting, billing quotas or DDoS protection*. Anyone who can reach \`POST /rooms\` can consume the bounded capacity; require upstream identity verification/abuse controls before a real public launch. Do not insert an administrator key into distributed game builds.

### Security and functionality boundaries

The short code itself is a bearer secret. Looking it up returns the ENet admission key to anyone with the code; TLS protects this during lookup. ENet gameplay packets remain unencrypted, and malicious networks may still disrupt traffic. The dedicated Godot server owns movement authority rather than trusting remote position RPCs, but competitive anti-cheat, save isolation auditing, authoritative shared races, synchronized upgrades, grief prevention and account identities are still unfinished. This does not guarantee functioning service from locked-down client networks where outbound UDP is blocked.

**Tests:** \`python3 -m unittest discover -s tests -p hosted_room_directory_test.py -v\`, plus Godot 4.6.3 \`tests/hosted_room_smoke_test.gd\`. Passing these local tests is not proof that a public deployment has been performed or that real WAN gameplay latency is acceptable.
