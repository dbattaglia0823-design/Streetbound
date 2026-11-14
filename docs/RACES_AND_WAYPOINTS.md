# Races and player waypoints

Open the atlas with **Tab** or by clicking the minimap. All seven playable
events have cyan race flags on the atlas and minimap. Choose a race in the
sidebar, or click its flag, to set a road route to its actual start circle.

| New event | Route | Approximate distance |
| --- | --- | --- |
| Juniper Ascent | Juniper Approach through the mountain hairpins to Summit Ribbon | 1.9 mi |
| Coastline Dash | Bellwether waterfront to the northern scenic highway | 1.2 mi |
| Harvest Run | Meadow Road through the Willowmere countryside to Harvest Road | 1.2 mi |
| Parkway Express | Northern Morrow Parkway around to the eastern highway | 1.8 mi |

These four events use the existing street-practice 1v1 rules: a physical rival
uses the player's equipped car configuration, traffic stays active, and the
whole course must be driven. They do not award cash or XP. Existing Ashford
drag rewards and circuit/street practice rules are preserved.

Stop inside the visible start circle, face along the course, and press **F**.
Wait for the three-second countdown. False starts, route shortcuts and
finish-line teleports invalidate a run. Only one event can run at a time;
after results clear, the event can be replayed.

Click anywhere on the atlas to set a personal waypoint. Selecting a place
uses its road access point; selecting a race uses its start. The amber GPS
route appears on the atlas, minimap and nearby road, with remaining distance.
It recalculates after leaving the route and clears on arrival. For off-road
destinations the route stops at the nearest reachable road and the map says
that the destination is off-road. Disconnected destinations retain their pin
and show that no road route is available.

Drag to pan without changing the waypoint. Right-click the map or choose
**Clear waypoint** to remove it. **Close [Tab]** returns to driving. GPS guidance
pauses during an event so the active race's cyan/braking guidance stays clear.

Event definitions live in `resources/races/`. They select named road pieces
and positions along them. The route planner follows the current loaded road
graph, so saved road edits generate updated event routes on the next world load.
