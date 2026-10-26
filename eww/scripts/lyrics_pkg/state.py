"""Per-track lyric state: lookup scheduling, retries and the emitted line."""

from bisect import bisect_right
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
        lines = [{"t": stamp, "text": text} for stamp, text in self.lines or []]
        index = -1
        if lines and position_ms is not None:
            index = bisect_right(self.lines, position_ms, key=lambda row: row[0]) - 1
        content = line_at(self.lines, position_ms)
        synced = bool(content)
        if self.lines is None:
            lines = [{"t": -1, "text": text} for text in self.plain or []]
            duration = duration_of(self.track.get("length"))
            content = plain_line_at(self.plain, position_ms, duration)
            if lines and position_ms is not None and duration is not None:
                index = min(int(max(0, position_ms) * len(lines) // (duration * 1000)),
                            len(lines) - 1)
        title = single_line(self.track.get("title", ""))
        artist = single_line(self.track.get("artist", ""))
        fallback = " — ".join(part for part in (title, artist) if part)
        return {"text": content or fallback, "synced": synced, "lines": lines, "index": index,
                "for_player": self.track.get("player", ""), "for_title": self.track.get("title", ""),
                "for_artist": self.track.get("artist", ""), "for_length": self.track.get("length", 0)}
