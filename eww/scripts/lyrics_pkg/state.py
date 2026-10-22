"""Per-track lyric state: lookup scheduling, retries and the emitted line."""

import time

from .lrc import line_at, plain_line_at
from .match import duration_of
from .text import single_line


class LyricsState:
    def __init__(self):
        self.track = {}
        self.key = None
        self.generation = 0
        self.lines = None
        self.plain = None
        self.lookup_at = None
        self.retry_at = None
        self.retries = 0

    def update_track(self, track):
        active = track.get("state") in ("playing", "paused")
        raw = (track.get("player", ""), track.get("title", ""),
               track.get("artist", ""), track.get("length")) if active else None
        previous = self.key[1] if self.key is not None else None
        if raw != previous:
            self.generation += 1
            self.key = (self.generation, raw) if raw is not None else None
            self.lines = None
            self.plain = None
            self.lookup_at = time.monotonic() + 1.0 if raw is not None else None
            self.retry_at = None
            self.retries = 0
        self.track = track if active else {}
        return self.key

    def accept_lookup(self, key, lines, retry_at=None, plain=None):
        if key is not None and key == self.key:
            self.lookup_at = None
            if lines is not None or retry_at is None:
                self.lines = lines
            if plain is not None or retry_at is None:
                self.plain = plain
            self.retry_at = (
                max(retry_at, time.monotonic() + 15 * 2 ** self.retries)
                if retry_at is not None and self.retries < 3 else None
            )

    def next_lookup(self, now):
        if self.lookup_at is not None and now >= self.lookup_at:
            self.lookup_at = None
            return self.key, dict(self.track)
        if self.retry_at is not None and now >= self.retry_at:
            self.retry_at = None
            self.retries += 1
            return self.key, dict(self.track)
        return None

    def output(self, position_ms):
        content = line_at(self.lines, position_ms)
        if content:
            return {"text": content, "synced": True}
        if self.lines is None:
            content = plain_line_at(self.plain, position_ms, duration_of(self.track.get("length")))
            if content:
                return {"text": content, "synced": False}
        title = single_line(self.track.get("title", ""))
        artist = single_line(self.track.get("artist", ""))
        fallback = " — ".join(part for part in (title, artist) if part)
        return {"text": fallback, "synced": False}
