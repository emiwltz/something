"""The OpenCode reader, on a fake database with the exact schema of the real one. No real text: all is invented."""
import itertools
import json
import shutil
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import extensions, guards  # noqa: E402

opencode = extensions.import_file(extensions.FOLDER / "opencode.py")

T0 = datetime(2026, 10, 7, 4, 0, tzinfo=timezone.utc).timestamp()   # the zero instant of the fake database
NOW = T0 + 3600
KEYS = {"title", "model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents", "activity"}
SES = "ses_" + "0" * 26                       # the pane's session; the real identifiers are 30 characters long
MODEL = ("openai", "gpt-test", "high")        # provider, model, effort (`variant`)

# The four tables the reader reads and their indexes, taken from the real database (OpenCode 1.18) by sqlite_master.
SCHEMA = """
CREATE TABLE `session` (
    `id` text PRIMARY KEY, `project_id` text NOT NULL, `parent_id` text, `slug` text NOT NULL,
    `directory` text NOT NULL, `title` text NOT NULL, `version` text NOT NULL, `share_url` text,
    `summary_additions` integer, `summary_deletions` integer, `summary_files` integer, `summary_diffs` text,
    `revert` text, `permission` text, `time_created` integer NOT NULL, `time_updated` integer NOT NULL,
    `time_compacting` integer, `time_archived` integer, `workspace_id` text, `path` text, `agent` text,
    `model` text, `cost` real DEFAULT 0 NOT NULL, `tokens_input` integer DEFAULT 0 NOT NULL,
    `tokens_output` integer DEFAULT 0 NOT NULL, `tokens_reasoning` integer DEFAULT 0 NOT NULL,
    `tokens_cache_read` integer DEFAULT 0 NOT NULL, `tokens_cache_write` integer DEFAULT 0 NOT NULL,
    `metadata` text,
    CONSTRAINT `fk_session_project_id_project_id_fk` FOREIGN KEY (`project_id`) REFERENCES `project`(`id`)
        ON DELETE CASCADE);
CREATE TABLE `message` (
    `id` text PRIMARY KEY, `session_id` text NOT NULL, `time_created` integer NOT NULL,
    `time_updated` integer NOT NULL, `data` text NOT NULL,
    CONSTRAINT `fk_message_session_id_session_id_fk` FOREIGN KEY (`session_id`) REFERENCES `session`(`id`)
        ON DELETE CASCADE);
CREATE TABLE `part` (
    `id` text PRIMARY KEY, `message_id` text NOT NULL, `session_id` text NOT NULL,
    `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `data` text NOT NULL,
    CONSTRAINT `fk_part_message_id_message_id_fk` FOREIGN KEY (`message_id`) REFERENCES `message`(`id`)
        ON DELETE CASCADE);
CREATE TABLE `todo` (
    `session_id` text NOT NULL, `content` text NOT NULL, `status` text NOT NULL, `priority` text NOT NULL,
    `position` integer NOT NULL, `time_created` integer NOT NULL, `time_updated` integer NOT NULL,
    CONSTRAINT `todo_pk` PRIMARY KEY(`session_id`, `position`),
    CONSTRAINT `fk_todo_session_id_session_id_fk` FOREIGN KEY (`session_id`) REFERENCES `session`(`id`)
        ON DELETE CASCADE);
CREATE INDEX `message_session_time_created_id_idx` ON `message` (`session_id`,`time_created`,`id`);
CREATE INDEX `part_message_id_id_idx` ON `part` (`message_id`,`id`);
CREATE INDEX `part_session_idx` ON `part` (`session_id`);
CREATE INDEX `session_parent_idx` ON `session` (`parent_id`);
CREATE INDEX `session_project_idx` ON `session` (`project_id`);
CREATE INDEX `session_workspace_idx` ON `session` (`workspace_id`);
CREATE INDEX `todo_session_idx` ON `todo` (`session_id`);
"""


# The factory: each function returns a value as OpenCode writes it in a `data` column.

def ms(t):
    """`t` seconds after T0, in Unix milliseconds: the unit of all OpenCode's dates."""
    return int((T0 + t) * 1000)


def text(content, **fields):
    return {"type": "text", "text": content, **fields}


def tool(name, status="completed", t=0, **inputs):
    """A tool part in one of the four states OpenCode writes: pending, running, completed, error."""
    state = {"status": status, "input": inputs}
    if status == "pending":
        state["raw"] = ""
    elif status == "running":
        state["time"] = {"start": ms(t)}
    elif status == "completed":
        state.update(output="result", metadata={"truncated": False}, title=name,
                     time={"start": ms(t), "end": ms(t + 1)})
    else:
        state.update(error="the tool failed", time={"start": ms(t), "end": ms(t + 1)})
    return {"type": "tool", "tool": name, "callID": "call_test", "state": state}


def question(label, *options, multiple=None):
    q = {"question": label, "header": "Test", "options": [{"label": o, "description": "…"} for o in options]}
    return q if multiple is None else {**q, "multiple": multiple}


def herdr(kind, value):
    return {"agent": "opencode",
            "agent_session": {"agent": "opencode", "kind": kind, "source": "herdr:opencode", "value": value}}


