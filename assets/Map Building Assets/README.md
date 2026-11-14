# Streetbound map-building asset library

Place PNG, WebP or SVG scenery anywhere inside this folder. Subfolders are scanned
recursively by both map editors; the browser needs **Start Map Editor.cmd** and
Godot needs the project to import new files. The legacy `assets/Buildings`
directory is also accepted to preserve existing scene references.

Recommended folders: `Buildings`, `Industrial`, `Roads and Infrastructure`,
`Construction`, `Commercial`, `Residential`, `Vegetation`,
`Ground Decals`, and `Sprite Sheets`. Use subfolders freely.

## Single-sprite metadata (optional)

Next to `Industrial/Shipping Containers/red.png`, create
`Industrial/Shipping Containers/red.asset.json`:

```json
{
  "name": "Weathered red container",
  "type": "industrial_prop",
  "collision": "solid",
  "worldSize": [12, 2.5]
}
```

`worldSize` is the object's width and height in **world metres**, not pixels.
`collision` is `solid` or `none`. Decals default to no collision;
other props default to solid. Type can be `house`, `building`, `warehouse`,
`garage`, `gas_station`, `industrial_prop`, `road_prop` or `ground_decal`.
Without metadata, the folder and filename supply the category and default
footprint. Use metadata for exact dimensions and categorization.

## Sprite sheets

A sheet is **one image**, with regions defined by a sidecar manifest. For
`Industrial/Cargo/props.png`, add `Industrial/Cargo/props.sheet.json`:

```json
{
  "sprites": [
    {"name": "Pallet", "region": [0, 0, 128, 128], "worldSize": [1.2, 1]},
    {"name": "Crate", "region": [128, 0, 128, 128], "worldSize": [1, 1]},
    {"name": "Oil stain", "region": [256, 0, 128, 128],
     "type": "ground_decal", "collision": "none", "worldSize": [2, 2]}
  ]
}
```

Regions are `[x, y, width, height]` in **image pixels**, measured from the
top-left. Every sprite needs a unique name; regions must stay within the
image. The editor lists each one as an individually placeable asset. The game
renders only its region of the sheet rather than the full image.

For uniform tile sheets, use a grid manifest instead:

```json
{"grid": {"width": 128, "height": 128}}
```

This creates one entry per complete cell (up to 512); use named regions for
irregular artwork. The system does **not** infer object outlines from image
content. For manually arranged or AI-generated sheets, prepare a manifest
and remove background pixels for correct transparency.

## Editor and game behavior

- Use **Refresh folders** in the browser or **Refresh assets** in Godot to
  rescan immediately; both also check for changes periodically.
- Place, rotate and scale a sprite; its source path, region, world size and
  collision choice are stored in the editable map source.
- **Save to Game / Apply to Game** validates the source image and region,
  rebakes collision and scenery, and saves the playable map.
- Restart a running game to see the rebuilt map.
- Do not rename or remove files already used by saved maps: path-based IDs
  are stable only while the source path and sheet sprite name remain the same.
- The game must ship with all referenced image files; a reference alone does
  not embed their bytes in the playable world.
- Traffic artwork belongs in `assets/vehicles/Traffic Vehicles/`, outside
  this scenery catalog.

Legacy `assets/Buildings` references remain supported while you migrate
existing maps. Avoid moving those originals until the placed references have
been updated; this change does not migrate already-saved paths.
