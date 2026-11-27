# Southgate and Southpoint — first content expansion draft

A separate editable Morrow source extends the southern boundary to 6.4 km. This is not a replacement for the existing shipped archive. The original source remains unchanged.

The draft adds 16 roads, 5 terrain parcels, 82 scenery objects, 8 markers and 3 linked time trials. Southgate contains housing, market frontage, parks, industrial warehouses, a garage/home, fuel stop, delivery contact with two legal jobs and a reputation-gated fictional robbery, and a reserved showroom site. South Morrow Parkway connects South County Road to the eastern coast, with a rural loop and bypass. Existing roads retain stable IDs. The showroom is a placeholder pending actual dealership stock placement. The existing stock robbery tiers remain unchanged; the added draft robbery uses the existing authored-job system. The eastern parkway connects at the exact existing South Coastal Link control point.

Compile in isolation:
```sh
python3 tools/build_morrow_coast.py --overlay map-editor/maps/morrow-coast.southgate-draft.world.json --output-dir /tmp/streetbound-southgate
```
Inspect warnings, compare source and archive, test physical traffic, routes, marker access, camera and collision before adopting the draft. Do not copy the source JSON over the production archive. The isolated compiler never activates a draft; do not ship it until verified.

Separate runtime changes: use existing named fuel/garage POI aprons where a marker is missing and road access is valid. Adjust low-heat police requests without changing high-tier caps or car dynamics. Increase first-win street rewards (not recurring rewards); soften audio shift/limiter recovery. All remain pending regression and live playtest. No measured claims about balance, vehicle progression, audio or FPS.
