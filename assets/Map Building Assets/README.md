# Streetbound map asset library

Place **map creation artwork** in this directory. Subfolders are your categories;
the browser and native Godot map editors scan them recursively, including after
you add or replace an image. Keep traffic sprites under `assets/vehicles/Traffic Vehicles/`.

Examples:

```
assets/Map Building Assets/
  Buildings/
  Industrial/
    Shipping Containers/
    Pallets and Crates/
    Dumpsters and Bins/
    Equipment/
  Roads and Infrastructure/
  Construction/
  Commercial/
  Residential/
  Vegetation/
  Ground Decals/
  Sprite Sheets/
```

Use transparent PNG (preferred) or WebP, or SVG for vector artwork. **One image
with no sidecar is one selectable object.** Filename becomes its name; its top
folder becomes its category. The editor can also import individual frames from
a sprite sheet if the source image has a neighboring JSON file:

```
Industrial/Pallets and Crates/cargo.png
Industrial/Pallets and Crates/cargo.sprites.json
```

Example manifest (pixel coordinates in the original, full-resolution image):

```json
{
  "sprites": [
    {
      "key": "empty-pallet",
      "name": "Empty wooden pallet",
      "rect": [0, 0, 256, 256],
      "type": "prop",
      "collision": "solid",
      "size": [1.4, 1.2]
    },
    {
      "key": "oil-stain",
      "name": "Oil stain",
      "rect": [256, 0, 256, 256],
      "type": "decal",
      "collision": "none",
      "size": [2.8, 2.8]
    }
  ]
}
```

`key` must be unique (letters, numbers, underscore, hyphen; 1–50 characters)
and must not change once a sprite has been placed. Sprite-sheet frames may
have different dimensions and positions. The region must lie entirely inside
the image. Change or remove a sprite cautiously: placed map assets retain
their identifiers and region references, and Save to Game refuses invalid or
missing source artwork.

For uniform sheets, an alternative sidecar defines a grid:

```json
{ "grid": { "columns": 4, "rows": 2, "names": ["Pallet", "Crate", "Barrel"] } }
```

Columns and rows must divide the image dimensions evenly; omitted names become
numbered frames. Do not include both `grid` and `sprites`. Grid IDs are the
1-based frame numbers; keep ordering stable for maps already using the sheet.

A `sprites.json` file may also specify default `type`, `category`,
`collision`, and `size` at its top level. Folder and filename give initial
defaults, **not visual recognition**. Use `type: "prop"` for solid general
scenery, `type: "decal"` for painted ground details, or compatible legacy
scenery types (house, building, warehouse, garage, bush, etc.). Collision
`"solid"` produces a world footprint; `"none"` creates decoration.
Dimensions are metres in the playable map. Other size and collision changes
must be made in the manifest; decorative objects should use none.

## Visual sprite-sheet tool

In the **browser Map Builder**, click **Sprite sheets** in the asset browser to
open the sprite region tool. Open the image, drag rectangles or choose grid /
automatic transparent-object detection, adjust the regions, then export the
`<image-stem>.sprites.json` file **beside the image**. The tool cannot
silently save files into the checkout. Review alpha detections: disconnected
art pieces may need one manually drawn region.

## Keeping existing artwork working

Existing `assets/Buildings/` artwork is still recognized for old placed maps
and procedural building appearances. Do not rename/move it without updating
saved references. Likewise, traffic artwork falls back to the former
`assets/Traffic Vehicles/` path if necessary.

For the real game, **Save to Game** rebuilds production scenery and collision.
Preview changes alone do not rewrite world data. A running gameplay session
must be restarted or its world explicitly reloaded after the bake.
