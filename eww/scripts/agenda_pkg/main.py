"""agenda watch | check: fetch the configured calendars and publish the agenda document."""

import datetime as dt
import importlib
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time

from . import config, fetch

INTERVAL = 300
TICK = 15


def _env_seconds(name, default):
    try:
        return max(1, int(os.environ.get(name, default)))
    except ValueError:
        return default


def paths():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "eww-island"
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "eww-island" / "calendar"
    return runtime / "agenda.json", cache


def window(now, tz):
    start = dt.datetime.fromtimestamp(now, tz).replace(hour=0, minute=0, second=0, microsecond=0)
    return start, start + dt.timedelta(days=2)


def collect(accounts, cache, now, tz, fetcher=None):
    """(timed, allday, errors, stale) over every account; a fetch error keeps the cached feed."""
    events = importlib.import_module(__package__ + ".events")
    timed, allday, errors, stale = [], [], [], False
    start, end = window(now, tz)
    for account in accounts:
        raw, error = fetch.refresh(cache, account.url, fetcher or fetch.download)
        if error:
            errors.append(f"{account.name}: {error}")
            stale = stale or raw is not None
        if raw is None:
            continue
        try:
            more, days = events.occurrences(raw, account, start, end, tz)
        except (ValueError, KeyError, TypeError):
            errors.append(f"{account.name}: kalender tidak bisa dibaca")
            continue
        timed += more
        allday += days
    return timed, allday, errors, stale


def failure(message):
    return {"ok": False, "stale": False, "updated": "", "error": message, "label": "Kalender",
            "remaining": 0, "allday": [], "next": None, "rows": [], "errors": []}


def publish(path, document):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False)
    os.replace(tmp, path)


def watch(clock=time.time, stopped=None):
    """Refetch every ISLAND_CAL_INTERVAL s, republish every TICK s, print one line per tick."""
    stopped = stopped or threading.Event()
    state_path, cache = paths()
    interval = _env_seconds("ISLAND_CAL_INTERVAL", INTERVAL)
    tz = dt.datetime.now().astimezone().tzinfo
    fetched = None
    next_fetch = 0.0
    try:
        importlib.import_module(__package__ + ".events")  # needs python-icalendar
        from . import render
    except ImportError:
        render = None
    while not stopped.is_set():
        now = clock()
        if render is None:
            document = failure("python-icalendar belum terpasang")
        else:
            accounts, errors, _loose = config.load(config.config_path())
            if now >= next_fetch:
                fetched = collect(accounts, cache, now, tz)
                fetched_at = dt.datetime.fromtimestamp(now, tz).strftime("%H:%M")
                next_fetch = now + interval
            timed, allday, feed_errors, stale = fetched
            document = render.agenda(timed, allday, errors + feed_errors, int(now), tz,
                                     fetched_at, stale)
        publish(state_path, document)
        print(int(now), flush=True)
        stopped.wait(TICK)


def check():
    """Fetch each account once; print one line per account without its URL. Status 1 on any error."""
    path = config.config_path()
    accounts, errors, loose = config.load(path)
    if not path.exists():
        print(f"config kalender belum ada: {path}")
        return 1
    if loose:
        print(f"peringatan: {path} bisa dibaca pengguna lain; jalankan chmod 600")
    for error in errors:
        print(error)
    _, cache = paths()
    tz = dt.datetime.now().astimezone().tzinfo
    failed = bool(errors)
    for account in accounts:
        timed, allday, feed_errors, _stale = collect([account], cache, time.time(), tz)
        if feed_errors:
            failed = True
            print(feed_errors[0])
        else:
            print(f"{account.name}: OK, {len(timed)} event berjam, {len(allday)} seharian (hari ini & besok)")
    return 1 if failed else 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    sys.stdout.reconfigure(encoding="utf-8")
    if argv == ["check"]:
        sys.exit(check())
    if argv == ["watch"]:
        stopped = threading.Event()
        for signum in (signal.SIGINT, signal.SIGTERM):
            signal.signal(signum, lambda _signum, _frame: stopped.set())
        try:
            watch(stopped=stopped)
        except BrokenPipeError:
            pass
        return
    print("pemakaian: agenda watch | check", file=sys.stderr)
    sys.exit(2)
