# Online multiplayer — friends-first foundation

**Status:** Initial implementation on \`feature/friends-online-multiplayer-foundation\`. Godot/CI and a two-machine test must pass before treating it as usable multiplayer. This is *not* public matchmaking, an invite-code service or a completed competitive racing mode.

## How to test with a friend

1. Both players use the **same Streetbound build and game data**.
2. At the title screen open **Multiplayer → Play with Friends (Online)**.
3. One player chooses a driver name and **Host Friend Session**. The default is **UDP 28163**.
4. On the same network, other players enter the host's **local IP address** (and matching port), then **Join Friend Session**. For friends on different networks, the host must configure router **UDP port forwarding** and allow that UDP port in the local firewall. The host then shares their **public IP** and port. Some carrier-grade NAT / restrictive networks cannot accept incoming connections without a relay or VPN.
5. Up to **four total drivers** (one host and three guests) can drive simultaneously in the same Morrow Coast world. Host and guest players see each other's cars and driver names. Returning to the title menu closes the session.

The default loopback address \`127.0.0.1\` is only for connecting to a host on the **same computer**; it does not reach a friend's PC. Do not share a private LAN address with someone outside the LAN.

## Architecture

- \`scripts/network/online_session.gd\` is a persistent autoload. ENet hosts and joins, admission handshake checks a protocol version, the host owns the driver roster, and disconnections clean up player entries.
- \`scripts/network/online_world.gd\` exists only in the real gameplay world when a friend session is active. Its RPC path is identical across clients. The host runs guest car inputs through the existing \`VehicleController2D\` physics, rather than trusting client-submitted positions.
- Guest clients predict their own controls locally, receive host transforms at 15 Hz, and blend large errors; other players' cars are interpolated visual replicas. Controls transmit at 30 Hz. Remote vehicle input expires after 450 ms without packets.
- Basic vehicle identity is shared via verified catalog IDs; each remote instance uses its model's stock visual/physics configuration. Each player's actual garage ownership and upgrades stay local.
- Network car-to-car collision/damage is **disabled** to avoid unverified physics impulses. Both local solo driving and local split-screen remain separate.

## Limitations to address before a public release

- This direct-IP mode is **not access-controlled**: there are no accounts, passwords, invite tokens or matchmaking, and anyone able to reach the advertised UDP port can attempt to join. Use only with trusted friends, and close the port when not hosting. A true private invite-code experience requires an authenticated lobby, NAT traversal/relay and server-side access control.
- No host migration or automatic reconnection. The host leaving closes the session for everyone.
- Car physics use the host's stock catalog configuration for guests; non-stock upgrades can cause client prediction corrections. Synchronized garage builds, racing rules, checkpoint timing, bets, rewards, vehicle impacts and anti-cheat are **not yet implemented**.
- The world stream still prioritizes the local player; test remote driving near each other until multi-focus streaming is expanded.
- No cryptographic authentication/encryption is provided by this initial admission layer. Validate trust boundaries and infrastructure before internet release.
- Needs real two-to-four-computer LAN/WAN test of joins, timeouts, FPS, high ping, packet loss, disconnect/reconnect and effects on other game systems. Headless test coverage cannot establish visual smoothness or connectivity through home routers.

## Next milestones

1. Two-process end-to-end network test in CI and hands-on LAN test; fix any parse, transport or spawning failures.
2. Connection health UI (ping, packet-loss indicators, retry/timeout), client interpolation/prediction tuning, world streaming for all peers, and verified model/build synchronization.
3. Authenticated invite-only rooms with a relay/NAT traversal backend. Do not represent a locally generated join code as functional without its lookup service.
4. Shared meetups, waypoints, coordinated races with authoritative countdown/checkpoints/results, then optional shared traffic events.
