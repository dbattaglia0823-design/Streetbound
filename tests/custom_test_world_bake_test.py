"""Custom Test Drive uses the production junction baker without touching Morrow Coast."""
import json
import pathlib
import sys
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_custom_test_world import make_archive,build_file


def source():
    return {
        "format":"gdt.racing-world","version":2,"customMap":True,
        "name":"Test Junctions","world":{"width":1200,"height":1000,"base":"grass","seed":1847},
        "roads":[
            {"id":"road-0","name":"East West","roadClass":"city","surface":"asphalt",
             "width":12,"lanes":2,"points":[{"x":100,"y":500},{"x":1100,"y":500}]},
            {"id":"road-1","name":"North South","roadClass":"city","surface":"asphalt",
             "width":12,"lanes":2,"points":[{"x":500,"y":120},{"x":500,"y":880}]},
            {"id":"road-2","name":"T road","roadClass":"city","surface":"asphalt",
             "width":10,"lanes":2,"points":[{"x":900,"y":500},{"x":900,"y":790}]}],
        "regions":[{"id":"region-0","biome":"lake",
                    "points":[{"x":250,"y":220},{"x":360,"y":220},
                              {"x":360,"y":340},{"x":250,"y":340}]}],
        "props":[{"id":"prop-test-house","type":"house","name":"Test Home",
                  "x":220,"y":240,"scale":1.0,"rotation":0.0}],
        "markers":[{"id":"marker-0","type":"player_spawn","x":160,"y":500,"rotation":90.0}],
        "assets":[],
        "races":[{"id":"race-0","name":"City Sprint","mode":"sprint","laps":1,
                  "points":[{"x":160,"y":500},{"x":500,"y":500}],
                  "enemy_starts":[]}]}


class CustomTestWorldBaker(unittest.TestCase):
    def test_full_junction_geometry_and_routing(self):
        archive=make_archive(source())
        self.assertEqual(archive["format"],"streetbound.streamed-world")
        self.assertTrue(archive["editor_custom_test_drive"])
        self.assertEqual(len(archive["roads"]),3)
        self.assertGreater(len(archive["segments"]),3)
        self.assertGreaterEqual(len(archive["junctions"]),2)
        self.assertTrue(any(j["control"]!="none" for j in archive["junctions"]))
        self.assertTrue(any(j.get("polygon") and j.get("approaches") for j in archive["junctions"]))
        self.assertTrue(any(r["marking_gaps"] for r in archive["roads"]))
        self.assertTrue(archive["road_connections"])
        self.assertEqual(len(archive["editor_races"]),1)
        self.assertEqual(len(archive["props"]),1)
        self.assertEqual(archive["spawn"]["position"],[160,500])
        self.assertEqual(len(archive["terrain"]),2)
        self.assertTrue(archive["chunks"])
        for cell in archive["chunks"].values():
            for field,kind in (("junctions","junctions"),("segments","segments"),("props","props")):
                self.assertTrue(all(0<=i<len(archive[kind]) for i in cell[field]))

    def test_empty_map_remains_drivable_and_has_terrain_chunks(self):
        doc=source()
        doc["roads"]=[]
        doc["props"]=[]
        doc["regions"]=[]
        doc["markers"]=[]
        doc["races"]=[]
        data=make_archive(doc)
        self.assertFalse(data["segments"])
        self.assertFalse(data["junctions"])
        self.assertFalse(data["props"])
        self.assertEqual(data["spawn"]["position"],[600.0,500.0])
        self.assertGreater(len(data["chunks"]),0)

    def test_isolated_atomic_temp_archive(self):
        doc=source()
        with tempfile.TemporaryDirectory() as temp:
            base=pathlib.Path(temp)
            src=base/"authoring.world.json"
            output=base/"temporary.stream.json"
            src.write_text(json.dumps(doc),encoding="utf-8")
            shipped=ROOT/"worlds"/"morrow-coast.world.json"
            before=(shipped.stat().st_size,shipped.stat().st_mtime_ns)
            baked=build_file(src,output)
            self.assertTrue(output.is_file())
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")),baked)
            self.assertEqual((shipped.stat().st_size,shipped.stat().st_mtime_ns),before)
            self.assertFalse(output.with_suffix(output.suffix+".tmp").exists())

    def test_rejects_wrong_source_and_nonintegral_dimensions(self):
        doc=source()
        doc["customMap"]=False
        with self.assertRaises(ValueError):make_archive(doc)
        doc=source()
        doc["world"]["width"]=1200.5
        with self.assertRaises(ValueError):make_archive(doc)


if __name__=="__main__":
    unittest.main()