class Database:
    """A fake OpenCode database, held open for writing as by a running OpenCode. Each method writes rows as
    OpenCode writes them; `t`: seconds after T0."""

    def __init__(self, folder):
        self.sql = sqlite3.connect(str(folder / "opencode.db"), isolation_level=None)    # each write is committed
        self.sql.execute("PRAGMA journal_mode=WAL")
        self.sql.executescript(SCHEMA)
        self._numbers = itertools.count(1)

    def _id(self, kind):
        return "%s_%026d" % (kind, next(self._numbers))       # increasing, like the real ones

    def session(self, ident=SES, parent=None, title="Test session", model=MODEL, cost=0, t=0, agent="build"):
        """A `session` row. `model` None: a session from before the `model` column."""
        chosen = None
        if model:
            chosen = {"id": model[1], "providerID": model[0], **({"variant": model[2]} if model[2] else {})}
        self.sql.execute(
            "INSERT INTO session (id, project_id, parent_id, slug, directory, title, version, summary_additions,"
            " summary_deletions, summary_files, time_created, time_updated, path, agent, model, cost)"
            " VALUES (?, 'global', ?, 'neutral-test', '/tmp/test', ?, '1.18.20', 0, 0, 0, ?, ?, '', ?, ?, ?)",
            (ident, parent, title, ms(t), ms(t), agent, chosen and json.dumps(chosen), cost))
        return ident

    def message(self, data, t=0, session=SES):
        """A `message` row; `data`: an object, or a raw text for a hostile column."""
        ident = self._id("msg")
        self.sql.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (ident, session, ms(t), ms(t), _column(data)))
        return ident

    def part(self, message, data, t=0, session=SES):
        ident = self._id("prt")
        self.sql.execute("INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)",
                         (ident, message, session, ms(t), ms(t), _column(data)))
        return ident

    def change(self, part, data, t):
        """OpenCode rewrites a part in place when its tool changes state."""
        self.sql.execute("UPDATE part SET data = ?, time_updated = ? WHERE id = ?", (_column(data), ms(t), part))

    def user(self, content, t=0, session=SES, added=()):
        """A received message: the typed text (None: none), then those OpenCode adds to it itself (`synthetic`)."""
        chosen = {"providerID": "openai", "modelID": "gpt-test", "variant": "high"}
        message = self.message({"role": "user", "time": {"created": ms(t)}, "agent": "build", "model": chosen,
                                "summary": {"diffs": []}}, t, session)
        for part in ([text(content)] if content else []) + [text(a, synthetic=True) for a in added]:
            self.part(message, part, t, session)
        return message

    def assistant(self, *parts, t=0, session=SES, finish="tool-calls", tokens=1000, cost=0, model=MODEL, error=None):
        """A reply from the model and its parts, between step-start and step-finish; its context is `tokens` + 600.
        `finish` None: the reply is in progress. `error`: it was interrupted, without tokens or `finish`."""
        count = {"input": 0, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}}
        if tokens:
            count = {"total": tokens + 600, "input": tokens, "output": 20, "reasoning": 10,
                     "cache": {"read": 500, "write": 70}}
        data = {"parentID": "msg_" + "9" * 26, "role": "assistant", "mode": "build", "agent": "build",
                "path": {"cwd": "/tmp/test", "root": "/tmp/test"}, "cost": cost, "tokens": count,
                "modelID": model[1], "providerID": model[0], "time": {"created": ms(t)}}
        if model[2]:
            data["variant"] = model[2]
        if error:
            data["error"] = {"name": error, "data": {"message": "interrupted"}}
        elif finish:
            data["finish"] = finish
        if error or finish:
            data["time"]["completed"] = ms(t + 1)
        message = self.message(data, t, session)
        closing = {"reason": finish, "type": "step-finish", "tokens": count, "cost": cost}
        for part in [{"type": "step-start"}, *parts, *([closing] if finish and not error else [])]:
            self.part(message, part, t, session)
        return message

    def todos(self, *tasks, session=SES):
        """The todo list, which OpenCode replaces in full at each write: (content, status), in order.
        The rows are inserted backwards: only their `position` says the order."""
        self.sql.execute("DELETE FROM todo WHERE session_id = ?", (session,))
        rows = [(session, content, status, i, ms(0), ms(0)) for i, (content, status) in enumerate(tasks)]
        self.sql.executemany("INSERT INTO todo VALUES (?, ?, ?, 'medium', ?, ?, ?)", rows[::-1])


def _column(data):
    return data if isinstance(data, str) else json.dumps(data, separators=(",", ":"), ensure_ascii=False)


class Case(unittest.TestCase):
    """A fake database in a temporary folder, in place of the real root."""

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="something-opencode-"))
        self.addCleanup(shutil.rmtree, self.folder, True)
        for name, value in (("ROOT", self.folder), ("MODELS", self.folder / "models.json"), ("TIMEOUT", 0.05)):
            patch = mock.patch.object(opencode, name, value)
            patch.start()
            self.addCleanup(patch.stop)
        opencode._cache.clear()
        opencode._windows.clear()
        self.db = Database(self.folder)
        self.addCleanup(self.db.sql.close)
        self.session = {"id": SES, "path": str(self.folder / "opencode.db")}

    def read(self, now=NOW):
        state = opencode.read(self.session, now)
        self.assertEqual(set(state), KEYS)
        return state

    def close(self):
        """Closes the database like an OpenCode that stops: it is left alone in its folder. Apple's SQLite keeps
        its -shm file and an empty -wal there; they are removed, as the other SQLites do themselves."""
        self.db.sql.close()
        for leftover in self.folder.glob("opencode.db-*"):
            leftover.unlink()

    def reopen(self):
        self.db.sql = sqlite3.connect(str(self.folder / "opencode.db"), isolation_level=None)
        self.addCleanup(self.db.sql.close)

    def files(self):
        return {file.name: file.read_bytes() for file in self.folder.iterdir()}

    def models(self, catalog):
        """The fake models.json: {provider: {model: window}}, put in the shape of the real one."""
        entries = {p: {"id": p, "models": {m: {"id": m, "limit": {"context": window, "output": 1000}}
                                           for m, window in models.items()}} for p, models in catalog.items()}
        opencode.MODELS.write_text(json.dumps(entries), encoding="utf-8")


