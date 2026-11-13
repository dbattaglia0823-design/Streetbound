"""Local-only Streetbound Map Builder with transactional live world rebaking.

No third-party dependencies. Starts from map-editor/Start Map Editor.cmd.
The browser cannot write Godot project files on its own; this server exposes
ONLY one validated Morrow Coast authoring transaction, and read-only game art.
"""
from __future__ import annotations

import hashlib
import json
import mimetypes
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit
from project_asset_catalog import catalog

ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "map-editor"
BAKED = ROOT / "worlds" / "morrow-coast.world.json"
OVERVIEW = ROOT / "worlds" / "morrow-coast-overview.svg"
EDIT = EDITOR / "maps" / "morrow-coast.edits.world.json"
BUILDER = ROOT / "tools" / "build_morrow_coast.py"
MAX_EDIT_SIZE = 8_000_000
MIN_SIZE = (6400, 4800)
MAX_SIZE = (9600, 7200)
TOKEN = secrets.token_urlsafe(32)
REBUILD_LOCK = threading.Lock()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ""


def allowed_file(route: str) -> Path | None:
    """Expose no source scripts outside map-editor, no arbitrary project files."""
    path = unquote(urlsplit(route).path)
    if path in {"/", "/index.html"}:
        return EDITOR / "index.html"
    if path == "/worlds/morrow-coast.world.json":
        return BAKED
    if path == "/worlds/morrow-coast-overview.svg":
        return OVERVIEW
    if path.startswith("/game-assets/"):
        relative = path[len("/game-assets/"):]
        target = (ROOT / "assets" / relative).resolve()
        parent = (ROOT / "assets").resolve()
        if (target.is_relative_to(parent) and target.suffix.lower() in {".png", ".webp", ".svg"}
                and target.is_file()):
            return target
        return None
    target = (EDITOR / path.lstrip("/")).resolve()
    if target.is_relative_to(EDITOR.resolve()) and target.is_file():
        return target
    return None


