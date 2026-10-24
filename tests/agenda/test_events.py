"""Expanding feeds: recurrence, exceptions, all-day, declined, cancelled and join links."""

import unittest

from .fixtures import FEED, HOME, OFFICE, TZ, at, window
from agenda_pkg.events import occurrences


def timed_of(day, account=OFFICE):
    timed, _ = occurrences(FEED, account, *window(day), TZ)
    return {(event["title"], event["start"]): event for event in timed}


class EventsTests(unittest.TestCase):
    def test_weekly_series_skips_exdates_and_follows_moved_occurrences(self):
        self.assertNotIn(("Weekly Report", at(14, 10)), timed_of(14))
        week = timed_of(21)
        self.assertNotIn(("Weekly Report", at(21, 10)), week)
        self.assertEqual(week[("Weekly Report", at(22, 14))]["end"], at(22, 15))
        self.assertIn(("Weekly Report", at(28, 10)), timed_of(28))

    def test_declined_events_are_left_out_only_for_the_declining_account(self):
        self.assertNotIn(("Sync vendor", at(21, 13)), timed_of(21))
        self.assertIn(("Sync vendor", at(21, 13)), timed_of(21, HOME))

    def test_cancelled_events_are_left_out(self):
        self.assertFalse(any(title == "Dibatalkan" for title, _ in timed_of(21)))

    def test_floating_times_are_local_and_duration_sets_the_end(self):
        review = timed_of(21)[("Review kode", at(22, 9))]
        self.assertEqual(review["end"], at(22, 9, 45))

    def test_join_links_come_from_conference_location_or_description(self):
        week = timed_of(21, HOME)
        self.assertEqual(week[("Standup", at(21, 15))]["join"], "https://meet.google.com/xyz-abcd-efg")
        self.assertEqual(week[("Sync vendor", at(21, 13))]["join"], "https://us02web.zoom.us/j/123456789?pwd=abc")
        self.assertEqual(week[("Weekly Report", at(22, 14))]["join"], "https://meet.google.com/abc-defg-hij")

    def test_rows_carry_the_account_and_a_stable_id_per_occurrence(self):
        first, second = timed_of(21), timed_of(21)
        standup = first[("Standup", at(21, 15))]
        self.assertEqual((standup["account"], standup["color"]), ("Kantor", "#4f8cff"))
        self.assertEqual(standup["id"], second[("Standup", at(21, 15))]["id"])
        self.assertNotEqual(standup["id"], first[("Weekly Report", at(22, 14))]["id"])

    def test_all_day_events_report_their_date_span(self):
        _, allday = occurrences(FEED, OFFICE, *window(21), TZ)
        spans = {item["title"]: (item["first"], item["last"]) for item in allday}
        self.assertEqual(spans["Cuti Bersama"], ("2026-10-21", "2026-10-22"))
        self.assertEqual(spans["Konferensi"], ("2026-10-20", "2026-10-23"))
