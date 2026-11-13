"""Drive the real Godot native HTTPRequest client against the existing
localhost transactional backend, using only disposable map files.
This tests the complete Apply path while the Godot scene tree is PAUSED.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location(
    "streetbound_map_backend_http_roundtrip",
    ROOT / "tools" / "map_editor_server.py",
)
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(godot_binary: str) -> None:
    original_baked = ROOT / "worlds/morrow-coast.world.json"
    original_source = ROOT / "map-editor/maps/morrow-coast.edits.world.json"
    original_overview = ROOT / "worlds/morrow-coast-overview.svg"
    original_hashes = {p: sha(p) for p in (
        original_baked, original_source, original_overview
    )}
    previous = backend.EDIT, backend.BAKED, backend.OVERVIEW, backend.BUILDER
    with tempfile.TemporaryDirectory(prefix="streetbound-native-http-") as temp:
        tmp = pathlib.Path(temp)
        source = tmp / "morrow-source.json"
        baked = tmp / "playable-world.json"
        overview = tmp / "overview.svg"
        builder = tmp / "fake_rebaker.py"
        for existing, copy_to in (
            (original_baked,baked),
            (original_source,source),
            (original_overview,overview),
        ):
            shutil.copy2(existing,copy_to)
        initial_baked_sha = sha(baked)
        initial_source_sha = sha(source)
        # The fake rebaker exercises server transactional semantics but never
        # writes into worlds/ or the map-editor/ source directory.
        builder.write_text(
            "import json\nfrom pathlib import Path\n"
            f"baked=Path({str(baked)!r})\n"
            f"overview=Path({str(overview)!r})\n"
            "data=json.loads(baked.read_text(encoding='utf-8'))\n"
            "data.setdefault('stats', {})['native_http_roundtrip']=1\n"
            "baked.write_text(json.dumps(data),encoding='utf-8')\n"
            "overview.write_text('Native HTTP Test Overview',encoding='utf-8')\n",
            encoding="utf-8",
        )
        backend.EDIT, backend.BAKED = source,baked
        backend.OVERVIEW,backend.BUILDER = overview,builder
        # Emit the backend's actual validation failure when debugging an
        # HTTP client/server roundtrip, never mask it as a network timeout.
        original_rebuild = backend.transactional_rebuild
        def traced_rebuild(doc, expected_sha):
            try:
                return original_rebuild(doc, expected_sha)
            except Exception as exc:
                print("NATIVE HTTP SERVER REBUILD:", repr(exc), flush=True)
                raise
        backend.transactional_rebuild = traced_rebuild
        server = ThreadingHTTPServer(
            ("127.0.0.1",8765),backend.make_handler("test-token-local-http")
        )
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            cmd = [
                godot_binary, "--headless", "--path", str(ROOT),
                "--fixed-fps", "60",
                "--script", "res://tests/native_map_bridge_client_test.gd",
            ]
            result = subprocess.run(
                cmd, cwd=ROOT, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True,
                timeout=110, check=False,
            )
            print(result.stdout)
            if result.returncode != 0 or "NATIVE BRIDGE HTTP ROUNDTRIP: PASS" not in result.stdout:
                raise AssertionError(
                    "Real Godot paused native-to-Python map apply failed"
                )
            if any(item in result.stdout for item in ("SCRIPT ERROR:","Parse Error:","FAIL ")):
                raise AssertionError("Godot logged a map bridge error")
            if sha(source)==initial_source_sha:
                raise AssertionError("Native edit was not written into isolated source")
            if sha(baked)==initial_baked_sha:
                raise AssertionError("Native edit did not rebuild isolated world")
            if overview.read_text(encoding="utf-8")!="Native HTTP Test Overview":
                raise AssertionError("Isolated overview was not regenerated")
            if any(sha(p)!=original for p,original in original_hashes.items()):
                raise AssertionError("HTTP test modified an actual repository map")
            print("NATIVE MAP GODOT-TO-PYTHON APPLY: PASS")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=6)
            backend.EDIT, backend.BAKED, backend.OVERVIEW, backend.BUILDER = previous
            backend.transactional_rebuild = original_rebuild


if __name__ == "__main__":
    if len(sys.argv)!=2:
        raise SystemExit("Usage: python tests/native_map_bridge_http_roundtrip_test.py <godot-bin>")
    run(sys.argv[1])