def transactional_rebuild(doc: object, expected_sha: str) -> dict:
    """Validate the revision; rollback source and both playable outputs on error."""
    if not isinstance(doc, dict):
        raise ValueError("Missing editable Morrow Coast document.")
    if doc.get("format") != "gdt.racing-world" or doc.get("version") != 2:
        raise ValueError("Unsupported editor document.")
    if doc.get("name") != "Morrow Coast":
        raise ValueError("Only the playable Morrow Coast map may be edited.")
    if digest(BAKED) != expected_sha:
        raise ValueError("The playable world changed since import. Reload it before applying.")
    current = json.loads(BAKED.read_text(encoding="utf-8"))
    if current.get("format") != "streetbound.streamed-world" or current.get("version") != 1:
        raise ValueError("Unknown original playable world format.")
    old_size = current.get("size", [])
    new_size = [doc.get("world",{}).get("width"),doc.get("world",{}).get("height")]
    if (len(old_size)!=2 or len(new_size)!=2 or
            any(type(v) is not int for v in new_size) or
            any(new_size[i]<max(old_size[i],MIN_SIZE[i]) or new_size[i]>MAX_SIZE[i]
                for i in range(2))):
        raise ValueError("Map expansion can only add space east and south; cannot shrink or shift the existing world.")
    encoded = (json.dumps(doc, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
    if len(encoded) > MAX_EDIT_SIZE:
        raise ValueError("Morrow Coast authoring document exceeds 8 MB.")
    paths = [EDIT, BAKED, OVERVIEW]
    previous = {path: path.read_bytes() if path.exists() else None for path in paths}
    EDIT.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Persist source first. The production generator validates all road,
        # prop, terrain and marker edits before deriving collision/stream indices.
        with tempfile.NamedTemporaryFile(dir=EDIT.parent, prefix=".morrow-", suffix=".json",
                                         delete=False) as handle:
            handle.write(encoded)
            tmp = Path(handle.name)
        try:
            os.replace(tmp, EDIT)
        finally:
            tmp.unlink(missing_ok=True)
        try:
            completed = subprocess.run([sys.executable, str(BUILDER)], cwd=str(ROOT),
                                       timeout=240, capture_output=True, text=True,
                                       check=False)
        except subprocess.TimeoutExpired as exc:
            raise ValueError("World rebuild exceeded four minutes; original map restored.") from exc
        if completed.returncode:
            errors = (completed.stderr or completed.stdout).strip()
            raise ValueError("Rebuild rejected the changes: " + errors[-4000:])
        baked = json.loads(BAKED.read_text(encoding="utf-8"))
        if baked.get("format") != "streetbound.streamed-world" or not baked.get("chunks"):
            raise ValueError("Rebuild did not produce a complete playable world.")
        return {"ok": True, "worldSha": digest(BAKED), "stats": baked.get("stats", {}),
                "message": "Playable Morrow Coast rebuilt. Restart the running game to load it."}
    except Exception:
        # A validation failure may occur after the builder wrote the world but
        # before the overview. Restore all three files, not just authoring JSON.
        for path, old in previous.items():
            if old is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(old)
        raise


def make_handler(token: str = TOKEN):
    class Handler(BaseHTTPRequestHandler):
        server_version = "StreetboundMapBuilder/1.0"

        def _send(self, code: int, payload: bytes, mime: str = "application/json; charset=utf-8"):
            self.send_response(code)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (ConnectionAbortedError, BrokenPipeError):
                pass

        def _json(self, code: int, body: dict):
            self._send(code, json.dumps(body).encode("utf-8"))

        def _origin_ok(self) -> bool:
            host = self.headers.get("Host", "")
            origin = self.headers.get("Origin", "")
            return (host in {f"127.0.0.1:{self.server.server_port}",
                             f"localhost:{self.server.server_port}"}
                    and origin in {f"http://127.0.0.1:{self.server.server_port}",
                                   f"http://localhost:{self.server.server_port}"})

        def do_GET(self):
            route = urlsplit(self.path).path
            if route == "/api/project-assets":
                return self._json(200, {"assets":catalog(ROOT)})
            if route == "/api/morrow-edits":
                if EDIT.exists():
                    return self._send(200, EDIT.read_bytes())
                return self._json(404, {"error": "No persisted editable overlay"})
            if route == "/api/editor-status":
                return self._json(200, {"live": True, "token": token,
                                        "worldSha": digest(BAKED),
                                        "overlayExists": EDIT.exists(),
                                        "assetAtlas": "/game-assets/scenery/morrow-atlas-v1.png"})
            target = allowed_file(route)
            if target is None or not target.exists():
                return self._json(404, {"error": "Not found"})
            size = target.stat().st_size
            mime = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(size))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            try:
                with target.open("rb") as stream:
                    while chunk := stream.read(256 * 1024):
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_POST(self):
            if urlsplit(self.path).path != "/api/apply-morrow":
                return self._json(404, {"error": "Unknown operation"})
            if (not self._origin_ok() or self.headers.get("X-Streetbound-Editor-Token") != token
                    or self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json"):
                return self._json(403, {"error": "This local project operation is not authorized."})
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= MAX_EDIT_SIZE + 2048:
                    return self._json(413, {"error": "Invalid edit payload size."})
                payload = json.loads(self.rfile.read(size))
                expected = payload.get("worldSha")
                if not isinstance(expected, str) or len(expected) != 64:
                    raise ValueError("Missing loaded-map revision. Reload Morrow Coast.")
                if not REBUILD_LOCK.acquire(blocking=False):
                    return self._json(409, {"error": "A world rebuild is already running."})
                try:
                    result = transactional_rebuild(payload.get("world"), expected)
                finally:
                    REBUILD_LOCK.release()
                return self._json(200, result)
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                return self._json(409, {"error": str(exc)})
            except Exception as exc:
                self.log_error("Rebuild failed: %s", exc)
                return self._json(500, {"error": "Could not apply edits; existing game map restored."})

    return Handler


def main(argv=None):
    import argparse
    args = argparse.ArgumentParser(description="Streetbound local Map Builder")
    args.add_argument("--port", type=int, default=8765)
    args.add_argument("--no-browser", action="store_true")
    opts = args.parse_args(argv)
    server = ThreadingHTTPServer(("127.0.0.1", opts.port), make_handler())
    url = f"http://127.0.0.1:{opts.port}/"
    print(f"Streetbound Map Builder with direct game-map editing: {url}", flush=True)
    print("Only accessible on this computer. Press Ctrl+C to stop.", flush=True)
    if not opts.no_browser:
        threading.Timer(0.35, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
