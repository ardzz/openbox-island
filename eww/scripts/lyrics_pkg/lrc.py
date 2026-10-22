"""LRC parsing, line lookup by position and validation of stored lyric lines."""

from bisect import bisect_right
import re

from .text import MAX_BYTES, single_line

STAMP = re.compile(r"\[(\d{1,3}):([0-5]\d)(?:\.(\d{1,3}))?\]")
OFFSET = re.compile(r"^\[offset:([+-]?\d+)\]$", re.IGNORECASE)


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


def plain_line_at(lines, position_ms, duration):
    # Plain lyrics carry no timing; spread the lines evenly over the track as an estimate.
    if not lines or position_ms is None or duration is None:
        return None
    index = int(max(0, position_ms) * len(lines) // (duration * 1000))
    return lines[min(index, len(lines) - 1)]


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


def valid_plain(value):
    return (isinstance(value, list) and 0 < len(value) <= 20000
            and all(isinstance(line, str) and line and len(line) <= 16000
                    and single_line(line) == line for line in value))
