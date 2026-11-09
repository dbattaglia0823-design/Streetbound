# Urban sidewalks, coastline boardwalk, and connected tire marks

## City streets

Both sides of every Morrow Coast `local` and `arterial` road now draw
continuous 3.3m concrete sidewalks outside the asphalt edge. The same
road centerline is used for both sidewalk offsets, with bounded miter
joins so bends cannot turn into disconnected straight rectangles.

Each junction already includes rounded outside curb-fillets from the
authored intersection baker. The renderer uses those fillets as rounded
sidewalk corner aprons, then masks them with the junction asphalt so
vehicle approaches and pedestrian crossing stripes remain open. Continuous
inner curb highlights and edge joints complete the layout.

The urban sidewalk surface is now firm (ASPHALT with 0.93 grip) instead
of being treated as grass when a vehicle pulls onto it. No new collision
barriers block cars or lanes; the existing street widths and driving
controller are otherwise unchanged.

## Beach boardwalk

The Morrow Coast ocean polygon contains the exact authored shoreline.
At runtime we derive the boardwalk path along the populated coastal beach
segment, inset by 35m into the 65m sandy beach. This keeps the walkway
attached to the actual curving coast rather than using an arbitrary
rectangle or a disconnected row of planks. The 5.6m deck has timber
planking, warm trim, seaward railing and regularly spaced posts.

Boardwalk geometry is clipped to each streamed 192m chunk with an 8m
overdraw band, preventing gaps as the player drives near a chunk border.
Planking intervals are based on global Y so the board seams retain
consistent spacing when neighboring chunks load.

The boardwalk is scenery/crossable terrain rather than a new pedestrian
navigation system; no on-foot character or boardwalk interaction exists
yet. Roads continue to draw above the boardwalk at any shared crossing.

## Continuous skid tracks

Replaced fixed 6x18 tire-stamp quads with a fixed-capacity MultiMesh
containing 6px-wide stretched strips connecting successive wheel sample
positions. Each rear wheel stores its own previous sample. A small
overlap removes hairline gaps around bends. Tracks restart when the
vehicle stops skidding, resets/teleports, changes surface, or jumps
more than 220px between samples. Dirt/grass tracks have a brown color,
road tracks are dark, and the original 1800-instance bounded GPU pool
is retained. There is no persistent node per sample and no full-scene
redraw each frame.

## Verification

Run `tests/urban_walkways_boardwalk_test.gd` and
`tests/continuous_tire_marks_test.gd` with Godot 4.4.1, alongside all
the existing road geometry, junction, handling, and streamed-world tests.
Visually check the city T-junctions and four-way intersections, tight
street bends, seaside promenade and long on-road/grass drifts. The
automated suite proves geometry behavior but not final visual polish.

Reference: https://docs.godotengine.org/en/4.4/classes/class_geometry2d.html
