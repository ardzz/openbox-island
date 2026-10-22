"""Track identity and strict candidate matching for LRCLIB and NetEase results."""

import math

from .lrc import parse_lrc
from .text import artist_names, normalize_artist, normalize_title


def duration_of(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) and 1 <= value <= 3600 else None


def identity(track):
    return [normalize_title(track.get("title", "")),
            normalize_artist(track.get("artist", "")), duration_of(track.get("length"))]


def is_ytm(track):
    player = track.get("player", "")
    return player == "ytm_player" or player.startswith("ytm_player.")


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
