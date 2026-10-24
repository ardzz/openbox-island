"""Google API items converted to ICS and expanded by the iCal pipeline."""

import hashlib
import unittest

from .fixtures import at
from .google_fixtures import dtstart, item, occurrences
from agenda_pkg import google


class ToIcsTests(unittest.TestCase):
    def test_skips_cancelled_declined_and_startless_and_carries_fields(self):
        items = [
            item(summary="Rapat", location="Ruang 1", description="Bawa laptop"),
            item(id="c1", iCalUID="c1@google.com", summary="Batal", status="cancelled"),
            item(id="d1", iCalUID="d1@google.com", summary="Ditolak",
                 attendees=[{"email": "reky@kantor.co.id", "self": True,
                             "responseStatus": "declined"}]),
            item(id="d2", iCalUID="d2@google.com", summary="Ditolak orang lain",
                 attendees=[{"email": "boss@kantor.co.id", "self": False,
                             "responseStatus": "declined"}]),
            {"id": "nostart", "iCalUID": "nostart@google.com", "summary": "Tanpa mulai"},
        ]
        raw = google.to_ics(items)
        text = raw.decode()
        for part in (b"BEGIN:VCALENDAR", b"VERSION:2.0", b"PRODID"):
            self.assertIn(part, raw)
        for part in ("SUMMARY:Rapat", "LOCATION:Ruang 1", "DESCRIPTION:Bawa laptop",
                     "UID:evt1@google.com", "Ditolak orang lain"):
            self.assertIn(part, text)
        for part in ("Batal", "UID:c1@google.com", "UID:d1@google.com", "nostart"):
            self.assertNotIn(part, text)

    def test_all_day_dates_and_missing_end(self):
        items = [
            item(id="ad1", iCalUID="ad1@google.com", summary="Cuti",
                 start={"date": "2026-10-21"}, end={"date": "2026-10-23"}),
            item(id="ad2", iCalUID="ad2@google.com", summary="Libur",
                 start={"date": "2026-10-24"}, end={}),
        ]
        timed, allday = occurrences(google.to_ics(items))
        spans = {entry["title"]: (entry["first"], entry["last"]) for entry in allday}
        self.assertEqual(spans, {"Cuti": ("2026-10-21", "2026-10-23"),
                                 "Libur": ("2026-10-24", "2026-10-25")})
        self.assertEqual(timed, [])

    def test_recurring_instances_all_survive_with_series_id(self):
        instances = []
        for day, hour in ((21, 8), (21, 10), (22, 8)):
            instances.append(item(
                id=f"series_{day}T{hour}", iCalUID="series@google.com", summary="Rutin",
                recurringEventId="series",
                start={"dateTime": dtstart(day, hour)},
                end={"dateTime": dtstart(day, hour, 30)},
                originalStartTime={"dateTime": dtstart(day, hour)}))
        timed, _ = occurrences(google.to_ics(instances))
        rutin = [event for event in timed if event["title"] == "Rutin"]
        self.assertEqual(len(rutin), 3)
        expected = {hashlib.sha1(f"series@google.com|{at(day, hour)}".encode()).hexdigest()[:12]
                    for day, hour in ((21, 8), (21, 10), (22, 8))}
        self.assertEqual({event["id"] for event in rutin}, expected)
        self.assertTrue(all(event["uid"] == "series@google.com" for event in rutin))

    def test_recurrence_id_falls_back_to_start_and_supports_all_day(self):
        items = [
            item(id="r1", iCalUID="series2@google.com", summary="Rutin2",
                 recurringEventId="series2",
                 start={"dateTime": dtstart(21, 9)}, end={"dateTime": dtstart(21, 9, 30)}),
            item(id="r2", iCalUID="series2@google.com", summary="Rutin2",
                 recurringEventId="series2",
                 start={"dateTime": dtstart(21, 11)}, end={"dateTime": dtstart(21, 11, 30)}),
            item(id="rd1", iCalUID="dayseries@google.com", summary="Harian",
                 recurringEventId="dayseries",
                 start={"date": "2026-10-21"}, end={"date": "2026-10-22"},
                 originalStartTime={"date": "2026-10-20"}),
            item(id="rd2", iCalUID="dayseries@google.com", summary="Harian",
                 recurringEventId="dayseries",
                 start={"date": "2026-10-22"}, end={"date": "2026-10-23"},
                 originalStartTime={"date": "2026-10-21"}),
        ]
        timed, allday = occurrences(google.to_ics(items))
        self.assertEqual(len([e for e in timed if e["title"] == "Rutin2"]), 2)
        self.assertEqual(sorted(e["first"] for e in allday if e["title"] == "Harian"),
                         ["2026-10-21", "2026-10-22"])

    def test_join_from_hangout_link_and_conference_data(self):
        items = [
            item(id="j1", iCalUID="j1@google.com", summary="Meet langsung",
                 hangoutLink="https://meet.google.com/abc-defg-hij"),
            item(id="j2", iCalUID="j2@google.com", summary="Meet conference",
                 conferenceData={"entryPoints": [
                     {"entryPointType": "phone", "uri": "tel:+62-21"},
                     {"entryPointType": "video",
                      "uri": "https://meet.google.com/xyz-abcd-efg"}]}),
            item(id="j3", iCalUID="j3@google.com", summary="Meet dua-duanya",
                 hangoutLink="https://meet.google.com/first-aaaa-bbb",
                 conferenceData={"entryPoints": [
                     {"entryPointType": "video",
                      "uri": "https://meet.google.com/second-cccc-ddd"}]}),
        ]
        timed, _ = occurrences(google.to_ics(items))
        joins = {event["title"]: event["join"] for event in timed}
        self.assertEqual(joins, {
            "Meet langsung": "https://meet.google.com/abc-defg-hij",
            "Meet conference": "https://meet.google.com/xyz-abcd-efg",
            "Meet dua-duanya": "https://meet.google.com/first-aaaa-bbb"})

    def test_uses_id_when_ical_uid_is_missing(self):
        raw = google.to_ics([item(id="only-id", iCalUID=None)])
        self.assertIn(b"UID:only-id", raw)
        self.assertEqual(occurrences(raw)[0][0]["uid"], "only-id")

    def test_naive_datetime_uses_its_timezone(self):
        jakarta = {"dateTime": "2026-10-21T08:00:00", "timeZone": "Asia/Jakarta"}
        jakarta_end = {"dateTime": "2026-10-21T08:30:00", "timeZone": "Asia/Jakarta"}
        items = [
            item(start=dict(jakarta), end=dict(jakarta_end)),
            item(id="mv1", iCalUID="series@google.com", summary="Rutin",
                 recurringEventId="series",
                 start={"dateTime": "2026-10-21T10:00:00", "timeZone": "Asia/Jakarta"},
                 end={"dateTime": "2026-10-21T10:30:00", "timeZone": "Asia/Jakarta"},
                 originalStartTime={"dateTime": "2026-10-21T08:00:00",
                                    "timeZone": "Asia/Jakarta"}),
            item(id="mv2", iCalUID="series@google.com", summary="Rutin",
                 recurringEventId="series",
                 start={"dateTime": "2026-10-22T10:00:00", "timeZone": "Asia/Jakarta"},
                 end={"dateTime": "2026-10-22T10:30:00", "timeZone": "Asia/Jakarta"},
                 originalStartTime={"dateTime": "2026-10-22T08:00:00",
                                    "timeZone": "Asia/Jakarta"}),
            item(id="bad", iCalUID="bad@google.com", summary="Zona rusak",
                 start={"dateTime": "2026-10-21T09:00:00", "timeZone": "Mars/Olympus"},
                 end={"dateTime": "2026-10-21T09:30:00", "timeZone": "Mars/Olympus"}),
        ]
        timed, _ = occurrences(google.to_ics(items))
        by_title = {(e["title"], e["start"]): e for e in timed}
        self.assertEqual(by_title[("Standup", at(21, 8))]["end"], at(21, 8, 30))
        rutin = sorted(e["start"] for e in timed if e["title"] == "Rutin")
        self.assertEqual(rutin, [at(21, 10), at(22, 10)])
        self.assertFalse(any(e["title"] == "Zona rusak" for e in timed))


if __name__ == "__main__":
    unittest.main()
