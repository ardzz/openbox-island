"""Cache-first lookup across providers with transient-failure retry scheduling."""

from collections import namedtuple
import sys
import time
import urllib.error

from . import http
from .cache import SOURCES, YTM_SOURCES
from .match import identity, is_ytm
from .sources.lrclib import lrclib_lyrics
from .sources.netease import netease_lyrics
from .sources.ytmusic import ytmusic_lyrics

LookupResult = namedtuple("LookupResult", "lines retry_at plain", defaults=(None, None))


def lookup_lyrics(track, cache):
    entry = cache.read(track, time.time())
    if entry is not None and entry.fresh:
        return LookupResult(entry.lines, None, entry.plain)
    stale = entry.lines if entry is not None else None
    stale_plain = entry.plain if entry is not None else None
    title, artist, duration = identity(track)
    if not title or not artist or duration is None:
        return LookupResult(stale, None, stale_plain)
    failed = False
    due = None
    plain = None
    # YouTube Music timed lyrics win; its plain lyrics only beat the title fallback.
    sources = [("lrclib", lambda current: (lrclib_lyrics(current), None)),
               ("netease", lambda current: (netease_lyrics(current), None))]
    if is_ytm(track):
        sources.insert(0, ("ytmusic", ytmusic_lyrics))
    for source, lookup in sources:
        try:
            lines, found_plain = lookup(track)
            plain = plain or found_plain
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
                eligible = max(time.monotonic() + 15, http.cooldown(source))
                due = min(due, eligible) if due is not None else eligible
    if not failed:
        cache.write(track, None, time.time(), YTM_SOURCES if is_ytm(track) else SOURCES, plain)
        return LookupResult(None, None, plain)
    return LookupResult(stale, due, plain or stale_plain)
