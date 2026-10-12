"""The Codex reader, on fake logs and fake databases in the exact shape of real ones (Codex 0.160.0). No real
text: everything is made up."""
import itertools
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import threading
import unittest
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import extensions, guards  # noqa: E402
from extensions import _reading as reading     # noqa: E402

codex = extensions.import_file(extensions.FOLDER / "codex.py")

THREAD = "019aaaaa-bbbb-7ccc-8ddd-eeeeffff0001"
TURN = "019aaaaa-0000-7000-8000-00000000000a"
T0 = datetime(2026, 10, 7, 4, 0, tzinfo=timezone.utc).timestamp()   # time zero of the fake logs
NOW = T0 + 3600
KEYS = {"title", "model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents", "activity"}
MB = 1024 * 1024
_numbers = itertools.count(1)

# The tables as Codex creates them, in state_5.sqlite then in goals_1.sqlite.
INDEX = """
CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL, source TEXT NOT NULL, model_provider TEXT NOT NULL, cwd TEXT NOT NULL,
    title TEXT NOT NULL, sandbox_policy TEXT NOT NULL, approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0, has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER, git_sha TEXT, git_branch TEXT, git_origin_url TEXT,
    cli_version TEXT NOT NULL DEFAULT '', first_user_message TEXT NOT NULL DEFAULT '', agent_nickname TEXT,
    agent_role TEXT, memory_mode TEXT NOT NULL DEFAULT 'enabled', model TEXT, reasoning_effort TEXT, agent_path TEXT,
    created_at_ms INTEGER, updated_at_ms INTEGER, thread_source TEXT, preview TEXT NOT NULL DEFAULT '',
    recency_at INTEGER NOT NULL DEFAULT 0, recency_at_ms INTEGER NOT NULL DEFAULT 0,
    history_mode TEXT NOT NULL DEFAULT 'legacy', name TEXT, is_pinned INTEGER NOT NULL DEFAULT 0,
    thread_section_id TEXT, section_position INTEGER, section_entered_at_ms INTEGER, project_id TEXT,
    originator TEXT, daybreak_enabled BOOLEAN, creator_user_id TEXT, creator_account_id TEXT);
CREATE TABLE thread_spawn_edges (parent_thread_id TEXT NOT NULL, child_thread_id TEXT NOT NULL PRIMARY KEY,
    status TEXT NOT NULL);"""
GOALS = """
CREATE TABLE thread_goals (thread_id TEXT PRIMARY KEY NOT NULL, goal_id TEXT NOT NULL, objective TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active', 'paused', 'blocked', 'usage_limited', 'budget_limited',
    'complete')), token_budget INTEGER, tokens_used INTEGER NOT NULL DEFAULT 0,
    time_used_seconds INTEGER NOT NULL DEFAULT 0, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);"""


# The line factory: each function returns a log line as Codex writes it.

