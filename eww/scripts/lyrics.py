#!/usr/bin/env python3
"""Stream the selected player's current lyric as newline-delimited JSON."""

from bisect import bisect_right
from collections import namedtuple
from datetime import timezone
from email.utils import parsedate_to_datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request


DAY = 86400
CACHE_VERSION = 2
MAX_BYTES = 2 * 1024 * 1024
STAMP = re.compile(r"\[(\d{1,3}):([0-5]\d)(?:\.(\d{1,3}))?\]")
OFFSET = re.compile(r"^\[offset:([+-]?\d+)\]$", re.IGNORECASE)
PROMO = r"(?:official\s+music\s+video|official\s+video|official\s+audio|lyrics)"
PROMO_SUFFIX = re.compile(
    r"(?:\s*\(\s*" + PROMO + r"\s*\)|\s*\[\s*" + PROMO
    + r"\s*\]|\s+-\s*" + PROMO + r"|\s+" + PROMO + r")$", re.IGNORECASE
)
CREDIT = re.compile(
    r"^(?:作词|作曲|编曲|制作人|监制|混音|母带|和声|录音|吉他|贝斯|鼓|出品|发行|词|曲"
    r"|OP|SP|Lyricist|Composer|Arranger|Producer)\s*[:：]", re.IGNORECASE
)
ARTIST_PART = re.compile(r"[()\[\]]|, | & | x | × | / | feat\. | ft\. | featuring | with ")
ARTIST_ALIAS = re.compile(r"^(.*?)\s*(?:\(([^()]*)\)|\[([^\[\]]*)\])$")
CacheEntry = namedtuple("CacheEntry", "lines fresh")
LookupResult = namedtuple("LookupResult", "lines retry_at", defaults=(None,))
_next_request = 0.0
_cooldowns = {"lrclib": 0.0, "netease": 0.0}


def single_line(value):
    return " ".join(value.split()) if isinstance(value, str) else ""


def normalize_title(value):
    title = single_line(unicodedata.normalize("NFKC", value or ""))
    while True:
        cleaned = PROMO_SUFFIX.sub("", title).strip()
        if cleaned == title:
            return title.casefold()
        title = cleaned


def normalize_artist(value):
    artist = single_line(unicodedata.normalize("NFKC", value or ""))
    return re.sub(r"\s+-\s+Topic$", "", artist, flags=re.IGNORECASE).casefold()


def artist_names(value):
    artist = normalize_artist(value)
    parts = [artist]
    depth = 0
    start = 0
    for match in ARTIST_PART.finditer(artist):
        token = match[0]
        if token in ("(", "["):
            depth += 1
        elif token in (")", "]"):
            depth = max(0, depth - 1)
        elif depth == 0:
            parts.append(artist[start:match.start()].strip())
            start = match.end()
    parts.append(artist[start:].strip())
    names = {normalize_artist(part) for part in parts}
    for part in parts:
        alias = ARTIST_ALIAS.fullmatch(part)
        if alias:
            names.update(normalize_artist(name) for name in alias.groups() if name is not None)
    names.discard("")
    return names


def duration_of(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) and 1 <= value <= 3600 else None


def identity(track):
    return [normalize_title(track.get("title", "")),
            normalize_artist(track.get("artist", "")), duration_of(track.get("length"))]


def parse_lrc(text):
    if not isinstance(text, str) or len(text) > MAX_BYTES:
        return []
    lines = []
    offset = 0
    for raw in text.splitlines():
        raw = raw.strip()
        adjustment = OFFSET.fullmatch(raw)
        if adjustment:
            value = int(adjustment[1])
            if abs(value) <= 3600000:
                offset = value
            continue
        stamps = []
        cursor = 0
        while True:
            match = STAMP.match(raw, cursor)
            if not match:
                break
            milliseconds = (int(match[1]) * 60 + int(match[2])) * 1000
            milliseconds += int((match[3] or "0").ljust(3, "0"))
            stamps.append(milliseconds)
            cursor = match.end()
        content = single_line(raw[cursor:])
        lines.extend((stamp, content) for stamp in stamps)
    return sorted(((stamp - offset, content) for stamp, content in lines), key=lambda row: row[0])


def line_at(lines, position_ms):
    if position_ms is None or not lines:
        return None
    index = bisect_right(lines, position_ms, key=lambda row: row[0]) - 1
    return lines[index][1] if index >= 0 else None


def choose_candidate(track, candidates):
    title, artist, duration = identity(track)
    if not title or not artist or duration is None or not isinstance(candidates, list):
        return None
    names = artist_names(artist)
    best = None
    distance = float("inf")
    for item in candidates:
        if not isinstance(item, dict) or item.get("instrumental") is not False:
            continue
        if not isinstance(item.get("trackName"), str) or not isinstance(item.get("artistName"), str):
            continue
        candidate_duration = duration_of(item.get("duration"))
        if (normalize_title(item["trackName"]) != title
                or names.isdisjoint(artist_names(item["artistName"]))
                or candidate_duration is None):
            continue
        difference = abs(candidate_duration - duration)
        if difference > 2 or difference >= distance:
            continue
        lines = parse_lrc(item.get("syncedLyrics"))
        if any(content for _, content in lines):
            best, distance = item, difference
    return best


