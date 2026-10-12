"""The Claude Code reader: linking by the pid and by the registry, reading the log, the turns, the hostile lines.

A fake ~/.claude folder is built in a temporary folder, in the shape recorded on Claude Code 2.1.285; the reader's
`ROOT` and `alive` are replaced. No real log is opened and all the texts are made up. The real Herdr is never
called: none of its reads is opened, except in front of a fake Herdr (LinkingByPid).
"""
import copy
import itertools
import json
import os
import re
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import extensions, guards, herdr     # noqa: E402
from extensions import _reading as reading     # noqa: E402
from tests.fake_herdr import FakeHerdr          # noqa: E402

claude = extensions.import_file(extensions.FOLDER / "claude.py")

NOW = 1791349200.0                   # the time passed to `read`; the fake lines are dated relative to it
REAL_ALIVE = claude.alive            # the real function, kept before the tests replace it
USAGE = {"input_tokens": 12, "cache_creation_input_tokens": 3000, "cache_read_input_tokens": 150000,
         "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 3000},
         "output_tokens": 420, "service_tier": "standard", "inference_geo": "not_available"}
_number = itertools.count(1)


# ── The line factory: the exact shape recorded, made-up texts ──

def stamp(when):
    """The time of a line, `when` seconds from NOW, as Claude Code writes it."""
    instant = datetime.fromtimestamp(NOW + when, timezone.utc)
    return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def line(kind, when=-600, **fields):
    """A conversation line (user, assistant, attachment, system) with the keys common to all of them."""
    n = next(_number)
    return {"parentUuid": f"u{n - 1}", "isSidechain": False, "uuid": f"u{n}", "timestamp": stamp(when),
            "userType": "external", "entrypoint": "cli", "cwd": "/fake/project", "sessionId": "s1",
            "version": "2.1.285", "gitBranch": "main", "type": kind, **fields}


def assistant(*blocks, when=-600, ident="msg_1", model="claude-opus-5-5", effort="xhigh", stop="tool_use",
              usage=USAGE, **fields):
    """The lines of a message from the assistant: one per block, that repeat `message.id`, `usage` and
    `stop_reason`."""
    return [line("assistant", when, requestId="req_" + ident, effort=effort, perTurnEffort=effort,
                 message={"model": model, "id": ident, "type": "message", "role": "assistant", "content": [block],
                          "stop_reason": stop, "stop_sequence": None, "usage": usage}, **fields) for block in blocks]


def text(t):
    return {"type": "text", "text": t}


def thinking():
    return {"type": "thinking", "thinking": "A reasoning that must not come out.", "signature": "sig"}


def tool(ident, name, **args):
    return {"type": "tool_use", "id": ident, "name": name, "input": args}


def human(t, when=-600):
    return line("user", when, message={"role": "user", "content": t}, origin={"kind": "human"}, turnOrigin="human",
                promptSource="typed", promptId="p1", permissionMode="auto")


def notification(t, when=-600):
    return line("user", when, message={"role": "user", "content": t}, promptSource="system",
                origin={"kind": "task-notification", "producer": "session-task"}, turnOrigin="task_notification")


def meta(t):
    """A `user` line that Claude Code writes for itself: neither a message, nor the start of a turn."""
    return line("user", message={"role": "user", "content": t}, isMeta=True)


def result(ident, when=-600, content="done", **fields):
    """The result of a tool: a `user` line that does not open a turn."""
    block = {"type": "tool_result", "tool_use_id": ident, "content": content}
    return {**line("user", when, message={"role": "user", "content": [block]}, toolUseResult={"stdout": content},
                   sourceToolUseID=ident), **fields}


def turn_end(when=-600):
    return line("system", when, subtype="turn_duration", durationMs=1000, messageCount=3, isMeta=False)


def queued(t, origin="human"):
    """A message that arrived while the agent was working: an attachment, not a `user` line."""
    attachment = {"type": "queued_command", "prompt": t, "commandMode": "prompt", "origin": {"kind": origin},
                  "source_uuid": "q1", "timestamp": stamp(-600), "humanTurn": True}
    return line("attachment", attachment=attachment)


def title(t, key="ai-title"):
    return {"type": key, "aiTitle" if key == "ai-title" else "customTitle": t, "sessionId": "s1"}


def cost(dollars):
    return {"type": "cost-state", "sessionId": "s1", "totalCostUSD": dollars, "totalAPIDuration": 1,
            "totalDuration": 2,
            "modelUsage": {"claude-opus-5-5": {"inputTokens": 1, "outputTokens": 2, "costUSD": dollars}}}


def reminder(*tasks):
    return line("attachment", attachment={"type": "task_reminder", "content": list(tasks), "itemCount": len(tasks)})


def task(ident, subject, status="pending", blocked_by=()):
    return {"id": ident, "subject": subject, "description": "A description.", "activeForm": subject + " in progress",
            "status": status, "blocks": [], "blockedBy": list(blocked_by)}


def pane(**fields):
    """An agent of `session.snapshot.agents`: Herdr gives neither session nor pid for Claude Code."""
    return {"agent": "claude", "agent_status": "working", "cwd": "/fake/project", "foreground_cwd": "/fake/project",
            "pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1", "terminal_id": "term_1", "focused": False,
            "terminal_title": "◑ Tidy the attic", "terminal_title_stripped": "Tidy the attic", **fields}


def processes(*pids, of="w1:p1"):
    """Herdr's response to `pane.process_info` for the pane `of`, in the shape recorded on the real one (protocol
    22): the foreground processes of the pane, among them Claude Code, which leads their group."""
    return {"type": "pane_process_info", "process_info": {
        "pane_id": of, "shell_pid": 90, "foreground_process_group_id": pids[-1] if pids else None,
        "foreground_processes": [{"pid": pid, "name": "program", "argv0": "program", "argv": ["program", "-x"],
                                  "cmdline": "program -x", "cwd": "/fake/project"} for pid in pids]}}


def flat(lines):
    """The lines one by one: `assistant` returns a list of them, the other factories a single one."""
    return [x for l in lines for x in (l if isinstance(l, list) else [l])]