class Session(Case):
    def test_known(self):
        self.db.session()
        self.assertEqual(opencode.session(herdr("id", SES)), self.session)

    def test_unknown_or_without_identifier(self):
        self.db.session()
        for agent in (None, "opencode", {}, {"agent_session": None}, {"agent_session": SES}, herdr("id", None),
                      herdr("id", 12), herdr("id", ""), herdr("path", SES), herdr("id", "ses_unknown")):
            self.assertIsNone(opencode.session(agent), agent)

    def test_database_missing(self):
        with mock.patch.object(opencode, "ROOT", self.folder / "elsewhere"):
            for call in (lambda: opencode.session(herdr("id", SES)), self.read, lambda: opencode.turns(self.session)):
                with self.assertRaises(OSError) as raised:
                    call()
                self.assertIn("opencode.db", str(raised.exception))     # the sentence says which database is missing


class Reading(Case):
    def test_session_without_message(self):
        self.db.session(t=-30)
        state = self.read()
        self.assertEqual((state["title"], state["model"], state["effort"]),
                         ("Test session", "openai/gpt-test", "high"))
        self.assertEqual(state["activity"], guards.iso(T0 - 30))
        self.assertEqual((state["todos"], state["subagents"]), ([], []))
        for key in ("context", "cost", "tool", "request", "goal"):
            self.assertIsNone(state[key], key)

    def test_session_gone(self):
        self.db.session()
        self.read()
        self.db.sql.execute("DELETE FROM session")
        with self.assertRaises(OSError):
            self.read()

    def test_chosen_model(self):
        self.db.session(model=("ollama-cloud", "glm-test", "max"))
        self.db.assistant(text("Hello"), finish="stop")         # another model's reply, before the change
        state = self.read()
        self.assertEqual((state["model"], state["effort"]), ("ollama-cloud/glm-test", "max"))

    def test_model_by_fallback(self):
        self.db.session(model=None)
        self.assertEqual((self.read()["model"], self.read()["effort"]), (None, None))
        self.db.assistant(text("Hello"), finish="stop", model=("ollama-cloud", "glm-test", "max"))
        state = self.read()
        self.assertEqual((state["model"], state["effort"]), ("ollama-cloud/glm-test", "max"))

    def test_effort_missing(self):
        self.db.session(model=("openai", "gpt-test", None))
        self.db.assistant(text("Hello"), finish="stop")         # its effort, "high", is not the choice's
        self.assertEqual((self.read()["model"], self.read()["effort"]), ("openai/gpt-test", None))

    def test_effort_missing_from_the_fallback(self):
        self.db.session(model=None)
        self.db.assistant(text("Hello"), finish="stop", model=("openai", "gpt-test", None))
        self.assertEqual((self.read()["model"], self.read()["effort"]), ("openai/gpt-test", None))

    def test_context_without_known_window(self):
        self.db.session()
        self.db.assistant(text("Hello"), finish="stop", tokens=1000)
        self.assertEqual(self.read()["context"], {"tokens": 1600, "window": None, "percent": None})
        self.models({"ollama-cloud": {"gpt-test": 4000}, "openai": {"other": 4000}})      # never both at once
        self.db.assistant(text("Again"), t=5, finish="stop", tokens=1400)
        self.assertEqual(self.read()["context"], {"tokens": 2000, "window": None, "percent": None})

    def test_percentage_when_the_window_is_known(self):
        self.models({"openai": {"gpt-test": 4000}})
        self.db.session()
        self.db.assistant(text("Hello"), finish="stop", tokens=400)
        self.assertEqual(self.read()["context"], {"tokens": 1000, "window": 4000, "percent": 25})
        self.db.assistant(text("Again"), t=5, finish="stop", tokens=9400)
        self.assertEqual(self.read()["context"]["percent"], 100)         # never more than the window

    def test_the_window_is_that_of_the_model_that_replied(self):
        self.models({"openai": {"gpt-test": 4000}, "ollama-cloud": {"glm-test": 8000}})
        self.db.session()                                           # the choice: openai/gpt-test
        self.db.assistant(text("Hello"), finish="stop", tokens=400, model=("ollama-cloud", "glm-test", "max"))
        self.assertEqual(self.read()["context"], {"tokens": 1000, "window": 8000, "percent": 12})

    def test_context_ignores_an_interrupted_reply(self):
        self.db.session()
        self.db.assistant(text("Hello"), finish="stop", tokens=1000)
        self.db.assistant(t=5, tokens=0, error="MessageAbortedError")
        self.assertEqual(self.read()["context"]["tokens"], 1600)

    def test_models_json_unreadable_then_read_again(self):
        self.db.session()
        self.db.assistant(text("Hello"), finish="stop", tokens=400)
        for hostile in ("{cut", "[1, 2]", '{"openai": {"models": {"gpt-test": {"limit": {"context": "x"}}}}}',
                        '{"openai": ["models"], "x": {"models": {"y": 12}}}'):
            opencode.MODELS.write_text(hostile, encoding="utf-8")
            opencode._cache.clear()
            self.assertEqual(self.read()["context"], {"tokens": 1000, "window": None, "percent": None}, hostile)
        self.models({"openai": {"gpt-test": 2000}})
        opencode._cache.clear()
        self.assertEqual(self.read()["context"]["percent"], 50)

    def test_zero_cost_is_unknown(self):
        self.db.session(cost=0)                     # subscription or free model: OpenCode writes 0
        self.db.assistant(text("Hello"), finish="stop")
        self.assertIsNone(self.read()["cost"])

    def test_cost(self):
        self.db.session(cost=1.25)
        self.assertEqual(self.read()["cost"], 1.25)

    def test_a_cost_too_small_to_be_written_is_unknown_too(self):
        self.db.session(cost=0.00004)               # with four decimals it would read as a zero
        self.assertIsNone(self.read()["cost"])

    def test_tool_running_then_finished(self):
        self.db.session()
        self.db.user("Run the command")
        message = self.db.assistant(t=10, finish=None)
        part = self.db.part(message, tool("bash", "pending"), 10)
        self.assertEqual(self.read()["tool"], {"name": "bash", "since": None})        # not started yet
        self.db.change(part, tool("bash", "running", 11, command="make"), 11)
        self.assertEqual(self.read()["tool"], {"name": "bash", "since": guards.iso(T0 + 11)})
        self.db.user("And then?", t=12)         # a message received while the tool runs does not hide it
        self.assertEqual(self.read()["tool"]["name"], "bash")
        self.db.change(part, tool("bash", "completed", 11, command="make"), 20)
        self.assertIsNone(self.read()["tool"])
        self.assertIsNone(self.read()["request"])

    def test_tool_in_error_is_no_longer_running(self):
        self.db.session()
        self.db.assistant(tool("bash", "error", 10, command="make"), t=10)
        self.assertIsNone(self.read()["tool"])

    def test_tools_in_parallel(self):
        self.db.session()
        self.db.assistant(tool("read", "completed", 10, filePath="/tmp/a"),
                          tool("grep", "running", 11, pattern="x"), tool("bash", "running", 12, command="make"),
                          t=10, finish=None)
        self.assertEqual(self.read()["tool"], {"name": "bash", "since": guards.iso(T0 + 12)})

    def test_only_the_last_message_carries_a_running_tool(self):
        self.db.session()
        self.db.assistant(tool("bash", "running", 10, command="make"), t=10, finish=None)   # wrongly left open
        self.db.assistant(text("Resumed"), t=20, finish="stop")
        self.assertIsNone(self.read()["tool"])

    def test_tool_left_open_in_an_abandoned_reply(self):
        self.db.session()
        message = self.db.assistant(t=10, finish=None)
        self.db.part(message, tool("bash", "pending"), 20)
        state = self.read(T0 + 20 + opencode.RECENT - 1)        # the session wrote a little less than two hours ago
        self.assertEqual(state["tool"], {"name": "bash", "since": None})
        for now in (T0 + 20 + opencode.RECENT, T0 + 5 * 86400):             # two hours, then five days
            state = self.read(now)
            self.assertIsNone(state["tool"])
            self.assertEqual(state["activity"], guards.iso(T0 + 20))

    def test_a_question_asked_stays_even_when_old(self):
        self.db.session()
        message = self.db.assistant(t=10, finish=None)
        self.db.part(message, tool("question", "running", 10, questions=[question("Which fruit?", "Apple")]), 10)
        state = self.read(T0 + 5 * 86400)                       # five days: the agent still waits for its answer
        self.assertEqual(state["request"]["kind"], "question")
        self.assertIsNotNone(state["tool"])

    def test_question_open_then_answered(self):
        self.db.session()
        message = self.db.assistant(t=10, finish=None)
        asked = tool("question", "running", 10, questions=[
            question("Which fruit?", "Apple", "Pear"), question("Which colors?", "Red", "Green", multiple=True),
            question("", "Empty"), "not a question"])
        part = self.db.part(message, asked, 10)
        state = self.read()
        self.assertEqual(state["tool"]["name"], "question")
        self.assertEqual(state["request"], {"kind": "question", "questions": [
            {"question": "Which fruit?", "options": ["Apple", "Pear"], "multi": False},
            {"question": "Which colors?", "options": ["Red", "Green"], "multi": True}]})
        self.db.change(part, {**asked, "state": {**asked["state"], "status": "completed", "output": "Apple"}}, 30)
        self.assertIsNone(self.read()["request"])

    def test_question_with_unreadable_arguments(self):
        self.db.session()
        self.db.assistant(tool("question", "running", 10, questions="Which fruit?"), t=10, finish=None)
        self.assertEqual(self.read()["request"], {"kind": "question", "questions": []})

    def test_todos(self):
        self.db.session()
        self.assertEqual(self.read()["todos"], [])
        self.db.todos(("Read", "completed"), ("Write", "in_progress"), ("Reread", "pending"),
                      ("Discard", "cancelled"))                 # a status something cannot say
        self.assertEqual(self.read()["todos"], [
            {"text": "Read", "status": "done", "phase": None},
            {"text": "Write", "status": "in_progress", "phase": None},
            {"text": "Reread", "status": "pending", "phase": None}])
        self.db.todos()
        self.assertEqual(self.read()["todos"], [])

    def test_todos_of_another_session(self):
        self.db.session()
        self.db.session("ses_other")
        self.db.todos(("Elsewhere", "pending"), session="ses_other")
        self.assertEqual(self.read()["todos"], [])

    def test_activity_is_the_last_write(self):
        self.db.session(t=0)                        # the session's row is only touched again at the end of a reply
        message = self.db.assistant(t=10, finish=None)
        self.assertEqual(self.read()["activity"], guards.iso(T0 + 10))
        part = self.db.part(message, tool("bash", "running", 20, command="make"), 20)
        self.assertEqual(self.read()["activity"], guards.iso(T0 + 20))
        self.db.change(part, tool("bash", "completed", 20, command="make"), 45)
        self.assertEqual(self.read()["activity"], guards.iso(T0 + 45))

    def test_read_again_only_when_the_database_changes(self):
        self.db.session()
        with mock.patch.object(opencode, "_read_session", wraps=opencode._read_session) as read_session:
            self.read()
            self.read()
            self.assertEqual(read_session.call_count, 1)
            self.db.assistant(text("Hello"), finish="stop")
            self.assertEqual(self.read()["context"]["tokens"], 1600)
            self.assertEqual(read_session.call_count, 2)

    def test_read_again_when_a_closed_database_is_rewritten(self):
        self.db.session()
        self.close()
        self.assertEqual(self.read()["title"], "Test session")          # read alone in its folder, and remembered
        self.reopen()
        self.db.sql.execute("UPDATE session SET title = 'Second title'")
        self.close()                            # written then closed between two reads: only the database changed
        self.assertEqual(self.read()["title"], "Second title")
        self.reopen()
        self.db.sql.execute("UPDATE session SET title = 'Third title'")             # written in the -wal, and held
        self.assertEqual(self.read()["title"], "Third title")

    def test_a_held_database_returns_its_last_writes(self):
        self.db.session()
        self.db.user("Hello")
        self.assertEqual(self.read()["title"], "Test session")
        checkpointed = (self.folder / "opencode.db").read_bytes()
        self.db.sql.execute("UPDATE session SET title = 'Other title'")
        self.db.user("Again", t=5)
        self.db.session("ses_new")
        self.assertEqual((self.folder / "opencode.db").read_bytes(), checkpointed)      # written in the -wal only
        self.assertEqual(self.read()["title"], "Other title")
        self.assertEqual([t["text"] for t in opencode.turns(self.session)["turns"]], ["Hello", "Again"])
        self.assertIsNotNone(opencode.session(herdr("id", "ses_new")))

    def test_nothing_is_written_next_to_a_closed_database(self):
        self.db.session()
        self.db.user("Hello")
        self.db.assistant(text("There."), t=1, finish="stop")
        self.close()
        before = self.files()
        self.assertEqual(list(before), ["opencode.db"])
        self.assertEqual(opencode.session(herdr("id", SES)), self.session)
        self.assertEqual(self.read()["context"]["tokens"], 1600)
        self.assertEqual(len(opencode.turns(self.session)["turns"]), 1)
        self.assertEqual(self.files(), before)          # no extra -wal or -shm, and the database has not moved


