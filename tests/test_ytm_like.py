"""Contracts for the ytmusicapi like-status helper of the YouTube Music buttons."""

from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "eww" / "scripts" / "ytm_like.py"


def load():
    spec = importlib.util.spec_from_file_location("ytm_like", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeYTMusic:
    calls = []
    playlist = {}
    error = None

    def __init__(self, auth):
        self.auth = auth

    def get_watch_playlist(self, video_id, limit=25):
        FakeYTMusic.calls.append((self.auth, video_id, limit))
        if FakeYTMusic.error:
            raise FakeYTMusic.error
        return FakeYTMusic.playlist


def watch(*tracks):
    return {"tracks": [{"videoId": v, "title": "T", "likeStatus": s} for v, s in tracks],
            "lyrics": "MPLYt_x"}


class LikeHelperTest(unittest.TestCase):
    def setUp(self):
        self.helper = load()
        self.tmp = tempfile.TemporaryDirectory()
        self.auth = Path(self.tmp.name) / "auth.json"
        self.auth.write_text("{}")
        FakeYTMusic.calls = []
        FakeYTMusic.playlist = watch(("vidA0000001", "LIKE"))
        FakeYTMusic.error = None
        fake = types.ModuleType("ytmusicapi")
        fake.YTMusic = FakeYTMusic
        patches = [mock.patch.dict(sys.modules, {"ytmusicapi": fake}),
                   mock.patch.dict(os.environ, {"OB_YTM_AUTH": str(self.auth)})]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.addCleanup(self.tmp.cleanup)

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = self.helper.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_prints_the_like_status_of_the_requested_video(self):
        for status in ("LIKE", "DISLIKE", "INDIFFERENT"):
            FakeYTMusic.playlist = watch(("vidA0000001", status), ("vidZ0000009", "LIKE"))
            self.assertEqual(self.run_main("vidA0000001")[:2], (0, f"{status}\n"))
        self.assertEqual(FakeYTMusic.calls[0], (str(self.auth), "vidA0000001", 1))

    def test_a_watch_list_without_the_video_or_with_an_unknown_status_prints_nothing(self):
        FakeYTMusic.playlist = watch(("vidZ0000009", "LIKE"))
        self.assertEqual(self.run_main("vidA0000001")[:2], (1, ""))
        FakeYTMusic.playlist = watch(("vidA0000001", None))
        self.assertEqual(self.run_main("vidA0000001")[:2], (1, ""))
        FakeYTMusic.playlist = {}
        self.assertEqual(self.run_main("vidA0000001")[:2], (1, ""))

    def test_api_errors_print_nothing_and_stay_quiet(self):
        FakeYTMusic.error = RuntimeError("HTTP 500")
        self.assertEqual(self.run_main("vidA0000001"), (1, "", ""))

    def test_missing_auth_file_is_unavailable(self):
        self.auth.unlink()
        self.assertEqual(self.run_main("vidA0000001")[:2], (3, "UNAVAILABLE\n"))
        self.assertEqual(FakeYTMusic.calls, [])

    def test_missing_ytmusicapi_is_unavailable(self):
        with mock.patch.dict(sys.modules, {"ytmusicapi": None}):
            self.assertEqual(self.run_main("vidA0000001"), (3, "UNAVAILABLE\n", ""))

    def test_invalid_video_ids_are_rejected_without_a_request(self):
        for bad in ([], ["../etc"], ["vidA0000001", "extra"], [""]):
            self.assertEqual(self.run_main(*bad)[:2], (2, ""))
        self.assertEqual(FakeYTMusic.calls, [])

    def test_default_auth_is_the_ytm_player_login(self):
        with mock.patch.dict(os.environ, {"HOME": self.tmp.name}, clear=False):
            os.environ.pop("OB_YTM_AUTH")
            self.assertEqual(self.helper.auth_path(),
                             Path(self.tmp.name) / ".config" / "ytm-player" / "auth.json")


if __name__ == "__main__":
    unittest.main()
