"""Strict asset/catalog coverage: every PNG has exactly one documented role."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class VehicleAssetCoverage(unittest.TestCase):
    def test_all_vehicle_pngs_have_one_role(self):
        catalog = []
        for name in ("player_vehicle_catalog", "player_vehicle_additions"):
            catalog += json.loads((ROOT / "data" / (name + ".json")).read_text(encoding="utf-8"))["vehicles"]
        excluded = json.loads((ROOT / "data/vehicle_asset_exclusions.json").read_text(encoding="utf-8"))["assets"]
        paths = [v["texture"].removeprefix("res://") for v in catalog]
        exclusions = [v["texture"].removeprefix("res://") for v in excluded]
        actual = {p.relative_to(ROOT).as_posix() for p in (ROOT / "assets/Vehicles").rglob("*.png")}
        self.assertEqual(len(paths + exclusions), len(set(paths + exclusions)))
        self.assertEqual(set(paths + exclusions), actual)
        self.assertEqual(len(catalog), len({v["id"] for v in catalog}))
        for row in excluded:
            self.assertIn(row["role"], ("traffic", "unidentified"))
            if row["role"] == "traffic":
                self.assertIn(row["texture"], (ROOT / "scripts/world/traffic_car.gd").read_text(encoding="utf-8"))
        self.assertTrue(all(v["id"] not in ["acura-tl","acura-tsx","acura-ilx","audi-a3","audi-a4","audi-a5","audi-a6","audi-a7","audi-a8","audi-q3","audi-q5","audi-q7","bentley-flying-spur","bentley-bentayga","bugatti-eb110","cadillac-ct4","cadillac-ct5","dodge-avenger","dodge-magnum","ferrari-308","ferrari-458-italia","ferrari-f8-tributo","ferrari-roma","ferrari-296-gtb"] for v in catalog))

if __name__ == "__main__":
    unittest.main()
