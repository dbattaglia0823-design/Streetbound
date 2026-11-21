#!/usr/bin/env python3
"""Run: python3 -m unittest discover -s tests -p hosted_room_directory_test.py"""
import json
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from hosted_rooms import RoomError, RoomRegistry, handler_factory  # noqa: E402


class FakeProcess:
    def __init__(self, command, *, env, **kwargs):
        self.alive = True
        self.command = command
        Path(env["STREETBOUND_ROOM_READY_FILE"]).write_text("READY\n")

    def poll(self):
        return None if self.alive else 0

    def terminate(self):
        self.alive = False

    def kill(self):
        self.alive = False

    def wait(self, *, timeout):
        return 0


class DirectoryTests(unittest.TestCase):
    def setUp(self):
        self.now = [1000.0]
        self.registry = RoomRegistry(
            godot="fake-godot", project=Path(".").resolve(),
            public_host="games.test.example", port_start=28200, port_end=28201,
            max_rooms=2, launcher=FakeProcess, clock=lambda: self.now[0])

    def tearDown(self):
        self.registry.shutdown()

    def test_room_creates_bearer_only_short_code_and_owns_dedicated_process(self):
        room = self.registry.create("203.0.113.1")
        self.assertEqual(len(room["code"]), 12)
        self.assertEqual(len(room["secret"]), 48)
        self.assertEqual(room["host"], "games.test.example")
        self.assertEqual(self.registry.resolve(room["code"])["secret"], room["secret"])
        self.assertNotIn("owner_token", self.registry.resolve(room["code"]))
        self.assertEqual(list(self.registry.rooms.values())[0].process.command[-1],
                         "res://tools/hosted_room.gd")
        with self.assertRaises(RoomError) as err:
            self.registry.close(room["code"], "forged")
        self.assertEqual(err.exception.status, 404)
        self.registry.close(room["code"], room["owner_token"])
        self.assertFalse(self.registry.rooms)
        with self.assertRaises(RoomError):
            self.registry.resolve(room["code"])

    def test_rate_limit_capacity_and_expiry(self):
        first = self.registry.create("203.0.113.1")
        with self.assertRaises(RoomError) as err:
            self.registry.create("203.0.113.1")
        self.assertEqual(err.exception.status, 429)
        second = self.registry.create("203.0.113.2")
        self.assertNotEqual(first["port"], second["port"])
        with self.assertRaises(RoomError) as err:
            self.registry.create("203.0.113.3")
        self.assertEqual(err.exception.status, 503)
        self.now[0] += 7201
        self.registry.reap()
        self.assertEqual(len(self.registry.rooms), 0)
        with self.assertRaises(RoomError):
            self.registry.resolve(first["code"])
        self.assertEqual(self.registry.create("203.0.113.1")["port"], 28200)

    def test_http_create_resolve_and_owner_only_close(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0),
                                     handler_factory(self.registry))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:%d" % server.server_port

        def request(path, method="GET", headers=None, data=None):
            req = Request(base + path, method=method, headers=headers or {},
                          data=data)
            with urlopen(req, timeout=5) as response:
                self.assertEqual(response.headers.get("Cache-Control"), "no-store")
                return response.status, json.loads(response.read())

        try:
            self.assertEqual(request("/health")[1], {"ok": True})
            status, room = request("/rooms", "POST",
                                   {"Content-Type": "application/json"}, b"{}")
            self.assertEqual(status, 201)
            status, lookup = request("/rooms/" + room["code"])
            self.assertEqual(status, 200)
            self.assertEqual(lookup["secret"], room["secret"])
            with self.assertRaises(HTTPError) as err:
                request("/rooms/" + room["code"], "DELETE",
                        {"X-Room-Owner": "invalid"})
            self.assertEqual(err.exception.code, 404)
            status, closed = request("/rooms/" + room["code"], "DELETE",
                                     {"X-Room-Owner": room["owner_token"]})
            self.assertEqual(status, 200)
            self.assertTrue(closed["closed"])
            with self.assertRaises(HTTPError) as err:
                request("/rooms/" + room["code"])
            self.assertEqual(err.exception.code, 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
