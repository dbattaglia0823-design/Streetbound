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

    def test_sprite_sheet_named_regions_and_grid(self):
        path = self.base / "Industrial" / "Pallets" / "cargo.png"
        fake_png(path, 256, 128)
        path.with_suffix(".sheet.json").write_text(json.dumps({
            "sprites": [
                {"name": "Pallet", "region": [0, 0, 128, 128]},
                {"name": "Crate", "region": [128, 0, 128, 128],
                 "worldSize": [2, 2]}]
        }), encoding="utf-8")
        entries = catalog(self.root)
        self.assertEqual(len(entries), 2)
        self.assertEqual([entry["name"] for entry in entries], ["Pallet", "Crate"])
        self.assertEqual(entries[1]["region"], [128, 0, 128, 128])
        self.assertEqual(entries[1]["id"], asset_id(entries[1]["path"] + "#Crate"))
        self.assertEqual(entries[1]["worldSize"], [2.0, 2.0])
        path.with_suffix(".sheet.json").write_text(
            json.dumps({"grid": {"width": 128, "height": 128}}), encoding="utf-8")
        self.assertEqual(len(catalog(self.root)), 2)

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

    def test_legacy_buildings_remain_available(self):
        path = self.root / "assets" / "Buildings" / "House.png"
        fake_png(path)
        entry = catalog(self.root)[0]
        self.assertEqual(entry["type"], "house")
        self.assertEqual(entry["id"], asset_id("Buildings/House.png"))

    def test_sprite_ids_use_original_manifest_names_and_keep_whole_sheet_references(self):
        path = self.base / 'Sprite Sheets' / 'cargo.png'
        fake_png(path)
        path.with_suffix('.sheet.json').write_text(json.dumps({'sprites':[
            {'name':'Cargo_Crate-A','region':[0,0,80,90]}]}))
        entry = catalog(self.root)[0]
        self.assertEqual(entry['id'], asset_id(entry['path']+'#Cargo_Crate-A'))
        self.assertEqual(entry['name'], 'Cargo Crate A')
        legacy = resolve_asset(entry['path'], asset_id(entry['path']), self.root)
        self.assertNotIn('region', legacy)
        self.assertEqual((legacy['width'], legacy['height']), (256,128))

    def test_supplied_sprite_sheets_have_named_regions_sizes_and_stable_ids(self):
        root = Path(__file__).resolve().parents[1]
        entries = [p for p in catalog(root) if '/Sprite Sheets/' in p['path']]
        self.assertEqual(len(entries), 271)
        self.assertEqual(len({p['path'] for p in entries}), 6)
        self.assertEqual(len({p['id'] for p in entries}), 271)
        for entry in entries:
            x,y,w,h = entry['region']
            self.assertTrue(0<=x<x+w<=1536 and 0<=y<y+h<=1024)
            self.assertTrue(all(0<v<=100 for v in entry['worldSize']))
            self.assertEqual(entry['id'], asset_id(entry['path']+'#'+entry['name']))
            if entry['type'] in ('oak','palm','bush','ground_decal'):
                self.assertEqual(entry['collision'], 'none')


if __name__ == "__main__":
    unittest.main()