def valid_lines(value):
    if not isinstance(value, list) or not value or len(value) > 20000:
        return False
    previous = -3600001
    nonempty = False
    for row in value:
        if not isinstance(row, (list, tuple)) or len(row) != 2:
            return False
        stamp, content = row
        if (type(stamp) is not int or not -3600000 <= stamp <= 86400000
                or stamp < previous or not isinstance(content, str)
                or len(content) > 16000 or single_line(content) != content):
            return False
        previous = stamp
        nonempty |= bool(content)
    return nonempty


class LyricsCache:
    def __init__(self, directory):
        self.directory = Path(directory)

    def path(self, track):
        key = json.dumps(identity(track), ensure_ascii=False, separators=(",", ":"))
        return self.directory / (hashlib.sha256(key.encode("utf-8")).hexdigest() + ".json")

    def read(self, track, now):
        try:
            with self.path(track).open("rb") as handle:
                raw = handle.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                return None
            data = json.loads(raw)
            if (not isinstance(data, dict) or data.get("version") != CACHE_VERSION
                    or data.get("identity") != identity(track)):
                return None
            saved = data.get("saved_at")
            if type(saved) not in (int, float) or not math.isfinite(saved) or saved > now:
                return None
            lines = data.get("lines")
            if "lines" not in data or (lines is not None and not valid_lines(lines)):
                return None
            if lines is None and data.get("negative") != ["lrclib", "netease"]:
                return None
            ttl = 30 * DAY if lines is not None else DAY
            return CacheEntry(None if lines is None else [tuple(row) for row in lines], now - saved < ttl)
        except (OSError, ValueError, TypeError, RecursionError):
            return None

    def write(self, track, lines, now):
        if lines is not None and not valid_lines(lines):
            return
        temporary = None
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            data = {"version": CACHE_VERSION, "identity": identity(track), "saved_at": now, "lines": lines}
            if lines is None:
                data["negative"] = ["lrclib", "netease"]
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.directory,
                                             prefix=".lyrics-", delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(data, handle, ensure_ascii=False, allow_nan=False)
            temporary.replace(self.path(track))
        except (OSError, ValueError) as error:
            print("lyrics: cache write failed: " + str(error), file=sys.stderr)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def retry_after(value):
    try:
        seconds = float(value)
        if math.isfinite(seconds):
            return max(0, seconds)
    except (TypeError, ValueError):
        pass
    try:
        date = parsedate_to_datetime(value)
        if date.tzinfo is None:
            date = date.replace(tzinfo=timezone.utc)
        return max(0, date.timestamp() - time.time())
    except (TypeError, ValueError, OverflowError):
        return 60


def request_json(endpoint, parameters, source="lrclib"):
    global _next_request
    now = time.monotonic()
    if now < _cooldowns[source]:
        raise OSError(source + " rate cooldown is active")
    if now < _next_request:
        time.sleep(_next_request - now)
    base = "https://lrclib.net/api/" if source == "lrclib" else "https://music.163.com/api/"
    url = base + endpoint + "?" + urllib.parse.urlencode(parameters)
    request = urllib.request.Request(url, headers={
        "User-Agent": "openbox-island/1.0 (+https://github.com/ardzz/openbox-island)", "Accept": "application/json"
    })
    try:
        with urllib.request.urlopen(request, timeout=5) as handle:
            raw = handle.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError(source + " response exceeds size limit")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        delay = error.headers.get("Retry-After")
        if (error.code in (429, 503)
                or (delay is not None and (error.code == 408 or 500 <= error.code < 600))):
            _cooldowns[source] = time.monotonic() + retry_after(delay)
        if error.code == 404 and source == "lrclib" and endpoint == "get":
            return None
        raise
    finally:
        _next_request = time.monotonic() + 0.2


def lrclib_lyrics(track):
    title, artist, duration = identity(track)
    result = request_json("get", {"track_name": title, "artist_name": artist, "duration": duration})
    if result is not None and not isinstance(result, dict):
        raise ValueError("Invalid LRCLIB get response")
    selected = choose_candidate(track, [result] if result is not None else [])
    if selected is None:
        results = request_json("search", {"track_name": title, "artist_name": artist})
        if not isinstance(results, list):
            raise ValueError("Invalid LRCLIB search response")
        selected = choose_candidate(track, results)
    return parse_lrc(selected["syncedLyrics"]) if selected is not None else None


