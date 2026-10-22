"""Listener loop: follow media.json, poll the player position and print changed lyric JSON."""

import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

from .cache import LyricsCache
from .state import LyricsState
from .worker import LookupWorker


def read_track(path):
    try:
        with path.open("rb") as handle:
            raw = handle.read(65537)
        if len(raw) > 65536:
            return {"state": "none"}
        data = json.loads(raw)
        if not isinstance(data, dict):
            return {"state": "none"}
        if any(not isinstance(data.get(field, ""), str) for field in ("player", "title", "artist")):
            return {"state": "none"}
        return data
    except (OSError, ValueError, RecursionError):
        return {"state": "none"}


def player_position(player):
    if not player:
        return None
    try:
        result = subprocess.run(["playerctl", "--player", player, "position"],
                                capture_output=True, text=True, timeout=0.2, check=True)
        seconds = float(result.stdout.strip())
        return int(seconds * 1000) if math.isfinite(seconds) and seconds >= 0 else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    media_path = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "eww-island" / "media.json"
    cache = LyricsCache(Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
                        / "eww-island" / "lyrics")
    stopped = threading.Event()
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda _signum, _frame: stopped.set())
    state = LyricsState()
    worker = LookupWorker(cache)
    last_output = None

    def emit(value):
        nonlocal last_output
        if value != last_output:
            print(json.dumps(value, ensure_ascii=False), flush=True)
            last_output = value

    try:
        emit({"text": "", "synced": False})
        while not stopped.is_set():
            started = time.monotonic()
            track = read_track(media_path)
            old_key = state.key
            key = state.update_track(track)
            if key != old_key:
                emit(state.output(None))
                worker.submit(None, track)
            completed = worker.take_result()
            if completed is not None:
                state.accept_lookup(*completed)
            due = state.next_lookup(time.monotonic())
            if due is not None:
                lookup_key, lookup_track = due
                cached = cache.read(lookup_track, time.time())
                if cached is not None:
                    state.accept_lookup(lookup_key, cached.lines, plain=cached.plain)
                if cached is None or not cached.fresh:
                    worker.submit(lookup_key, lookup_track)
            position = player_position(track.get("player", "")) if key is not None else None
            current = read_track(media_path)
            if current != track:
                continue
            emit(state.output(position))
            interval = 0.25 if key is not None else 1.0
            stopped.wait(max(0, interval - (time.monotonic() - started)))
    except BrokenPipeError:
        pass
    finally:
        worker.close()
