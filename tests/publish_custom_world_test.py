"""Production map promotion: real archive, manifest switch, assets and rollback."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from publish_custom_world import publish, restore, DEFAULT
from custom_test_world_bake_test import source


class ProductionWorldPublisher(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/"game"
        (self.root/"worlds").mkdir(parents=True)
        (self.root/"worlds"/"morrow-coast.world.json").write_text('{"untouched":true}',encoding="utf-8")
        self.source=Path(self.temp.name)/"user"/"my-city.world.json"
        self.source.parent.mkdir(parents=True)
        self.backups=Path(self.temp.name)/"saved-backups"
        self.doc=source()
        self.doc["name"]="My City"
        self._write()

    def _write(self):
        self.source.write_text(json.dumps(self.doc,indent=2),encoding="utf-8")

    def active(self):
        return json.loads((self.root/"worlds"/"active-world.json").read_text(encoding="utf-8"))

    def test_publish_complete_world_and_source_for_normal_gameplay(self):
        result=publish(self.source,self.root,self.backups)
        self.assertEqual(result["result"],"published")
        self.assertEqual(result["roads"],3)
        self.assertGreaterEqual(result["junctions"],2)
        self.assertEqual(result["races"],1)
        self.assertEqual(result["markers"],1)
        self.assertEqual(result["world_id"],"my-city.world.json")
        manifest=self.active()
        self.assertEqual(manifest["mode"],"published")
        self.assertEqual(manifest["id"],"my-city.world.json")
        self.assertEqual(manifest["name"],"My City")
        archive=self.root/manifest["archive"].removeprefix("res://")
        data=json.loads(archive.read_text(encoding="utf-8"))
        self.assertTrue(data["editor_published_world"])
        self.assertTrue(data["editor_custom_world"])
        self.assertFalse(data["editor_custom_test_drive"])
        self.assertEqual(data["editor_world_id"],"my-city.world.json")
        self.assertGreaterEqual(len(data["road_connections"]),1)
        self.assertGreaterEqual(len(data["junctions"]),2)
        self.assertEqual(data["editor_races"][0]["id"],"race-0")
        self.assertEqual(data["editor_game_markers"][0]["type"],"player_spawn")
        source_copy=self.root/manifest["source"].removeprefix("res://")
        self.assertEqual(source_copy.read_bytes(),self.source.read_bytes())
        self.assertEqual(json.loads((self.root/"worlds"/"morrow-coast.world.json").read_text()),
                         {"untouched":True})
        self.assertEqual(len(list(self.backups.glob("active-world-*.json"))),1)

    def test_publish_immutable_versions_backup_restore_and_republish(self):
        first=publish(self.source,self.root,self.backups)
        first_manifest=self.active()
        old_archive=self.root/first_manifest["archive"].removeprefix("res://")
        old_bytes=old_archive.read_bytes()
        second=publish(self.source,self.root,self.backups)
        self.assertEqual(second["archive"],first["archive"])
        self.doc["name"]="My City Updated"
        self.doc["races"][0]["reward_cash"]=5000
        self._write()
        third=publish(self.source,self.root,self.backups)
        self.assertNotEqual(first["archive"],third["archive"])
        self.assertTrue(old_archive.exists())
        self.assertEqual(old_archive.read_bytes(),old_bytes)
        self.assertEqual(self.active()["name"],"My City Updated")
        self.assertEqual(restore(self.root,self.backups)["result"],"restored")
        self.assertEqual(self.active(),DEFAULT)
        self.assertTrue(old_archive.exists())
        self.assertTrue((self.root/third["archive"].removeprefix("res://")).exists())
        self.assertEqual(len(list(self.backups.glob("active-world-*.json"))),4)

    def test_invalid_spawn_never_switches_active_map(self):
        publish(self.source,self.root,self.backups)
        before=self.active()
        known_files=set((self.root/"worlds"/"published").iterdir())
        self.doc["markers"][0]["x"]=350
        self.doc["markers"][0]["y"]=360
        self._write()
        with self.assertRaisesRegex(ValueError,"Player Spawn"):
            publish(self.source,self.root,self.backups)
        self.assertEqual(self.active(),before)
        self.assertEqual(set((self.root/"worlds"/"published").iterdir()),known_files)

    def test_spawn_overlapping_building_rejected(self):
        self.doc["props"][0]["x"]=160
        self.doc["props"][0]["y"]=500
        self._write()
        with self.assertRaisesRegex(ValueError,"overlaps solid scenery"):
            publish(self.source,self.root,self.backups)
        self.assertFalse((self.root/"worlds"/"active-world.json").exists())

    def test_missing_spawn_or_road_rejected_without_writing_manifest(self):
        self.doc["markers"]=[]
        self._write()
        with self.assertRaisesRegex(ValueError,"Player Spawn"):
            publish(self.source,self.root,self.backups)
        self.assertFalse((self.root/"worlds"/"active-world.json").exists())
        self.doc["markers"]=source()["markers"]
        self.doc["roads"]=[]
        self._write()
        with self.assertRaisesRegex(ValueError,"drivable road"):
            publish(self.source,self.root,self.backups)
        self.assertFalse((self.root/"worlds"/"published").exists())

    def test_invalid_event_dependency_and_artwork_rejected_before_activation(self):
        self.doc["races"][0]["prerequisite_races"]=["race-does-not-exist"]
        self._write()
        with self.assertRaises(ValueError):
            publish(self.source,self.root,self.backups)
        self.assertFalse((self.root/"worlds"/"active-world.json").exists())

    def test_backup_failure_never_changes_active_world(self):
        publish(self.source,self.root,self.backups)
        previous=self.active()
        invalid_backup=Path(self.temp.name)/"not-a-directory"
        invalid_backup.write_text("not a folder",encoding="utf-8")
        self.doc["name"]="Failed update"
        self._write()
        with self.assertRaises(OSError):
            publish(self.source,self.root,invalid_backup)
        self.assertEqual(self.active(),previous)

    def test_publish_does_not_rewrite_exiting_package_with_same_identity(self):
        result=publish(self.source,self.root,self.backups)
        archive=self.root/result["archive"].removeprefix("res://")
        archive.write_text('{"tampered":true}',encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"conflicting bytes"):
            publish(self.source,self.root,self.backups)


if __name__=="__main__":
    unittest.main()
