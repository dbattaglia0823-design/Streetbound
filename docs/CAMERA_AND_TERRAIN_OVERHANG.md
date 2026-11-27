# Camera mode snap and terrain overhang

Switching between north-up and heading-follow cameras now sets the destination rotation immediately (including from settings while paused), clears angular velocity and resets physics interpolation. Normal steering response, positional follow, manual zoom and speed zoom remain smooth.

Terrain polygons may be drawn, moved and resized outside the playable map, up to 24 km beyond each boundary. The width/height inspector and percentage resize controls preserve the full editable source polygon; undo/redo and saves retain its vertices. Runtime terrain chunks clip to the actual world edges; roads, props and gameplay markers still require in-bounds positions. Map size and playable limits are not increased. Browser source validation and Morrow/custom map compilation accept the same overhang. The existing Morrow stock terrain proxy remains unchanged for unedited legacy terrain.
