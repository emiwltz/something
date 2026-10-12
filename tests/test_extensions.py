"""The extension loader: what it loads, what it rejects and what it says about it, on fake files dropped in a
temporary folder. Then the boundary: without an extension the core polls Herdr alone, it names no harness, and
the real extensions load.
"""
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from something import extensions, herdr      # noqa: E402
from something.poll import SESSION_KEYS, Poller  # noqa: E402

# The names Herdr gives to the harnesses that have had a reader here: the core carries none of them. A reader that
# is removed leaves its name in this list without harm; nothing here depends on the files of extensions/.
HARNESSES = ("omp", "claude", "codex", "opencode", "pi")
SNAPSHOT = {"workspaces": [{"workspace_id": "w1", "label": "trial"}],
            "agents": [{"terminal_id": "term_1", "agent_status": "working", "workspace_id": "w1", "tab_id": "w1:t1",
                        "pane_id": "w1:p1", "focused": True, "revision": 3, "agent": "trial"}]}


def reader(harness="trial", extra=""):
    """The text of a valid reader, which imports the core by its name; `extra`: lines to add to it."""
    return (f"from something import guards\n\nHARNESS = {harness!r}\n{extra}\n\n"
            "def session(agent):\n    return {'id': 's-1', 'path': '/tmp/trial/s-1.jsonl'}\n\n"
            "def read(session, now):\n    return {'model': guards.text('model-' + HARNESS)}\n")


