"""NetEase Cloud Music: search, then fetch the matched song's LRC without credit lines."""

import re

from ..http import request_json
from ..lrc import parse_lrc
from ..match import choose_netease_candidate, identity

CREDIT = re.compile(
    r"^(?:作词|作曲|编曲|制作人|监制|混音|母带|和声|录音|吉他|贝斯|鼓|出品|发行|词|曲"
    r"|OP|SP|Lyricist|Composer|Arranger|Producer)\s*[:：]", re.IGNORECASE
)


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
