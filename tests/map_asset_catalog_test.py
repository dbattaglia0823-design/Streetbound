"""Regression coverage for recursive map art, sprite metadata, and path security."""
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from project_asset_catalog import catalog, asset_id, building_file, resolve_asset


def fake_png(path, width=256, height=128):
    """The catalog only reads the 24-byte PNG header for dimensions."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 8 +
                     struct.pack(">II", width, height) + b"\x00" * 16)


class MapAssetCatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.base = self.root / "assets" / "Map Building Assets"

    def tearDown(self):
        self.tmp.cleanup()

    def test_recursive_categories_and_collision(self):
        path = self.base / "Industrial" / "Cargo" / "red_container.png"
        fake_png(path)
        path.with_suffix(".asset.json").write_text(
            json.dumps({"worldSize": [12, 2.5], "collision": "solid"}),
            encoding="utf-8")
        ground = self.base / "Ground Decals" / "Skid Marks" / "rubber.png"
        fake_png(ground)
        result = catalog(self.root)
        self.assertEqual(len(result), 2)
        by_type = {a["type"]: a for a in result}
        self.assertEqual(by_type["industrial_prop"]["worldSize"], [12.0, 2.5])
        self.assertEqual(by_type["industrial_prop"]["collision"], "solid")
        self.assertEqual(by_type["ground_decal"]["collision"], "none")
        item = by_type["industrial_prop"]
        self.assertEqual(resolve_asset(item["path"], item["id"], self.root), item)

    def test_retired_sheets_never_enter_catalog(self):
        path = self.base / "Industrial" / "cargo.png"
        fake_png(path)
        path.with_suffix(".sheet.json").write_text(json.dumps({"grid":{"width":128,"height":128}}))
        self.assertEqual(catalog(self.root), [])
        with self.assertRaises(ValueError):
            resolve_asset("Map Building Assets/Industrial/cargo.png", asset_id("Map Building Assets/Industrial/cargo.png"), self.root)

    def test_reject_invalid_regions_and_path_traversal(self):
        path = self.base / "Industrial" / "barrels.png"
        fake_png(path)
        sheet = path.with_suffix(".sheet.json")
        sheet.write_text(json.dumps({"sprites": [
            {"name": "Overflow", "region": [250, 0, 25, 30]}
        ]}), encoding="utf-8")
        self.assertEqual(catalog(self.root), [])
        for relative in ("../config.png", "Map Building Assets/../config.png",
                         "Map Building Assets//a.png", "Buildings/../../secret.png"):
            with self.assertRaises(ValueError):
                building_file(relative, self.root)

    def test_moved_filename_resolves_to_canonical_location(self):
        old = "Map Building Assets/Buildings/Corner Shop.png"
        new = self.base / "Commercial" / "Downtown" / "Corner Shop.png"
        fake_png(new)
        item = resolve_asset(old, asset_id(old), self.root)
        relative = new.relative_to(self.root / "assets").as_posix()
        self.assertEqual(item["path"], relative)
        self.assertEqual(item["id"], asset_id(relative))
        self.assertEqual(resolve_asset(relative, item["id"], self.root), item)
        # A direct path wins even when another file has the same basename.
        duplicate = self.base / "Other" / "Corner Shop.png"
        fake_png(duplicate)
        self.assertEqual(building_file(relative, self.root), new)
        with self.assertRaisesRegex(ValueError, "multiple exact filename matches"):
            building_file(old, self.root)
        new.unlink()
        duplicate.unlink()
        with self.assertRaisesRegex(ValueError, "no exact filename match"):
            building_file(old, self.root)

    def test_legacy_buildings_remain_available(self):
        path = self.root / "assets" / "Buildings" / "House.png"
        fake_png(path)
        entry = catalog(self.root)[0]
        self.assertEqual(entry["type"], "house")
        self.assertEqual(entry["id"], asset_id("Buildings/House.png"))

    def test_sheet_directory_is_excluded_even_without_manifest(self):
        path = self.base / "Sprite Sheets" / "cargo.png"
        fake_png(path)
        self.assertEqual(catalog(self.root), [])
        with self.assertRaises(ValueError):
            building_file("Map Building Assets/Sprite Sheets/cargo.png", self.root)

    def test_shipped_map_library_uses_standalone_art(self):
        root = Path(__file__).resolve().parents[1]
        base = root / 'assets' / 'Map Building Assets'
        removed = base / 'Sprite Sheets'
        self.assertFalse(any(p.is_file() for p in removed.rglob('*')))
        entries = catalog(root)
        self.assertTrue(any(p['path'].startswith('Map Building Assets/') for p in entries))
        self.assertFalse(any('/Sprite Sheets/' in p['path'] for p in entries))
        self.assertFalse(any(p.get('region') for p in entries))
        for path in (root / 'map-editor' / 'maps').glob('*.world.json'):
            doc = json.loads(path.read_text(encoding='utf-8'))
            for prop in doc.get('props', []):
                self.assertNotIn('/Sprite Sheets/', prop.get('assetPath', ''))
                self.assertFalse(prop.get('assetRegion'), f'{path.name}: {prop.get("id")} references a sheet')


if __name__ == "__main__":
    unittest.main()
