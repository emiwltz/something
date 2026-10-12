"""The OMP reader, on fake logs with the exact shape of real ones. No real text: everything is invented."""
import itertools
import json
import os
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
from extensions import _reading as reading     # noqa: E402

omp = extensions.import_file(extensions.FOLDER / "omp.py")

UUID = "0199aaaa-bbbb-7ccc-8ddd-eeeeffff0001"
T0 = datetime(2026, 10, 7, 4, 0, tzinfo=timezone.utc).timestamp()   # the zero instant of the fake logs
NOW = T0 + 3600
KEYS = {"title", "model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents", "activity"}
_numbers = itertools.count(1)


# The line factory: each function returns a log line as OMP writes it.

def date(t):
    return datetime.fromtimestamp(T0 + t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def line(kind, t=0, **fields):
    """A line of the tree: type, 8-hex id, ISO date in UTC. `t`: seconds after T0."""
    o = {"type": kind, "id": "%08x" % next(_numbers), "parentId": None, "timestamp": date(t), **fields}
    return json.dumps(o, separators=(",", ":"), ensure_ascii=False)


def title(text="Test session"):
    return json.dumps({"type": "title", "v": 1, "title": text, "updatedAt": date(0), "pad": " " * 180},
                      separators=(",", ":"), ensure_ascii=False)


def header(ident=UUID, t=0, **fields):
    return line("session", t, version=3, id=ident, cwd="/tmp/test", **fields)


def user(text, t=0, attribution="user", **fields):
    message = {"role": "user", "content": [{"type": "text", "text": text}], "attribution": attribution}
    return line("message", t, message=message, **fields)


def assistant(*blocks, t=0, stop="toolUse", tokens=1000, cost=0.25, provider="anthropic", model="claude-opus-5-5"):
    """A reply of the model. `tokens` at 0: an interrupted reply, zero usage and no contextSnapshot."""
    usage = {"input": tokens, "output": 10 if tokens else 0, "cacheRead": 0, "cacheWrite": 0,
             "totalTokens": tokens + 10 if tokens else 0, "cost": {"input": cost, "output": 0, "total": cost}}
    message = {"role": "assistant", "content": list(blocks), "api": "anthropic-messages", "provider": provider,
               "model": model, "usage": usage, "stopReason": stop}
    if tokens:
        message["contextSnapshot"] = {"promptTokens": tokens, "nonMessageTokens": 100, "compactionEpoch": 0}
    return line("message", t, message=message)


def text(content):
    return {"type": "text", "text": content}


def call(ident, name, **arguments):
    return {"type": "toolCall", "id": ident, "name": name, "arguments": arguments, "intent": arguments.get("i")}


def tool_start(ident, name, t=0):
    """The start of a tool. As in real logs, `ask`, `todo` and `yield` carry no arguments there."""
    return line("custom", t, customType="tool_execution_start",
                data={"toolCallId": ident, "toolName": name, "startedAt": date(t)})


def result(ident, name, t=0, error=False, details=None):
    message = {"role": "toolResult", "toolCallId": ident, "toolName": name, "content": [text("result")],
               "details": details, "isError": error}
    return line("message", t, message=message)


def phases(*lists):
    """Todo phases: phases(("Prepare", [("Read", "completed")]), …)."""
    return [{"name": name, "tasks": [{"content": c, "status": s} for c, s in tasks]} for name, tasks in lists]


def goal(mode, status, t=0):
    body = {"id": "0123456789abcdef", "objective": "Tidy the workshop", "status": status, "tokensUsed": 1200,
            "timeUsedSeconds": 90, "createdAt": 1791345600000, "updatedAt": 1791345690000}
    return line("mode_change", t, mode=mode, data={"goal": body})


class Case(unittest.TestCase):
    """A fake OMP folder in a temporary folder, in place of the real root."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="something-omp-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        patch = mock.patch.object(omp, "ROOT", self.root)
        patch.start()
        self.addCleanup(patch.stop)
        omp._followed.clear()
        omp._windows.clear()
        self.path = self.root / "sessions" / "-tmp-test" / ("2026-10-07T04-00-00-000Z_" + UUID + ".jsonl")
        self.session = {"id": UUID, "path": str(self.path)}

    def write(self, *lines, path=None, age=0, head=None):
        """Writes a log (title, header, then `lines`), `age` seconds old."""
        path = path or self.path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(l + "\n" for l in (head or [title(), header()]) + list(lines)), encoding="utf-8")
        os.utime(path, (NOW - age, NOW - age))
        return path

    def append(self, *lines, end="\n", age=0):
        with open(self.path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + end)
        os.utime(self.path, (NOW - age, NOW - age))

    def subagent(self, name, *lines, age=0, t=0, kind="scout"):
        """The log of a subagent, with the first five lines OMP writes in it."""
        head = [title(name), header("0199aaaa-0000-7000-8000-%012x" % next(_numbers), t, parentSession=str(self.path)),
                line("model_change", t, model="anthropic/claude-sonnet-5-5", resolvedModelIsFallback=False),
                line("thinking_level_change", t, thinkingLevel="medium", configured=None),
                line("session_init", t, agent=kind, task="Search", tools=["read"], resolvedModel="x/other")]
        return self.write(*lines, path=self.path.with_suffix("") / (name + ".jsonl"), age=age, head=head)

    def read(self, now=NOW):
        state = omp.read(self.session, now)
        self.assertEqual(set(state), KEYS)
        return state


class Session(Case):
    def herdr(self, kind, value):
        return {"agent": "omp", "agent_session": {"agent": "omp", "kind": kind, "source": "herdr:omp", "value": value}}

    def test_by_path(self):
        self.assertEqual(omp.session(self.herdr("path", str(self.path))), self.session)

    def test_by_identifier(self):
        self.write()
        self.assertEqual(omp.session(self.herdr("id", UUID)), self.session)

    def test_absent(self):
        self.write()
        for agent in (None, "omp", {}, {"agent_session": None}, {"agent_session": "path"},
                      self.herdr("path", None), self.herdr("path", 12), self.herdr("other", str(self.path)),
                      self.herdr("id", "0199aaaa-unknown"), self.herdr("id", "*")):
            self.assertIsNone(omp.session(agent), agent)

    def test_a_file_outside_the_sessions_is_not_a_log(self):
        outside = str(self.root / "sessions" / "x" / ".." / ".." / "elsewhere.jsonl")
        for value in ("/etc/passwd", str(self.root / "models.db"), str(self.root / "elsewhere.jsonl"), outside,
                      str(self.path.with_suffix(".key")), "sessions/relative.jsonl", "a\x00b.jsonl"):
            self.assertIsNone(omp.session(self.herdr("path", value)), value)

    def test_an_ambiguous_identifier_links_nothing(self):
        self.write()
        self.write(path=self.root / "sessions" / "-other" / self.path.name)
        self.assertIsNone(omp.session(self.herdr("id", UUID)))


class Reading(Case):
    def test_empty_log_everything_is_unknown(self):
        self.write(age=30)
        state = self.read()
        self.assertEqual(state["title"], "Test session")
        self.assertEqual(state["activity"], guards.iso(NOW - 30))
        self.assertEqual((state["todos"], state["subagents"]), ([], []))
        for key in KEYS - {"title", "activity", "todos", "subagents"}:
            self.assertIsNone(state[key], key)

    def test_log_gone(self):
        with self.assertRaises(OSError):
            self.read()
        self.write()
        self.read()
        self.path.unlink()
        with self.assertRaises(OSError):
            self.read()

    def test_title_rewritten_in_place(self):
        self.write(user("Hello"))
        self.assertEqual(self.read()["title"], "Test session")
        content = self.path.read_text(encoding="utf-8").replace("Test session", "Renamed session", 1)
        self.path.write_text(content, encoding="utf-8")
        self.assertEqual(self.read()["title"], "Renamed session")

    def test_model_by_model_change(self):
        self.write(line("model_change", model="anthropic/claude-opus-5-5", resolvedModelIsFallback=False),
                   assistant(text("Hello")),
                   line("model_change", model="openai-codex/gpt-6-astra", resolvedModelIsFallback=False))
        self.assertEqual(self.read()["model"], "openai-codex/gpt-6-astra")   # holds once it appears, without a reply

    def test_model_by_fallback(self):
        self.write(assistant(text("Hello"), provider="ollama-cloud", model="glm-5.3-flash"))
        self.assertEqual(self.read()["model"], "ollama-cloud/glm-5.3-flash")

    def test_effort_changed_in_the_middle_of_the_log(self):
        self.write(line("thinking_level_change", thinkingLevel="low", configured="low"), assistant(text("One")))
        self.assertEqual(self.read()["effort"], "low")
        self.append(line("thinking_level_change", thinkingLevel="xhigh", configured="xhigh"),
                    *[assistant(text("Answer " + str(i))) for i in range(300)])
        self.assertEqual(self.read()["effort"], "xhigh")   # the change is far from the end, it counts all the same
        self.append(assistant(text("Again")))
        self.assertEqual(self.read()["effort"], "xhigh")   # the log grows and says no more of it: it stays remembered

    def test_context_by_snapshot(self):
        self.write(assistant(text("One"), tokens=1000), assistant(text("Two"), tokens=42000))
        self.assertEqual(self.read()["context"], {"tokens": 42000, "window": None, "percent": None})

    def test_context_ignores_a_zero_usage(self):
        self.write(assistant(text("One"), tokens=42000), assistant(stop="aborted", tokens=0, cost=0))
        self.assertEqual(self.read()["context"]["tokens"], 42000)

    def test_context_unknown_after_compaction(self):
        self.write(assistant(text("One"), tokens=850000))
        self.assertEqual(self.read()["context"]["tokens"], 850000)
        self.append(line("compaction", summary="Summary", tokensBefore=850000, tokensAfter=120000, method="remote"))
        self.assertIsNone(self.read()["context"])
        self.append(assistant(text("Two"), tokens=125000))
        self.assertEqual(self.read()["context"]["tokens"], 125000)

    def models_database(self, **providers):
        """A fake models.db: models_database(anthropic={"claude-opus-5-5": 1000000}). Like the real one, it is in
        WAL mode; closed cleanly, nobody holds it: neither a -wal file nor a -shm file next to it."""
        path = self.root / "models.db"
        if path.exists():
            path.unlink()
        db = sqlite3.connect(str(path))
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("CREATE TABLE model_cache (provider_id TEXT PRIMARY KEY, version INTEGER, updated_at INTEGER,"
                   " authoritative INTEGER, models TEXT)")
        for provider, models in providers.items():
            entries = [{"id": name, "name": name, "contextWindow": window} for name, window in models.items()]
            db.execute("INSERT INTO model_cache VALUES (?, 1, 0, 1, ?)", (provider, json.dumps(entries)))
        db.commit()
        db.close()
        for leftover in ("models.db-wal", "models.db-shm"):     # macOS's SQLite leaves them, even closed cleanly
            (self.root / leftover).unlink(missing_ok=True)
        moment = NOW + next(_numbers)                           # each write of the database has its own date
        os.utime(path, (moment, moment))

    def test_percent_when_the_window_is_known(self):
        self.models_database(**{"anthropic": {"claude-opus-5-5": 1000000},
                                "factory-droid:models-v4:abc": {"claude-opus-5-5": 500000}})
        self.write(assistant(text("One"), tokens=250000))
        self.assertEqual(self.read()["context"], {"tokens": 250000, "window": 1000000, "percent": 25})
        # the same model through another provider has another window; the provider's key loses its suffix
        self.append(assistant(text("Two"), tokens=250000, provider="factory-droid"))
        self.assertEqual(self.read()["context"], {"tokens": 250000, "window": 500000, "percent": 50})
        self.append(assistant(text("Three"), tokens=900000, provider="factory-droid"))
        self.assertEqual(self.read()["context"]["percent"], 100)   # never more than 100

    def test_no_percent_without_a_window(self):
        self.write(assistant(text("One"), tokens=250000))
        expected = {"tokens": 250000, "window": None, "percent": None}
        self.assertEqual(self.read()["context"], expected)                       # no models.db
        self.models_database(anthropic={"other-model": 1000000, "claude-opus-5-5": None}, ollama={"claude-opus-5-5": 9})
        self.assertEqual(self.read()["context"], expected)                       # model absent, or null window
        (self.root / "models.db").write_bytes(b"this is not a database")
        self.assertEqual(self.read()["context"], expected)                       # unreadable database

    def test_the_models_database_is_read_again_when_it_changes(self):
        self.write(assistant(text("One"), tokens=250000))
        self.models_database(anthropic={"claude-opus-5-5": 1000000})
        self.assertEqual(self.read()["context"]["percent"], 25)
        self.models_database(anthropic={"claude-opus-5-5": 500000, "claude-sonnet-5-5": 1000000})
        self.assertEqual(self.read()["context"]["percent"], 50)

    def test_the_models_database_is_read_again_when_a_running_omp_writes_to_it(self):
        self.models_database(anthropic={"claude-opus-5-5": 1000000})
        self.write(assistant(text("One"), tokens=250000))
        self.assertEqual(self.read()["context"]["percent"], 25)
        held = sqlite3.connect(str(self.root / "models.db"))    # OMP, running: what it writes stays in the -wal
        self.addCleanup(held.close)
        before = reading.fingerprint(self.root / "models.db")
        entries = [{"id": "claude-opus-5-5", "name": "claude-opus-5-5", "contextWindow": 500000}]
        held.execute("UPDATE model_cache SET models = ?", (json.dumps(entries),))
        held.commit()
        self.assertEqual(reading.fingerprint(self.root / "models.db"), before, "the database itself did not move")
        self.assertEqual(self.read()["context"]["percent"], 50)

    def test_reading_the_models_database_writes_nothing_next_to_it(self):
        self.models_database(anthropic={"claude-opus-5-5": 1000000})
        self.write(assistant(text("One"), tokens=250000))
        before = sorted(os.listdir(self.root))
        self.assertEqual((self.root / "models.db").read_bytes()[18:20], b"\x02\x02")   # the database is indeed in WAL
        self.assertEqual(self.read()["context"]["percent"], 25)
        self.assertEqual(sorted(os.listdir(self.root)), before)   # no models.db-shm, no models.db-wal in OMP's folder

    def test_cost(self):
        self.write(user("Hello"))
        self.assertIsNone(self.read()["cost"])                  # no cost read: unknown, not zero
        self.append(assistant(text("One"), cost=0.25), assistant(text("Two"), cost=0.5))
        self.assertEqual(self.read()["cost"], 0.75)
        self.subagent("Scout", assistant(text("Three"), cost=0.125), age=5 * 3600)
        state = self.read()
        self.assertEqual(state["cost"], 0.875)                  # the cost of a subagent counts, even an old one
        self.assertEqual(state["subagents"], [])

    def test_a_zero_cost_measures_nothing(self):
        # As in real logs: a reply that failed or was cut short carries a zero usage and a zero cost.
        self.write(user("Hello"), assistant(stop="error", tokens=0, cost=0), assistant(stop="aborted", tokens=0, cost=0))
        self.assertIsNone(self.read()["cost"])                  # nothing was measured: unknown, never zero
        self.subagent("Scout", assistant(stop="error", tokens=0, cost=0))
        self.assertIsNone(self.read()["cost"])
        self.append(assistant(text("One"), cost=0.00004))
        self.assertIsNone(self.read()["cost"], "too small to be written with four decimals: not a zero either")
        self.append(assistant(text("Two"), cost=0.25), assistant(stop="aborted", tokens=0, cost=0))
        self.assertEqual(self.read()["cost"], 0.25)

    def test_cost_rounded(self):
        self.write(assistant(text("One"), cost=0.1), assistant(text("Two"), cost=0.2))
        self.assertEqual(self.read()["cost"], 0.3)              # not 0.30000000000000004

    def test_tool_running_then_finished(self):
        self.write(assistant(call("toolu_1", "bash", command="ls", i="List")), tool_start("toolu_1", "bash", t=5))
        self.assertEqual(self.read()["tool"], {"name": "bash", "since": guards.iso(T0 + 5)})
        self.append(result("toolu_1", "bash", t=9))
        self.assertIsNone(self.read()["tool"])

    def test_a_tool_left_open_when_the_program_stopped_is_no_longer_running(self):
        exit_line = line("custom", t=20, customType="session_exit", data={"reason": "sigterm", "kind": "signal"})
        for name in ("bash", "ask"):
            with self.subTest(name):
                omp._followed.clear()
                self.write(assistant(call("toolu_1", name, i="Wait")), tool_start("toolu_1", name, t=5))
                self.assertEqual(self.read()["tool"]["name"], name)
                self.append(exit_line)
                state = self.read()
                self.assertEqual((state["tool"], state["request"]), (None, None))
                self.append(user("Go on", t=7200), assistant(text("I resume"), t=7201, stop="stop"))
                state = self.read()         # the session resumed: what was open before the stop does not come back
                self.assertEqual((state["tool"], state["request"]), (None, None))
                self.append(result("toolu_1", name, t=7202))        # a late result closes nothing and breaks nothing
                self.assertIsNone(self.read()["tool"])
                self.append(assistant(call("toolu_2", "read", path="a"), t=7203), tool_start("toolu_2", "read", t=7204))
                self.assertEqual(self.read()["tool"]["name"], "read")       # a tool started since is shown

    def test_a_tool_left_open_by_a_killed_omp_ends_at_the_next_message(self):
        # Killed, OMP writes no exit line. In real logs a message is only received when no tool runs.
        for name in ("bash", "ask"):
            with self.subTest(name):
                omp._followed.clear()
                self.write(user("Wait for it"), assistant(call("toolu_1", name, i="Wait")),
                           tool_start("toolu_1", name, t=5))
                self.assertEqual(self.read()["tool"]["name"], name)
                self.append(line("model_change", t=7200, model="anthropic/claude-opus-5-5"))
                self.assertEqual(self.read()["tool"]["name"], name, "resumed, but nothing says yet that it died")
                self.append(user("Go on", t=7201))
                state = self.read()
                self.assertEqual((state["tool"], state["request"]), (None, None))
                self.append(assistant(call("toolu_2", "read", path="a"), t=7203), tool_start("toolu_2", "read", t=7204))
                self.assertEqual(self.read()["tool"]["name"], "read")
                self.append(user("A brief from the parent", t=7205, attribution="agent"))
                self.assertIsNone(self.read()["tool"], "whoever the message comes from")

    def test_tools_in_parallel(self):
        self.write(assistant(call("toolu_1", "read", path="a"), call("toolu_2", "grep", pattern="b", path=".")),
                   tool_start("toolu_1", "read", t=1), tool_start("toolu_2", "grep", t=2), result("toolu_2", "grep"))
        self.assertEqual(self.read()["tool"]["name"], "read")   # the last one started that has no result

    def test_question_open_then_answered(self):
        questions = [{"id": "color", "question": "Which color?", "header": "Color", "multi": True,
                      "options": [{"label": "Red", "description": "warm"}, {"label": "Blue"}]},
                     {"id": "size", "question": "Which size?", "options": [{"label": "Small"}]}]
        self.write(assistant(call("toolu_q", "ask", i="Ask", questions=questions)))
        self.assertIsNone(self.read()["request"])               # called, not started yet
        self.append(tool_start("toolu_q", "ask", t=3))
        state = self.read()
        self.assertEqual(state["request"], {"kind": "question", "questions": [
            {"question": "Which color?", "options": ["Red", "Blue"], "multi": True},
            {"question": "Which size?", "options": ["Small"], "multi": False}]})
        self.assertEqual(state["tool"]["name"], "ask")
        self.append(result("toolu_q", "ask", details={"results": []}))
        state = self.read()
        self.assertIsNone(state["request"])
        self.assertIsNone(state["tool"])

    def test_todos_by_phases(self):
        todo = phases(("Prepare", [("Read the plan", "completed"), ("Sort", "in_progress")]),
                      ("Finish", [("Tidy", "pending"), ("Paint", "blocked")]))
        self.write(assistant(call("toolu_t", "todo", op="init", i="Plan")), tool_start("toolu_t", "todo"),
                   result("toolu_t", "todo", details={"op": "init", "phases": todo, "storage": "session"}))
        self.assertEqual(self.read()["todos"], [
            {"text": "Read the plan", "status": "done", "phase": "Prepare"},
            {"text": "Sort", "status": "in_progress", "phase": "Prepare"},
            {"text": "Tidy", "status": "pending", "phase": "Finish"},
            {"text": "Paint", "status": "blocked", "phase": "Finish"}])

    def test_todos_error_result_ignored(self):
        self.write(result("toolu_1", "todo", details={"phases": phases(("One", [("Read", "pending")]))}),
                   result("toolu_2", "todo", error=True, details={"phases": phases(("Wrong", [("Never", "pending")]))}),
                   result("toolu_3", "todo", error=True),
                   result("toolu_4", "read", details={"phases": phases(("Wrong", [("Never", "pending")]))}))
        self.assertEqual(self.read()["todos"], [{"text": "Read", "status": "pending", "phase": "One"}])

    def test_todos_later_user_edit(self):
        self.write(line("custom", customType="user_todo_edit", data={"phases": phases(("Before", [("Old", "pending")]))}),
                   result("toolu_1", "todo", details={"phases": phases(("One", [("Read", "pending")]))}))
        self.assertEqual(self.read()["todos"][0]["text"], "Read")
        self.append(line("custom", customType="user_todo_edit", data={"phases": phases(("One", [("Read", "completed")]))}),
                    line("custom", customType="todo_hud_state", data={"visibility": "dismissed", "fingerprint": "[]"}))
        self.assertEqual(self.read()["todos"], [{"text": "Read", "status": "done", "phase": "One"}])
        self.append(line("custom", customType="user_todo_edit", data={"phases": []}))
        self.assertEqual(self.read()["todos"], [])

    def test_goal_active_paused_complete(self):
        self.write(goal("goal", "active"))
        expected = {"objective": "Tidy the workshop", "status": "active", "tokens": 1200, "seconds": 90}
        self.assertEqual(self.read()["goal"], expected)
        self.append(goal("goal_paused", "paused"))
        self.assertEqual(self.read()["goal"], dict(expected, status="paused"))
        self.append(goal("goal", "active"), goal("goal", "complete"))
        self.assertIsNone(self.read()["goal"])
        self.append(goal("goal", "active"), line("mode_change", mode="none", data={}))
        self.assertIsNone(self.read()["goal"])

    def test_log_that_grows(self):
        self.write(line("model_change", model="anthropic/claude-opus-5-5"), assistant(text("One"), cost=0.25), age=60)
        self.assertEqual(self.read()["cost"], 0.25)
        self.assertEqual(self.read()["cost"], 0.25)             # reading again without a change counts nothing again
        rest = assistant(call("toolu_1", "bash", command="ls"), cost=0.5, tokens=5000)
        self.append(rest[:40], end="", age=30)                  # a line being written
        self.assertEqual(self.read()["cost"], 0.25)
        self.append(rest[40:], tool_start("toolu_1", "bash"), line("model_change", model="anthropic/claude-sonnet-5-5"))
        state = self.read()
        self.assertEqual((state["cost"], state["model"], state["tool"]["name"], state["context"]["tokens"]),
                         (0.75, "anthropic/claude-sonnet-5-5", "bash", 5000))
        self.assertEqual(state["activity"], guards.iso(NOW))

    def test_log_that_shrinks(self):
        self.write(assistant(text("One"), cost=0.25), assistant(text("Two"), cost=0.25), tool_start("toolu_1", "bash"))
        self.assertEqual(self.read()["cost"], 0.5)
        self.write(assistant(text("Other"), cost=0.125))
        state = self.read()
        self.assertEqual((state["cost"], state["tool"]), (0.125, None))   # the read started again from zero

    def test_log_replaced_by_another_file(self):
        self.write(assistant(text("One"), cost=0.25), tool_start("toolu_1", "bash"))
        before = (self.read()["cost"], os.stat(self.path).st_size)
        other = self.write(assistant(text("One"), cost=0.75), tool_start("toolu_2", "read"),
                           path=self.path.with_name("other.jsonl"))
        os.replace(other, self.path)                            # same size, same date: only the inode gives it away
        state = self.read()
        self.assertEqual(before, (0.25, os.stat(self.path).st_size))
        self.assertEqual((state["cost"], state["tool"]["name"]), (0.75, "read"))
        other = self.write(user("Hello"), assistant(text("Two"), cost=0.125), user("m" * 2000),
                           path=self.path.with_name("other.jsonl"))
        os.replace(other, self.path)                            # bigger: nothing of the old one remains
        state = self.read()
        self.assertEqual((state["cost"], state["tool"]), (0.125, None))

    def test_log_followed_in_blocks(self):
        lines = [assistant(text("Answer %d" % i), cost=0.25) for i in range(40)]
        with mock.patch.object(reading, "BLOCK", 100):          # each line spans several blocks
            self.write(*lines[:30])
            self.assertEqual(self.read()["cost"], 7.5)
            self.append(*lines[30:])
            self.assertEqual(self.read()["cost"], 10)


HOSTILE = [
    '{"type":"message","id":"0000000a","message":{"role":"assistant","content":[{"type":"te',    # cut JSON
    "", "null", "[]", '"text"', "12", "{}", "\x00\x01\x02", "[" * 100000,
    '{"type":["message"],"timestamp":true}',
    '{"type":"message"}',
    '{"type":"message","message":"not an object","timestamp":{}}',
    '{"type":"message","id":7,"message":{"role":"user","content":"a string","attribution":3}}',
    '{"type":"message","id":"0000000b","message":{"role":"user","content":[1,null,{"type":"text","text":5}]}}',
    '{"type":"message","message":{"role":"assistant","content":"x","usage":[1],"provider":3,"model":null}}',
    '{"type":"message","message":{"role":"assistant","content":[1,null,{"type":"toolCall","id":[1],"name":"ask"},'
    '{"type":"toolCall","id":"a","name":{"x":1},"arguments":"no"}],"usage":{"totalTokens":"a lot",'
    '"cost":{"total":"expensive"}},"contextSnapshot":7,"stopReason":["stop"]}}',
    '{"type":"message","message":{"role":"assistant","usage":{"totalTokens":NaN,"cost":{"total":Infinity}},'
    '"contextSnapshot":{"promptTokens":-5}}}',
    '{"type":"message","message":{"role":"assistant","usage":{"totalTokens":10,"cost":true},'
    '"contextSnapshot":{"promptTokens":true}}}',
    '{"type":"message","message":{"role":"toolResult","toolCallId":{"a":1},"toolName":["todo"],"isError":false,'
    '"details":{"phases":"no"}}}',
    '{"type":"message","message":{"role":"toolResult","toolCallId":null,"toolName":"todo","isError":false,"details":[]}}',
    '{"type":"message","message":{"role":"toolResult","toolName":"yield","isError":"false"}}',
    '{"type":"message","message":{"role":"fileMention","files":["a"],"timestamp":1791345600000}}',
    '{"type":"custom","customType":"tool_execution_start","data":["toolCallId"]}',
    '{"type":"custom","customType":"tool_execution_start","data":{"toolCallId":["x"],"toolName":"bash"}}',
    '{"type":"custom","customType":"tool_execution_start","data":{"toolCallId":"x","toolName":null}}',
    '{"type":"custom","customType":{"a":1},"data":null}',
    '{"type":"custom","customType":"user_todo_edit","data":{"phases":{"name":"no"}}}',
    '{"type":"custom","customType":"user_todo_edit","data":{"phases":[1,"a",null,{"tasks":"x"},{"name":3,"tasks":'
    '[1,{"content":5,"status":[]},{"content":"No status","status":{"x":1}},{"content":"","status":"pending"}]}]}}',
    '{"type":"model_change","model":5}',
    '{"type":"thinking_level_change","thinkingLevel":["high"]}',
    '{"type":"mode_change","mode":["goal"],"data":"x"}',
    '{"type":"mode_change","mode":"goal","data":{"goal":{"status":"active","objective":12}}}',
    '{"type":"mode_change","mode":"goal_paused","data":{"goal":[]}}',
    '{"type":"compaction","tokensBefore":"x"}',
    '{"type":"session","timestamp":{"a":1},"id":4}',
    '{"type":"session_init","agent":5,"resolvedModel":[]}',
]


class Robustness(Case):
    def test_hostile_lines(self):
        self.write(*HOSTILE, head=["not a title"], age=10)
        self.write(path=self.path.with_suffix("") / "Odd.jsonl", head=HOSTILE, age=10)
        state = self.read()
        self.assertEqual(state["todos"], [])
        self.assertEqual(state["subagents"], [{"id": "Odd", "name": "Odd", "type": None, "parent": None,
                                               "state": "working", "model": None, "start": None, "end": None}])
        for key in KEYS - {"activity", "todos", "subagents"}:
            self.assertIsNone(state[key], key)
        self.assertEqual(omp.turns(self.session), {"turns": [], "older": False, "before": None})

    def test_a_hostile_line_does_not_hide_the_good_ones(self):
        good = [line("model_change", model="anthropic/claude-opus-5-5"), user("Hello", id="0000aaaa"),
                assistant(text("Hi"), stop="stop", tokens=3000, cost=0.5)]
        self.write(*[l for one in good for l in HOSTILE[:9] + [one]])
        state = self.read()
        self.assertEqual((state["model"], state["cost"], state["context"]["tokens"]), ("anthropic/claude-opus-5-5", 0.5, 3000))
        self.assertEqual([t["text"] for t in omp.turns(self.session)["turns"]], ["Hello"])


class Subagents(Case):
    def setUp(self):
        super().setUp()
        self.write(user("Hello"))

    def only(self, now=NOW):
        (alone,) = self.read(now)["subagents"]
        return alone

    def test_done_by_accepted_yield(self):
        self.subagent("Scout", assistant(call("toolu_y", "yield", data={"ok": True}), t=50),
                      tool_start("toolu_y", "yield", t=51),
                      result("toolu_y", "yield", t=52, details={"data": {"ok": True}, "status": "success"}),
                      line("custom", t=53, customType="session_exit", data={"reason": "dispose", "kind": "normal"}),
                      age=600, t=20, kind="reviewer")
        self.assertEqual(self.only(), {
            "id": "Scout", "name": "Scout", "type": "reviewer", "parent": None, "state": "done",
            "model": "anthropic/claude-sonnet-5-5", "start": guards.iso(T0 + 20), "end": guards.iso(T0 + 52)})

    def test_refused_yield_is_not_done(self):
        lines = [assistant(call("toolu_y", "yield", data={})), tool_start("toolu_y", "yield"),
                 result("toolu_y", "yield", error=True)]
        self.subagent("Scout", *lines, age=10)
        self.assertEqual((self.only()["state"], self.only()["end"]), ("working", None))
        self.assertEqual(self.only(NOW + 600)["state"], "unknown")   # silent since: we do not know, we do not say done

    def test_done_by_final_reply(self):
        self.subagent("Scout", assistant(text("Here it is"), stop="stop", t=30), age=900)
        self.assertEqual((self.only()["state"], self.only()["end"]), ("done", guards.iso(T0 + 30)))

    def test_an_error_or_an_abort_does_not_finish(self):
        self.subagent("Scout", assistant(text("Here it is"), stop="stop"), assistant(stop="error", tokens=0), age=900)
        self.assertEqual((self.only()["state"], self.only()["end"]), ("unknown", None))

    def test_working_or_unknown(self):
        self.subagent("Recent", assistant(text("I am searching")), age=60)
        self.subagent("Silent", assistant(text("I am searching")), age=600)
        self.subagent("Tool", assistant(call("toolu_1", "bash", command="make")), tool_start("toolu_1", "bash"), age=600)
        self.subagent("OldTool", assistant(call("toolu_1", "bash", command="make")), tool_start("toolu_1", "bash"),
                      age=1200)
        states = {a["name"]: a["state"] for a in self.read()["subagents"]}
        self.assertEqual(states, {"Recent": "working", "Silent": "unknown", "Tool": "working", "OldTool": "unknown"})

    def test_stopped_without_having_yielded_no_longer_works(self):
        exit_line = line("custom", customType="session_exit", data={"reason": "sigterm", "kind": "signal"})
        self.subagent("Cut", assistant(call("toolu_1", "bash", command="make")), tool_start("toolu_1", "bash"),
                      exit_line, age=5)
        self.subagent("Aborted", assistant(stop="aborted", tokens=0), exit_line, age=5)
        self.subagent("Resumed", assistant(text("I am searching")), exit_line, assistant(text("I resume")), age=5)
        # A tool left open before the stop no longer earns the longer delay of a tool in progress.
        self.subagent("Silent", assistant(call("toolu_1", "bash", command="make")), tool_start("toolu_1", "bash"),
                      exit_line, assistant(text("I resume")), age=600)
        states = {a["name"]: a["state"] for a in self.read()["subagents"]}
        self.assertEqual(states, {"Cut": "unknown", "Aborted": "unknown", "Resumed": "working", "Silent": "unknown"})

    def test_two_hour_window(self):
        done = [assistant(text("Here it is"), stop="stop")]
        self.subagent("DoneRecent", *done, age=7100)
        self.subagent("DoneOld", *done, age=7300)
        self.subagent("SilentOld", assistant(text("I am searching")), age=7300)
        self.assertEqual([a["name"] for a in self.read()["subagents"]], ["DoneRecent"])
        self.assertEqual(self.read(NOW + 200)["subagents"], [])   # time passes without the log changing

    def test_parent_of_a_deep_level(self):
        self.subagent("Lead", t=1)
        self.subagent("Lead/Lead.Helper", t=2)
        self.subagent("Lead/Lead.Helper/Lead.Helper.Small", t=3)
        self.subagent("Lost/Lost.Alone", t=4)                    # its parent has no log: a direct child
        (self.path.with_suffix("") / "38.bash.log").write_text("output\n", encoding="utf-8")
        seen = [(a["id"], a["name"], a["parent"]) for a in self.read()["subagents"]]
        self.assertEqual(seen, [("Lead", "Lead", None), ("Lead/Lead.Helper", "Helper", "Lead"),
                                ("Lead/Lead.Helper/Lead.Helper.Small", "Small", "Lead/Lead.Helper"),
                                ("Lost/Lost.Alone", "Lost.Alone", None)])

    def test_sorted_by_start_fifty_at_most(self):
        for i in range(53):   # born in the reverse order of their last write
            self.subagent("Agent%02d" % i, t=100 - i, age=i)
        names = [a["name"] for a in self.read()["subagents"]]
        self.assertEqual(names, ["Agent%02d" % i for i in range(49, -1, -1)])   # the three oldest written are dropped

    def test_model_of_a_subagent_without_model_change(self):
        head = [title("Old"), header("0199aaaa-0000-7000-8000-00000000abcd", 7),
                line("session_init", 7, agent="task", task="Search", resolvedModel="openai-codex/gpt-6-astra")]
        self.write(path=self.path.with_suffix("") / "Old.jsonl", head=head)
        self.assertEqual((self.only()["model"], self.only()["type"]), ("openai-codex/gpt-6-astra", "task"))


class Turns(Case):
    def conversation(self, n):
        """n turns: "Question i" of identifier 0000000i, one final reply each."""
        return [l for i in range(1, n + 1) for l in (user("Question %d" % i, t=10 * i, id="%08x" % i),
                                                     assistant(text("Answer %d" % i), t=10 * i + 5, stop="stop"))]

    def test_splitting(self):
        self.write(
            assistant(text("Answer without a question"), t=1),   # before any message: belongs to no turn
            user("Tidy the workshop", t=10, id="0000aaaa"),
            assistant({"type": "thinking", "thinking": "I am thinking", "thinkingSignature": "x"}, text("Looking"),
                      call("toolu_1", "read", path="/tmp/test/plan.md", i="Read the plan"),
                      call("toolu_2", "bash", command="ls /tmp/test", i="List"),
                      call("toolu_3", "todo", op="init", i="Plan"), t=12),
            tool_start("toolu_1", "read", t=12), result("toolu_1", "read", t=13),
            line("custom_message", t=14, customType="async-result", content="<system-notice>done", display=False),
            line("message", t=15, message={"role": "developer", "content": [text("Reminder")], "attribution": "agent"}),
            line("message", t=15, message={"role": "fileMention", "files": ["plan.md"]}),
            user("   ", t=16),                                   # an empty message does not open a turn
            assistant(text("It is tidy"), t=20, stop="stop"),
            user("Brief from the parent", t=30, id="0000bbbb", attribution="agent"),
            assistant(call("toolu_4", "eval", code="1 + 1"), t=32))
        returned = omp.turns(self.session)
        self.assertEqual(returned, {"older": False, "before": None, "turns": [
            {"id": "0000aaaa", "t": guards.iso(T0 + 10), "from": "user", "text": "Tidy the workshop",
             "replies": [{"t": guards.iso(T0 + 12), "text": "Looking"},
                         {"t": guards.iso(T0 + 20), "text": "It is tidy"}],
             "tools": [{"name": "read", "target": "/tmp/test/plan.md"}, {"name": "bash", "target": "ls /tmp/test"},
                       {"name": "todo", "target": "Plan"}],
             "end": guards.iso(T0 + 20)},
            {"id": "0000bbbb", "t": guards.iso(T0 + 30), "from": "system", "text": "Brief from the parent",
             "replies": [], "tools": [{"name": "eval", "target": None}], "end": None}]})

    def test_clipping(self):
        self.write(user("m" * 5000), assistant(text("r" * 9000), call("toolu_1", "bash", command="c" * 300)))
        (turn,) = omp.turns(self.session)["turns"]
        lengths = (len(turn["text"]), len(turn["replies"][0]["text"]), len(turn["tools"][0]["target"]))
        self.assertEqual(lengths, (4000, 8000, 160))
        self.assertTrue(turn["text"].endswith("…"))

    def test_paging_by_before(self):
        self.write(*self.conversation(5))
        page = omp.turns(self.session, limit=2)
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 4", "Question 5"], True, "00000004"))
        page = omp.turns(self.session, limit=2, before=page["before"])
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 2", "Question 3"], True, "00000002"))
        page = omp.turns(self.session, limit=2, before=page["before"])
        self.assertEqual(page["turns"][0]["replies"][0]["text"], "Answer 1")
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 1"], False, None))
        self.assertEqual(omp.turns(self.session, limit=2, before="00000001")["turns"], [])
        self.assertEqual(len(omp.turns(self.session)["turns"]), 5)

    def test_unknown_before(self):
        self.write(*self.conversation(3))
        with self.assertRaisesRegex(LookupError, "^none of the turns read carries this identifier$"):
            omp.turns(self.session, before="ffffffff")

    def test_the_end_of_the_log_grows_as_long_as_it_is_not_enough(self):
        self.write(*self.conversation(40))
        whole = omp.turns(self.session, limit=50)["turns"]
        with mock.patch.object(reading, "TAIL", 700):             # a tail that does not hold two turns
            for limit in range(1, 12):   # even when the tail holds just `limit` turns, older ones remain
                page = omp.turns(self.session, limit=limit)
                self.assertEqual((page["turns"], page["older"], page["before"]),
                                 (whole[-limit:], True, whole[-limit]["id"]))
            page = omp.turns(self.session, limit=4, before="0000000a")
            self.assertEqual((page["turns"], page["older"], page["before"]), (whole[5:9], True, "00000006"))
            self.assertEqual(omp.turns(self.session, limit=50)["turns"], whole)
            with self.assertRaises(LookupError):
                omp.turns(self.session, before="ffffffff")

    def test_the_end_read_is_bounded(self):
        self.write(*self.conversation(40))
        whole = omp.turns(self.session, limit=50)["turns"]
        with mock.patch.object(reading, "TAIL", 700), mock.patch.object(reading, "CONVERSATION_MAX", 5000):
            with mock.patch.object(reading, "tail_lines", wraps=reading.tail_lines) as tail:
                page = omp.turns(self.session, limit=50)
            self.assertEqual([a.args[1] for a in tail.call_args_list], [700, 2800, 5000])   # never the whole log
            n = len(page["turns"])
            self.assertTrue(0 < n < 40, n)
            self.assertEqual((page["turns"], page["older"]), (whole[-n:], True))
            self.assertEqual(page["before"], whole[-n]["id"])
            # at the far side of the end read: nothing more to return, but the log is longer than it
            self.assertEqual(omp.turns(self.session, before=page["before"]),
                             {"turns": [], "older": True, "before": None})
            with self.assertRaises(LookupError):
                omp.turns(self.session, before="00000001")
        self.assertEqual(omp.turns(self.session, limit=2, before="00000002")["turns"], whole[:1])

    def test_log_gone(self):
        with self.assertRaises(OSError):
            omp.turns(self.session)


if __name__ == "__main__":
    unittest.main()
