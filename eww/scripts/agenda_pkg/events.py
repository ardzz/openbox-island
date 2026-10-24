"""Expand ICS feeds into the occurrences of a time window."""

import datetime as dt
import hashlib
import re

import icalendar
import recurring_ical_events

JOIN = re.compile(r"https://(?:meet\.google\.com/[a-z0-9-]+"
                  r"|[\w.-]*zoom\.us/(?:j|my|w)/[^\s<>\"'\\]+"
                  r"|teams\.microsoft\.com/l/meetup-join/[^\s<>\"'\\]+)", re.IGNORECASE)


def _values(event, name):
    value = event.get(name)
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def join_link(event):
    """The first Meet, Zoom or Teams link, from conference data first, then location and notes."""
    for name in ("CONFERENCE", "X-GOOGLE-CONFERENCE", "LOCATION", "DESCRIPTION"):
        for value in _values(event, name):
            match = JOIN.search(str(value))
            if match:
                return match.group(0)
    return ""


def declined(event, email):
    if not email:
        return False
    for attendee in _values(event, "ATTENDEE"):
        if str(attendee).lower().removeprefix("mailto:") == email:
            return str(attendee.params.get("PARTSTAT", "")).upper() == "DECLINED"
    return False


def _local(value, tz):
    return value.replace(tzinfo=tz) if value.tzinfo is None else value


def occurrences(raw, account, start, end, tz):
    """(timed, allday) of one feed between the aware datetimes START and END.

    timed: {id, uid, start, end, title, account, color, join} with epoch seconds;
    allday: {title, account, color, first, last} with ISO dates, LAST exclusive.
    Cancelled occurrences and ones the account's email declined are left out.
    """
    calendar = icalendar.Calendar.from_ical(raw)
    timed, allday = [], []
    for event in recurring_ical_events.of(calendar, skip_bad_series=True).between(start, end):
        if str(event.get("STATUS", "")).upper() == "CANCELLED" or declined(event, account.email):
            continue
        title = " ".join(str(event.get("SUMMARY", "")).split()) or "(tanpa judul)"
        begin = event["DTSTART"].dt
        finish = event["DTEND"].dt if "DTEND" in event else None
        if not isinstance(begin, dt.datetime):
            last = finish if isinstance(finish, dt.date) else begin + dt.timedelta(days=1)
            allday.append({"title": title, "account": account.name, "color": account.color,
                           "first": begin.isoformat(), "last": last.isoformat()})
            continue
        begin = _local(begin, tz)
        if not isinstance(finish, dt.datetime):
            duration = event["DURATION"].dt if "DURATION" in event else dt.timedelta(0)
            finish = begin + duration
        finish = _local(finish, tz)
        uid = str(event.get("UID", title))
        epoch = int(begin.timestamp())
        timed.append({"id": hashlib.sha1(f"{uid}|{epoch}".encode()).hexdigest()[:12], "uid": uid,
                      "start": epoch, "end": int(finish.timestamp()), "title": title,
                      "account": account.name, "color": account.color, "join": join_link(event)})
    return timed, allday
