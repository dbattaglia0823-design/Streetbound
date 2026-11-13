"""Unit tests for the local-only editor, path allowlist and safe rollback."""
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import map_editor_server as server


class LocalMapEditorTests(unittest.TestCase):
    def test_only_named_project_assets_are_readable(self):
        self.assertEqual(server.allowed_file("/worlds/morrow-coast.world.json"),server.BAKED)
        self.assertIsNone(server.allowed_file("/../../.git/config"))
        self.assertIsNone(server.allowed_file("/game-assets/../../.git/config"))
        self.assertIsNone(server.allowed_file("/worlds/other-map.json"))
        self.assertIsNone(server.allowed_file("/tools/build_morrow_coast.py"))
        self.assertIsNotNone(server.allowed_file("/game-assets/scenery/morrow-atlas-v1.png"))

    def test_post_requires_valid_same_origin_token(self):
        host=server.ThreadingHTTPServer(("127.0.0.1",0),server.make_handler("test-token"))
        thread=threading.Thread(target=host.serve_forever,daemon=True)
        thread.start()
        try:
            url=f"http://127.0.0.1:{host.server_port}"
            with urlopen(url+"/api/editor-status") as response:
                self.assertTrue(json.load(response)["live"])
            with urlopen(url+"/api/project-assets") as response:
                assets=json.load(response)["assets"]
                self.assertTrue(assets)
                self.assertEqual(len({a['id'] for a in assets}),len(assets))
                self.assertTrue(all(a['path'].startswith('Buildings/') for a in assets))
                self.assertFalse(any(a['path'].endswith('.import') for a in assets))
            # A page at another origin must not initiate a local file write,
            # even if it somehow supplies the private session token.
            bad=Request(url+"/api/apply-morrow",data=b'{}',method="POST",
                        headers={"Origin":"https://untrusted.example",
                                 "Host":f"127.0.0.1:{host.server_port}",
                                 "Content-Type":"application/json",
                                 "X-Streetbound-Editor-Token":"test-token"})
            with self.assertRaises(HTTPError) as observed:
                urlopen(bad)
            self.assertEqual(observed.exception.code,403)
        finally:
            host.shutdown()
            host.server_close()
            thread.join(timeout=3)

    def test_rebuild_failure_restores_edit_world_and_overview(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            edit,world,svg=(base/"edit.json",base/"world.json",base/"map.svg")
            edit.write_bytes(b'old edits')
            world_bytes=json.dumps({"format":"streetbound.streamed-world",
                "version":1,"size":[6400,4800]}).encode()
            world.write_bytes(world_bytes)
            svg.write_bytes(b'old overview')
            def failed_process(*args,**kwargs):
                world.write_bytes(b'partial rebuilt world')
                svg.write_bytes(b'partial map')
                return type("Result",(),{"returncode":1,"stderr":"Invalid road",
                                         "stdout":""})()
            doc={"format":"gdt.racing-world","version":2,"name":"Morrow Coast",
                 "world":{"width":6400,"height":4800},"roads":[],"props":[]}
            with patch.object(server,"EDIT",edit),patch.object(server,"BAKED",world),\
                 patch.object(server,"OVERVIEW",svg),patch.object(server.subprocess,"run",failed_process):
                old_hash=server.digest(world)
                with self.assertRaisesRegex(ValueError,"Invalid road"):
                    server.transactional_rebuild(doc,old_hash)
            self.assertEqual(edit.read_bytes(),b'old edits')
            self.assertEqual(world.read_bytes(),world_bytes)
            self.assertEqual(svg.read_bytes(),b'old overview')

    def test_identical_explicit_save_skips_full_rebuild(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            edit,world,svg=(base/"edit.json",base/"world.json",base/"map.svg")
            doc={"format":"gdt.racing-world","version":2,"name":"Morrow Coast",
                 "world":{"width":6400,"height":4800},"roads":[],"props":[]}
            edit.write_text(json.dumps(doc),encoding="utf-8")
            world.write_bytes(b'previous baked world')
            svg.write_bytes(b'<svg/>')
            old_edit=edit.stat().st_mtime_ns
            old_world=world.stat().st_mtime_ns
            with patch.object(server,"EDIT",edit),patch.object(server,"BAKED",world),\
                 patch.object(server,"OVERVIEW",svg),\
                 patch.object(server.subprocess,"run") as run:
                result=server.transactional_rebuild(doc,server.digest(world))
            self.assertTrue(result["ok"])
            self.assertTrue(result["unchanged"])
            self.assertEqual(edit.stat().st_mtime_ns,old_edit)
            self.assertEqual(world.stat().st_mtime_ns,old_world)
            run.assert_not_called()

    def test_stale_revision_is_rejected_before_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            world=Path(tmp)/"world.json"
            world.write_bytes(b'live content')
            with patch.object(server,"BAKED",world):
                with self.assertRaisesRegex(ValueError,"changed since import"):
                    server.transactional_rebuild({
                        "format":"gdt.racing-world","version":2,
                        "name":"Morrow Coast","world":{"width":6400,"height":4800}},
                        "f"*64)


if __name__=="__main__":
    unittest.main()
