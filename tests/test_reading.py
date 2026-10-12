"""The readers' toolbox: dates read, end of a file, lines followed in blocks, page of a conversation, SQLite
database read without writing anything next to it."""
import io
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from extensions import _reading as reading   # noqa: E402

INSTANT = 1791349200          # 2026-10-07T05:00:00Z


class Dates(unittest.TestCase):
    def test_seconds(self):
        for date in ("2026-10-07T05:00:00Z", "2026-10-07T05:00:00.000Z", "2026-10-07T07:00:00+02:00",
                     INSTANT, float(INSTANT), INSTANT * 1000):
            self.assertEqual(reading.seconds(date), INSTANT, date)
        for hostile in (True, False, None, "", "absurd text", "2026-13-45", [], {}, -1, float("nan"), float("inf"),
                        5e10, reading.SECONDS_MAX * 1000 + 1, 10 ** 400, -10 ** 400):
            self.assertIsNone(reading.seconds(hostile), hostile)


class Files(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.path = os.path.join(folder.name, "log.jsonl")

    def write(self, raw, mode="wb"):
        with open(self.path, mode) as f:
            f.write(raw)

    def test_fingerprint(self):
        self.assertIsNone(reading.fingerprint(self.path))
        self.assertIsNone(reading.fingerprint(None))
        self.write(b"abc\n")
        st = os.stat(self.path)
        self.assertEqual(reading.fingerprint(self.path), (4, st.st_mtime_ns, st.st_ino))

    def test_tail_lines(self):
        self.write(b"line one\nline two\n\naccent: \xc3\xa9\nunderway")
        self.assertEqual(reading.tail_lines(self.path), ["line one", "line two", "accent: é"])   # the whole file
        self.assertEqual(reading.tail_lines(self.path, 37), ["line two", "accent: é"])   # "ine one" is cut
        self.assertEqual(reading.tail_lines(self.path, 29), ["accent: é"])   # whole, perhaps cut: dropped
        self.assertEqual(reading.tail_lines(self.path, 3), [])
        self.write(b"\n", "ab")
        self.assertEqual(reading.tail_lines(self.path, 12), ["underway"])
        self.assertEqual(reading.tail_lines(self.path + ".missing"), [])
        self.assertEqual(reading.tail_lines(None), [])

    def test_lines_from(self):
        self.write(b"one\n\ntwo\nthr")
        self.assertEqual(list(reading.lines_from(self.path)), [("one", 4), ("two", 9)])   # "thr" is being written
        self.assertEqual(list(reading.lines_from(self.path, 9)), [])
        self.write(b"ee\nfour\n", "ab")
        self.assertEqual(list(reading.lines_from(self.path, 9)), [("three", 15), ("four", 20)])
        self.assertEqual(list(reading.lines_from(self.path, 4)), [("two", 9), ("three", 15), ("four", 20)])
        self.assertEqual(list(reading.lines_from(self.path, 20)), [])
        self.assertEqual(list(reading.lines_from(self.path, 500)), [])      # beyond the end: nothing

    def test_lines_from_reads_in_blocks(self):
        lines = ["a" * 5, "é" * 40, "b" * 7, "c" * 16, "d"]      # longer than a block, equal, shorter
        self.write("".join(l + "\n" for l in lines).encode() + b"underway")
        with mock.patch.object(reading, "BLOCK", 8):
            returned = list(reading.lines_from(self.path))
        self.assertEqual([l for l, _ in returned], lines)
        self.assertEqual([p for _, p in returned], [6, 87, 95, 112, 114])
        with open(self.path, "rb") as f:
            self.assertEqual(f.read()[114:], b"underway")      # the last position stops before the line being written

    def test_lines_from_never_loads_more_than_one_block(self):
        self.write(b"x" * 99 + b"\n" + b"y" * 400 + b"\n")
        asked = []

        class Spy(io.FileIO):
            def read(self, n=-1):
                asked.append(n)
                return super().read(n)
        with mock.patch.object(reading, "BLOCK", 64), mock.patch.object(reading, "open", Spy, create=True):
            self.assertEqual([p for _, p in reading.lines_from(self.path)], [100, 501])
        self.assertEqual(set(asked), {64})                      # never the file in one piece

    def test_lines_from_without_a_file(self):
        for hostile in (self.path, os.path.dirname(self.path), None, "a\x00b"):
            self.assertEqual(list(reading.lines_from(hostile, 0)), [], hostile)
        self.write(b"one\n")
        self.assertEqual(list(reading.lines_from(self.path, -5)), [])
        self.assertEqual(list(reading.lines_from(self.path, "3")), [])


def turns(lines):
    """The simplest of readers: one turn per line, which is its identifier."""
    return [{"id": line} for line in lines]


def names(start, end):
    return [f"t{i:03d}" for i in range(start, end)]


class Page(unittest.TestCase):
    """A log of forty turns, from "t000" to "t039": five bytes per line, two hundred in all."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.path = os.path.join(folder.name, "log.jsonl")
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("".join(name + "\n" for name in names(0, 40)))

    def page(self, limit, before=None):
        """(identifiers of the turns returned, older, before)."""
        returned = reading.page(self.path, turns, limit, before)
        self.assertEqual(list(returned), ["turns", "older", "before"])
        return [turn["id"] for turn in returned["turns"]], returned["older"], returned["before"]

    def test_the_last_turns(self):
        self.assertEqual(self.page(3), (names(37, 40), True, "t037"))
        self.assertEqual(reading.page(self.path, turns)["turns"], turns(names(20, 40)), "twenty by default")
        self.assertEqual(self.page(0), (["t039"], True, "t039"), "one turn at least")

    def test_the_previous_page_through_before(self):
        self.assertEqual(self.page(3, "t037"), (names(34, 37), True, "t034"))
        self.assertEqual(self.page(3, "t034"), (names(31, 34), True, "t031"))

    def test_before_is_none_when_there_is_nothing_older(self):
        self.assertEqual(self.page(40), (names(0, 40), False, None))
        self.assertEqual(self.page(50), (names(0, 40), False, None))
        self.assertEqual(self.page(3, "t003"), (names(0, 3), False, None))
        self.assertEqual(self.page(3, "t001"), (["t000"], False, None))
        self.assertEqual(self.page(3, "t000"), ([], False, None))
        open(self.path, "w").close()
        self.assertEqual(self.page(3), ([], False, None), "an empty log")

    def test_unknown_before_raises_lookup_error(self):
        with self.assertRaises(LookupError):
            self.page(3, "t404")

    def test_missing_log_raises_file_not_found_error(self):
        with self.assertRaises(FileNotFoundError):
            reading.page(self.path + ".missing", self.fail)        # nothing is read: `turns` is not called

    def test_the_window_grows_as_long_as_the_end_is_not_enough(self):
        with mock.patch.object(reading, "TAIL", 12), \
                mock.patch.object(reading, "tail_lines", wraps=reading.tail_lines) as read:
            def windows():
                asked = [call.args[1] for call in read.call_args_list]
                read.reset_mock()
                return asked
            self.assertEqual(self.page(5), (names(35, 40), True, "t035"))
            self.assertEqual(windows(), [12, 48], "two turns, then nine: enough, the log is not read in full")
            self.assertEqual(self.page(5, "t010"), (names(5, 10), True, "t005"))
            self.assertEqual(windows(), [12, 48, 192])
            self.assertEqual(self.page(5, "t005"), (names(0, 5), False, None))
            self.assertEqual(windows(), [12, 48, 192, 768], "up to the whole log")
            with self.assertRaises(LookupError):
                self.page(5, "t404")

    def test_at_the_ceiling_older_turns_may_exist(self):
        with mock.patch.object(reading, "TAIL", 12), mock.patch.object(reading, "CONVERSATION_MAX", 48):
            self.assertEqual(self.page(20), (names(31, 40), True, "t031"), "what the ceiling lets read")
            self.assertEqual(self.page(3, "t034"), (names(31, 34), True, "t031"))
            with self.assertRaises(LookupError):
                self.page(3, "t010")            # a turn from before the ceiling is not read


class Database(unittest.TestCase):
    """A database in WAL mode, like the harnesses', that a connection writes in a temporary folder."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = folder.name
        self.path = os.path.join(self.folder, "data.db")
        self.writer = sqlite3.connect(self.path)
        self.addCleanup(self.writer.close)
        self.writer.execute("PRAGMA journal_mode=WAL")
        self.writer.execute("CREATE TABLE turns (text)")
        self.write("first")

    def write(self, text):
        with self.writer:
            self.writer.execute("INSERT INTO turns VALUES (?)", (text,))

    def close(self):
        """Cleanly closes the connection that writes: nobody holds the database any more, only it remains. Apple's
        SQLite leaves, emptied, the -shm and -wal files that the others remove: they are removed here."""
        self.writer.close()
        for name in os.listdir(self.folder):
            if name != "data.db":
                os.remove(os.path.join(self.folder, name))

    def texts(self, database):
        return [text for text, in database.execute("SELECT text FROM turns")]

    def test_a_database_nobody_holds_is_read_without_any_file_appearing(self):
        self.close()
        with reading.database(self.path) as database:
            self.assertEqual(self.texts(database), ["first"])
            self.assertEqual(os.listdir(self.folder), ["data.db"], "neither -shm nor -wal during the read")
        self.assertEqual(os.listdir(self.folder), ["data.db"], "nor after")

    def test_a_database_held_by_another_connection_returns_the_last_writes(self):
        self.write("last")                      # in the -wal: the database's file does not carry it yet
        self.assertEqual(sorted(os.listdir(self.folder)), ["data.db", "data.db-shm", "data.db-wal"])
        with reading.database(self.path) as database:
            self.assertEqual(self.texts(database), ["first", "last"])
            self.write("during")
            self.assertEqual(self.texts(database), ["first", "last", "during"])

    def test_the_database_is_not_written(self):
        for held in (True, False):              # by another connection, then by nobody
            if not held:
                self.close()
            with self.subTest(held=held), reading.database(self.path) as database:
                with self.assertRaises(sqlite3.Error):
                    database.execute("INSERT INTO turns VALUES ('intruder')")
                self.assertEqual(self.texts(database), ["first"])

    def test_a_missing_database_raises_sqlite3_error_and_is_not_created(self):
        missing = os.path.join(self.folder, "missing.db")
        with self.assertRaises(sqlite3.Error):
            with reading.database(missing):
                self.fail("a missing database opened")
        self.assertFalse(os.path.exists(missing))

    def test_the_connection_is_closed_on_leaving_the_block(self):
        with reading.database(self.path) as database:
            self.assertEqual(self.texts(database), ["first"])
        with self.assertRaises(sqlite3.ProgrammingError):
            database.execute("SELECT 1")
        with self.assertRaises(RuntimeError):   # even when the block raises
            with reading.database(self.path) as database:
                raise RuntimeError("failure in the block")
        with self.assertRaises(sqlite3.ProgrammingError):
            database.execute("SELECT 1")


if __name__ == "__main__":
    unittest.main()
