"""Background thread running one lookup at a time; the newest submission wins."""

import sys
import threading

from .lookup import LookupResult, lookup_lyrics


class LookupWorker:
    def __init__(self, cache):
        self.cache = cache
        self.condition = threading.Condition()
        self.pending = None
        self.completed = None
        self.closed = False
        self.thread = threading.Thread(target=self.run, name="lyrics-lookup", daemon=True)
        self.thread.start()

    def submit(self, key, track):
        with self.condition:
            self.pending = (key, dict(track)) if key is not None else None
            self.condition.notify()

    def take_result(self):
        with self.condition:
            result, self.completed = self.completed, None
            return result

    def close(self):
        with self.condition:
            self.closed = True
            self.pending = None
            self.condition.notify()

    def run(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.closed or self.pending is not None)
                if self.closed:
                    return
                key, track = self.pending
                self.pending = None
            try:
                result = lookup_lyrics(track, self.cache)
            except Exception as error:
                print("lyrics: worker failed: " + str(error), file=sys.stderr)
                result = LookupResult(None)
            with self.condition:
                self.completed = (key, result.lines, result.retry_at, result.plain)