class Failures(Case):
    """OpenCode has already changed its storage: what the reader no longer finds there, it says."""

    def test_table_missing(self):
        self.db.session()
        self.db.assistant(text("Hello"), finish="stop")
        self.db.sql.execute("DROP TABLE part")
        for call in (self.read, lambda: opencode.turns(self.session)):
            with self.assertRaises(OSError) as raised:
                call()
            self.assertIn("part", str(raised.exception))        # the sentence says what is missing
        self.db.sql.execute("DROP TABLE session")
        with self.assertRaises(OSError) as raised:
            opencode.session(herdr("id", SES))
        self.assertIn("session", str(raised.exception))

    def test_column_missing(self):
        self.db.session()
        self.db.sql.execute("ALTER TABLE session RENAME COLUMN model TO renamed")
        with self.assertRaises(OSError) as raised:
            self.read()
        self.assertIn("model", str(raised.exception))

    def test_database_locked(self):
        self.db.session()
        self.close()
        lock = sqlite3.connect(str(self.folder / "opencode.db"), isolation_level=None)
        self.addCleanup(lock.close)
        lock.execute("PRAGMA locking_mode=EXCLUSIVE")
        lock.execute("UPDATE session SET title = 'Other title'")        # written in the -wal, and the lock stays held
        for call in (lambda: opencode.session(herdr("id", SES)), self.read, lambda: opencode.turns(self.session)):
            with self.assertRaises(OSError):
                call()
        lock.close()
        self.assertEqual(self.read()["title"], "Other title")           # the failure over, reading resumes

    def test_a_file_that_is_not_a_database(self):
        self.db.sql.close()
        for file in self.folder.glob("opencode.db*"):
            file.unlink()
        (self.folder / "opencode.db").write_text("this is not a SQLite database\n" * 200, encoding="utf-8")
        with self.assertRaises(OSError):
            opencode.session(herdr("id", SES))


