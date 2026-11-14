"""Regression coverage for categorized project props and sprite-sheet rebakes."""
import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from project_asset_catalog import asset_id, building_file, catalog, validated_asset
import morrow_editor_import as importer


def png_header(width=512, height=256):
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\x08\x06\x00\x00\x00" + b"\x00" * 8


class MapLibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        folder = self.root / "assets/Map Building Assets/Industrial/Shipping Containers"
        folder.mkdir(parents=True)
        (self.root / "assets/Buildings").mkdir(parents=True)
        self.image = folder / "containers.png"
        self.image.write_bytes(png_header())
        self.relative = self.image.relative_to(self.root / "assets").as_posix()

    def test_recursive_scan_and_legacy_identity(self):
        legacy = self.root / "assets/Buildings/House.png"
        legacy.write_bytes(png_header())
        items = catalog(self.root)
        self.assertEqual({a["path"] for a in items},
                         {self.relative, "Buildings/House.png"})
        cargo = next(a for a in items if a["path"] == self.relative)
        self.assertEqual(cargo["type"], "prop")
        self.assertEqual(cargo["category"], "Industrial")
        self.assertEqual(cargo["collision"], "solid")
        self.assertEqual(cargo["id"], asset_id(self.relative))
        self.assertEqual(cargo["size"], [5.2, 2.6])  # retain 2:1 source aspect within 12 × 2.6 m
        self.assertEqual(asset_id("Buildings/House.png"),
                         "project-" + hashlib.sha256(b"Buildings/House.png").hexdigest()[:24])

    def test_legacy_building_reference_survives_folder_migration(self):
        moved = self.root / "assets/Map Building Assets/Buildings/Dealerships/01_showroom.png"
        moved.parent.mkdir(parents=True)
        moved.write_bytes(png_header())
        legacy = "Buildings/Dealerships/01_showroom.png"
        self.assertEqual(building_file(legacy, self.root), moved)
        entry = validated_asset(legacy, asset_id(legacy), self.root)
        self.assertEqual(entry["id"], asset_id(legacy))
        self.assertEqual(entry["path"], legacy)
        self.assertEqual(entry["type"], "building")

    def test_explicit_crops_preserve_ids_and_collision_modes(self):
        sidecar = self.image.with_name("containers.sprites.json")
        sidecar.write_text(json.dumps({"sprites": [
            {"key": "red", "name": "Red container", "rect": [0, 0, 256, 256]},
            {"key": "paint", "name": "Oil stain", "rect": [256, 0, 256, 256],
             "type": "decal", "collision": "none", "size": [2, 2]}
        ]}))
        entries = catalog(self.root)
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["id"], asset_id(self.relative, "red"))
        self.assertEqual(entries[0]["region"], [0, 0, 256, 256])
        self.assertEqual(entries[1]["type"], "decal")
        self.assertEqual(entries[1]["collision"], "none")
        self.assertEqual(entries[1]["size"], [2, 2])
        self.assertEqual(validated_asset(self.relative, entries[1]["id"], self.root), entries[1])
        with self.assertRaises(ValueError):
            validated_asset(self.relative, asset_id(self.relative, "missing"), self.root)

        def prop(entry, name):
            return {"id": "prop-" + name, "x": 700, "y": 800, "rotation": 0,
                    "scale": 1, "type": entry["type"], "assetId": entry["id"],
                    "assetPath": entry["path"], "assetRegion": entry.get("region"),
                    "assetSprite": entry.get("sprite"), "assetSize": entry["size"],
                    "assetCollision": entry["collision"]}

        with patch.object(importer, "ROOT", self.root):
            rendered = importer._authoring_props({"props": [prop(entries[0], "one"), prop(entries[1], "two")]})
            self.assertTrue(rendered[0]["solid"])
            self.assertFalse(rendered[1]["solid"])
            self.assertEqual(rendered[1]["radius"], 0)
            self.assertEqual(rendered[0]["asset_region"], [0, 0, 256, 256])
            with self.assertRaises(ValueError):
                importer._authoring_props({"props": [{**prop(entries[0], "one"),
                                                        "assetRegion": [2, 0, 256, 256]}]})

    def test_uniform_grids_and_invalid_references(self):
        sidecar = self.image.with_name("containers.sprites.json")
        sidecar.write_text(json.dumps({"grid": {"columns": 2, "rows": 1,
                                               "names": ["Red", "Blue"]}}))
        items = catalog(self.root)
        self.assertEqual([x["sprite"] for x in items], ["1", "2"])
        self.assertEqual(items[1]["region"], [256, 0, 256, 256])
        for path in ("../private.png", "Map Building Assets/../private.png",
                     "Map Building Assets/Industrial/../../private.png", "vehicles/car.png"):
            with self.assertRaises(ValueError):
                building_file(path, self.root)

    def test_invalid_sheet_excluded_without_hiding_good_images(self):
        sidecar = self.image.with_name("containers.sprites.json")
        sidecar.write_text(json.dumps({"sprites": [
            {"key": "bad", "rect": [999, 0, 500, 500]}
        ]}))
        good = self.root / "assets/Buildings/House.png"
        good.write_bytes(png_header())
        self.assertEqual([i["path"] for i in catalog(self.root)], ["Buildings/House.png"])
        with self.assertRaises(ValueError):
            validated_asset(self.relative, asset_id(self.relative, "bad"), self.root)


if __name__ == "__main__":
    unittest.main()
