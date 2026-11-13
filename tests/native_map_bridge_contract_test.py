"""Exercise the EXACT localhost authorization, revision and rollback path used
by the native Godot editor, without touching the repository's actual world.
"""
from __future__ import annotations
import hashlib
import http.client
import importlib.util
import json
import pathlib
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location(
    "streetbound_local_map_backend", ROOT / "tools" / "map_editor_server.py"
)
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assert_check(label: str, condition: bool) -> None:
    if not condition:
        raise AssertionError(label)
    print("PASS", label)


def send(port: int, method: str, path: str, body=None, token="test-token-local",
         origin=True, secret=True):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    encoded = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"}
    if origin:
        headers["Origin"] = f"http://127.0.0.1:{port}"
    if secret:
        headers["X-Streetbound-Editor-Token"] = token
    conn.request(method, path, body=encoded, headers=headers)
    response = conn.getresponse()
    result = (response.status, json.loads(response.read().decode()))
    conn.close()
    return result


def main():
    previous = (server_module.EDIT, server_module.BAKED,
                server_module.OVERVIEW, server_module.BUILDER)
    with tempfile.TemporaryDirectory() as tmp:
        directory = pathlib.Path(tmp)
        source = directory / "source.json"
        game = directory / "world.json"
        overview = directory / "overview.svg"
        builder = directory / "builder.py"
        original = {
            "format": "streetbound.streamed-world",
            "version": 1, "size": [6400, 4800],
            "chunks": {"0,0": {"props": []}},
            "stats": {"roads": 1}
        }
        authored = {
            "format": "gdt.racing-world", "version": 2, "name": "Morrow Coast",
            "world": {"width": 6400, "height": 4800, "seed": 28114, "base": "grass"},
            "roads": [], "regions": [], "props": [], "markers": [], "assets": []
        }
        game.write_text(json.dumps(original), encoding="utf-8")
        overview.write_text("original overview", encoding="utf-8")
        source.write_text(json.dumps(authored), encoding="utf-8")
        server_module.EDIT = source
        server_module.BAKED = game
        server_module.OVERVIEW = overview
        server_module.BUILDER = builder
        initial = {f: f.read_bytes() for f in (source, game, overview)}
        try:
            host = ThreadingHTTPServer(("127.0.0.1", 0),
                                       server_module.make_handler("test-token-local"))
            thread = threading.Thread(target=host.serve_forever, daemon=True)
            thread.start()
            port = host.server_port
            try:
                code, status = send(port, "GET", "/api/editor-status")
                assert_check("local_backend_exposes_loaded_map_sha",
                             code == 200 and status["live"] and
                             status["worldSha"] == sha(game) and status["overlayExists"])
                code, value = send(port, "GET", "/api/morrow-edits")
                assert_check("native_source_reads_original_editor_overlay",
                             code == 200 and value == authored)
                payload = {"worldSha": sha(game), "world": authored}
                code, _ = send(port, "POST", "/api/apply-morrow",
                               payload, origin=False)
                assert_check("reject_post_without_same_origin", code == 403)
                code, _ = send(port, "POST", "/api/apply-morrow",
                               payload, secret=False)
                assert_check("reject_post_without_private_session_token", code == 403)
                code, response = send(port, "POST", "/api/apply-morrow",
                                      {"worldSha": "a" * 64, "world": authored})
                assert_check("reject_stale_baked_revision",
                             code == 409 and "changed" in response["error"])
                assert_check("unauthorized_and_stale_requests_modify_nothing",
                             all(f.read_bytes() == data for f, data in initial.items()))
                # Simulate a builder that writes a world and overview then fails.
                # The transactional server must restore ALL three old files.
                builder.write_text(
                    "from pathlib import Path\n"
                    f"Path({str(game)!r}).write_text('broken')\n"
                    f"Path({str(overview)!r}).write_text('broken')\n"
                    "raise SystemExit(3)\n", encoding="utf-8"
                )
                changed = dict(authored)
                changed["roads"] = [{"id": "road-0"}]
                code, response = send(port, "POST", "/api/apply-morrow",
                                      {"worldSha": sha(game), "world": changed})
                assert_check("builder_failure_returns_conflict",
                             code == 409 and "rejected" in response["error"])
                assert_check("failed_rebuild_restores_source_world_and_overview",
                             all(f.read_bytes() == data for f, data in initial.items()))
                updated = dict(original)
                updated["stats"] = {"roads": 2}
                builder.write_text(
                    "from pathlib import Path\n"
                    f"Path({str(game)!r}).write_text({json.dumps(updated)!r})\n"
                    f"Path({str(overview)!r}).write_text('new overview')\n",
                    encoding="utf-8"
                )
                old_sha = sha(game)
                code, response = send(port, "POST", "/api/apply-morrow",
                                      {"worldSha": old_sha, "world": changed})
                assert_check("authenticated_native_apply_rebuilds_playable_world",
                             code == 200 and response["ok"] and
                             response["worldSha"] == sha(game) and
                             response["worldSha"] != old_sha)
                assert_check("successful_apply_persists_source_and_overview",
                             json.loads(source.read_text()) == changed and
                             overview.read_text() == "new overview")
                code, response = send(port, "POST", "/api/apply-morrow",
                                      {"worldSha": old_sha, "world": changed})
                assert_check("second_apply_with_old_revision_is_blocked",
                             code == 409 and "changed" in response["error"])
            finally:
                host.shutdown()
                host.server_close()
                thread.join(timeout=4)
        finally:
            (server_module.EDIT, server_module.BAKED,
             server_module.OVERVIEW, server_module.BUILDER) = previous
    print("NATIVE MAP BACKEND CONTRACT: PASS")


if __name__ == "__main__":
    main()
