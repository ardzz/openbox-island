"""Background lookup worker."""

from unittest import mock

from .fixtures import LyricsCase
from .ytm_fixtures import ytm_track
from lyrics_pkg import worker as worker_module
from lyrics_pkg.lookup import LookupResult
from lyrics_pkg.worker import LookupWorker


class WorkerTests(LyricsCase):
    def test_worker_delivers_plain_lyrics(self):
        result = LookupResult(None, None, ["Plain"])
        with mock.patch.object(worker_module, "lookup_lyrics", return_value=result):
            worker = LookupWorker(cache=None)
            try:
                worker.submit("key", ytm_track())
                for _ in range(200):
                    completed = worker.take_result()
                    if completed is not None:
                        break
                    worker.thread.join(0.01)
                self.assertEqual(completed, ("key", None, None, ["Plain"]))
            finally:
                worker.close()
