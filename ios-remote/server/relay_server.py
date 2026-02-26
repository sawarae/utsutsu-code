#!/usr/bin/env python3
"""
utsutsu-code iOS Relay Server

WebSocket server that:
1. Streams Claude Code session activity to iOS clients
2. Relays TTS requests from iOS to the desktop mascot
3. Sends notification events for key session moments

Protocol (JSON messages):
  Server → Client:
    {"type": "session_line",  "data": {"timestamp": "...", "kind": "...", "content": "..."}}
    {"type": "session_lines", "data": [<session_line.data>, ...]}   # bulk history
    {"type": "notify",        "data": {"title": "...", "body": "...", "emotion": "..."}}
    {"type": "status",        "data": {"connected": true, "session_active": bool}}

  Client → Server:
    {"type": "tts",       "data": {"message": "...", "emotion": "Joy"}}
    {"type": "subscribe", "data": {"notifications": true}}
    {"type": "ping"}
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import websockets
    from websockets.server import serve
except ImportError:
    print("ERROR: websockets not installed. Run: pip install websockets", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_PORT = 8765
SIGNAL_DIR = Path.home() / ".claude" / "utsutsu-code"
SESSION_LOG = SIGNAL_DIR / "session.jsonl"
MASCOT_SPEAKING = SIGNAL_DIR / "mascot_speaking"

LOG_POLL_INTERVAL = 0.3  # seconds between log file checks
MAX_HISTORY_LINES = 200  # lines to keep in memory for new clients

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [relay] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("relay")

# ---------------------------------------------------------------------------
# Session log watcher
# ---------------------------------------------------------------------------


class SessionWatcher:
    """Watches session.jsonl and yields new lines."""

    def __init__(self, path: Path):
        self.path = path
        self._offset = 0
        self._history: list[dict] = []

    def _ensure_file(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self.path.touch()

    def load_history(self) -> list[dict]:
        """Load existing lines (up to MAX_HISTORY_LINES)."""
        self._ensure_file()
        lines: list[dict] = []
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                for raw in f:
                    raw = raw.strip()
                    if not raw:
                        continue
                    try:
                        lines.append(json.loads(raw))
                    except json.JSONDecodeError:
                        lines.append({
                            "timestamp": time.time(),
                            "kind": "raw",
                            "content": raw,
                        })
                self._offset = f.tell()
        except FileNotFoundError:
            pass
        self._history = lines[-MAX_HISTORY_LINES:]
        return list(self._history)

    def poll_new(self) -> list[dict]:
        """Return newly appended lines since last poll."""
        new_lines: list[dict] = []
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                # Check if file was truncated / rotated
                f.seek(0, 2)  # end
                size = f.tell()
                if size < self._offset:
                    self._offset = 0
                f.seek(self._offset)
                for raw in f:
                    raw = raw.strip()
                    if not raw:
                        continue
                    try:
                        entry = json.loads(raw)
                    except json.JSONDecodeError:
                        entry = {
                            "timestamp": time.time(),
                            "kind": "raw",
                            "content": raw,
                        }
                    new_lines.append(entry)
                self._offset = f.tell()
        except FileNotFoundError:
            pass

        if new_lines:
            self._history.extend(new_lines)
            self._history = self._history[-MAX_HISTORY_LINES:]
        return new_lines

    @property
    def history(self) -> list[dict]:
        return list(self._history)


# ---------------------------------------------------------------------------
# TTS relay
# ---------------------------------------------------------------------------


def write_tts_signal(message: str, emotion: str = "Gentle") -> bool:
    """Write to mascot_speaking signal file (same as mascot_tts.py)."""
    try:
        SIGNAL_DIR.mkdir(parents=True, exist_ok=True)
        payload = json.dumps({"message": message, "emotion": emotion},
                             ensure_ascii=False)
        tmp = MASCOT_SPEAKING.with_suffix(".tmp")
        tmp.write_text(payload, encoding="utf-8")
        tmp.rename(MASCOT_SPEAKING)
        log.info("TTS signal written: [%s] %s", emotion, message)
        return True
    except Exception as e:
        log.error("Failed to write TTS signal: %s", e)
        return False


# ---------------------------------------------------------------------------
# WebSocket server
# ---------------------------------------------------------------------------

CLIENTS: set = set()


async def register(ws):
    CLIENTS.add(ws)
    log.info("Client connected (%d total)", len(CLIENTS))


async def unregister(ws):
    CLIENTS.discard(ws)
    log.info("Client disconnected (%d total)", len(CLIENTS))


async def broadcast(message: dict):
    """Send a message to all connected clients."""
    if not CLIENTS:
        return
    payload = json.dumps(message, ensure_ascii=False)
    dead = set()
    for ws in CLIENTS:
        try:
            await ws.send(payload)
        except websockets.exceptions.ConnectionClosed:
            dead.add(ws)
    CLIENTS.difference_update(dead)


async def handle_client(ws):
    await register(ws)
    try:
        # Send status
        await ws.send(json.dumps({
            "type": "status",
            "data": {"connected": True, "session_active": SESSION_LOG.exists()},
        }))

        # Send history
        history = watcher.history
        if history:
            await ws.send(json.dumps({
                "type": "session_lines",
                "data": history,
            }, ensure_ascii=False))

        # Handle incoming messages
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "tts":
                data = msg.get("data", {})
                message = data.get("message", "")
                emotion = data.get("emotion", "Gentle")
                if message:
                    ok = write_tts_signal(message, emotion)
                    await ws.send(json.dumps({
                        "type": "tts_result",
                        "data": {"ok": ok},
                    }))
                    # Also log it as a session line
                    entry = {
                        "timestamp": time.time(),
                        "kind": "tts_request",
                        "content": f"[iOS → TTS] ({emotion}) {message}",
                    }
                    await broadcast({
                        "type": "session_line",
                        "data": entry,
                    })

            elif msg_type == "ping":
                await ws.send(json.dumps({"type": "pong"}))

            elif msg_type == "subscribe":
                pass  # all clients get notifications by default

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        await unregister(ws)


async def poll_session_log():
    """Periodically poll session.jsonl and broadcast new lines."""
    while True:
        new_lines = watcher.poll_new()
        for line in new_lines:
            await broadcast({
                "type": "session_line",
                "data": line,
            })
            # Check for notification-worthy events
            kind = line.get("kind", "")
            content = line.get("content", "")
            if kind in ("task_complete", "error", "test_result"):
                emotion = "Joy" if kind == "task_complete" else "Trouble"
                await broadcast({
                    "type": "notify",
                    "data": {
                        "title": "utsutsu-code",
                        "body": content[:100],
                        "emotion": emotion,
                    },
                })
        await asyncio.sleep(LOG_POLL_INTERVAL)


# ---------------------------------------------------------------------------
# Bonjour / mDNS advertisement (optional)
# ---------------------------------------------------------------------------

_zeroconf = None
_service_info = None


def start_mdns(port: int):
    """Advertise the relay server via Bonjour/mDNS."""
    global _zeroconf, _service_info
    try:
        from zeroconf import Zeroconf, ServiceInfo
        import socket
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
        _service_info = ServiceInfo(
            "_utsutsu-relay._tcp.local.",
            f"utsutsu-relay-{hostname}._utsutsu-relay._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=port,
            properties={"version": "1"},
        )
        _zeroconf = Zeroconf()
        _zeroconf.register_service(_service_info)
        log.info("mDNS: advertising on %s:%d", ip, port)
    except ImportError:
        log.info("mDNS: zeroconf not installed, skipping (pip install zeroconf)")
    except Exception as e:
        log.warning("mDNS: failed to advertise: %s", e)


def stop_mdns():
    global _zeroconf, _service_info
    if _zeroconf and _service_info:
        _zeroconf.unregister_service(_service_info)
        _zeroconf.close()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

watcher = SessionWatcher(SESSION_LOG)


async def main():
    port = int(os.environ.get("RELAY_PORT", DEFAULT_PORT))
    host = os.environ.get("RELAY_HOST", "0.0.0.0")

    watcher.load_history()
    log.info("Session log: %s (%d lines in history)", SESSION_LOG, len(watcher.history))

    start_mdns(port)

    stop_event = asyncio.Event()
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop_event.set)

    async with serve(handle_client, host, port):
        log.info("Relay server listening on ws://%s:%d", host, port)
        poll_task = asyncio.create_task(poll_session_log())
        await stop_event.wait()
        poll_task.cancel()

    stop_mdns()
    log.info("Relay server stopped")


if __name__ == "__main__":
    asyncio.run(main())
