#!/usr/bin/env python3
"""Minimal short-code room directory + per-room authoritative Godot process.

Use behind a TLS reverse proxy. This is a bounded deployment scaffold, not an
account-authenticated public service. Never expose its management port raw.
"""
from __future__ import annotations

import json
import os
import re
import secrets
import signal
import shutil
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_RE = re.compile(r"^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$")
ROOM_TTL = 2 * 60 * 60
MAX_BODY = 512


@dataclass
class Room:
    code: str
    secret: str
    owner_token: str
    port: int
    created_at: float
    process: subprocess.Popen
    directory: Path


class RoomRegistry:
    def __init__(self, *, godot: str, project: Path, public_host: str,
                 port_start: int = 28200, port_end: int = 28207,
                 max_rooms: int = 4, spawn_timeout: float = 35.0,
                 clock=time.monotonic, launcher=subprocess.Popen):
        if not public_host or "/" in public_host or ":" in public_host:
            raise ValueError("STREETBOUND_PUBLIC_GAME_HOST must be a bare IPv4 address or DNS name")
        if not 1024 <= port_start <= port_end <= 65535:
            raise ValueError("invalid UDP port range")
        self.godot, self.project, self.public_host = godot, project, public_host
        self.port_start, self.port_end = port_start, port_end
        self.max_rooms, self.spawn_timeout = max_rooms, spawn_timeout
        self.clock, self.launcher = clock, launcher
        self.rooms: dict[str, Room] = {}
        self.last_create: dict[str, float] = {}
        self.lock = threading.RLock()

    def _stop(self, room: Room) -> None:
        try:
            if room.process.poll() is None:
                room.process.terminate()
                try:
                    room.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    room.process.kill()
                    room.process.wait(timeout=3)
        finally:
            shutil.rmtree(room.directory, ignore_errors=True)

    def reap(self) -> None:
        with self.lock:
            now = self.clock()
            for code, room in list(self.rooms.items()):
                if now - room.created_at >= ROOM_TTL or room.process.poll() is not None:
                    self.rooms.pop(code, None)
                    self._stop(room)

    def create(self, client_ip: str) -> dict:
        with self.lock:
            self.reap()
            if len(self.rooms) >= self.max_rooms:
                raise RoomError(503, "Room capacity reached; try again later.")
            now = self.clock()
            if now - self.last_create.get(client_ip, -1e9) < 30.0:
                raise RoomError(429, "Room creation is rate limited.")
            in_use = {room.port for room in self.rooms.values()}
            port = next((p for p in range(self.port_start, self.port_end + 1)
                         if p not in in_use), None)
            if port is None:
                raise RoomError(503, "No game server ports are available.")
            code = "".join(secrets.choice(ALPHABET) for _ in range(12))
            while code in self.rooms:
                code = "".join(secrets.choice(ALPHABET) for _ in range(12))
            secret = secrets.token_hex(24)
            owner_token = secrets.token_urlsafe(32)
            directory = Path(tempfile.mkdtemp(prefix="streetbound-room-"))
            ready = directory / "ready"
            env = os.environ.copy()
            env.update({
                "STREETBOUND_ROOM_PORT": str(port),
                "STREETBOUND_ROOM_SECRET": secret,
                "STREETBOUND_ROOM_READY_FILE": str(ready),
                "XDG_DATA_HOME": str(directory / "user_data"),
            })
            try:
                process = self.launcher([
                    self.godot, "--headless", "--path", str(self.project),
                    "--script", "res://tools/hosted_room.gd"],
                    cwd=str(self.project), env=env,
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL)
                deadline = time.monotonic() + self.spawn_timeout
                while not ready.is_file() and time.monotonic() < deadline:
                    if process.poll() is not None:
                        break
                    time.sleep(0.05)
                if not ready.is_file() or process.poll() is not None:
                    temp = Room(code, secret, owner_token, port, now, process, directory)
                    self._stop(temp)
                    raise RoomError(503, "Dedicated game server did not become ready.")
            except RoomError:
                raise
            except OSError as exc:
                shutil.rmtree(directory, ignore_errors=True)
                raise RoomError(503, "Could not launch game server.") from exc
            self.rooms[code] = Room(code, secret, owner_token, port, now, process, directory)
            self.last_create[client_ip] = now
            return {"code": code, "owner_token": owner_token,
                    "host": self.public_host, "port": port, "secret": secret,
                    "expires_in": ROOM_TTL}

    def resolve(self, code: str) -> dict:
        with self.lock:
            self.reap()
            if not CODE_RE.fullmatch(code) or code not in self.rooms:
                raise RoomError(404, "Room not found or expired.")
            room = self.rooms[code]
            return {"code": code, "host": self.public_host, "port": room.port,
                    "secret": room.secret,
                    "expires_in": max(0, int(ROOM_TTL - (self.clock() - room.created_at)))}

    def close(self, code: str, owner_token: str) -> None:
        with self.lock:
            self.reap()
            room = self.rooms.get(code)
            if room is None or not secrets.compare_digest(room.owner_token, owner_token):
                raise RoomError(404, "Room not found.")
            self.rooms.pop(code)
            self._stop(room)

    def shutdown(self) -> None:
        with self.lock:
            for code, room in list(self.rooms.items()):
                self.rooms.pop(code)
                self._stop(room)


