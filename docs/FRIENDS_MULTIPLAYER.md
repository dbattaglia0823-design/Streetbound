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
