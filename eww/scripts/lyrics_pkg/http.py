"""Rate-limited JSON requests with per-source cooldowns."""

from datetime import timezone
from email.utils import parsedate_to_datetime
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request

from .text import MAX_BYTES

_next_request = 0.0
_cooldowns = {"lrclib": 0.0, "netease": 0.0}


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


def cooldown(source):
    return _cooldowns.get(source, 0.0)