def date(t):
    return datetime.fromtimestamp(T0 + t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def line(kind, payload, t=0, **others):
    """A line: date, ordinal, kind, payload, in this order and without spaces. `t`: seconds after T0."""
    o = {"timestamp": date(t), "ordinal": next(_numbers), "type": kind, "payload": payload, **others}
    return json.dumps(o, separators=(",", ":"), ensure_ascii=False)


def meta(thread=THREAD, **fields):
    return line("session_meta", {
        "session_id": thread, "id": thread, "timestamp": date(0), "cwd": "/tmp/trial", "originator": "codex-tui",
        "cli_version": "0.160.0", "source": "cli", "thread_source": "user", "model_provider": "openai",
        "base_instructions": {"text": "Trial instructions.", "provenance": {"type": "default", "model": "gpt-trial"}},
        "history_mode": "paginated", **fields})


def context(model="gpt-6.1-sol", effort="high", t=0):
    """The `turn_context` that opens each turn. `effort` at None: Codex does not write the key."""
    fields = {"turn_id": TURN, "cwd": "/tmp/trial", "current_date": "2026-10-07", "timezone": "Europe/Paris",
              "approval_policy": "on-request", "sandbox_policy": {"type": "workspace-write", "network_access": False},
              "model": model, "personality": "pragmatic", "effort": effort, "summary": "auto"}
    return line("turn_context", {key: v for key, v in fields.items() if v is not None}, t)


def event(kind, t=0, **fields):
    return line("event_msg", {"type": kind, **fields}, t)


def turn_start(t=0, turn=TURN):
    return event("task_started", t, turn_id=turn, started_at=int(T0 + t), model_context_window=258400,
                 collaboration_mode_kind="default")


def turn_end(t=0, turn=TURN, **fields):
    return event("task_complete", t, turn_id=turn, last_agent_message="Finished.", **fields, started_at=int(T0),
                 completed_at=int(T0 + t), duration_ms=1000, time_to_first_token_ms=100)


def abort(t=0):
    return event("turn_aborted", t, turn_id=TURN, reason="interrupted", started_at=int(T0),
                 completed_at=int(T0 + t), duration_ms=1000)


def tokens(input_tokens, t=0, window=258400):
    """A `token_count`. `input_tokens` at None: a line without a measure, which carries only the quotas."""
    usage = {"input_tokens": input_tokens, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
             "output_tokens": 50, "reasoning_output_tokens": 10, "total_tokens": (input_tokens or 0) + 50}
    info = None if input_tokens is None else {"total_token_usage": usage, "last_token_usage": usage,
                                              "model_context_window": window}
    quotas = {"limit_id": "codex", "limit_name": None, "primary": {"used_percent": 3.0, "window_minutes": 300},
              "secondary": None, "credits": None, "plan_type": "pro"}
    return event("token_count", t, info=info, rate_limits=quotas)


def raw_response(payload, t):
    passthrough = {"internal_chat_message_metadata_passthrough": {"turn_id": TURN, "create_time": T0 + t}}
    return line("response_item", {**payload, **passthrough}, t, metadata={"client_authored": False})


def call(ident, name, t=0, **arguments):
    """A tool call with JSON arguments. Codex writes it as soon as the model has emitted it, before the tool runs."""
    return raw_response({"type": "function_call", "id": "fc_" + ident, "name": name,
                         "arguments": json.dumps(arguments, ensure_ascii=False), "call_id": ident}, t)


def output(ident, t=0, text="done"):
    return raw_response({"type": "function_call_output", "id": "fco_" + ident, "call_id": ident, "output": text}, t)


def custom_call(ident, t=0):
    """The call of the `exec` tool, whose input is code and not JSON."""
    return raw_response({"type": "custom_tool_call", "id": "ctc_" + ident, "status": "completed", "call_id": ident,
                         "name": "exec", "input": "const r = await tools.exec_command({cmd: \"ls\"});"}, t)


def custom_output(ident, t=0, text="done"):
    return raw_response({"type": "custom_tool_call_output", "id": "ctco_" + ident, "call_id": ident,
                         "output": [{"type": "input_text", "text": text}]}, t)


def item(item_kind, t=0, turn=TURN, **fields):
    """A completed item (`item_completed`): Codex writes a message, a command, a file only once it is finished."""
    fields = {"type": item_kind, "id": "item-%d" % next(_numbers), **fields}
    return event("item_completed", t, thread_id=THREAD, turn_id=turn, item=fields,
                 started_at_ms=int((T0 + t) * 1000), completed_at_ms=int((T0 + t) * 1000))


def message(ident, text, t=0, turn=TURN):
    content = [{"type": "text", "text": text, "text_elements": []}]
    return item("UserMessage", t, turn, id=ident, client_id="client-" + ident, content=content)


def reply(text, t=0, phase="final_answer"):
    return item("AgentMessage", t, content=[{"type": "Text", "text": text}], phase=phase)


def command(script, t=0, written=""):
    """A completed command; what it wrote is there three times, as in the real logs."""
    return item("CommandExecution", t, process_id="1", command=["/bin/zsh", "-lc", script], cwd="/tmp/trial",
                parsed_cmd=[{"type": "unknown", "cmd": script}], source="unified_exec_startup", status="completed",
                stdout=written, stderr="", aggregated_output=written, exit_code=0,
                duration={"secs": 0, "nanos": 1000}, formatted_output=written)


def plan(*steps):
    return [{"step": text, "status": status} for text, status in steps]


def herdr(value, kind="id"):
    """What Herdr says of a Codex pane: its integration reports only the session's identifier."""
    return {"agent": "codex", "agent_session": {"source": "herdr:codex", "agent": "codex", "kind": kind,
                                                "value": value}}


class Case(unittest.TestCase):
    """A fake Codex folder in a temporary folder, in place of the real root."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="something-codex-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        patch = mock.patch.object(codex, "ROOT", self.root)
        patch.start()
        self.addCleanup(patch.stop)
        codex._followed.clear()
        self.path = self.log_of(THREAD)
        self.session = {"id": THREAD, "path": str(self.path)}

    def log_of(self, thread, day="07"):
        return self.root / "sessions" / "2026" / "10" / day / f"rollout-2026-10-{day}T04-00-00-{thread}.jsonl"

    def write(self, *lines, path=None, age=0):
        """Writes a log (the session header, then `lines`), `age` seconds old."""
        path = path or self.path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(l + "\n" for l in (meta(),) + lines), encoding="utf-8")
        os.utime(path, (NOW - age, NOW - age))
        return path

    def append(self, *lines, end="\n", age=0):
        with open(self.path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + end)
        os.utime(self.path, (NOW - age, NOW - age))

    def database(self, name, tables, rows):
        """Writes a Codex database: `rows` is a list of (table, dictionary of columns)."""
        path = self.root / name
        if path.exists():
            path.unlink()
        with closing(sqlite3.connect(str(path))) as db:
            db.executescript(tables)
            for table, columns in rows:
                db.execute(f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({', '.join('?' * len(columns))})",
                           list(columns.values()))
            db.commit()

    def index(self, *threads, links=(), name="state_5.sqlite"):
        """Writes the index: the threads (see `thread`), and the links (parent, child) of thread_spawn_edges."""
        edges = [{"parent_thread_id": p, "child_thread_id": c, "status": "open"} for p, c in links]
        self.database(name, INDEX, [("threads", t) for t in threads] + [("thread_spawn_edges", e) for e in edges])

    def thread(self, ident=THREAD, path=None, **columns):
        """A row of the `threads` table, with what Codex always puts in it."""
        path = self.log_of(ident) if path is None else path
        return {"id": ident, "rollout_path": str(path), "created_at": int(T0),
                "updated_at": int(T0), "source": "cli", "model_provider": "openai", "cwd": "/tmp/trial", "title": "",
                "sandbox_policy": "{}", "approval_mode": "on-request", "thread_source": "user",
                "history_mode": "paginated", **columns}

    def goal(self, status, thread=THREAD):
        """A row of the `thread_goals` table."""
        return ("thread_goals", {"thread_id": thread, "goal_id": "goal-1", "objective": "Tidy the workshop",
                                 "status": status, "tokens_used": 1200, "time_used_seconds": 90,
                                 "created_at_ms": int(T0 * 1000), "updated_at_ms": int(T0 * 1000)})

    def read(self, now=NOW):
        state = codex.read(self.session, now)
        self.assertEqual(set(state), KEYS)
        return state


class Session(Case):
    def test_by_the_index(self):
        elsewhere = self.path.with_name(self.path.stem + "_019aaaaa-9999-7000-8000-000000000009.jsonl")
        self.index(self.thread(path=elsewhere))        # a name the search by file would not find
        self.assertEqual(codex.session(herdr(THREAD)), {"id": THREAD, "path": str(elsewhere)})

    def test_by_the_file_name(self):
        self.write()
        self.assertEqual(codex.session(herdr(THREAD)), self.session)               # without an index
        self.index(self.thread("019aaaaa-other"))
        self.assertEqual(codex.session(herdr(THREAD)), self.session)               # the index does not know it
        (self.root / "state_5.sqlite").write_bytes(b"this is not a database")
        self.assertEqual(codex.session(herdr(THREAD)), self.session)               # the index cannot be read

    def test_the_index_with_the_highest_number(self):
        new, old = self.log_of(THREAD, "08"), self.log_of(THREAD, "06")
        self.index(self.thread(path=old), name="state_5.sqlite")
        self.index(self.thread(path=new), name="state_10.sqlite")
        self.assertEqual(codex.session(herdr(THREAD))["path"], str(new))

    def test_missing(self):
        self.write()
        self.index(self.thread())
        for agent in (None, "codex", {}, {"agent_session": None}, {"agent_session": THREAD}, herdr(None), herdr(12),
                      herdr(str(self.path), "path"), herdr(THREAD, "other"), herdr("019aaaaa-unknown"),
                      herdr(THREAD[-12:]), herdr("*"), herdr("../" + THREAD), herdr("")):
            self.assertIsNone(codex.session(agent), agent)

    def test_two_files_for_one_thread_link_nothing(self):
        self.write()
        self.write(path=self.log_of(THREAD, "08"))
        self.assertIsNone(codex.session(herdr(THREAD)))

    def test_a_file_outside_codex_s_folder_is_not_a_log(self):
        climbing = str(self.root / "sessions" / ".." / ".." / "elsewhere.jsonl")     # inside by its text only
        for path in ("/etc/passwd", "/tmp/elsewhere.jsonl", str(self.root / "auth.json"), "relative.jsonl", "",
                     climbing):
            self.index(self.thread(path=path))
            self.assertIsNone(codex.session(herdr(THREAD)), path)
        inside = str(self.root / "sessions" / ".." / "sessions" / self.path.relative_to(self.root / "sessions"))
        self.index(self.thread(path=inside))
        self.assertEqual(codex.session(herdr(THREAD)), {"id": THREAD, "path": str(self.path)})


class Databases(Case):
    """The index and the goals database are in WAL mode, like the real ones: reading them writes nothing there."""

    NAMES = ("state_5.sqlite", "goals_1.sqlite")

    def setUp(self):
        super().setUp()
        self.write(message("m1", "One"))
        self.index(self.thread(name="Before"))
        self.database("goals_1.sqlite", GOALS, [self.goal("active")])

    def wal(self, name):
        """A connection to this database, switched to WAL mode. Closing it removes its -wal and -shm files."""
        connection = sqlite3.connect(str(self.root / name))
        self.addCleanup(connection.close)
        connection.execute("PRAGMA journal_mode=WAL")
        return connection

    def files(self):
        """Each file of the Codex folder, and its fingerprint: nothing created, nothing touched."""
        return {p.name: reading.fingerprint(p) for p in self.root.iterdir()}

    def read_all(self):
        """Everything the linking, the poll and the conversation return, which read both databases."""
        state, page = self.read(), codex.turns(self.session)
        status = guards.as_dict(state["goal"]).get("status")
        return codex.session(herdr(THREAD)), state["title"], status, state["subagents"], len(page["turns"])

    def test_at_rest_nothing_is_created(self):
        for name in self.NAMES:
            self.wal(name).close()                     # closed cleanly: neither -wal nor -shm
        before = self.files()
        self.assertEqual(sorted(before), ["goals_1.sqlite", "sessions", "state_5.sqlite"])
        self.assertEqual(self.read_all(), (self.session, "Before", "active", [], 1))
        self.assertEqual(self.files(), before)

    def test_an_empty_wal_without_shm_nothing_is_created(self):
        for name in self.NAMES:
            self.wal(name).close()
            (self.root / (name + "-wal")).touch()      # nobody holds it: an empty -wal has nothing to say
        before = self.files()
        self.assertEqual(self.read_all(), (self.session, "Before", "active", [], 1))
        self.assertEqual(self.files(), before)

    def test_held_by_codex_it_returns_its_last_write(self):
        index, goals = map(self.wal, self.NAMES)
        index.execute("UPDATE threads SET name = 'After'")
        goals.execute("UPDATE thread_goals SET status = 'paused'")
        index.commit()
        goals.commit()                                 # these writes are still only in the -wal files
        before = sorted(self.files())
        self.assertEqual(len(before), 7)               # the two databases, their -wal and their -shm, and sessions/
        self.assertEqual(self.read_all(), (self.session, "After", "paused", [], 1))
        self.assertEqual(sorted(self.files()), before)


class Reading(Case):
    def test_empty_log_everything_is_unknown(self):
        self.write(age=30)
        state = self.read()
        self.assertEqual(state["activity"], guards.iso(NOW - 30))
        self.assertEqual(state["todos"], [])
        for key in KEYS - {"activity", "todos"}:       # without an index, even the subagents are unknown
            self.assertIsNone(state[key], key)

    def test_log_gone(self):
        with self.assertRaises(OSError):
            self.read()
        self.write()
        self.read()
        self.path.unlink()
        with self.assertRaises(OSError):
            self.read()

    def test_title_from_the_index(self):
        self.write()
        self.index(self.thread(name="Trial session", title='The first message, which Codex files under "title"'))
        self.assertEqual(self.read()["title"], "Trial session")
        self.index(self.thread(name=""))
        self.assertIsNone(self.read()["title"])

    def test_model_and_effort_of_the_last_context(self):
        self.write(context("gpt-5.5", "low"), context("gpt-6.1-sol", "xhigh"))
        state = self.read()
        self.assertEqual((state["model"], state["effort"]), ("gpt-6.1-sol", "xhigh"))
        self.append(context("gpt-6.1-sol", None))
        self.assertIsNone(self.read()["effort"])       # this turn has no effort: the one from before no longer holds

    def test_context(self):
        self.write(tokens(1000), tokens(64600))
        self.assertEqual(self.read()["context"], {"tokens": 64600, "window": 258400, "percent": 25})
        self.append(tokens(None), tokens(0))           # without a measure, or at zero: the last measure stays
        self.assertEqual(self.read()["context"]["tokens"], 64600)
        self.append(tokens(300000))
        self.assertEqual(self.read()["context"]["percent"], 100)                   # never more than 100
        self.append(tokens(5000, window=None))
        self.assertEqual(self.read()["context"], {"tokens": 5000, "window": None, "percent": None})

    def test_context_unknown_after_compaction(self):
        self.write(tokens(200000))
        self.append(line("compacted", {"message": "", "replacement_history": [
            {"type": "function_call", "name": "update_plan", "arguments": "{}", "call_id": "call_old"}]}))
        state = self.read()
        self.assertIsNone(state["context"])
        self.assertIsNone(state["tool"])               # the history copied by the compaction is not replayed
        self.append(tokens(30000))
        self.assertEqual(self.read()["context"]["tokens"], 30000)

    def test_cost_always_unknown(self):
        self.write(context(), tokens(64600), turn_end())
        self.assertIsNone(self.read()["cost"])

    def test_plan_becomes_todos(self):
        self.write(call("call_1", "update_plan", explanation="Why", plan=plan(
            ("Read", "completed"), ("Write", "in_progress"), ("Check", "pending"), ("Guess", "other"))),
            output("call_1", text="Plan updated"))
        self.assertEqual(self.read()["todos"], [
            {"text": "Read", "status": "done", "phase": None},
            {"text": "Write", "status": "in_progress", "phase": None},
            {"text": "Check", "status": "pending", "phase": None}])

    def test_plan_replaced_by_a_more_recent_one(self):
        self.write(call("call_1", "update_plan", plan=plan(("Read", "in_progress"), ("Write", "pending"))),
                   output("call_1"))
        self.assertEqual(len(self.read()["todos"]), 2)
        self.append(call("call_2", "update_plan", plan=plan(("Redo everything", "in_progress"))), output("call_2"))
        self.assertEqual(self.read()["todos"], [{"text": "Redo everything", "status": "in_progress", "phase": None}])
        self.append(call("call_3", "update_plan", plan="unreadable"), output("call_3"))
        self.assertEqual(len(self.read()["todos"]), 1)                             # an unreadable plan replaces nothing
        self.append(call("call_4", "update_plan", plan=[]), output("call_4"))
        self.assertEqual(self.read()["todos"], [])

    def test_goal(self):
        active = {"objective": "Tidy the workshop", "status": "active", "tokens": 1200, "seconds": 90}
        # The log notes the steps forward of a goal, not its removal: only the goals database says how it stands.
        self.write(event("thread_goal_updated", threadId=THREAD, turnId=TURN, goal={
            "threadId": THREAD, "objective": "Tidy the workshop", "status": "active", "tokensUsed": 1200,
            "timeUsedSeconds": 90, "createdAt": int(T0 * 1000), "updatedAt": int(T0 * 1000)}))
        self.assertIsNone(self.read()["goal"])
        paused = {**active, "status": "paused"}        # stopped, it still exists: only a finished goal disappears
        for status, expected in (("active", active), ("paused", paused), ("blocked", paused),
                                 ("usage_limited", paused), ("budget_limited", paused), ("complete", None)):
            self.database("goals_1.sqlite", GOALS, [self.goal(status)])
            self.assertEqual(self.read()["goal"], expected, status)
        self.database("goals_1.sqlite", GOALS, [self.goal("active", "019aaaaa-other")])
        self.assertIsNone(self.read()["goal"])         # the goal of another thread

    def test_running_tool(self):
        self.write(turn_start(), custom_call("call_1", t=5))
        self.assertEqual(self.read()["tool"], {"name": "exec", "since": guards.iso(T0 + 5)})
        self.append(custom_output("call_1", t=9))
        self.assertIsNone(self.read()["tool"])
        self.append(call("call_2", "wait_agent", t=10, timeout_ms=1000), call("call_3", "view_image", t=11))
        self.assertEqual(self.read()["tool"]["name"], "view_image")
        self.append(output("call_3", t=12))
        self.assertEqual(self.read()["tool"], {"name": "wait_agent", "since": guards.iso(T0 + 10)})
        self.append(turn_end(t=20))
        self.assertIsNone(self.read()["tool"])         # the turn is over: nothing runs any more

    def test_a_new_turn_closes_the_tools_left_open(self):
        self.write(turn_start(), custom_call("call_1"), turn_start(t=60))
        self.assertIsNone(self.read()["tool"])

    def test_a_6_mb_output_closes_its_tool_without_being_parsed(self):
        self.write(context(), custom_call("call_1"), custom_output("call_1", text="x" * 6 * MB), tokens(1000))
        with mock.patch.object(guards, "json_object", wraps=guards.json_object) as parsed:
            state = self.read()
        self.assertIsNone(state["tool"])
        self.assertEqual((state["model"], state["context"]["tokens"]), ("gpt-6.1-sol", 1000))
        self.assertLess(max(len(a.args[0]) for a in parsed.call_args_list), 4096)

    def test_question(self):
        options = [{"label": "Yes", "description": "We go on."}, {"label": "No", "description": "We stop."}]
        self.write(turn_start(), call("call_1", "request_user_input", t=5, questions=[
            {"header": "Next", "id": "next", "question": "Shall we go on?", "options": options},
            {"header": "Empty", "id": "empty", "options": options}]))
        state = self.read()
        self.assertEqual(state["request"], {"kind": "question", "questions": [
            {"question": "Shall we go on?", "options": ["Yes", "No"], "multi": False}]})
        self.assertEqual(state["tool"]["name"], "request_user_input")
        self.append(output("call_1", text='{"answers":{"next":{"answers":["Yes"]}}}'))
        self.assertIsNone(self.read()["request"])

    def test_a_question_already_accepted_waits_no_more(self):
        # `request_user_input_async` returns right away: nothing says afterwards whether the answer came.
        self.write(call("call_1", "request_user_input_async", questions=[{"title": "Shall we go on?"}]),
                   output("call_1", text='{"accepted":true}'))
        self.assertIsNone(self.read()["request"])

    def test_hostile_lines(self):
        hostile = [
            "", "not json", "[]", "null", '{"type":"event_msg"}', '{"type":"turn_context","payload":[]}',
            '{"type":"turn_context","payload":{"model":["x"],"effort":7}}',
            '{"type":"event_msg","payload":{"type":"token_count","info":"a lot"}}',
            '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":-5}}}}',
            '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":true}}}}',
            '{"type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":{"plan":[]}}}',
            '{"type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"[1]"}}',
            '{"type":"response_item","payload":{"type":"function_call","name":7,"call_id":["x"]}}',
            '{"type":"response_item","payload":{"type":"function_call_output","call_id":7}}',
            '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","id":7}}}',
            '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":"x"}}}',
            '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":["UserMessage"]}}}',
            '{"type":"event_msg","payload":{"type":"task_complete","turn_id":' + "[" * 2000 + "]" * 2000 + "}}",
        ]
        self.write(context(), tokens(1000), call("call_1", "update_plan", plan=plan(("Read", "pending"))),
                   *hostile, call("call_2", "request_user_input", questions="none"))
        with open(self.path, "ab") as f:
            f.write(b'\xff\xfe{"type":"turn_context"\n{"type":"turn_context","payload":{"model":"gpt-cut')
        state = self.read()
        self.assertEqual((state["model"], state["effort"], state["context"]["tokens"]), ("gpt-6.1-sol", "high", 1000))
        self.assertEqual(state["todos"], [{"text": "Read", "status": "pending", "phase": None}])
        self.assertEqual(state["request"], {"kind": "question", "questions": []})
        self.assertEqual(codex.turns(self.session), {"turns": [], "older": False, "before": None})

    def test_growing_log(self):
        self.write(context("gpt-5.5", "low"), tokens(1000),
                   call("call_1", "update_plan", plan=plan(("Read", "pending"))))
        self.assertEqual(self.read()["model"], "gpt-5.5")
        with mock.patch.object(codex, "_note", wraps=codex._note) as noted:
            self.read()
            self.assertEqual(noted.call_count, 0)      # nothing has changed: nothing is read again
            self.append(context("gpt-6.1-sol", "high"), tokens(2000), end='\n{"timestamp":"2026-10-07T04:00:0')
            state = self.read()
            self.assertEqual(noted.call_count, 2)      # the two added lines, not the line being written
        self.assertEqual((state["model"], state["context"]["tokens"], len(state["todos"])), ("gpt-6.1-sol", 2000, 1))
        self.append('0.000Z","ordinal":99,"type":"turn_context","payload":{"model":"gpt-6-astra","effort":"low"}}')
        self.assertEqual(self.read()["model"], "gpt-6-astra")                      # the finished line is read whole

    def test_replaced_log_is_read_again_from_the_start(self):
        self.write(context(), call("call_1", "update_plan", plan=plan(("Read", "pending"))), message("m1", "One"))
        self.assertEqual(len(self.read()["todos"]), 1)
        self.write(context("gpt-5.5", "low"))
        state = self.read()
        self.assertEqual((state["model"], state["todos"]), ("gpt-5.5", []))
        self.assertEqual(codex.turns(self.session)["turns"], [])


class Subagents(Case):
    def child(self, name, *lines, age=0, parent=THREAD, **columns):
        """A child thread: its log, and its index row. Returns (row of `threads`, link)."""
        ident = "019aaaaa-eeee-7000-8000-%012x" % next(_numbers)
        path = self.write(context("gpt-5.6-luna", "medium"), *lines, path=self.log_of(ident), age=age)
        source = {"subagent": {"thread_spawn": {"parent_thread_id": parent, "depth": 1, "agent_path": "/root/" + name,
                                                "agent_nickname": "Lagrange", "agent_role": None}}}
        columns = {"source": json.dumps(source), "thread_source": "subagent", "agent_path": "/root/" + name,
                   "agent_nickname": "Lagrange", **columns}
        return self.thread(ident, path, **columns), (parent, ident)

    def place(self, *children, others=()):
        self.write()
        self.index(self.thread(), *[c[0] for c in children], *others, links=[c[1] for c in children])

    def test_done_and_working(self):
        done, working = (self.child("audit", turn_start(), turn_end(t=90), age=600, created_at=int(T0) + 20,
                                    agent_role="explorer"),
                         self.child("tests", turn_start(t=50), age=30, created_at=int(T0) + 10))
        self.place(done, working)
        self.assertEqual(self.read()["subagents"], [
            {"id": working[0]["id"], "name": "tests", "type": None, "parent": None, "state": "working",
             "model": "gpt-5.6-luna", "start": guards.iso(T0 + 10), "end": None},
            {"id": done[0]["id"], "name": "audit", "type": "explorer", "parent": None, "state": "done",
             "model": "gpt-5.6-luna", "start": guards.iso(T0 + 20), "end": guards.iso(T0 + 90)}])

    def states(self):
        return {a["name"]: a["state"] for a in self.read()["subagents"]}

    def test_without_an_end_mark_a_silent_one_becomes_unknown(self):
        self.place(self.child("lively", turn_start(), age=100), self.child("silent", turn_start(), age=300),
                   self.child("tool", turn_start(), custom_call("call_1"), age=300),
                   self.child("silent_tool", turn_start(), custom_call("call_1"), age=1000),
                   self.child("new", age=10), self.child("aborted", turn_start(), abort(t=5), age=10))
        self.assertEqual(self.states(), {"lively": "working", "silent": "unknown", "tool": "working",
                                         "silent_tool": "unknown", "new": "working", "aborted": "unknown"})

    def test_a_turn_ended_on_an_error_is_a_failure(self):
        error = {"message": "The model did not answer.", "codex_error_info": None}
        self.place(self.child("broken", turn_start(), turn_end(t=40, error=error), age=10),
                   self.child("resumed", turn_start(), turn_end(t=40), turn_start(t=50), age=10))
        broken, resumed = sorted(self.read()["subagents"], key=lambda a: a["name"])
        self.assertEqual((broken["state"], broken["end"]), ("failed", guards.iso(T0 + 40)))
        self.assertEqual((resumed["state"], resumed["end"]), ("working", None))    # a new task has come to it

    def test_two_hour_window(self):
        self.place(self.child("recent", turn_start(), turn_end(), age=2 * 3600 - 60),
                   self.child("old", turn_start(), turn_end(), age=2 * 3600 + 60))
        self.assertEqual(self.states(), {"recent": "done"})

    def test_a_guardian_thread_is_not_a_subagent(self):
        ident = "019aaaaa-9999-7000-8000-00000000000f"
        path = self.write(turn_start(), path=self.log_of(ident))
        guardian = self.thread(ident, path, source='{"subagent":{"other":"guardian"}}', thread_source="guardian_review")
        stranger = self.child("elsewhere", turn_start(), parent="019aaaaa-other")
        self.place(self.child("audit", turn_start()), others=[guardian, stranger[0]])
        self.assertEqual(self.states(), {"audit": "working"})

    def test_grandchild(self):
        child = self.child("audit", turn_start())
        grandchild = self.child("audit/detail", turn_start(), parent=child[0]["id"], created_at=int(T0) + 5)
        self.place(child, grandchild)
        self.assertEqual([(a["name"], a["parent"]) for a in self.read()["subagents"]],
                         [("audit", None), ("detail", child[0]["id"])])

    def test_nickname_when_the_thread_has_no_path(self):
        self.place(self.child("audit", turn_start(), agent_path=None, agent_role="worker"))
        self.assertEqual([(a["name"], a["type"]) for a in self.read()["subagents"]], [("Lagrange", "worker")])

    def test_fifty_at_most_the_last_to_have_written(self):
        self.place(*[self.child("a%02d" % i, age=i) for i in range(55)])
        self.assertEqual(sorted(self.states()), ["a%02d" % i for i in range(50)])

    def test_none_or_unknown(self):
        self.write()
        self.assertIsNone(self.read()["subagents"])                                # without an index: unknown
        self.index(self.thread())
        self.assertEqual(self.read()["subagents"], [])                             # index read: none
        self.index(self.thread(), links=[(THREAD, "019aaaaa-no-log"), (THREAD, "019aaaaa-no-thread")])
        self.assertEqual(self.read()["subagents"], [])
        (self.root / "state_5.sqlite").write_bytes(b"this is not a database")
        self.assertIsNone(self.read()["subagents"])


class Conversation(Case):
    def turns(self, **options):
        return codex.turns(self.session, **options)

    def test_one_turn_per_message(self):
        self.write(
            turn_start(), context(), message("m1", "Tidy the workshop", t=1),
            item("Reasoning", t=2, summary_text=["I am thinking."], raw_content=[]),
            reply("I am looking.", t=3, phase="commentary"), command("ls workshop", t=4, written="tools\n"),
            item("FileChange", t=5, changes={"/tmp/trial/plan.md": {"type": "add", "content": "Plan"}},
                 status="completed", stdout="", stderr=""),
            item("McpToolCall", t=6, server="workshop", tool="inventory", arguments={}, status="completed"),
            item("Extension", t=7, kind="web.search", query="tidying tips", results=[]),
            item("ContextCompaction", t=8), reply("It is tidy.", t=9), tokens(1000, t=9), turn_end(t=10),
            turn_start(t=20, turn="turn-2"), message("m2", "Thanks", t=21, turn="turn-2"))
        self.assertEqual(self.turns(), {"older": False, "before": None, "turns": [
            {"id": "m1", "t": guards.iso(T0 + 1), "from": "user", "text": "Tidy the workshop",
             "replies": [{"t": guards.iso(T0 + 3), "text": "I am looking."},
                         {"t": guards.iso(T0 + 9), "text": "It is tidy."}],
             "tools": [{"name": "CommandExecution", "target": "ls workshop"},
                       {"name": "FileChange", "target": "/tmp/trial/plan.md"},
                       {"name": "inventory", "target": "workshop"}, {"name": "web.search", "target": "tidying tips"}],
             "end": guards.iso(T0 + 10)},
            {"id": "m2", "t": guards.iso(T0 + 21), "from": "user", "text": "Thanks", "replies": [],
             "tools": [], "end": None}]})

    def test_a_message_during_a_turn_opens_a_turn(self):
        # Codex keeps the same `turn_id` when the user writes while the agent is working.
        self.write(turn_start(), message("m1", "Start", t=1), reply("I am starting.", t=2, phase="commentary"),
                   message("m2", "Rather from the end", t=3), reply("From the end, then.", t=4), turn_end(t=5))
        read = self.turns()["turns"]
        self.assertEqual([(t["id"], [r["text"] for r in t["replies"]], t["end"]) for t in read],
                         [("m1", ["I am starting."], None), ("m2", ["From the end, then."], guards.iso(T0 + 5))])

    def test_a_resumed_turn_is_no_longer_ended(self):
        self.write(turn_start(), message("m1", "Start"), reply("Done."), turn_end(t=5))
        self.assertIsNotNone(self.turns()["turns"][0]["end"])
        self.append(turn_start(t=9, turn="turn-2"), reply("A subagent has answered: I am resuming.", t=10))
        turn, = self.turns()["turns"]              # a turn Codex starts without a message extends the previous one
        self.assertEqual((len(turn["replies"]), turn["end"]), (2, None))

    def test_what_opens_no_turn(self):
        self.write(reply("Before any message."), message("", "Without an identifier"), message("m0", "   "),
                   item("UserMessage", id="m1", content=[{"type": "local_image", "path": "/tmp/trial/view.png"}]),
                   command("ls"), turn_end())
        self.assertEqual(self.turns()["turns"], [])

    def test_pagination(self):
        self.write(*[l for i in range(1, 6) for l in (message("m%d" % i, "Message %d" % i, t=i),
                                                      reply("Reply %d" % i, t=i), turn_end(t=i))])
        page = self.turns(limit=2)
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]),
                         (["m4", "m5"], True, "m4"))
        page = self.turns(limit=2, before="m4")
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]),
                         (["m2", "m3"], True, "m2"))
        self.assertEqual(page["turns"][1]["replies"][0]["text"], "Reply 3")
        page = self.turns(limit=2, before="m2")
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]), (["m1"], False, None))
        self.assertEqual(self.turns(before="m1"), {"turns": [], "older": False, "before": None})
        self.assertEqual(len(self.turns(limit=0)["turns"]), 1)

    def test_unknown_before(self):
        self.write(message("m1", "One"))
        with self.assertRaises(LookupError):
            self.turns(before="unknown")

    def test_log_gone(self):
        with self.assertRaises(OSError):
            self.turns()

    def test_clipped_texts(self):
        self.write(message("m1", "m" * 5000), reply("r" * 9000), command("c" * 300))
        turn, = self.turns()["turns"]
        self.assertEqual((len(turn["text"]), len(turn["replies"][0]["text"]), len(turn["tools"][0]["target"])),
                         (4000, 8000, 160))

    def test_a_turn_of_more_than_16_mb_stays_readable(self):
        big = [command("produce %d" % i, written="x" * 2 * MB) for i in range(3)]       # 6 MB per line
        self.write(message("m1", "One"), reply("Reply 1"), message("m2", "Two"), *big, reply("Reply 2"),
                   message("m3", "Three"), reply("Reply 3"))
        self.assertGreater(self.path.stat().st_size, reading.CONVERSATION_MAX)
        page = self.turns()                            # no more than 16 MB read again: the first two turns wait
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]), (["m3"], True, "m3"))
        page = self.turns(before="m3")                 # a turn bigger than 16 MB is returned all the same, alone
        self.assertEqual(([t["id"] for t in page["turns"]], page["older"], page["before"]), (["m2"], True, "m2"))
        self.assertEqual(([o["target"] for o in page["turns"][0]["tools"]], page["turns"][0]["replies"][0]["text"]),
                         (["produce 0", "produce 1", "produce 2"], "Reply 2"))
        self.assertEqual([t["id"] for t in self.turns(before="m2")["turns"]], ["m1"])

    def test_the_conversation_follows_the_growing_log(self):
        self.write(message("m1", "One"), reply("Reply 1"))
        self.assertEqual(len(self.turns()["turns"]), 1)
        self.append(message("m2", "Two"), reply("Reply 2"), end='\n{"timestamp":"2026')
        self.assertEqual([(t["id"], len(t["replies"])) for t in self.turns()["turns"]], [("m1", 1), ("m2", 1)])
        self.read()                                    # the poll and the conversation share the same followed state
        self.assertEqual(len(self.turns()["turns"]), 2)

    def test_the_poll_and_the_conversation_read_at_the_same_time(self):
        """`read` comes from the poll's thread, `turns` from the server's: no line is noted twice."""
        self.write()
        failures = []

        def reader(start, read):
            try:
                start.wait()
                read()
            except Exception as e:      # a failure in a thread would not fail the test: it is reported
                failures.append(e)

        for i in range(60):
            self.append(message("m%d" % i, "Message %d" % i), reply("Reply %d" % i))
            start = threading.Barrier(4)
            threads = [threading.Thread(target=reader, args=(start, read))
                       for read in (self.read, self.turns, self.turns, self.read)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
        page = self.turns(limit=60)
        self.assertEqual((failures, len(page["turns"]), page["older"]), ([], 60, False))


if __name__ == "__main__":
    unittest.main()