class Robustness(Case):
    HOSTILES = ("{cut", "", "[1, 2]", '"text"', "null", "12", '{"role":{"a":1},"tokens":"abc","time":[]}',
                '{"role":"assistant","tokens":{"output":"abc","input":[]},"finish":12,"error":"x",'
                '"time":{"completed":"yesterday"},"providerID":{},"modelID":[]}',
                '{"role":"assistant","tokens":{"output":5,"input":null,"reasoning":true,"cache":7},"providerID":7}',
                '{"role":"user","time":"yesterday"}', '{"role":"assistant","error":{"name":7},"finish":["stop"]}')
    PARTS = ("{cut", "[1, 2]", "null", '{"type":"tool","tool":{"a":1},"state":"running"}',
             '{"type":"tool","tool":12,"state":{"status":"running","input":[],"time":"yesterday"}}',
             '{"type":"tool","tool":"bash","state":{"status":"running","input":{"command":{"a":1}},'
             '"time":{"start":"yesterday"}}}',
             '{"type":"tool","tool":"question","state":{"status":"pending","input":{"questions":{"question":"x"}}}}',
             '{"type":"text","text":{"a":1}}', '{"type":"text","text":12,"synthetic":"yes"}', '{"type":["text"]}')

    def test_hostile_columns(self):
        self.db.session()
        self.db.sql.execute("UPDATE session SET model = '{cut', cost = 'expensive', title = '', agent = 12")
        self.db.session("ses_child", parent=SES, t=3500)
        self.db.sql.execute("UPDATE session SET model = '[1]', title = x'00ff' WHERE id = 'ses_child'")
        self.db.todos(("Good", "pending"), ("", "pending"), ("No status", ""))
        for session in (SES, "ses_child"):
            for i, data in enumerate(self.HOSTILES):
                message = self.db.message(data, 3500 + i, session)
                for part in self.PARTS:
                    self.db.part(message, part, 3500 + i, session)
        state = self.read()
        self.assertEqual(state["todos"], [{"text": "Good", "status": "pending", "phase": None}])
        self.assertEqual(state["tool"], {"name": "question", "since": None})      # of the last readable message
        self.assertEqual(state["request"], {"kind": "question", "questions": []})
        child = state["subagents"][0]           # without a readable end mark, it has just written and a tool is open
        self.assertEqual((child["state"], child["name"], child["model"], child["end"]),
                         ("working", None, None, None))
        for key in ("title", "model", "effort", "context", "cost", "goal"):
            self.assertIsNone(state[key], key)
        page = opencode.turns(self.session)
        self.assertEqual(page, {"turns": [], "older": False, "before": None})

    def test_a_hostile_row_does_not_hide_the_good_ones(self):
        self.db.session()
        opener = self.db.user("Hello")
        message = self.db.assistant(text("I am looking"), t=10, finish=None, tokens=1000)
        self.db.part(message, tool("bash", "running", 11, command="make"), 11)
        for data in self.PARTS[:3]:
            self.db.part(message, data, 12)
        for data in self.HOSTILES[:6]:
            self.db.message(data, 20)
        state = self.read()
        self.assertEqual(state["tool"], {"name": "bash", "since": guards.iso(T0 + 11)})
        self.assertEqual(state["context"]["tokens"], 1600)
        turns = opencode.turns(self.session)["turns"]
        self.assertEqual([(t["id"], t["text"]) for t in turns], [(opener, "Hello")])
        self.assertEqual(turns[0]["replies"], [{"t": guards.iso(T0 + 10), "text": "I am looking"}])
        self.assertEqual(turns[0]["tools"], [{"name": "bash", "target": "make"}])

    def test_a_looping_parentage_does_not_run_forever(self):
        self.db.session()
        self.db.session("ses_a", parent=SES, t=3500)
        self.db.session("ses_b", parent="ses_a", t=3510)
        self.db.sql.execute("UPDATE session SET parent_id = 'ses_b' WHERE id = ?", (SES,))
        self.assertEqual([a["id"] for a in self.read()["subagents"]][-2:], ["ses_a", "ses_b"])