class RoomError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def handler_factory(registry: RoomRegistry):
    class Handler(BaseHTTPRequestHandler):
        server_version = "StreetboundRoomDirectory/1"

        def log_message(self, format, *args):
            # Avoid logging bearer codes, tokens and request URL paths.
            pass

        def _json(self, status: int, value: dict):
            body = json.dumps(value, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def _code(self):
            path = urlsplit(self.path)
            if path.query or path.fragment:
                raise RoomError(400, "Invalid path.")
            segments = path.path.split("/")
            if len(segments) != 3 or segments[1] != "rooms":
                raise RoomError(404, "Not found.")
            return segments[2]

        def do_GET(self):
            try:
                if self.path == "/health":
                    self._json(200, {"ok": True})
                else:
                    self._json(200, registry.resolve(self._code()))
            except RoomError as error:
                self._json(error.status, {"error": str(error)})

        def do_POST(self):
            try:
                if self.path != "/rooms":
                    raise RoomError(404, "Not found.")
                length = self.headers.get("Content-Length", "")
                if not length.isdigit() or not 0 <= int(length) <= MAX_BODY:
                    raise RoomError(413, "Invalid request size.")
                payload = self.rfile.read(int(length))
                if payload and payload.strip() not in (b"{}",):
                    raise RoomError(400, "No room creation options are accepted.")
                self._json(201, registry.create(self.client_address[0]))
            except RoomError as error:
                self._json(error.status, {"error": str(error)})

        def do_DELETE(self):
            try:
                code = self._code()
                owner_token = self.headers.get("X-Room-Owner", "")
                if len(owner_token) > 128:
                    raise RoomError(404, "Room not found.")
                registry.close(code, owner_token)
                self._json(200, {"closed": True})
            except RoomError as error:
                self._json(error.status, {"error": str(error)})

    return Handler


def main():
    registry = RoomRegistry(
        godot=os.environ.get("STREETBOUND_GODOT", "godot"),
        project=Path(os.environ.get("STREETBOUND_GAME_ROOT", ".")).resolve(),
        public_host=os.environ["STREETBOUND_PUBLIC_GAME_HOST"],
        port_start=int(os.environ.get("STREETBOUND_PORT_START", "28200")),
        port_end=int(os.environ.get("STREETBOUND_PORT_END", "28207")),
        max_rooms=int(os.environ.get("STREETBOUND_MAX_ROOMS", "4")))
    server = ThreadingHTTPServer(("127.0.0.1",
                                  int(os.environ.get("STREETBOUND_API_PORT", "8090"))),
                                 handler_factory(registry))
    stopping = threading.Event()

    def sweeper():
        while not stopping.wait(5):
            registry.reap()

    worker = threading.Thread(target=sweeper, name="room-expiry-sweeper", daemon=True)
    worker.start()

    def shutdown_server(_signum, _frame):
        # HTTPServer.shutdown must execute on another thread.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown_server)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        stopping.set()
        worker.join(timeout=2)
        registry.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
