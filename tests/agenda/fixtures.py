"""Shared fixtures for the agenda package tests."""

import datetime as dt
from pathlib import Path
import sys
import zoneinfo

SCRIPTS = Path(__file__).resolve().parents[2] / "eww" / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from agenda_pkg.config import Account  # noqa: E402

TZ = zoneinfo.ZoneInfo("Asia/Jakarta")
OFFICE = Account("Kantor", "#4f8cff", "reky@kantor.co.id", "https://calendar.example/kantor/basic.ics")
HOME = Account("Pribadi", "#34c759", "", "https://calendar.example/pribadi/basic.ics")


def at(day, hour=0, minute=0):
    """Epoch seconds of 2026-10-DAY HOUR:MINUTE WIB."""
    return int(dt.datetime(2026, 10, day, hour, minute, tzinfo=TZ).timestamp())


def window(day):
    start = dt.datetime(2026, 10, day, tzinfo=TZ)
    return start, start + dt.timedelta(days=2)


FEED = b"""BEGIN:VCALENDAR
PRODID:-//Google Inc//Google Calendar 70.9054//EN
VERSION:2.0
X-WR-TIMEZONE:Asia/Jakarta
BEGIN:VTIMEZONE
TZID:Asia/Jakarta
BEGIN:STANDARD
TZOFFSETFROM:+0700
TZOFFSETTO:+0700
TZNAME:WIB
DTSTART:19700101T000000
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
DTSTART;TZID=Asia/Jakarta:20261007T100000
DTEND;TZID=Asia/Jakarta:20261007T103000
RRULE:FREQ=WEEKLY;BYDAY=WE
EXDATE;TZID=Asia/Jakarta:20261014T100000
UID:weekly-report@google.com
SUMMARY:Weekly Report
DESCRIPTION:Join with Google Meet: https://meet.google.com/abc-defg-hij\\nAgenda
ATTENDEE;CN=Reky;PARTSTAT=ACCEPTED:mailto:reky@kantor.co.id
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Jakarta:20261022T140000
DTEND;TZID=Asia/Jakarta:20261022T150000
RECURRENCE-ID;TZID=Asia/Jakarta:20261021T100000
UID:weekly-report@google.com
SUMMARY:Weekly Report
DESCRIPTION:Join with Google Meet: https://meet.google.com/abc-defg-hij
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261021
DTEND;VALUE=DATE:20261022
UID:cuti@google.com
SUMMARY:Cuti Bersama
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261020
DTEND;VALUE=DATE:20261023
UID:konferensi@google.com
SUMMARY:Konferensi
END:VEVENT
BEGIN:VEVENT
DTSTART:20261021T060000Z
DTEND:20261021T070000Z
UID:sync@google.com
SUMMARY:Sync vendor
LOCATION:https://us02web.zoom.us/j/123456789?pwd=abc
ATTENDEE;CN=Reky;PARTSTAT=DECLINED:mailto:Reky@Kantor.co.id
END:VEVENT
BEGIN:VEVENT
DTSTART:20261021T080000Z
DTEND:20261021T083000Z
UID:standup@google.com
SUMMARY:Standup
X-GOOGLE-CONFERENCE:https://meet.google.com/xyz-abcd-efg
END:VEVENT
BEGIN:VEVENT
DTSTART:20261022T090000
DURATION:PT45M
UID:review@google.com
SUMMARY:Review   kode
LOCATION:https://us02web.zoom.us/j/987654321
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Jakarta:20261022T110000
DTEND;TZID=Asia/Jakarta:20261022T113000
UID:batal@google.com
STATUS:CANCELLED
SUMMARY:Dibatalkan
END:VEVENT
END:VCALENDAR
""".replace(b"\n", b"\r\n")