class Case(unittest.TestCase):
    """An empty extensions folder, where each test drops its files. No read of Herdr is opened at the start;
    `herdr.opened` gets its previous state back at the end of the test. The socket something would call does not
    exist: a call that a test expects to be refused never reaches a real Herdr, even if the refusal breaks."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        for patch in (mock.patch.object(herdr, "opened", set()),
                      mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": str(self.folder / "no-herdr.sock")})):
            patch.start()
            self.addCleanup(patch.stop)

    def load(self, **files):
        """Drops these files (name without ".py" → text) and returns what the loader makes of them."""
        for name, text in files.items():
            (self.folder / f"{name}.py").write_text(text, encoding="utf-8")
        return extensions.load(self.folder)


class Load(Case):
    def test_a_valid_reader_is_loaded(self):
        readers, reported = self.load(trial=reader())
        self.assertEqual(reported, [{"name": "trial", "harness": "trial", "error": None}])
        self.assertEqual(list(readers), ["trial"])
        self.assertEqual(readers["trial"].read(None, 0), {"model": "model-trial"}, "the file's module")

    def test_the_file_name_is_not_the_harness_name(self):
        readers, reported = self.load(my_reader=reader("trial"))
        self.assertEqual((list(readers), reported[0]["name"], reported[0]["harness"]),
                         (["trial"], "my_reader", "trial"))

    def test_a_hidden_file_is_ignored(self):
        # "._trial.py" is what macOS leaves next to a file on some disks, ".#trial.py" an editor's lock.
        _, reported = self.load(**{"trial": reader(), "._trial": "\x00\x05\x16\x07", ".#trial": "",
                                   ".hidden": reader()})
        self.assertEqual([r["name"] for r in reported], ["trial"])

    def test_a_file_with_an_underscore_name_is_ignored(self):
        self.assertEqual(self.load(_draft=reader(), _helper="raise RuntimeError('never imported')"), ({}, []))

    def test_a_missing_or_empty_folder_loads_nothing(self):
        self.assertEqual(extensions.load(self.folder), ({}, []))
        self.assertEqual(extensions.load(self.folder / "missing"), ({}, []))

    def test_a_file_that_raises_on_import_is_reported_and_the_others_are_loaded(self):
        readers, reported = self.load(a=reader("before"), b="raise RuntimeError('failure ' + 'x' * 500)",
                                      c="this isn't Python", d=reader("after"))
        self.assertEqual(sorted(readers), ["after", "before"])
        self.assertEqual([(x["name"], x["harness"], x["error"] is None) for x in reported],
                         [("a", "before", True), ("b", None, False), ("c", None, False), ("d", "after", True)])
        self.assertIn("RuntimeError", reported[1]["error"])
        self.assertIn("SyntaxError", reported[2]["error"])
        self.assertLessEqual(len(reported[1]["error"]), 200)

    def test_a_file_that_exits_on_import_is_reported_and_does_not_stop_the_start(self):
        readers, reported = self.load(a="import sys\nsys.exit(3)", b="raise SystemExit", c=reader("after"))
        self.assertEqual(list(readers), ["after"])
        self.assertEqual([(x["name"], x["harness"], x["error"] is None) for x in reported],
                         [("a", None, False), ("b", None, False), ("c", "after", True)])
        self.assertIn("SystemExit", reported[0]["error"])

    def test_without_a_harness_the_extension_is_rejected(self):
        readers, reported = self.load(missing=reader().replace("HARNESS = 'trial'", ""), empty=reader(""),
                                      number=reader(3))
        self.assertEqual(readers, {})
        self.assertEqual([(x["harness"], bool(x["error"])) for x in reported], [(None, True)] * 3)

    def test_without_session_or_without_read_the_extension_is_rejected(self):
        readers, reported = self.load(without_read=reader("a").replace("def read", "def reads"),
                                      without_session=reader("b").replace("def session", "def sessions"),
                                      not_a_function=reader("c") + "\nread = 'later'\n")
        self.assertEqual(readers, {})
        self.assertEqual([x["harness"] for x in reported], ["c", "a", "b"], "the harness is reported, rejection too")
        for entry, missing in zip(reported, ("read", "read", "session")):
            self.assertIn(missing, entry["error"])

    def test_the_second_reader_of_a_harness_is_rejected(self):
        readers, reported = self.load(a=reader("trial", "RANK = 1"), b=reader("trial", "RANK = 2"))
        self.assertEqual(readers["trial"].RANK, 1, "the first in name order keeps the harness")
        self.assertEqual([(x["name"], x["error"] is None) for x in reported], [("a", True), ("b", False)])


class HerdrReads(Case):
    def test_an_action_asked_of_herdr_rejects_the_extension(self):
        for asked in ('{"agent.send_keys"}', '{"pane.process_info", "agent.send_keys"}', '{"unknown.method"}',
                      '{"pane.read"}', "None"):         # an action, an action among what is allowed, another read
            with self.subTest(asked):
                readers, reported = self.load(action=reader(extra=f"HERDR = {asked}"))
                self.assertEqual(readers, {}, "the extension is not loaded")
                self.assertEqual((reported[0]["harness"], bool(reported[0]["error"])), ("trial", True))
                self.assertEqual(herdr.opened, set(), "nothing is opened, not even the allowed read")
        with self.assertRaises(ValueError):
            herdr.call("agent.send_keys", {"target": "w1:p1", "keys": "y"})

    def test_an_allowed_read_is_opened(self):
        with self.assertRaises(ValueError):                 # closed as long as no extension asks for it
            herdr.call("pane.process_info", {"target": "w1:p1"})
        readers, reported = self.load(trial=reader(extra='HERDR = {"pane.process_info"}'))
        self.assertEqual((list(readers), reported[0]["error"]), (["trial"], None))
        self.assertEqual(herdr.opened, {"pane.process_info"})
        with self.assertRaises(herdr.Unavailable):          # allowed: the call goes out, to a missing socket
            herdr.call("pane.process_info", {"target": "w1:p1"})
        with self.assertRaises(ValueError):                 # another read stays closed
            herdr.call("pane.read", {"target": "w1:p1"})

    def test_a_rejected_reader_opens_nothing(self):
        self.load(a=reader(), b=reader(extra='HERDR = {"pane.process_info"}'))      # b: second of the harness
        self.assertEqual(herdr.opened, set())


class Boundary(Case):
    """What the core does with its extensions, and without them."""

    def setUp(self):
        super().setUp()
        for name, returned in (("snapshot", SNAPSHOT), ("version", {"version": "0.9.3", "protocol": 22})):
            replaced = mock.patch.object(herdr, name, return_value=returned)
            setattr(self, name, replaced.start())
            self.addCleanup(replaced.stop)

    def test_without_a_reader_the_core_polls_herdr_alone(self):
        state = Poller().poll()
        agent, = state["agents"]
        self.assertEqual((state["error"], state["extensions"]), (None, []))
        self.assertEqual((agent["id"], agent["harness"], agent["state"], agent["workspace"]),
                         ("w1:p1", "trial", "working", "trial"))
        self.assertEqual({agent[key] for key in ("session", "read_error") + SESSION_KEYS}, {None})

    def test_a_loaded_extension_reads_its_harness(self):
        agent, = Poller(*self.load(trial=reader())).poll()["agents"]
        self.assertEqual((agent["session"]["id"], agent["model"], agent["read_error"]), ("s-1", "model-trial", None))

    def test_the_state_reports_the_loaded_and_rejected_extensions(self):
        readers, reported = self.load(trial=reader(), failure="raise RuntimeError('failure')")
        poller = Poller(readers, reported)
        self.assertEqual([x["name"] for x in reported], ["failure", "trial"])
        self.assertEqual(poller.state()["extensions"], reported, "before the first poll")
        self.assertEqual(poller.poll()["extensions"], reported)
        self.snapshot.side_effect = herdr.Unavailable("connection refused")
        self.assertEqual(poller.poll()["extensions"], reported, "during a failure of Herdr")

    def test_the_core_names_no_harness(self):
        """The rule: no line of a file of `something/` carries a harness name written as Herdr writes it, in lowercase
        and as a whole word. The name of a product in a sentence ("OMP", "Claude Code") is not one: the core does
        nothing with it."""
        word = re.compile(r"\b(?:%s)\b" % "|".join(HARNESSES))
        files = sorted((ROOT / "something").glob("*.py"))
        self.assertIn("poll.py", [f.name for f in files])
        for file in files:
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                self.assertIsNone(word.search(line), f"{file.name}:{number}: {line.strip()}")

    def test_the_real_extensions_load(self):
        """The real folder: its modules are loaded, but neither `session` nor `read` is called. No session file
        is read."""
        readers, reported = extensions.load()
        self.assertEqual([x for x in reported if x["error"]], [], "no extension in error")
        self.assertLessEqual(herdr.opened, {"pane.process_info"}, "at most one read of Herdr is opened")


if __name__ == "__main__":
    unittest.main()
