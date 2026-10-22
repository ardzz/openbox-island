"""Single-line text and title/artist normalization."""

import re
import unicodedata

MAX_BYTES = 2 * 1024 * 1024
PROMO = r"(?:official\s+music\s+video|official\s+video|official\s+audio|lyrics)"
PROMO_SUFFIX = re.compile(
    r"(?:\s*\(\s*" + PROMO + r"\s*\)|\s*\[\s*" + PROMO
    + r"\s*\]|\s+-\s*" + PROMO + r"|\s+" + PROMO + r")$", re.IGNORECASE
)
ARTIST_PART = re.compile(r"[()\[\]]|, | & | x | × | / | feat\. | ft\. | featuring | with ")
ARTIST_ALIAS = re.compile(r"^(.*?)\s*(?:\(([^()]*)\)|\[([^\[\]]*)\])$")


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
