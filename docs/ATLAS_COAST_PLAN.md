# Atlas Coast — Grand Touring Open World

**Editable master map:** [atlas-coast.world.json](atlas-coast.world.json)  
**Scalable overview:** [atlas-coast-overview.svg](atlas-coast-overview.svg)  
**Open in World Forge:** [World Forge](index.html) → **Atlas Coast map** (top toolbar) or **New world → Open large world**.

This is an original 22,000 × 18,000-unit, continuous-coordinate, top-down **level layout**, not a finished game or final art pack. It is deliberately built for replacement with cozy illustrated top-down assets without cast shadows. World units are authoring units and are not automatically meters.

**Organic city revision:** The initial straight, repetitive city streets have been redesigned into **62 irregular and curved urban routes** across Avalon, Westhaven, Seabright, Summit Village, and South Harbor. Streets now include crescents, offset intersections, nonlinear branches, shorter residential roads and diagonally sloped port approaches. Atlas Coast's roadside structures have been moved off road surfaces and oriented using each road's local tangent; garages, dealerships, and fuel stop markers were also moved off the lanes where necessary. All authored race starts and traffic path markers remain attached to the roadway.

**Placement behavior:** World Forge now checks a conservative bound around the entire sprite, including road shoulders. Buildings and lots snap to nearby road edges and face the road; landscape props remain freeform outside road bounds. The new **Fix all road overlaps** command offers explicit repairs for older/imported worlds. This does not replace detailed physics/collision geometry, production road-junction validation or guaranteed driveway access.

## Regional layout

| Region | Approximate placement | Content and intended gameplay |
| --- | --- | --- |
| Ironcap Highlands | NW x 0–7k, y 0–6k | Hairpin mountain pass, off-road switchbacks, reservoir, rock peaks, hillclimb |
| Cloudpine Forest | North x 6–14k, y 0–6k | Pine forest, rural roads, Summit Village and long scenic drives |
| Seacliff Coast | NE x 14–20k, y 0–7k | Coastal cliffs, Seacliff GP circuit, airport/logistics zone and race garage |
| Westhaven & farm valley | West x 0–7k, y 6–13k | Starter town, starter garage/dealer, farmland, fuel stations, dirt oval |
| Avalon Metropolitan Area | Center x 7–15k, y 5.5–13k | Largest city, highway ring, downtown grid, several car dealers and workshops |
| Seabright Bay | East x 14–20k, y 7–13k | Beach town, luxury dealer, oceanfront boulevard, marina and gas stations |
| Wildwood & Redstone Canyon | SW x 0–7k, y 12–18k | Rally track, dirt/gravel driving and 4×4 showroom |
| Motor Valley | South x 7–14k, y 13–18k | Main GP circuit, drag strip, paddocks and race-car dealership |
| South Harbor | SE x 14–20k, y 12–18k | Industrial waterfront, docks, cargo streets and street racing circuit |
| Open ocean | Eastern coast near x 20–22k | Beach/ocean backdrop and reserve for future waterfront content |

The player begins at Westhaven Home Garage, can travel to Avalon for tuning, and unlock scenic mountain routes and higher-class circuits while exploring the coastline.

## Infrastructure

- **132 roads:** multi-lane highways, city streets, rural lanes, service roads, country curves, mountain passes, dirt and gravel tracks. The main routes are Meridian Cross-State Expressway, Pacific Coast Freeway, Northern Ridge Expressway, Western Scenic Interstate, South County Turnpike, and the Avalon Metropolitan Ring Road.
- **7 planned race venues:** Seacliff Grand Prix, Motor Valley Grand Prix, Wildwood Forest Rally, Silver Quarry Dirt Oval, South Bay Waterfront Street Championship, Motor Valley Drag Nights, and Ironcap Mountain Hillclimb. Every venue has start, finish, and checkpoint markers linked to a real authored road ID, plus a race paddock/garage marker.
- **11 dealerships** with editable class and specialty metadata: Westhaven Starter Autos (D/C), Summit Classics & Imports (C/B/A), Avalon General Motors (D/C/B), Avalon Performance Exchange (B/A), Avalon Hypercar Gallery (A/S), Seabright Luxury Collection (B/A/S), Seacliff Track Specials (A/S), Wildwood 4x4 Outfitters (D/C/B), Motor Valley Raceworks Dealer (B/A/S), South Harbor Commercial Auto (C/B), and Avalon Classic Garage Sales (C/B/A).
- **18 fuel stops** spread through cities, highways, mountains, coast, motorsport grounds and rural areas.
- **18 garage markers** including home garages, tuning shops, race paddocks and industrial workshops.
- **32 terrain zones**, **2,079 scene props**, **136 gameplay/landmark markers**, fast-travel hubs and traffic spawn positions.

The map includes buildings, parking areas and service-location placeholders next to selected points of interest. Dealership inventory, fuel purchases, car storage, race completion, traffic, and checkpoint activation still need game logic to make those markers interactive.

**Automatically rendered intersections:** World Forge now creates paved junction surfaces wherever crossing road centerlines or overlapping T/endpoint approaches meet, with street markings interrupted through the junction and urban stop bars. Atlas Coast's entire 132-road network participates, with no 50-road visualization limit. Junctions are computed from road geometry and regenerated whenever it changes; the Godot adapter and exported navigation JSON include the connection data. This is an **at-grade assumption** and should be replaced by authored overpasses, ramps, traffic lights, and legal-turn rules for complex freeway interchanges.

## Asset replacement handoff

1. **Verify world scale with a driveable car.** Road widths and world units are authoring coordinates; calibrate them against the car sprite, camera and road grip. Track and circuit widths are not yet playtested.
2. **Lock geography and the major road network first.** Use the Road Geometry inspector to move, insert, or extend road points. Validate interchanges and track loop continuity. The exported road centerlines and intersection hints are not a complete traffic routing system.
3. **Replace hub artwork first:** garage facades, showroom buildings, race paddocks, fuel pumps, parking and important waterfront facilities. Use original or properly licensed, transparent, shadow-free top-down sprites.
4. **Replace environmental scenery by sector:** soft rounded pine/oak forests, rock cliffs and switchbacks, city blocks, suburbs, agriculture, beaches, palms, harbors and docks. The 2,079 props are a density/layout starting point, not production-quality placement.
5. **Implement traffic and racing systems:** lane-based routing, signals, intersections, car AI, start/finish triggers, waypoint order, car classes, fuel, upgrades, inventory and persistent owned vehicles.
6. **Chunk large-world rendering and collision.** A 22k × 18k world should not keep all scenery and building collision bodies active around the player at once; use camera-aware streaming and LOD for the final game.
7. **Export portable files.** Use World Forge's Export JSON after changes and Godot 4 ZIP when ready to integrate. Preserve backups outside browser storage.

## File format and limitations

The editable master uses the existing **gdt.racing-world v2** schema and is fully freeform, without tile maps or grid coordinates. It can be imported, edited and exported through World Forge. Marker metadata is descriptive, not self-executing game content. Elevation remains metadata rather than a 3D mesh. There is no complete traffic AI, game economy, race timing, fully implemented production collision, city simulation, external artwork licensing, or world streaming in this layout file. The SVG is a schematic geography overview, not a final in-game texture.