def put(path, *lines):
    """Writes a JSONL file (a line can also be raw bytes); returns its path."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    raw = [x if isinstance(x, bytes) else json.dumps(x).encode() + b"\n" for x in flat(lines)]
    Path(path).write_bytes(b"".join(raw))
    return str(path)


def append(path, one_line):
    with open(path, "ab") as f:
        f.write(json.dumps(one_line).encode() + b"\n")


class Fake(unittest.TestCase):
    """A fake ~/.claude: registry, logs, tasks, subagents. A session s1 lives in /fake/project. No read of Herdr
    is opened, even if another test has loaded the extensions: the link is made without it."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root, self.dead = Path(folder.name), set()
        self.project = self.root / "projects" / "-fake-project"
        for patch in (mock.patch.object(claude, "ROOT", self.root),
                      mock.patch.object(claude, "alive", lambda pid: pid not in self.dead),
                      mock.patch.object(herdr, "opened", set()),
                      mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": str(self.root / "no-herdr.sock")})):
            patch.start()
            self.addCleanup(patch.stop)

    def session(self, pid, ident, *lines, cwd="/fake/project", **registry):
        """Enters a session in the registry and writes its log; returns the path of the log. The reader starts
        again from zero: a real log only grows, a test can replace it with another."""
        claude._CACHE.clear()
        claude._FOLLOWED.clear()
        record = {"pid": pid, "sessionId": ident, "cwd": cwd, "startedAt": 1791340000000, "procStart": "x",
                  "version": "2.1.285", "peerProtocol": 1, "peerFeatures": ["notify_idle"], "kind": "interactive",
                  "entrypoint": "cli", "pidDomain": "host", "messagingSocketPath": f"/tmp/cc-socks/{pid}.sock",
                  "name": "project-ab", "nameSince": 1, "nameSource": "derived", "status": "busy", "updatedAt": 2,
                  "statusUpdatedAt": 3, **registry}
        put(self.root / "sessions" / f"{pid}.json", record)
        return put(self.root / "projects" / re.sub(r"[/. ]", "-", cwd) / f"{ident}.jsonl", *lines)

    def read(self):
        return claude.read(claude.session(pane()), NOW)

    def read_log(self, *lines, **registry):
        """What `read` returns for the session s1, alone in its folder, whose log carries these lines."""
        self.session(100, "s1", *lines, **registry)
        return self.read()

    def subagent(self, ident, *lines, age=10, workflow=None, **record):
        """Writes the log and the record of a subagent of s1, silent for `age` seconds; returns its log."""
        folder = self.project / "s1" / "subagents" / (f"workflows/{workflow}" if workflow else "")
        its_own = [{**x, "isSidechain": True, "agentId": ident} if isinstance(x, dict) else x for x in flat(lines)]
        path = put(folder / f"agent-{ident}.jsonl", *its_own)
        put(folder / f"agent-{ident}.meta.json", {"agentType": "general-purpose", "spawnDepth": 1,
                                                 "description": "Count the boxes", **record})
        os.utime(path, (NOW - age, NOW - age))
        return path


class Linking(Fake):
    def test_a_single_candidate_in_the_folder(self):
        path = self.session(100, "s1", title("A quite different title"))
        self.session(101, "s2", cwd="/fake/elsewhere")
        self.assertEqual(claude.session(pane()), {"id": "s1", "path": path})
        self.assertTrue(os.path.isabs(path))

    def test_the_foreground_folder_counts_too(self):
        self.session(100, "s1", cwd="/fake/sub/folder")
        self.assertEqual(claude.session(pane(foreground_cwd="/fake/sub/folder"))["id"], "s1")

    def test_the_folder_of_the_pane_goes_through_a_symbolic_link(self):
        real = os.path.realpath(self.root / "real folder")
        os.mkdir(real)
        os.symlink(real, self.root / "link")
        self.session(100, "s1", cwd=real)                        # the registry carries the real path
        link = str(self.root / "link")
        self.assertNotEqual(link, real)
        self.assertEqual(claude.session(pane(cwd=link, foreground_cwd=link))["id"], "s1")

    def test_two_candidates_told_apart_by_the_title(self):
        self.session(100, "s1", title("Old title"), title("Tidy the attic"))
        self.session(101, "s2", title("Tidy the attic"), title("Paint the door"))
        self.session(102, "s3", title("Mow"), title("Water the tomatoes", "custom-title"))
        self.assertEqual(claude.session(pane())["id"], "s1")
        self.assertEqual(claude.session(pane(terminal_title_stripped="Paint the door"))["id"], "s2")
        self.assertEqual(claude.session(pane(terminal_title_stripped="Water the tomatoes"))["id"], "s3")

    def test_two_candidates_with_the_same_title_link_nothing(self):
        self.session(100, "s1", title("Tidy the attic"))
        self.session(101, "s2", title("Tidy the attic"))
        self.assertIsNone(claude.session(pane()))

    def test_two_candidates_that_no_title_designates(self):
        self.session(100, "s1", title("Paint the door"))
        self.session(101, "s2")
        self.assertIsNone(claude.session(pane()))
        self.assertIsNone(claude.session(pane(terminal_title_stripped=None)))

    def test_no_candidate(self):
        self.session(100, "s1", cwd="/fake/elsewhere")
        self.assertIsNone(claude.session(pane()))
        self.assertIsNone(claude.session({"agent": "claude"}))

    def test_background_session_dropped(self):
        self.session(100, "s1", kind="bg")
        self.assertIsNone(claude.session(pane()))
        self.session(101, "s2")
        self.assertEqual(claude.session(pane())["id"], "s2")

    def test_dead_process_dropped(self):
        self.session(100, "s1")
        self.session(101, "s2")
        self.dead.add(100)
        self.assertEqual(claude.session(pane())["id"], "s2")
        self.dead.add(101)
        self.assertIsNone(claude.session(pane()))

    def test_the_real_life_test(self):
        self.assertTrue(REAL_ALIVE(os.getpid()))
        self.assertFalse(REAL_ALIVE(2 ** 80))

    def test_name_of_the_project_folder(self):
        path = self.session(100, "s1", cwd="/fake/My Project/v2.1")
        self.assertTrue(path.endswith("/projects/-fake-My-Project-v2-1/s1.jsonl"))
        self.assertEqual(claude.session(pane(cwd="/fake/My Project/v2.1"))["path"], path)

    def test_log_filed_in_another_project_folder(self):
        self.session(100, "s1")
        elsewhere = self.root / "projects" / "-another-name" / "s1.jsonl"
        elsewhere.parent.mkdir()
        (self.project / "s1.jsonl").rename(elsewhere)
        self.assertEqual(claude.session(pane())["path"], str(elsewhere))

    def test_a_key_file_is_never_opened(self):
        self.session(100, "s1")
        intruder = {"pid": 101, "sessionId": "s2", "cwd": "/fake/project", "kind": "interactive"}
        (self.root / "sessions" / "100.abc.key").write_text(json.dumps(intruder))
        opened = []
        with mock.patch.object(claude, "_record", lambda path: opened.append(str(path)) or {}):
            claude.session(pane())
        self.assertEqual(opened, [str(self.root / "sessions" / "100.json")])
        self.assertEqual(claude.session(pane())["id"], "s1")

    def test_session_identifier_that_leaves_the_folder(self):
        self.session(100, "s1", sessionId="../../elsewhere")
        self.assertIsNone(claude.session(pane()))


class LinkingByPid(Fake):
    """Two sessions live in the folder of the pane: s1 (pid 100), that the title of the pane designates, and s2
    (pid 101). When Herdr does not say the processes of the pane, the link therefore returns s1: it is the fallback.
    When it says them, it returns the session of the only one of them that has one, and otherwise nothing: no more
    fallback."""

    def setUp(self):
        super().setUp()
        self.session(100, "s1", title("Tidy the attic"))
        self.session(101, "s2", title("Paint the door"))

    def mount(self, response, opened=True):
        """Mounts a fake Herdr that answers `response` to `pane.process_info` and, like the extensions' loader,
        opens the read that the reader asks for; returns the fake. Fake.setUp puts `herdr.opened` back at the end
        of the test."""
        fake = FakeHerdr({"pane.process_info": response})
        self.addCleanup(fake.stop)
        aimed = mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": fake.path})
        aimed.start()
        self.addCleanup(aimed.stop)
        if opened:
            herdr.open_reads(claude.HERDR)
        return fake

    def linked(self, **fields):
        """The identifier of the session linked to the pane, or None if it is linked to none."""
        return (claude.session(pane(**fields)) or {}).get("id")

    def test_the_pid_wins_over_a_misleading_title(self):
        self.assertEqual(self.linked(), "s1")                    # without Herdr: the title
        fake = self.mount(processes(77, 101))                    # 77: a child of Claude Code, without a record
        self.assertEqual(claude.session(pane()), {"id": "s2", "path": str(self.project / "s2.jsonl")})
        self.assertEqual([(r["method"], r["params"]) for r in fake.received],
                         [("pane.process_info", {"pane_id": "w1:p1"})])

    def test_two_panes_with_the_same_folder_and_the_same_title(self):
        self.session(101, "s2", title("Tidy the attic"))
        self.assertIsNone(claude.session(pane()))                # without Herdr, nothing tells s1 and s2 apart
        self.mount(lambda params: processes({"w1:p1": 100, "w1:p2": 101}[params["pane_id"]], of=params["pane_id"]))
        self.assertEqual((self.linked(), self.linked(pane_id="w1:p2")), ("s1", "s2"))

    def test_the_pid_wins_over_the_folder(self):
        self.session(102, "s3", cwd="/fake/elsewhere")
        self.mount(processes(102))
        self.assertEqual(self.linked(), "s3")

    def test_a_pane_without_a_record_does_not_take_its_neighbour_s_session(self):
        # two panes in the same folder; the Claude Code of w1:p2 has just started, its record is not written yet
        self.dead.add(101)                                       # only s1 lives in the folder
        self.assertEqual((self.linked(), self.linked(pane_id="w1:p2")), ("s1", "s1"))   # without Herdr: the folder
        pids = {"w1:p1": 100, "w1:p2": 77}
        fake = self.mount(lambda params: processes(pids[params["pane_id"]], of=params["pane_id"]))
        self.assertEqual((self.linked(), self.linked(pane_id="w1:p2")), ("s1", None))
        self.assertEqual(len(fake.received), 2)                  # Herdr answered: the registry is what says nothing

    def test_the_pid_of_a_dropped_session_links_nothing(self):
        self.mount(processes(101))
        self.session(101, "s2", title("Paint the door"), kind="bg")
        self.assertIsNone(self.linked())                         # neither s2, dropped, nor s1 by the folder and title
        self.session(101, "s2", title("Paint the door"))
        self.assertEqual(self.linked(), "s2")
        self.dead.add(101)
        self.assertIsNone(self.linked())

    def test_two_processes_of_the_pane_have_a_record(self):
        self.mount(processes(101, 100))
        self.assertIsNone(self.linked())                         # the pid does not settle it, the title stays out

    def test_herdr_unavailable(self):
        herdr.open_reads(claude.HERDR)                           # the socket that Fake designates does not exist
        self.assertEqual(self.linked(), "s1")
        fake = self.mount(b"")                                   # a connection closed without a response
        self.assertEqual(self.linked(), "s1")
        self.assertEqual(len(fake.received), 1)

    def test_herdr_that_is_slow(self):
        self.mount(lambda params: time.sleep(0.2) or processes(101))
        with mock.patch.object(claude, "TIMEOUT", 0.05):
            self.assertEqual(self.linked(), "s1")                # past the timeout, the response is no longer awaited

    def test_refusal_from_herdr(self):
        fake = self.mount(herdr.Refused("made_up_code", "A made-up refusal."))
        self.assertEqual(self.linked(), "s1")
        self.assertEqual(len(fake.received), 1)

    def test_read_not_opened(self):
        fake = self.mount(processes(101), opened=False)
        self.assertEqual(self.linked(), "s1")
        self.assertEqual(fake.received, [])                      # nothing is asked of Herdr

    def test_a_pane_without_an_identifier_asks_nothing(self):
        fake = self.mount(processes(101))
        for ident in (None, "", 7, ["w1:p1"]):
            self.assertEqual(self.linked(pane_id=ident), "s1")
        self.assertEqual(fake.received, [])

    def test_response_of_unexpected_shape(self):
        self.session(1, "s9", cwd="/fake/elsewhere")             # the session a "true" pid would wrongly designate
        fake = self.mount(None)
        pids = (None, True, "101", 101.0, [101], {"pid": 101}, float("nan"))
        for response in (b"not json\n", b"[1, 2]\n", {}, {"process_info": [processes(101)]}, processes(*pids),
                         processes(), {"foreground_processes": [{"pid": 101}]},
                         {"process_info": {"foreground_processes": {"pid": 101}}},
                         {"process_info": {"foreground_processes": [101, [101], "101", None]}}):
            fake.responses["pane.process_info"] = response
            self.assertEqual(self.linked(), "s1", response)      # no readable process: Herdr said nothing
        for pid in (-101, 2 ** 80):                              # an integer that is the pid of no session
            fake.responses["pane.process_info"] = processes(*pids, pid)
            self.assertIsNone(self.linked(), pid)
        for response in mutations(processes(101)):               # one value changes: s2, the fallback, or nothing
            fake.responses["pane.process_info"] = response
            self.assertIn(self.linked(), ("s1", "s2", None), response)


class Reading(Fake):
    KEYS = {"title", "model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents",
            "activity"}

    def test_model_effort_context_cost_title(self):
        made_up = assistant(text("Interrupted."), ident="msg_3", model="<synthetic>", effort=None,
                            usage={"input_tokens": 0}, stop="stop_sequence")
        got = self.read_log(title("Tidy the attic"), cost(1.5), human("Tidy the attic."),
                            assistant(thinking(), text("I am starting."), effort="medium", model="claude-sonnet-5-5"),
                            assistant(text("It is tidy."), ident="msg_2", stop="end_turn"), made_up, cost(4.21))
        self.assertEqual(set(got), self.KEYS)
        self.assertEqual(got["title"], "Tidy the attic")
        self.assertEqual(got["model"], "claude-opus-5-5")        # the <synthetic> line does not count
        self.assertEqual(got["effort"], "xhigh")
        self.assertEqual(got["context"], {"tokens": 153012, "window": None, "percent": None})
        self.assertEqual(got["cost"], 4.21)
        self.assertIsNone(got["goal"])
        self.assertEqual(got["activity"], guards.iso(os.stat(self.project / "s1.jsonl").st_mtime))

    def test_a_log_without_a_message_says_nothing(self):
        got = self.read_log({"type": "mode", "mode": "normal", "sessionId": "s1"})
        self.assertEqual(set(got), self.KEYS)
        for key in ("title", "model", "effort", "context", "cost", "tool", "request", "goal"):
            self.assertIsNone(got[key], key)
        self.assertEqual((got["todos"], got["subagents"]), ([], []))

    def test_the_title_given_by_hand_wins(self):
        self.assertEqual(self.read_log(title("My title", "custom-title"), title("Found title"))["title"], "My title")

    def test_unreadable_usage_or_compaction_context_unknown(self):
        self.assertIsNone(self.read_log(assistant(text("Hello."), usage={"input_tokens": 5}))["context"])
        compaction = line("system", subtype="compact_boundary", content="Conversation compacted",
                          compactMetadata={"trigger": "auto", "preTokens": 900000, "postTokens": 17000})
        got = self.read_log(assistant(text("Hello.")), compaction)
        self.assertIsNone(got["context"])
        self.assertEqual(got["model"], "claude-opus-5-5")

    def test_a_usage_of_zero_measures_nothing(self):
        zero = {**USAGE, "input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
                "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}, "output_tokens": 0}
        empty = assistant(thinking(), tool("t1", "Bash", command="ls"), ident="msg_2", usage=zero)
        got = self.read_log(human("Tidy."), assistant(text("I am looking.")), empty)
        self.assertEqual(got["context"], {"tokens": 153012, "window": None, "percent": None})   # the measure before
        self.assertIsNone(self.read_log(human("Tidy."), empty)["context"])                      # never "0 token"

    def test_tool_running_then_finished(self):
        two = assistant(tool("t1", "Read", file_path="/fake/a.py"), tool("t2", "Bash", command="make"), when=-30)
        path = self.session(100, "s1", human("Run the tests."), two, result("t1", -20))
        self.assertEqual(self.read()["tool"], {"name": "Bash", "since": guards.iso(NOW - 30)})
        self.assertIsNone(self.read()["request"])
        append(path, result("t2", -5))
        self.assertIsNone(self.read()["tool"])

    def test_of_several_open_tools_the_first_called_is_named(self):
        # Claude Code runs the tools of one reply in the order of the calls: the first left without a result is
        # the one that runs, or the one that waits for a permission; the next ones have not started.
        three = assistant(tool("t1", "Read", file_path="/fake/a.py"), tool("t2", "Bash", command="make"),
                          tool("t3", "Write", file_path="/fake/b.py"), when=-30)
        start = [human("Run the tests."), three, result("t1", -20)]
        waiting = {"status": "waiting", "waitingFor": "permission prompt"}
        self.assertEqual(self.read_log(*start)["tool"], {"name": "Bash", "since": guards.iso(NOW - 30)})
        self.assertEqual(self.read_log(*start, **waiting)["request"], {"kind": "permission", "tool": "Bash"})
        self.assertEqual(self.read_log(*start, result("t2", -10), **waiting)["request"]["tool"], "Write")

    def test_a_tool_that_never_returned_does_not_outlive_the_turn(self):
        start = [human("Run the tests."), assistant(tool("t1", "Bash", command="make"))]
        self.assertIsNone(self.read_log(*start, turn_end())["tool"])
        self.assertIsNone(self.read_log(*start, human("Stop."))["tool"])
        self.assertEqual(self.read_log(*start, meta("A note."))["tool"]["name"], "Bash")

    def test_open_question(self):
        questions = [
            {"question": "Which colour?", "header": "Colour", "multiSelect": False,
             "options": [{"label": "Red", "description": "Bright"}, {"label": "Blue", "description": "Calm"}]},
            {"question": "Which rooms?", "header": "Rooms", "multiSelect": True,
             "options": [{"label": "Living room", "description": "", "preview": "x"}, {"description": "no label"}]},
            {"header": "No question", "options": []}]
        start = [human("Repaint."), assistant(tool("t1", "AskUserQuestion", questions=questions))]
        got = self.read_log(*start, status="waiting", waitingFor="input needed")
        self.assertEqual(got["request"], {"kind": "question", "questions": [
            {"question": "Which colour?", "options": ["Red", "Blue"], "multi": False},
            {"question": "Which rooms?", "options": ["Living room"], "multi": True}]})
        self.assertEqual(got["tool"]["name"], "AskUserQuestion")
        answer = result("t1", toolUseResult={"questions": questions, "answers": {"Which colour?": "Red"}})
        self.assertIsNone(self.read_log(*start, answer)["request"])

    def test_a_question_called_after_another_tool_is_not_asked_yet(self):
        questions = [{"question": "Which colour?", "multiSelect": False, "options": [{"label": "Red"}]}]
        both = assistant(tool("t1", "Bash", command="make"), tool("t2", "AskUserQuestion", questions=questions))
        start = [human("Repaint."), both]
        waiting = {"status": "waiting", "waitingFor": "permission prompt"}
        self.assertIsNone(self.read_log(*start)["request"], "Bash runs first: nothing is asked yet")
        self.assertEqual(self.read_log(*start, **waiting)["request"], {"kind": "permission", "tool": "Bash"})
        asked = self.read_log(*start, result("t1"))
        self.assertEqual((asked["tool"]["name"], asked["request"]["kind"]), ("AskUserQuestion", "question"))

    def test_permission_awaited_by_the_registry(self):
        start = [human("Delete the folder."), assistant(tool("t1", "Bash", command="rm -r old"))]
        waiting = {"status": "waiting", "waitingFor": "permission prompt"}
        self.assertIsNone(self.read_log(*start)["request"])               # the log alone does not show the wait
        self.assertEqual(self.read_log(*start, **waiting)["request"], {"kind": "permission", "tool": "Bash"})
        self.assertEqual(self.read_log(human("Hello."), **waiting)["request"], {"kind": "permission", "tool": None})
        self.assertIsNone(self.read_log(*start, status="waiting", waitingFor="input needed")["request"])
        self.assertIsNone(self.read_log(*start, status="busy", waitingFor="permission prompt")["request"])

    def test_todos_from_the_tasks_folder(self):
        tasks = [task("10", "Varnish"), task("2", "Sand", "in_progress"), task("1", "Empty", "completed"),
                 task("3", "Paint", blocked_by=["2"]), task("4", "Deliver", blocked_by=["1"]),
                 task("5", "Deleted", "deleted")]
        for t in tasks:
            put(self.root / "tasks" / "s1" / f"{t['id']}.json", t)
        (self.root / "tasks" / "s1" / ".lock").write_text("")
        todos = self.read_log(reminder(task("1", "An old reminder")))["todos"]
        self.assertEqual([(t["text"], t["status"], t["phase"]) for t in todos], [
            ("Empty", "done", None), ("Sand", "in_progress", None), ("Paint", "blocked", None),
            ("Deliver", "pending", None), ("Varnish", "pending", None)])

    def test_todos_from_the_reminder_as_a_fallback_then_none(self):
        last = reminder(task("1", "Empty", "completed"), task("2", "Sand"))
        self.assertEqual(self.read_log(reminder(task("1", "Old")), human("Next."), last)["todos"], [
            {"text": "Empty", "status": "done", "phase": None},
            {"text": "Sand", "status": "pending", "phase": None}])
        self.assertEqual(self.read_log(human("Nothing to do."), reminder())["todos"], [])
        self.assertEqual(self.read_log(human("Nothing to do."))["todos"], [])

    def test_what_precedes_the_end_of_the_log_is_followed(self):
        path = self.session(100, "s1", title("Tidy the attic"), cost(2.5), reminder(task("1", "Empty")),
                            human("Read this big file."), assistant(tool("t1", "Read", file_path="/fake/big")),
                            result("t1", content="x" * 700_000))
        self.assertGreater(os.path.getsize(path), reading.TAIL)
        got = self.read()
        self.assertEqual((got["title"], got["cost"], len(got["todos"])), ("Tidy the attic", 2.5, 1))
        self.assertEqual(got["model"], "claude-opus-5-5")        # no message at the end: a longer end is read
        self.assertIsNone(got["tool"])

    def test_only_what_changes_is_read_again(self):
        path = self.session(100, "s1", title("Tidy the attic"), cost(1.0), assistant(text("Hello.")))
        with mock.patch.object(claude, "_scan", wraps=claude._scan) as scan:
            self.assertEqual(self.read()["cost"], 1.0)
            seen = scan.call_count
            self.read()
            self.assertEqual(scan.call_count, seen)              # nothing has changed: the log is not analysed
            append(path, cost(3.0))
            self.assertEqual(self.read()["cost"], 3.0)
            self.assertGreater(scan.call_count, seen)
        put(path, title("A rewritten log"))                      # a log that shrinks is read again from the start
        got = self.read()
        self.assertEqual((got["title"], got["cost"], got["model"]), ("A rewritten log", None, None))

    def test_a_log_replaced_by_another_file_is_read_again_from_the_start(self):
        path = self.session(100, "s1", title("Tidy the attic"), cost(1.5), human("Tidy the attic."))
        self.assertEqual((self.read()["title"], self.read()["cost"]), ("Tidy the attic", 1.5))
        other = put(self.project / "other", title("Paint the door"), cost(2.5), human("Paint the door blue."))
        self.assertGreater(os.path.getsize(other), os.path.getsize(path))
        os.replace(other, path)                                  # bigger than the old one: only the inode betrays it
        got = self.read()
        self.assertEqual((got["title"], got["cost"]), ("Paint the door", 2.5))

    def test_log_gone(self):
        session = {"id": "s1", "path": str(self.project / "s1.jsonl")}
        with self.assertRaises(OSError):
            claude.read(session, NOW)
        with self.assertRaises(OSError):
            claude.turns(session)


class Subagents(Fake):
    def read_all(self):
        """The subagents of s1, by identifier, in the order returned."""
        if not (self.root / "sessions").exists():
            self.session(100, "s1", human("Delegate."))
        return {a["id"]: a for a in self.read()["subagents"]}

    def test_simple_agent(self):
        sonnet = {"model": "claude-sonnet-5-5"}
        path = self.subagent("a1", human("Count.", -500), assistant(tool("t1", "Bash", command="ls"), **sonnet),
                             result("t1", toolEndsTurn=True), age=300, model="sonnet", agentType="Explore",
                             toolUseId="toolu_1")
        self.subagent("a2", human("Count.", -90), assistant(text("Twelve."), stop="end_turn", **sonnet), age=80)
        got = self.read_all()
        self.assertEqual(got["a1"], {
            "id": "a1", "name": "Count the boxes", "type": "Explore", "parent": None, "state": "done",
            "model": "sonnet", "start": guards.iso(NOW - 500), "end": guards.iso(os.stat(path).st_mtime)})
        self.assertEqual((got["a2"]["state"], got["a2"]["model"]), ("done", "claude-sonnet-5-5"))
        self.assertEqual(list(got), ["a1", "a2"])                 # sorted by start

    def test_working_then_unknown(self):
        open_tool = [human("Count."), assistant(tool("t1", "Bash", command="sleep 600"))]
        self.subagent("thinking", human("Count."), age=60)
        self.subagent("silent", human("Count."), age=300)
        self.subagent("waits-for-its-tool", *open_tool, age=300)
        self.subagent("lost", *open_tool, age=1800)
        self.subagent("no-record", human("Count."), age=5)
        os.remove(self.project / "s1" / "subagents" / "agent-no-record.meta.json")
        got = self.read_all()
        self.assertEqual({i: a["state"] for i, a in got.items()}, {
            "thinking": "working", "silent": "unknown", "waits-for-its-tool": "working", "lost": "unknown",
            "no-record": "working"})
        self.assertTrue(all(a["end"] is None for a in got.values()))
        self.assertEqual([got["no-record"][c] for c in ("name", "type", "model")], [None, None, None])

    def test_workflow_agents(self):
        def started(ident, label):
            return {"type": "started", "key": ident, "agentId": ident, "label": label, "phase": "Check"}
        for ident in ("w1", "w2", "w3", "w4"):
            self.subagent(ident, human("Check."), assistant(tool("t1", "Read", file_path="/fake/a")), age=30,
                          workflow="wf_1", agentType="workflow-subagent", workflowPhase="Check", model="sonnet")
        put(self.project / "s1" / "subagents" / "workflows" / "wf_1" / "journal.jsonl",
            {"type": "launched"}, started("w1", "Read"), started("w2", "Count"), started("w3", "Weigh"),
            started("w4", "Sort"), {"type": "result", "agentId": "w1", "key": "w1", "result": {"verdict": "good"}},
            {"type": "failed", "agentId": "w2", "key": "w2"}, {"type": "failed", "agentId": "w4", "key": "w4"},
            started("w4", "Sort again"))
        got = self.read_all()
        self.assertEqual({i: a["state"] for i, a in got.items()},
                         {"w1": "done", "w2": "failed", "w3": "working", "w4": "working"})
        self.assertEqual([got[i]["name"] for i in got], ["Read", "Count", "Weigh", "Sort again"])
        self.assertEqual((got["w1"]["type"], got["w1"]["parent"]), ("workflow-subagent", None))
        self.assertEqual([got[i]["end"] is None for i in got], [False, False, True, True])

    def test_failure_by_api_error(self):
        error = assistant(text("API Error"), model="<synthetic>", stop="stop_sequence", isApiErrorMessage=True)
        self.subagent("a1", human("Count."), assistant(text("I am counting."), model="claude-sonnet-5-5"), error)
        self.assertEqual([self.read_all()["a1"][c] for c in ("state", "model")], ["failed", "claude-sonnet-5-5"])

    def test_two_hour_window(self):
        done = [human("Count."), assistant(text("Twelve."), stop="end_turn")]
        self.subagent("recent", *done, age=2 * 3600 - 60)
        self.subagent("old", *done, age=2 * 3600 + 60)
        self.assertEqual(list(self.read_all()), ["recent"])

    def test_cap_of_fifty(self):
        for n in range(55):
            self.subagent(f"a{n:02d}", human("Count.", -n * 60), assistant(text("Twelve."), stop="end_turn"),
                          age=n * 60 + 1)
        self.assertEqual(list(self.read_all()), [f"a{n:02d}" for n in range(49, -1, -1)])    # the 50 latest, by start

    def test_a_subagent_that_moves_on_is_read_again(self):
        path = self.subagent("a1", human("Count."), age=5)
        self.assertEqual(self.read_all()["a1"]["state"], "working")
        append(path, assistant(text("Twelve."), stop="end_turn")[0])
        os.utime(path, (NOW - 1, NOW - 1))
        self.assertEqual(self.read_all()["a1"]["state"], "done")


class Turns(Fake):
    def turns(self, *lines, **options):
        if lines:
            self.session(100, "s1", *lines)
        return claude.turns(claude.session(pane()), **options)

    def test_spread_message_grouped_by_identifier(self):
        question = human("Tidy the attic.", -100)
        returned = self.turns(
            question,
            assistant(thinking(), text("I am looking."), text("Then I tidy."), tool("t1", "Bash", command="ls -l"),
                      tool("t2", "Read", file_path="/fake/list.txt"), when=-90),
            result("t1", -80), result("t2", -80),
            assistant(text("It is tidy."), tool("t3", "TaskStop", task_id="b1"), ident="msg_2", when=-70),
            turn_end(-60))
        self.assertEqual(returned, {"older": False, "before": None, "turns": [{
            "id": question["uuid"], "t": guards.iso(NOW - 100), "from": "user",
            "text": "Tidy the attic.",
            "replies": [{"t": guards.iso(NOW - 90), "text": "I am looking.\n\nThen I tidy."},
                        {"t": guards.iso(NOW - 70), "text": "It is tidy."}],
            "tools": [{"name": "Bash", "target": "ls -l"}, {"name": "Read", "target": "/fake/list.txt"},
                      {"name": "TaskStop", "target": None}],
            "end": guards.iso(NOW - 60)}]})
        self.assertNotIn("reasoning", json.dumps(returned))

    def test_human_turn_against_system_turn(self):
        image = {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "x"}}
        returned = self.turns(
            assistant(text("The end of a turn started higher up.")),
            human("Start the count."), assistant(text("It is started."), ident="m1"), turn_end(),
            notification("<task-notification><task-id>b1</task-id><status>completed</status></task-notification>"),
            assistant(text("The count is done."), ident="m2"), meta("A note."),
            queued("And the cellar?"), queued("<task-notification>…</task-notification>", "task-notification"),
            assistant(text("I move on to the cellar."), ident="m3"),
            line("user", message={"role": "user", "content": "<command-name>/model</command-name>"}),
            human([text("Look."), image]))["turns"]
        self.assertEqual([(t["from"], t["text"][:12], len(t["replies"]), t["end"] is None) for t in returned], [
            ("user", "Start the co", 1, False), ("system", "<task-notifi", 1, True),
            ("user", "And the cell", 1, True), ("system", "<command-nam", 0, True),
            ("user", "Look.", 0, True)])
        self.assertEqual(len({t["id"] for t in returned}), 5)

    def test_pagination(self):
        exchanges = [[human(f"Question {n}."), *assistant(text(f"Answer {n}."), ident=f"m{n}"), turn_end()]
                     for n in range(5)]
        page = self.turns(*exchanges, limit=2)
        self.assertEqual([t["text"] for t in page["turns"]], ["Question 3.", "Question 4."])
        self.assertEqual((page["older"], page["before"]), (True, page["turns"][0]["id"]))
        page = self.turns(limit=2, before=page["before"])
        self.assertEqual([t["text"] for t in page["turns"]], ["Question 1.", "Question 2."])
        page = self.turns(limit=2, before=page["before"])
        self.assertEqual([t["text"] for t in page["turns"]], ["Question 0."])
        self.assertEqual((page["older"], page["before"]), (False, None))
        everything = self.turns()
        self.assertEqual((len(everything["turns"]), everything["older"], everything["before"]), (5, False, None))
        self.assertEqual(self.turns(before=everything["turns"][0]["id"])["turns"], [])

    def test_unknown_before(self):
        with self.assertRaisesRegex(LookupError, "^none of the turns read carries this identifier$"):
            self.turns(human("Question."), before="never-seen")

    def test_the_limit_is_bounded_only_by_the_server(self):
        exchanges = [human(f"Question {n}.") for n in range(55)]
        self.assertEqual(len(self.turns(*exchanges, limit=60)["turns"]), 55)

    def test_the_end_read_is_bounded(self):
        exchanges = [[human(f"Question {n}."), *assistant(text(f"Answer {n}."), ident=f"m{n}"), turn_end()]
                     for n in range(40)]
        whole = self.turns(*exchanges, limit=50)["turns"]
        with mock.patch.object(reading, "TAIL", 2000), mock.patch.object(reading, "CONVERSATION_MAX", 20000):
            with mock.patch.object(reading, "tail_lines", wraps=reading.tail_lines) as tail:
                page = self.turns(limit=50)
            self.assertEqual([a.args[1] for a in tail.call_args_list], [2000, 8000, 20000])   # never the whole log
            n = len(page["turns"])
            self.assertTrue(0 < n < 40, n)
            self.assertEqual((page["turns"], page["older"]), (whole[-n:], True))
            self.assertEqual(page["before"], whole[-n]["id"])
            # at the far side of the end read: nothing more to return, but the log is longer than it
            self.assertEqual(self.turns(before=page["before"]), {"turns": [], "older": True, "before": None})
            with self.assertRaises(LookupError):
                self.turns(before=whole[0]["id"])
        self.assertEqual(self.turns(limit=2, before=whole[1]["id"])["turns"], whole[:1])

    def test_a_turn_beyond_the_end_read_is_found(self):
        old, big = human("Old question."), [result(f"t{n}", content="x" * 300_000) for n in range(4)]
        path = self.session(100, "s1", old, assistant(text("Old answer.")), *big,
                            human("Recent question."))
        self.assertGreater(os.path.getsize(path), 2 * reading.TAIL)
        returned = self.turns()
        self.assertEqual([t["text"] for t in returned["turns"]], ["Old question.", "Recent question."])
        self.assertFalse(returned["older"])
        recent = returned["turns"][1]["id"]
        self.assertEqual(self.turns(limit=1)["before"], recent)
        self.assertEqual([t["id"] for t in self.turns(before=recent)["turns"]], [old["uuid"]])

    def test_clipped_texts(self):
        long = assistant(text("r" * 9000), tool("t1", "Bash", command="c" * 500))
        turn = self.turns(human("q" * 5000), long)["turns"][0]
        lengths = len(turn["text"]), len(turn["replies"][0]["text"]), len(turn["tools"][0]["target"])
        self.assertEqual(lengths, (4000, 8000, 160))


# ── The hostile lines: nothing raises, and nothing leaves the promised shape ──

REPLACEMENTS = (None, True, 7, -1.5, float("inf"), float("nan"), "x", [], [None, 3, "x", {}, []], {},
                {"type": "tool_result"})
RAW = (b"\n", b"not json\n", b"[1, 2]\n", b"null\n", b'"text"\n', b"{\n", b"\xff\xfe\x00\n", b'{"type": 5}\n',
       b'{"type": "assistant"}\n', b'{"type": "user", "message": "x"}\n',
       b'{"type": "attachment", "attachment": 3}\n', b'{"type": "system", "subtype": []}\n', b"[" * 5000 + b"\n")
CUT = b'{"type": "assistant", "message": {"content": ['           # a line being written, without an end of line


def mutations(obj):
    """All the copies of `obj` where a single value, at any depth, has changed its nature."""
    def paths(x, prefix=()):
        if prefix:
            yield prefix
        for key, value in (x.items() if isinstance(x, dict) else enumerate(x) if isinstance(x, list) else ()):
            yield from paths(value, prefix + (key,))
    for path in paths(obj):
        for replacement in REPLACEMENTS:
            clone = copy.deepcopy(obj)
            parent = clone
            for key in path[:-1]:
                parent = parent[key]
            parent[path[-1]] = replacement
            yield clone


def date_or_none(x):
    return x is None or isinstance(x, str) and reading.seconds(x) is not None


def text_or_none(x):
    return x is None or isinstance(x, str)


class Robustness(Fake):
    def check(self, got):
        """`read` returned the promised shape: each value is of the README's type, or None."""
        self.assertEqual(set(got), Reading.KEYS)
        for key in ("title", "model", "effort"):
            self.assertTrue(got[key] is None or isinstance(got[key], str) and got[key], key)
        if got["context"] is not None:
            self.assertIs(type(got["context"]["tokens"]), int)
            self.assertEqual((got["context"]["window"], got["context"]["percent"]), (None, None))
        self.assertTrue(got["cost"] is None or type(got["cost"]) in (int, float) and 0 <= got["cost"] < 1e15)
        if got["tool"] is not None:
            self.assertTrue(isinstance(got["tool"]["name"], str) and date_or_none(got["tool"]["since"]))
        if got["request"] is not None:
            self.assertIn(got["request"]["kind"], ("question", "permission"))
            self.assertTrue(text_or_none(got["request"].get("tool")))
            for q in got["request"].get("questions", []):
                self.assertTrue(isinstance(q["question"], str) and type(q["multi"]) is bool)
                self.assertTrue(all(isinstance(o, str) for o in q["options"]))
        for todo in got["todos"]:
            self.assertIsInstance(todo["text"], str)
            self.assertIn(todo["status"], ("pending", "in_progress", "done", "blocked"))
        for a in got["subagents"]:
            self.assertIn(a["state"], ("working", "done", "failed", "unknown"))
            self.assertTrue(isinstance(a["id"], str) and date_or_none(a["start"]) and date_or_none(a["end"]))
            self.assertTrue(all(text_or_none(a[c]) for c in ("name", "type", "model", "parent")))
        self.assertTrue(date_or_none(got["activity"]))
        json.dumps(got, allow_nan=False)

    def check_turns(self, returned):
        self.assertEqual(set(returned), {"turns", "older", "before"})
        for turn in returned["turns"]:
            self.assertTrue(isinstance(turn["id"], str) and turn["from"] in ("user", "system"))
            self.assertTrue(isinstance(turn["text"], str) and date_or_none(turn["t"]) and date_or_none(turn["end"]))
            self.assertTrue(all(isinstance(r["text"], str) and date_or_none(r["t"]) for r in turn["replies"]))
            self.assertTrue(all(isinstance(o["name"], str) and text_or_none(o["target"]) for o in turn["tools"]))
        json.dumps(returned, allow_nan=False)

    def sound_log(self):
        questions = [{"question": "Which colour?", "header": "Colour", "multiSelect": False,
                      "options": [{"label": "Red", "description": "Bright"}]}]
        return flat([
            title("Tidy the attic"), title("My title", "custom-title"), cost(1.5), reminder(task("1", "Empty")),
            human("Tidy the attic."), queued("And the cellar?"),
            assistant(thinking(), text("I am looking."), tool("t1", "Bash", command="ls")), result("t1"),
            assistant(tool("t2", "AskUserQuestion", questions=questions), ident="m2"), turn_end(),
            line("system", subtype="compact_boundary", compactMetadata={"preTokens": 9})])

    def test_raw_lines(self):
        got = self.read_log(*RAW, *self.sound_log()[:5], assistant(text("Hello.")), *RAW, CUT)
        self.check(got)
        self.assertEqual((got["title"], got["model"], got["cost"]), ("My title", "claude-opus-5-5", 1.5))
        returned = claude.turns(claude.session(pane()))
        self.check_turns(returned)
        self.assertEqual([(t["text"], len(t["replies"])) for t in returned["turns"]], [("Tidy the attic.", 1)])

    def test_each_field_of_the_log_changes_its_nature(self):
        sound = self.sound_log()
        hostile = [m for l in sound for m in mutations(l)]
        # each hostile line in the middle of a sound turn: once when a tool runs, once in front of a question
        mixed = [x for m in hostile for x in (*sound[4:9], m, *sound[9:11], m, *sound[11:])]
        self.assertGreater(len(hostile), 1000)
        waiting = {"status": "waiting", "waitingFor": "permission prompt"}
        for lines in (hostile, mixed):
            for start in range(0, len(lines), 200):           # in batches, so that the end read carries all the lines
                self.check(self.read_log(*lines[start:start + 200], **waiting))
                self.assertLess(os.path.getsize(self.project / "s1.jsonl"), reading.TAIL)
                self.check_turns(claude.turns(claude.session(pane()), limit=50))

    def test_hostile_registry(self):
        self.session(100, "s1", *self.sound_log())
        sound = json.loads((self.root / "sessions" / "100.json").read_text())
        session = {"id": "s1", "path": str(self.project / "s1.jsonl")}
        (self.root / "sessions" / "101.json").write_bytes(b"\xff not json")
        (self.root / "sessions" / "102.json").write_text("[]")
        (self.root / "sessions" / "103.json").mkdir()
        self.assertEqual(claude.session(pane()), session)
        for record in mutations(sound):
            put(self.root / "sessions" / "100.json", record)
            linked = claude.session(pane())
            self.assertTrue(linked is None or linked["id"] in ("s1", "x"), record)
            self.check(claude.read(session, NOW))
        for hostile in (None, 3, "x", [], {"cwd": 5, "foreground_cwd": ["x"]}, {"cwd": "\x00"}):
            self.assertIsNone(claude.session(hostile))

    def test_hostile_tasks_and_subagents(self):
        self.session(100, "s1", human("Delegate."))
        base = self.project / "s1" / "subagents"
        rest = flat([human("Count."), assistant(tool("t1", "Bash", command="ls")), result("t1", toolEndsTurn=True)])
        started = {"type": "started", "key": "k", "agentId": "w1", "label": "Count", "phase": "Count"}
        self.subagent("a1", *(m for l in rest for m in mutations(l)), *RAW, CUT)
        self.subagent("a2", CUT)
        self.subagent("w1", *rest, workflow="wf_1")
        (base / "agent-a2.meta.json").write_bytes(b"\xff")
        put(base / "workflows" / "wf_1" / "journal.jsonl", *RAW, *mutations(started),
            *mutations({**started, "type": "result"}), CUT)
        for n, t in enumerate(mutations(task("1", "Empty", blocked_by=["2"]))):
            put(self.root / "tasks" / "s1" / f"{n}.json", t)
        (self.root / "tasks" / "s1" / "x.json").write_bytes(b"{")
        got = self.read()
        self.check(got)
        self.assertEqual({a["id"] for a in got["subagents"]}, {"a1", "a2", "w1"})
        record = {"agentType": "workflow-subagent", "description": "Count", "model": "sonnet", "spawnDepth": 1}
        for hostile in mutations(record):
            claude._CACHE.clear()
            put(base / "agent-a1.meta.json", hostile)
            self.check(self.read())


if __name__ == "__main__":
    unittest.main()
