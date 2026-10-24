"""Fetch ICS feeds into an on-disk cache; a failed fetch falls back to the last good copy."""

import hashlib
import http.client
import os
from pathlib import Path
import tempfile
import urllib.error
import urllib.request

MAX_BYTES = 5 * 1024 * 1024
USER_AGENT = "openbox-island/1.0 (+https://github.com/ardzz/openbox-island)"


class FeedError(Exception):
    """A response that is not a usable calendar; the message never contains the URL."""


def cache_file(root, url):
    return Path(root) / (hashlib.sha256(url.encode()).hexdigest()[:32] + ".ics")


def validate(raw):
    """RAW when it looks like an ICS feed within the size limit; FeedError otherwise."""
    if len(raw) > MAX_BYTES:
        raise FeedError("kalender lebih dari 5 MB")
    if b"BEGIN:VCALENDAR" not in raw[:4096]:
        raise FeedError("bukan file kalender")
    return raw


def download(url, timeout=15):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as handle:
        return validate(handle.read(MAX_BYTES + 1))


def refresh(root, url, fetch=download, check=None):
    """(raw bytes or None, error or ""). A success replaces the cached copy atomically."""
    path = cache_file(root, url)
    try:
        raw = fetch(url)
        if check is not None:
            try:
                check(raw)
            except Exception:
                raise FeedError("kalender tidak bisa dibaca") from None
    except urllib.error.HTTPError as error:
        message = f"HTTP {error.code}"
        error.close()
    except FeedError as error:
        message = str(error)
    except (OSError, ValueError, http.client.HTTPException):
        message = "gagal mengambil"
    else:
        tmp = None
        try:
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.parent.chmod(0o700)
            fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
            with os.fdopen(fd, "wb") as handle:
                handle.write(raw)
            os.replace(tmp, path)
        except OSError:
            pass
        finally:
            if tmp is not None:
                try:
                    Path(tmp).unlink(missing_ok=True)
                except OSError:
                    pass
        return raw, ""
    try:
        return path.read_bytes(), message
    except OSError:
        return None, message