class Subagents(Case):
    def setUp(self):
        super().setUp()
        self.db.session()

    def child(self, ident, t=3500, parent=SES, kind="explore", model=("ollama-cloud", "glm-test", "max")):
        """A session born of the `task` tool: its title carries the subagent's description and kind."""
        self.db.session(ident, parent, f"Find the files (@{kind} subagent)", model, t=t, agent=kind)
        self.db.user("Find the files.", t, ident)
        return ident

    def states(self, now=NOW):
        return {a["id"]: a["state"] for a in self.read(now)["subagents"]}

    def test_done(self):
        self.child("ses_a", t=3000)
        self.db.assistant(tool("grep", "completed", 3010, pattern="x"), t=3010, session="ses_a")
        self.db.assistant(text("Found."), t=3020, session="ses_a", finish="stop")
        self.assertEqual(self.read()["subagents"], [{
            "id": "ses_a", "name": "Find the files (@explore subagent)", "type": "explore", "parent": None,
            "state": "done", "model": "ollama-cloud/glm-test", "start": guards.iso(T0 + 3000),
            "end": guards.iso(T0 + 3021)}])

    def test_failed(self):
        self.child("ses_a")
        self.db.assistant(t=3510, session="ses_a", tokens=0, error="MessageAbortedError")
        agent = self.read()["subagents"][0]
        self.assertEqual((agent["state"], agent["end"]), ("failed", guards.iso(T0 + 3511)))

    def test_resumed_after_being_done(self):
        self.child("ses_a", t=3000)
        self.db.assistant(text("Found."), t=3020, session="ses_a", finish="stop")
        self.db.assistant(tool("grep", "running", 3590, pattern="y"), t=3590, session="ses_a", finish=None)
        agent = self.read()["subagents"][0]
        self.assertEqual((agent["state"], agent["end"]), ("working", None))

    def test_restarted_by_a_message_after_being_done(self):
        self.child("ses_a", t=3000)
        self.db.assistant(text("Found."), t=3020, session="ses_a", finish="stop")
        self.child("ses_b", t=3000)
        self.db.assistant(t=3020, session="ses_b", tokens=0, error="MessageAbortedError")
        self.assertEqual(self.states(), {"ses_a": "done", "ses_b": "failed"})
        self.db.user("Find the tests too.", 3590, "ses_a")      # the brief of the restart, still without a reply
        self.db.user("Resume.", 3020, "ses_b")                  # in the millisecond of the reply, and silent since
        self.assertEqual([(a["id"], a["state"], a["end"]) for a in self.read()["subagents"]],
                         [("ses_a", "working", None), ("ses_b", "unknown", None)])
        self.db.assistant(text("Found too."), t=3595, session="ses_a", finish="stop")
        agent = self.read()["subagents"][0]
        self.assertEqual((agent["state"], agent["end"]), ("done", guards.iso(T0 + 3596)))

    def test_working_or_unknown(self):
        self.child("ses_recent", t=3570)                        # wrote 30 s ago
        self.child("ses_silent", t=3300)                        # silent for 5 min
        self.child("ses_tool", t=3300)                          # silent for 5 min, a tool open
        self.db.assistant(tool("bash", "running", 3300, command="make"), t=3300, session="ses_tool", finish=None)
        self.child("ses_tool_old", t=2400)                      # silent for 20 min, a tool open
        self.db.assistant(tool("bash", "running", 2400, command="make"), t=2400, session="ses_tool_old", finish=None)
        self.assertEqual(self.states(), {"ses_recent": "working", "ses_silent": "unknown", "ses_tool": "working",
                                         "ses_tool_old": "unknown"})

    def test_the_state_follows_the_time_without_the_database_changing(self):
        self.child("ses_a", t=3570)
        self.assertEqual(self.states(), {"ses_a": "working"})
        self.assertEqual(self.states(NOW + 600), {"ses_a": "unknown"})
        self.assertEqual(self.states(NOW + 3 * 3600), {})

    def test_two_hour_window(self):
        self.child("ses_old", t=3600 - 3 * 3600)
        self.db.assistant(text("Found."), t=3600 - 3 * 3600, session="ses_old", finish="stop")
        self.child("ses_recent", t=0)
        self.db.assistant(text("Found."), t=10, session="ses_recent", finish="stop")
        self.assertEqual(self.states(), {"ses_recent": "done"})

    def test_the_last_write_is_that_of_its_parts(self):
        self.child("ses_a", t=3600 - 3 * 3600)              # born 3 h ago: its row has not moved since
        message = self.db.assistant(t=3000, session="ses_a", finish=None)
        self.db.part(message, tool("bash", "running", 3590, command="make"), 3590, "ses_a")
        self.assertEqual(self.states(), {"ses_a": "working"})

    def test_grandchild(self):
        self.child("ses_a", t=3500)
        self.child("ses_b", t=3510, parent="ses_a", kind="general")
        agents = self.read()["subagents"]
        self.assertEqual([(a["id"], a["parent"], a["type"]) for a in agents],
                         [("ses_a", None, "explore"), ("ses_b", "ses_a", "general")])

    def test_the_children_of_another_session_do_not_count(self):
        self.db.session("ses_neighbor")
        self.child("ses_a", parent="ses_neighbor")
        self.assertEqual(self.read()["subagents"], [])

    def test_sorted_by_start_fifty_at_most(self):
        for i in range(55):                                     # the youngest wrote first
            self.child("ses_%02d" % i, t=3000 + i)
            self.db.assistant(text("Found."), t=3500 - i, session="ses_%02d" % i, finish="stop")
        agents = self.read()["subagents"]
        self.assertEqual([a["id"] for a in agents], ["ses_%02d" % i for i in range(50)])

    def test_model_by_fallback(self):
        self.child("ses_a", model=None)
        self.assertIsNone(self.read()["subagents"][0]["model"])
        self.db.assistant(text("Found."), t=3510, session="ses_a", finish="stop")
        self.assertEqual(self.read()["subagents"][0]["model"], "openai/gpt-test")


