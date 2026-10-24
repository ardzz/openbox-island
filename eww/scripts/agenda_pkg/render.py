"""The agenda document shared by the Kalender tab, the meeting alerts and the left pill."""

import datetime as dt

SOON = 15 * 60
DAYS = ("Hari ini", "Besok")


def _hhmm(epoch, tz):
    return dt.datetime.fromtimestamp(epoch, tz).strftime("%H:%M")


def _state(event, now):
    # A zero-length event counts as one minute long.
    end = event["start"] + 60 if event["end"] == event["start"] else event["end"]
    if end <= now:
        return "past"
    if event["start"] <= now:
        return "now"
    return "soon" if event["start"] - now <= SOON else "later"


def agenda(timed, allday, errors, now, tz, updated, stale):
    """Rows of today and tomorrow in time order (one per uid and start), today's all-day titles,
    the next not-yet-ended event, and the count of today's events still to come or running."""
    today = dt.datetime.fromtimestamp(now, tz).date()
    rows, seen = [], set()
    for event in sorted(timed, key=lambda e: (e["start"], e["end"], e["title"])):
        key = (event["uid"], event["start"])
        day = (dt.datetime.fromtimestamp(event["start"], tz).date() - today).days
        if key in seen or day not in (0, 1):
            continue
        seen.add(key)
        time = f"{_hhmm(event['start'], tz)}–{_hhmm(event['end'], tz)}"
        rows.append({"id": event["id"], "start": event["start"], "end": event["end"],
                     "title": event["title"], "account": event["account"], "color": event["color"],
                     "join": event["join"], "day": DAYS[day],
                     "time": time if day == 0 else f"{DAYS[day]} {time}", "state": _state(event, now)})
    ahead = [row for row in rows if row["state"] != "past"]
    remaining = sum(1 for row in ahead if row["day"] == DAYS[0])
    iso = today.isoformat()
    titles = []
    for item in allday:
        if item["first"] <= iso < item["last"] and item["title"] not in titles:
            titles.append(item["title"])
    return {"ok": True, "stale": stale, "updated": updated, "error": "",
            "label": "Kalender" + (f" {remaining}" if remaining else ""), "remaining": remaining,
            "allday": titles, "next": ahead[0] if ahead else None, "rows": rows, "errors": errors}
