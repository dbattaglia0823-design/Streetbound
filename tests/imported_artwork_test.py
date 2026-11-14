"""Guard against stale image references and accidental procedural building fallback."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "scripts/world/coast_art.gd"
CATALOG = ROOT / "data/player_vehicle_catalog.json"


class ImportedArtworkTest(unittest.TestCase):
    def test_verified_vehicle_images_exist_and_legacy_names_are_not_reintroduced(self):
        data = json.loads(CATALOG.read_text(encoding="utf-8"))
        ids = set()
        for vehicle in data["vehicles"]:
            self.assertNotIn(vehicle["id"], ids)
            ids.add(vehicle["id"])
            path = vehicle["texture"]
            self.assertTrue(path.startswith("res://assets/Vehicles/"), path)
            if not vehicle.get("source_model_unverified", False):
                self.assertTrue((ROOT / path.removeprefix("res://")).is_file(), path)
                self.assertNotIn("ChatGPT Image", path)

    def test_default_buildings_use_current_png_library(self):
        source = ART.read_text(encoding="utf-8")
        block = source.split("const BUILDING_ART :=", 1)[1].split("static var textures:", 1)[0]
        paths = re.findall(r'"([^"]+\.png)"', block)
        self.assertGreater(len(paths), 20)
        for name in paths:
            self.assertTrue((ROOT / "assets/Buildings" / name).is_file(), name)
        self.assertIn('return project_sprite("Buildings/"+str(available[index]))', source)
        self.assertNotIn('"building": index = 3', source)


if __name__ == "__main__":
    unittest.main()