class Turns(Case):
    def setUp(self):
        super().setUp()
        self.db.session()

    def turns(self, limit=20, before=None):
        return opencode.turns(self.session, limit, before)

    def test_empty_conversation(self):
        self.assertEqual(self.turns(), {"turns": [], "older": False, "before": None})

    def test_splitting(self):
        one = self.db.user("Hello", t=0)
        self.db.assistant({"type": "reasoning", "text": "I am thinking.", "time": {"start": ms(1), "end": ms(2)}},
                          text("I am looking."), tool("read", "completed", 2, filePath="/tmp/test/a.py"),
                          tool("todowrite", "completed", 3, todos=[]), t=1)
        self.db.assistant(text("There."), t=5, finish="stop")
        two = self.db.user("Run the tests", t=60)
        self.db.assistant(tool("bash", "running", 61, command="make test", description="Run"), t=61, finish=None)
        page = self.turns()
        self.assertEqual((page["older"], page["before"]), (False, None))
        self.assertEqual(page["turns"], [
            {"id": one, "t": guards.iso(T0), "from": "user", "text": "Hello",
             "replies": [{"t": guards.iso(T0 + 1), "text": "I am looking."},
                         {"t": guards.iso(T0 + 5), "text": "There."}],
             "tools": [{"name": "read", "target": "/tmp/test/a.py"}, {"name": "todowrite", "target": None}],
             "end": guards.iso(T0 + 6)},
            {"id": two, "t": guards.iso(T0 + 60), "from": "user", "text": "Run the tests", "replies": [],
             "tools": [{"name": "bash", "target": "make test"}], "end": None}])

    def test_interrupted_turn(self):
        self.db.user("Hello")
        self.db.assistant(text("I am starting"), t=5, tokens=0, error="MessageAbortedError")
        turn = self.turns()["turns"][0]
        self.assertEqual((turn["replies"][0]["text"], turn["end"]), ("I am starting", guards.iso(T0 + 6)))

    def test_text_added_by_opencode(self):
        self.db.user("Read this file", t=0, added=("Called the Read tool", "content of the file"))
        self.db.assistant(text("Read."), t=1, finish="stop")
        self.db.user(None, t=10, added=("Continue if you have next steps.",))
        self.db.assistant(text("I continue."), t=11, finish="stop")
        self.assertEqual([(t["from"], t["text"]) for t in self.turns()["turns"]],
                         [("user", "Read this file"), ("system", "Continue if you have next steps.")])

    def test_a_message_without_text_opens_no_turn(self):
        one = self.db.user("Hello", t=0)
        self.db.assistant(text("There."), t=1, finish="stop")
        compaction = self.db.user(None, t=10)
        self.db.part(compaction, {"type": "compaction", "auto": True, "overflow": False}, 10)
        self.db.assistant(text("Summary of the session."), t=11, finish="stop")
        page = self.turns(1)
        self.assertEqual([t["id"] for t in page["turns"]], [one])
        self.assertEqual([r["text"] for r in page["turns"][0]["replies"]], ["There.", "Summary of the session."])
        self.assertFalse(page["older"])

    def test_a_blank_text_opens_no_turn(self):
        one = self.db.user("Hello", t=0)
        self.db.assistant(text("There."), t=1, finish="stop")
        for i, blank in enumerate((" \n\t", "  ", "", {"a": 1}, 12)):     # blank, or not a text
            self.db.part(self.db.user(None, t=10 + i), text(blank), 10 + i)
            self.db.assistant(text(f"Next {i}"), t=10 + i, finish="stop")
        two = self.db.user("Again", t=20)
        page = self.turns(1)
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]), ([two], True, two))
        page = self.turns(1, two)               # the turn before is returned, with all that was said up to `two`
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]), ([one], False, None))
        self.assertEqual([r["text"] for r in page["turns"][0]["replies"]],
                         ["There."] + [f"Next {i}" for i in range(5)])
        self.assertEqual([t["id"] for t in self.turns(5)["turns"]], [one, two])

    def test_clipping(self):
        self.db.user("a" * 5000)
        self.db.assistant(text("b" * 9000), tool("bash", "completed", 1, command="c" * 500), t=1, finish="stop")
        turn = self.turns()["turns"][0]
        self.assertEqual((len(turn["text"]), len(turn["replies"][0]["text"]), len(turn["tools"][0]["target"])),
                         (4000, 8000, 160))

    def test_paging_by_before(self):
        ids = []
        for i in range(5):                  # two turns in the same millisecond: the identifier tells them apart
            ids.append(self.db.user(f"Question {i}", t=10 * (i // 2)))
            self.db.assistant(text(f"Answer {i}"), t=10 * (i // 2), finish="stop")
        page = self.turns(2)
        self.assertEqual([t["id"] for t in page["turns"]], ids[3:])
        self.assertEqual((page["older"], page["before"]), (True, ids[3]))
        page = self.turns(2, page["before"])
        self.assertEqual([(t["id"], t["replies"][0]["text"]) for t in page["turns"]],
                         [(ids[1], "Answer 1"), (ids[2], "Answer 2")])
        self.assertEqual((page["older"], page["before"]), (True, ids[1]))
        page = self.turns(2, page["before"])
        self.assertEqual([t["id"] for t in page["turns"]], ids[:1])
        self.assertEqual((page["older"], page["before"]), (False, None))
        self.assertEqual([t["id"] for t in self.turns(0)["turns"]], ids[4:])      # one turn at least

    def test_a_page_reads_only_its_turns(self):
        for i in range(30):
            self.db.user(f"Question {i}", t=i)
            self.db.assistant(text(f"Answer {i}"), t=i, finish="stop")
        seen = []
        real = opencode._turns
        with mock.patch.object(opencode, "_turns", lambda rows: seen.extend(rows) or real(rows)):
            self.assertEqual(len(self.turns(3)["turns"]), 3)
        self.assertEqual(len({row[0] for row in seen}), 6)          # three received messages and their three replies

    def test_unknown_before(self):
        self.db.user("Hello")
        self.db.session("ses_other")
        elsewhere = self.db.user("Elsewhere", session="ses_other")
        for before in ("msg_unknown", elsewhere, ""):
            with self.assertRaises(LookupError):
                self.turns(20, before)


if __name__ == "__main__":
    unittest.main()
