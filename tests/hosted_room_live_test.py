#!/usr/bin/env python3
"""Real localhost integration: HTTP short code -> headless Godot authority -> Godot guest."""
import json
import os
import subprocess
import sys
import threading
import traceback
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from hosted_rooms import RoomRegistry, handler_factory  # noqa: E402


def main(binary: str):
    registry = RoomRegistry(
        godot=str(Path(binary).resolve()), project=ROOT,
        public_host="127.0.0.1", port_start=28291, port_end=28291,
        max_rooms=1, spawn_timeout=90.0)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler_factory(registry))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = "http://127.0.0.1:%d" % server.server_port
    try:
        request = Request(base + "/rooms", data=b"{}", method="POST",
                          headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=110) as response:
            assert response.status == 201
            room = json.loads(response.read())
        assert room["host"] == "127.0.0.1"
        env = os.environ.copy()
        env["STREETBOUND_TEST_DIRECTORY"] = base
        env["STREETBOUND_TEST_ROOM_CODE"] = room["code"]
        result = subprocess.run([
            str(Path(binary).resolve()), "--headless", "--path", str(ROOT),
            "--script", "res://tests/hosted_room_network_probe.gd"
        ], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        print(result.stdout)
        if result.returncode != 0:
            print(result.stderr)
        assert result.returncode == 0, "Guest exited with error"
        assert "HOSTED ROOM NETWORK GUEST: PASS" in result.stdout
        assert "SCRIPT ERROR:" not in result.stdout + result.stderr
        assert "Parse Error:" not in result.stdout + result.stderr
        close = Request(base + "/rooms/" + room["code"], method="DELETE",
                        headers={"X-Room-Owner": room["owner_token"]})
        with urlopen(close, timeout=10) as response:
            assert json.loads(response.read())["closed"] is True
        assert not registry.rooms
        print("HOSTED ROOM LIVE LOOPBACK: PASS")
        return 0
    except Exception:
        traceback.print_exc()
        return 1
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        registry.shutdown()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
