"""The agenda document: rows, states, labels, next event and all-day titles."""

import unittest

from .fixtures import TZ, at
from agenda_pkg.render import agenda


def event(title, start, end, uid=None, account="Kantor", join=""):
    return {"id": f"id-{title}", "uid": uid or title, "start": start, "end": end, "title": title,
            "account": account, "color": "#4f8cff", "join": join}


def doc(timed, now, allday=(), errors=()):
    return agenda(list(timed), list(allday), list(errors), now, TZ, "09:55", False)


class RenderTests(unittest.TestCase):
    def test_rows_cover_today_and_tomorrow_in_time_order(self):
        result = doc([event("Besok", at(22, 9), at(22, 10)), event("Pagi", at(21, 8), at(21, 9)),
                      event("Lusa", at(23, 9), at(23, 10)), event("Siang", at(21, 13), at(21, 14))],
                     at(21, 10))
        self.assertEqual([row["title"] for row in result["rows"]], ["Pagi", "Siang", "Besok"])
        self.assertEqual([row["time"] for row in result["rows"]],
                         ["08:00–09:00", "13:00–14:00", "Besok 09:00–10:00"])
        self.assertEqual([row["day"] for row in result["rows"]], ["Hari ini", "Hari ini", "Besok"])

    def test_states_mark_past_running_soon_and_later(self):
        result = doc([event("a", at(21, 9), at(21, 10)), event("b", at(21, 9, 30), at(21, 10, 30)),
                      event("c", at(21, 10, 15), at(21, 11)), event("d", at(21, 10, 16), at(21, 11))],
                     at(21, 10))
        self.assertEqual([row["state"] for row in result["rows"]], ["past", "now", "soon", "later"])

    def test_a_zero_length_event_runs_for_a_minute(self):
        result = doc([event("pengingat", at(21, 10), at(21, 10))], at(21, 10))
        self.assertEqual(result["rows"][0]["state"], "now")
        self.assertEqual(doc([event("pengingat", at(21, 10), at(21, 10))], at(21, 10, 1))["rows"][0]["state"], "past")

    def test_label_counts_todays_events_not_yet_over_and_next_is_the_first_of_them(self):
        result = doc([event("lewat", at(21, 8), at(21, 9)), event("jalan", at(21, 9, 30), at(21, 10, 30)),
                      event("nanti", at(21, 15), at(21, 16)), event("besok", at(22, 9), at(22, 10))],
                     at(21, 10))
        self.assertEqual((result["label"], result["remaining"]), ("Kalender 2", 2))
        self.assertEqual(result["next"]["title"], "jalan")
        empty = doc([event("lewat", at(21, 8), at(21, 9))], at(21, 10))
        self.assertEqual((empty["label"], empty["next"]), ("Kalender", None))

    def test_the_same_occurrence_from_two_accounts_shows_once(self):
        result = doc([event("rapat", at(21, 13), at(21, 14), uid="u1"),
                      event("rapat", at(21, 13), at(21, 14), uid="u1", account="Pribadi")], at(21, 10))
        self.assertEqual([row["account"] for row in result["rows"]], ["Kantor"])

    def test_all_day_titles_cover_today_only_once_each(self):
        allday = [{"title": "Cuti", "first": "2026-10-21", "last": "2026-10-22"},
                  {"title": "Konferensi", "first": "2026-10-20", "last": "2026-10-23"},
                  {"title": "Cuti", "first": "2026-10-21", "last": "2026-10-22"},
                  {"title": "Kemarin", "first": "2026-10-20", "last": "2026-10-21"}]
        self.assertEqual(doc([], at(21, 10), allday)["allday"], ["Cuti", "Konferensi"])

    def test_document_reports_freshness_and_errors(self):
        result = agenda([], [], ["Kantor: HTTP 404"], at(21, 10), TZ, "09:55", True)
        self.assertEqual((result["ok"], result["stale"], result["updated"], result["errors"]),
                         (True, True, "09:55", ["Kantor: HTTP 404"]))
