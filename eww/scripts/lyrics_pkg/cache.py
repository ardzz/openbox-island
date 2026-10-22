"""On-disk lyrics cache keyed by normalized track identity."""

from collections import namedtuple
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile

from .lrc import valid_lines, valid_plain
from .match import identity, is_ytm
from .text import MAX_BYTES

DAY = 86400
CACHE_VERSION = 2
SOURCES = ["lrclib", "netease"]
YTM_SOURCES = ["ytmusic", "lrclib", "netease"]
CacheEntry = namedtuple("CacheEntry", "lines fresh plain", defaults=(None,))


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
            plain = None
            if lines is None:
                # Negative entries name the sources that confirmed the miss; one written without
                # YouTube Music must not hide it from ytm_player.
                negative = data.get("negative")
                if negative not in (SOURCES, YTM_SOURCES) or (is_ytm(track) and negative != YTM_SOURCES):
                    return None
                plain = data.get("plain")
                if plain is not None and (negative != YTM_SOURCES or not valid_plain(plain)):
                    return None
            ttl = 30 * DAY if lines is not None else DAY
            return CacheEntry(None if lines is None else [tuple(row) for row in lines],
                              now - saved < ttl, plain)
        except (OSError, ValueError, TypeError, RecursionError):
            return None

    def write(self, track, lines, now, negative=SOURCES, plain=None):
        if (lines is not None and not valid_lines(lines)) or (plain is not None and not valid_plain(plain)):
            return
        temporary = None
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            data = {"version": CACHE_VERSION, "identity": identity(track), "saved_at": now, "lines": lines}
            if lines is None:
                data["negative"] = list(negative)
                if plain is not None:
                    data["plain"] = plain
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
