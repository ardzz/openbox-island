"""LRCLIB: exact get first, then search for the closest synced candidate."""

from ..http import request_json
from ..lrc import parse_lrc
from ..match import choose_candidate, identity


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
