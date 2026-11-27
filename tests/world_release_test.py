import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from custom_test_world_bake_test import source
from publish_custom_world import publish
from world_release import preflight, export_package, verify_package, compare, rollback
from world_release_audit import structural_audit

class WorldRelease(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/"game"
        (self.root/"worlds").mkdir(parents=True)
        (self.root/"worlds/morrow-coast.world.json").write_text("{}")
        self.backups=Path(self.temp.name)/"backups"
        self.file=Path(self.temp.name)/"sample.world.json"
        self.doc=source()
        self.file.write_text(json.dumps(self.doc))
        self.pointer=self.root/"worlds/active-world.json"

    def test_dry_run_export_and_publish_match(self):
        result=preflight(self.file,self.root)
        self.assertFalse(self.pointer.exists())
        self.assertEqual(result["audit"]["error_count"],0)
        path=Path(self.temp.name)/"package.zip"
        exported=export_package(self.file,self.root,path)
        self.assertFalse(self.pointer.exists())
        self.assertEqual(verify_package(path)["archive_sha256"],result["archive_sha256"])
        published=publish(self.file,self.root,self.backups)
        self.assertIn(exported["archive_sha256"][:20],published["archive"])
        with self.assertRaises(ValueError):
            export_package(self.file,self.root,path)

    def test_tamper_and_traversal(self):
        path=Path(self.temp.name)/"release.zip"
        export_package(self.file,self.root,path)
        altered=path.with_name("altered.zip")
        with zipfile.ZipFile(path) as src, zipfile.ZipFile(altered,"w") as dst:
            for name in src.namelist():
                data=src.read(name)
                dst.writestr(name,b"x"*len(data) if name.startswith("worlds/published/source-") else data)
        with self.assertRaisesRegex(ValueError,"checksum"):
            verify_package(altered)
        with zipfile.ZipFile(path,"a") as z:z.writestr("../bad","x")
        with self.assertRaises(ValueError):verify_package(path)

    def test_rollback_checks_bytes_before_switch(self):
        first=publish(self.file,self.root,self.backups)
        self.doc["name"]="Second"
        self.file.write_text(json.dumps(self.doc))
        publish(self.file,self.root,self.backups)
        saved=sorted(self.backups.glob("active-world-*.json"))[-1]
        current=self.pointer.read_bytes()
        old=self.root/first["archive"].removeprefix("res://")
        payload=old.read_bytes()
        old.write_bytes(b"corrupted")
        with self.assertRaises(ValueError):rollback(self.root,self.backups,saved)
        self.assertEqual(self.pointer.read_bytes(),current)
        old.write_bytes(payload)
        self.assertEqual(rollback(self.root,self.backups,saved)["result"],"rolled_back")
        self.assertEqual(json.loads(self.pointer.read_bytes())["archive"],first["archive"])

    def test_diff_and_index_failure(self):
        original=source()
        updated=source()
        updated["roads"][0]["width"]=14
        updated["props"]=[]
        delta=compare(original,updated)["entities"]
        self.assertEqual(delta["roads"]["changed"],1)
        self.assertEqual(delta["props"]["removed"],1)
        from build_custom_test_world import make_archive
        archive=make_archive(original)
        for row in archive["chunks"].values():row["segments"]=[]
        self.assertGreater(structural_audit(archive)["error_count"],0)

if __name__=="__main__":unittest.main()
