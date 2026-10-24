"""The agenda document shared by the Kalender tab, the meeting alerts and the left pill."""

import datetime as dt

SOON = 15 * 60
WEEKDAYS = ("Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min")
MONTHS = ("Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des")


def _hhmm(epoch, tz):
    return dt.datetime.fromtimestamp(epoch, tz).strftime("%H:%M")


def _day_label(started, today):
    delta = (started.date() - today).days
    if delta == 0:
        return "Hari ini"
    if delta == 1:
        return "Besok"
    return f"{WEEKDAYS[started.weekday()]} {started.day} {MONTHS[started.month - 1]}"


def _state(event, now):
    # A zero-length event counts as one minute long.
    end = event["start"] + 60 if event["end"] == event["start"] else event["end"]
    if end <= now:
        return "past"
    if event["start"] <= now:
        return "now"
    return "soon" if event["start"] - now <= SOON else "later"


def agenda(timed, allday, errors, now, tz, updated, stale):
    """Rows from today onward in time order (one per uid and start), today's all-day titles,
    the next not-yet-ended event, and the count of today's events still to come or running."""
    today = dt.datetime.fromtimestamp(now, tz).date()
    rows, seen = [], set()
    for event in sorted(timed, key=lambda e: (e["start"], e["end"], e["title"])):
        key = (event["uid"], event["start"])
        started = dt.datetime.fromtimestamp(event["start"], tz)
        if key in seen or started.date() < today:
            continue
        seen.add(key)
        day = _day_label(started, today)
        time = f"{_hhmm(event['start'], tz)}–{_hhmm(event['end'], tz)}"
        rows.append({"id": event["id"], "start": event["start"], "end": event["end"],
                     "title": event["title"], "account": event["account"], "color": event["color"],
                     "join": event["join"], "day": day,
                     "time": time if day == "Hari ini" else f"{day} {time}", "state": _state(event, now)})
    ahead = [row for row in rows if row["state"] != "past"]
    remaining = sum(1 for row in ahead if row["day"] == "Hari ini")
    iso = today.isoformat()
    titles = []
    for item in allday:
        if item["first"] <= iso < item["last"] and item["title"] not in titles:
            titles.append(item["title"])
    return {"ok": True, "stale": stale, "updated": updated, "error": "",
            "label": "Kalender" + (f" {remaining}" if remaining else ""), "remaining": remaining,
            "allday": titles, "next": ahead[0] if ahead else None, "rows": rows, "errors": errors}