def choose_netease_candidate(track, songs):
    title, artist, duration = identity(track)
    our_names = artist_names(artist)
    matched = []
    unique = []
    for song in songs:
        if not isinstance(song, dict) or not isinstance(song.get("name"), str):
            continue
        if normalize_title(song["name"]) != title or type(song.get("id")) is not int or song["id"] <= 0:
            continue
        milliseconds = song.get("duration")
        seconds = duration_of(milliseconds / 1000) if type(milliseconds) in (int, float) else None
        if seconds is None:
            continue
        distance = abs(seconds - duration)
        artists = song.get("artists")
        names = []
        for item in artists if isinstance(artists, list) else []:
            if not isinstance(item, dict):
                continue
            if isinstance(item.get("name"), str):
                names.append(item["name"])
            aliases = item.get("alias")
            if isinstance(aliases, list):
                names.extend(alias for alias in aliases if isinstance(alias, str))
        if distance <= 2 and any(not our_names.isdisjoint(artist_names(name)) for name in names):
            matched.append((distance, song))
        if distance <= 1:
            unique.append(song)
    if matched:
        return min(matched, key=lambda item: item[0])[1]
    return unique[0] if len(unique) == 1 else None


def netease_lyrics(track):
    title, artist, _duration = identity(track)
    result = request_json("search/get", {"s": title + " " + artist, "type": 1, "limit": 10},
                          source="netease")
    if not isinstance(result, dict) or result.get("code") != 200 or not isinstance(result.get("result"), dict):
        raise OSError("Invalid NetEase search response")
    songs = result["result"].get("songs", [])
    if not isinstance(songs, list):
        raise OSError("Invalid NetEase song list")
    selected = choose_netease_candidate(track, songs)
    if selected is None:
        return None
    result = request_json("song/lyric", {"id": selected["id"], "lv": 1}, source="netease")
    if not isinstance(result, dict) or result.get("code") != 200:
        raise OSError("Invalid NetEase lyrics response")
    if result.get("nolyric") is True or result.get("uncollected") is True:
        return None
    lrc = result.get("lrc", {})
    if not isinstance(lrc, dict):
        raise OSError("Invalid NetEase LRC response")
    lines = parse_lrc(lrc.get("lyric", ""))
    if any("纯音乐，请欣赏" in content for _, content in lines):
        return None
    lines = [(stamp, content) for stamp, content in lines if not CREDIT.match(content)]
    return lines if any(content for _, content in lines) else None


def lookup_lyrics(track, cache):
    entry = cache.read(track, time.time())
    if entry is not None and entry.fresh:
        return LookupResult(entry.lines)
    stale = entry.lines if entry is not None else None
    title, artist, duration = identity(track)
    if not title or not artist or duration is None:
        return LookupResult(stale)
    failed = False
    due = None
    for source, lookup in (("lrclib", lrclib_lyrics), ("netease", netease_lyrics)):
        try:
            lines = lookup(track)
            if lines is not None:
                cache.write(track, lines, time.time())
                return LookupResult(lines)
        except (OSError, ValueError, TypeError, RecursionError) as error:
            print("lyrics: " + source + " lookup failed: " + str(error), file=sys.stderr)
            failed = True
            transient = isinstance(error, OSError) and (
                not isinstance(error, urllib.error.HTTPError)
                or error.code in (408, 429) or 500 <= error.code < 600
            )
            if transient:
                eligible = max(time.monotonic() + 15, _cooldowns[source])
                due = min(due, eligible) if due is not None else eligible
    if not failed:
        cache.write(track, None, time.time())
        return LookupResult(None)
    return LookupResult(stale, due)


class LyricsState:
    def __init__(self):
        self.track = {}
        self.key = None
        self.generation = 0
        self.lines = None
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
            self.lookup_at = time.monotonic() + 1.0 if raw is not None else None
            self.retry_at = None
            self.retries = 0
        self.track = track if active else {}
        return self.key

    def accept_lookup(self, key, lines, retry_at=None):
        if key is not None and key == self.key:
            self.lookup_at = None
            if lines is not None or retry_at is None:
                self.lines = lines
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
        title = single_line(self.track.get("title", ""))
        artist = single_line(self.track.get("artist", ""))
        fallback = " — ".join(part for part in (title, artist) if part)
        return {"text": fallback, "synced": False}


class LookupWorker:
    def __init__(self, cache):
        self.cache = cache
        self.condition = threading.Condition()
        self.pending = None
        self.completed = None
        self.closed = False
        self.thread = threading.Thread(target=self.run, name="lyrics-lookup", daemon=True)
        self.thread.start()

    def submit(self, key, track):
        with self.condition:
            self.pending = (key, dict(track)) if key is not None else None
            self.condition.notify()

    def take_result(self):
        with self.condition:
            result, self.completed = self.completed, None
            return result

    def close(self):
        with self.condition:
            self.closed = True
            self.pending = None
            self.condition.notify()

    def run(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.closed or self.pending is not None)
                if self.closed:
                    return
                key, track = self.pending
                self.pending = None
            try:
                result = lookup_lyrics(track, self.cache)
            except Exception as error:
                print("lyrics: worker failed: " + str(error), file=sys.stderr)
                result = LookupResult(None)
            with self.condition:
                self.completed = (key, result.lines, result.retry_at)


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
                    state.accept_lookup(lookup_key, cached.lines)
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


if __name__ == "__main__":
    main()
