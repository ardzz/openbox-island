"""Package import contract."""

import importlib
import sys
import unittest
from unittest import mock

from . import fixtures  # noqa: F401  (puts eww/scripts on sys.path)


class MainTests(unittest.TestCase):
    def test_module_loads_without_ytmusicapi(self):
        loaded = [name for name in sys.modules if name.split(".")[0] == "lyrics_pkg"]
        # patch.dict restores the original modules afterwards, so other tests keep their patches.
        with mock.patch.dict(sys.modules, {"ytmusicapi": None}):
            for name in loaded:
                del sys.modules[name]
            module = importlib.import_module("lyrics_pkg.main")
            lookup = importlib.import_module("lyrics_pkg.lookup")
        self.assertTrue(callable(module.main))
        self.assertTrue(callable(lookup.lookup_lyrics))
