"""Real browser bridge -> two production bakes, entirely in a temporary copy.

Run with Python 3 and Node installed. Never writes the playable world or overlay.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RebuildStabilityTests(unittest.TestCase):
    def test_repeated_editor_saves_preserve_roads_widths_and_markers(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            shutil.copytree(ROOT / "tools", work / "tools", ignore=shutil.ignore_patterns("__pycache__"))
            (work / "worlds").mkdir()
            (work / "map-editor/maps").mkdir(parents=True)
            archive = work / "worlds/morrow-coast.world.json"
            overlay = work / "map-editor/maps/morrow-coast.edits.world.json"
            shutil.copy2(ROOT / "worlds/morrow-coast.world.json", archive)
            bridge = (ROOT / "map-editor/morrow-coast-bridge.js").as_uri()
            def import_world(edit=False):
                code = f"""
                    import {{readFileSync,writeFileSync}} from 'node:fs';
                    import {{convertMorrowWorld}} from {json.dumps(bridge)};
                    const {{doc}}=convertMorrowWorld(JSON.parse(readFileSync(process.argv[1],'utf8')));
                    if(process.argv[3]==='edit'){{
                        doc.roads[67].name='QA Coastal Edit';
                        doc.roads[67].width=14;
                        const source=doc.roads[0];
                        doc.roads.push({{...source,id:'road-'+doc.roads.length,name:'QA Added Road',
                            points:[source.points[0],{{x:source.points[0].x+80,y:source.points[0].y+80}},source.points.at(-1)]}});
                        doc.markers.push({{id:'marker-'+doc.markers.length,name:'QA checkpoint',
                            type:'checkpoint',x:2420,y:3035,rotation:0,properties:{{}}}});
                    }}
                    writeFileSync(process.argv[2],JSON.stringify(doc));
                """
                subprocess.run(["node", "--input-type=module", "-e", code,
                    str(archive), str(overlay), "edit" if edit else ""], check=True,
                    capture_output=True, text=True, timeout=30)
            def bake():
                result = subprocess.run([sys.executable, "-B",
                    str(work / "tools/build_morrow_coast.py")], cwd=work,
                    capture_output=True, text=True, timeout=240)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return json.loads(archive.read_text(encoding="utf-8"))
            import_world(edit=True)
            first = bake()
            import_world()
            exported = json.loads(overlay.read_text(encoding="utf-8"))
            self.assertTrue(any(m["name"] == "QA checkpoint" for m in exported["markers"]))
            second = bake()
            self.assertEqual(len(first["roads"]), len(second["roads"]), "Repeated saves appended source roads")
            self.assertEqual(first["roads"], second["roads"], "Road widths or geometry changed without an edit")
            self.assertEqual(first["props"], second["props"], "Repeated saves changed scenery or collision footprints")
            self.assertEqual(first["editor_markers"], second["editor_markers"])
            self.assertEqual(second["roads"][67]["name"], "QA Coastal Edit")
            self.assertEqual(sum(r["name"] == "QA Added Road" for r in second["roads"]), 1)
            self.assertTrue(second["chunks"])
            print(f"Two isolated production bakes: {len(second['roads'])} stable roads, "
                  f"{len(second['props'])} stable scenery props, coastal edit and checkpoint retained.")


if __name__ == "__main__":
    unittest.main()
