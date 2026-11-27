# Streetbound map-building asset library

Place PNG, WebP or SVG scenery anywhere inside this folder. Subfolders are scanned
recursively by both map editors; the browser needs **Start Map Editor.cmd** and
Godot needs the project to import new files. The legacy `assets/Buildings`
directory is also accepted to preserve existing scene references.

Recommended folders: `Buildings`, `Industrial`, `Roads and Infrastructure`,
`Construction`, `Commercial`, `Residential`, `Vegetation`,
and `Ground Decals`. Use subfolders freely. Prefer one transparent asset per image.

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

## Standalone artwork

Use individual PNG or WebP assets with transparent backgrounds. The six
previously supplied sprite sheets and their crop manifests have been removed.
Legacy sprite-region parsing remains available for compatibility, but the
shipped map-building library contains standalone artwork. If a local custom
map used a removed sheet, replace or delete those placed objects before baking.

## Editor and game behavior

- Use **Refresh folders** in the browser or **Refresh assets** in Godot to
  rescan immediately; both also check for changes periodically.
- Place, rotate and scale a sprite; its source path, optional legacy region, world size and
  collision choice are stored in the editable map source.
- **Save to Game / Apply to Game** validates the source image and region,
  rebakes collision and scenery, and saves the playable map.
- Restart a running game to see the rebuilt map.
- Do not rename or remove files already used by saved maps: path-based IDs
  are stable only while the source path (and any legacy sprite name) remains the same.
- The game must ship with all referenced image files; a reference alone does
  not embed their bytes in the playable world.
- Traffic artwork belongs in `assets/Vehicles/Traffic Vehicles/`, outside
  this scenery catalog.

Legacy `assets/Buildings` references remain supported while you migrate
existing maps. Avoid moving those originals until the placed references have
been updated; this change does not migrate already-saved paths.
