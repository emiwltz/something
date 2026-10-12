"""The poll: Herdr and the readers brought together, its snapshot served as is, the failures said, the changes dated,
the events. At the end, the example state: its shapes are those of a state that `Poller` builds.

Neither a real Herdr nor a real log: the functions of `something.herdr` are replaced, and fake readers are injected.
"""
import copy
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from something import extensions, guards, herdr         # noqa: E402
from something.poll import SESSION_KEYS, STALE, Poller, loop    # noqa: E402

HOME = str(Path.home())


def raw(pane, harness, status, **more):
    """An agent of `session.snapshot.agents`, in the shape recorded on the real Herdr (protocol 22)."""
    workspace = pane.split(":")[0]
    return {"terminal_id": "term_" + pane, "agent_status": status, "workspace_id": workspace,
            "tab_id": workspace + ":t1", "pane_id": pane, "focused": False, "revision": 3, "agent": harness,
            "display_agent": harness, "cwd": HOME + "/Projects/trial", "foreground_cwd": HOME + "/Projects/trial",
            "terminal_title": "✳ Pane title", "terminal_title_stripped": "Pane title",
            "state_change_seq": 1, **more}


def read(**values):
    """What a reader returns: all the keys present, None for what it does not know."""
    return {**dict.fromkeys(("title",) + SESSION_KEYS), **values}


class FakeReader:
    """A reader reduced to its interface. `sessions` is set by pane, `reads` by session identifier; `failure`
    makes `read` raise."""

    def __init__(self):
        self.sessions, self.reads, self.failure = {}, {}, None

    def session(self, agent):
        return self.sessions.get(agent["pane_id"])

    def read(self, session, now):
        if self.failure:
            raise self.failure
        return self.reads.get(session["id"], read())


class Case(unittest.TestCase):
    """An adjustable fake Herdr (`self.agents`, `self.more`, `self.failure`), two fake readers and a clock held by
    hand, which both dates what happens and counts the age of a poll."""

    def setUp(self):
        self.agents = [raw("w1:p1", "claude", "working"), raw("w1:p2", "omp", "idle")]
        self.more = {}            # what the snapshot carries besides: panes, a key that something does not know
        self.failure = None
        self.now = 1_800_000_000.0
        self.claude, self.omp = FakeReader(), FakeReader()
        self.claude.sessions["w1:p1"] = {"id": "s-1", "path": HOME + "/logs/s-1.jsonl"}
        self.omp.sessions["w1:p2"] = {"id": "s-2", "path": "/elsewhere/s-2.jsonl"}
        for name, fake in (("snapshot", self._snapshot), ("version", self._version)):
            patcher = mock.patch.object(herdr, name, side_effect=fake)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)
        aimed = mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": "/no/where/herdr.sock"})     # never a real Herdr
        aimed.start()
        self.addCleanup(aimed.stop)
        self.poller = Poller({"claude": self.claude, "omp": self.omp}, clock=lambda: self.now, ticks=lambda: self.now)

    def _snapshot(self):
        if self.failure:
            raise self.failure
        return copy.deepcopy({      # a new object at each read, as the socket returns one
            "version": "0.9.3", "protocol": 22, "focused_pane_id": "w1:p1",
            "workspaces": [{"workspace_id": "w1", "number": 1, "label": "trial", "focused": True}],
            "tabs": [], "panes": [], "layouts": [], "agents": self.agents, **self.more})

    def _version(self):
        if self.failure:
            raise self.failure
        return {"version": "0.9.3", "protocol": 22}

    def poll(self, seconds=2):
        self.now += seconds
        return self.poller.poll()

    def agent(self, ident, state=None):
        return next(a for a in (state or self.poller.state())["agents"] if a["id"] == ident)

    def status(self, ident, status):
        next(a for a in self.agents if a["pane_id"] == ident)["agent_status"] = status


class Merge(Case):
    def test_before_the_first_poll_the_state_is_empty_and_says_so(self):
        state = self.poller.state()
        self.assertEqual(state["agents"], [])
        self.assertEqual(state["events"], [])
        self.assertFalse(state["herdr"]["connected"])
        self.assertIsNone(state["generated"])
        self.assertTrue(state["error"])

    def test_the_state_always_has_the_same_keys(self):
        keys = ["generated", "example", "herdr", "error", "agents", "events", "extensions", "snapshot"]
        self.assertEqual(list(self.poller.state()), keys, "before the first poll")
        self.assertEqual(list(self.poll()), keys)
        self.failure = herdr.Unavailable("connection refused")
        self.assertEqual(list(self.poll()), keys, "during a failure")
        self.assertIs(self.poller.state()["example"], False, "a poll is never an example")

    def test_herdr_and_the_reader_are_brought_together(self):
        self.agents[0].update(name="lookout", focused=True)
        self.claude.reads["s-1"] = read(
            title="Log title", model="trial-model", effort="high",
            context={"tokens": 1200, "window": None, "percent": None}, cost=0.5,
            tool={"name": "Bash", "since": None}, todos=[], activity="2027-01-15T10:00:00+01:00",
            subagents=[{"id": "a", "name": "Explore", "type": "general-purpose", "parent": None, "state": "working",
                        "model": None, "start": None, "end": None},
                       {"id": "b", "name": "Small", "type": "general-purpose", "parent": "a", "state": "done",
                        "model": None, "start": None, "end": None}])
        state = self.poll()
        self.assertEqual(state["herdr"], {"connected": True, "version": "0.9.3", "protocol": 22})
        self.assertIsNone(state["error"])
        self.assertEqual(state["generated"], guards.iso(self.now))
        a = self.agent("w1:p1")
        self.assertEqual(list(a), ["id", "name", "harness", "state", "since", "title", "cwd", "workspace", "focused",
                                   "session", *SESSION_KEYS, "read_error"])
        self.assertEqual((a["name"], a["harness"], a["state"], a["workspace"], a["focused"]),
                         ("lookout", "claude", "working", "trial", True))
        self.assertEqual(a["cwd"], "~/Projects/trial")
        self.assertEqual(a["session"], {"id": "s-1", "path": "~/logs/s-1.jsonl"})
        self.assertEqual(a["title"], "Log title")
        self.assertEqual((a["model"], a["effort"], a["cost"]), ("trial-model", "high", 0.5))
        self.assertEqual(a["context"], {"tokens": 1200, "window": None, "percent": None})
        self.assertEqual(a["todos"], [])
        self.assertIsNone(a["goal"])
        self.assertIsNone(a["read_error"])
        self.assertEqual([s["parent"] for s in a["subagents"]], ["w1:p1", "a"])
        self.assertIsNone(self.claude.reads["s-1"]["subagents"][0]["parent"], "the reader's result stayed intact")

    def test_herdr_s_title_holds_when_the_log_says_nothing_of_it(self):
        self.poll()
        self.assertEqual(self.agent("w1:p1")["title"], "Pane title")

    def test_each_state_of_herdr_is_kept_and_the_unknown_stays_unknown(self):
        expected = {"working": "working", "blocked": "blocked", "done": "done", "idle": "idle",
                    "unknown": "unknown", "other": "unknown", None: "unknown"}
        for status, wanted in expected.items():
            self.status("w1:p1", status)
            self.poll()
            self.assertEqual(self.agent("w1:p1")["state"], wanted, status)

    def test_an_agent_without_a_reader_appears_with_what_herdr_says_of_it(self):
        self.agents.append(raw("w1:p3", "codex", "working"))
        self.poll()
        a = self.agent("w1:p3")
        self.assertEqual((a["harness"], a["state"], a["title"]), ("codex", "working", "Pane title"))
        self.assertIsNone(a["session"])
        self.assertIsNone(a["read_error"])
        self.assertEqual({a[key] for key in SESSION_KEYS}, {None})

    def test_a_pane_without_a_session_says_so_and_makes_nothing_up(self):
        del self.claude.sessions["w1:p1"]
        self.poll()
        a = self.agent("w1:p1")
        self.assertIsNone(a["session"])
        self.assertTrue(a["read_error"])
        self.assertEqual({a[key] for key in SESSION_KEYS}, {None})

    def test_a_reader_that_raises_says_so_and_the_other_agents_are_polled(self):
        self.claude.failure = OSError("log gone " + "x" * 500)
        self.omp.reads["s-2"] = read(model="trial-model")
        state = self.poll()
        a = self.agent("w1:p1")
        self.assertIn("OSError", a["read_error"])
        self.assertIn("log gone", a["read_error"])
        self.assertLessEqual(len(a["read_error"]), 200)
        self.assertEqual({a[key] for key in SESSION_KEYS}, {None})
        self.assertEqual(a["state"], "working")
        self.assertEqual(self.agent("w1:p2")["model"], "trial-model")
        self.assertIsNone(self.agent("w1:p2")["read_error"])
        self.assertIsNone(state["error"])

    def test_a_reader_result_outside_the_contract_merges_nothing(self):
        self.claude.reads["s-1"] = read(model="trial-model", subagents=["not a dictionary"])
        self.poll()
        a = self.agent("w1:p1")
        self.assertTrue(a["read_error"])
        self.assertEqual({a[key] for key in SESSION_KEYS}, {None})

    def test_a_result_that_json_cannot_write_stores_nothing(self):
        path, infinity = Path("/logs/s-1.jsonl"), float("inf")
        for hostile in ({"model": path}, {"todos": {"one", "two"}}, {"effort": b"bytes"}, {"cost": float("nan")},
                        {"cost": infinity}, {"context": {"tokens": -infinity}}, {"title": path},
                        {"subagents": [{"id": "a", "start": path}]}):
            with self.subTest(hostile):
                self.claude.reads["s-1"] = read(**{"activity": "2027-01-15T10:00:00+01:00", **hostile})
                state = self.poll()
                json.dumps(state, allow_nan=False)      # what the routes write: strict JSON
                a = self.agent("w1:p1")
                self.assertTrue(a["read_error"])
                self.assertEqual({a[key] for key in SESSION_KEYS}, {None}, "not even what could be written")
                self.assertEqual((a["title"], a["session"]["id"]), ("Pane title", "s-1"))
                self.assertIsNone(state["error"])
        self.claude.sessions["w1:p1"] = {"id": path, "path": str(path)}        # the session's identifier too
        json.dumps(self.poll(), allow_nan=False)
        a = self.agent("w1:p1")
        self.assertEqual((a["session"], bool(a["read_error"])), (None, True))

    def test_a_reader_that_exits_is_a_failure_like_any_other(self):
        self.omp.reads["s-2"] = read(model="trial-model")
        for method in ("read", "session"):
            with self.subTest(method), mock.patch.object(self.claude, method, side_effect=SystemExit(3)):
                state = self.poll()                     # nothing gets out: the loop holds
                a = self.agent("w1:p1")
                self.assertIn("SystemExit", a["read_error"])
                self.assertEqual({a[key] for key in SESSION_KEYS}, {None})
                self.assertEqual(self.agent("w1:p2")["model"], "trial-model")
                self.assertIsNone(state["error"])

    def test_the_cost_is_rounded_to_four_decimals(self):
        self.claude.reads["s-1"] = read(cost=8.856228200000002)
        self.omp.reads["s-2"] = read(cost=3)
        self.poll()
        self.assertEqual(self.agent("w1:p1")["cost"], 8.8562)
        self.assertEqual(self.agent("w1:p2")["cost"], 3)
        self.claude.reads["s-1"] = read()
        self.poll()
        self.assertIsNone(self.agent("w1:p1")["cost"], "an unknown cost stays unknown")

    def test_a_session_that_two_panes_compete_for_is_linked_to_neither(self):
        self.agents.append(raw("w1:p3", "claude", "idle"))
        self.claude.sessions["w1:p3"] = self.claude.sessions["w1:p1"]
        self.claude.reads["s-1"] = read(title="Log title", model="trial-model",
                                        tool={"name": "Bash", "since": None}, todos=[], subagents=[])
        self.omp.reads["s-2"] = read(model="other-model")
        self.poll()
        for pane in ("w1:p1", "w1:p3"):
            a = self.agent(pane)
            self.assertIsNone(a["session"], pane)
            self.assertEqual({a[key] for key in SESSION_KEYS}, {None}, pane)
            self.assertEqual(a["title"], "Pane title", "the log's title goes too")
            self.assertEqual(a["read_error"], "several panes compete for this session")
            self.assertEqual(self.poller.raw(pane)[1:], (self.claude, None), "the routes do not link it either")
        other = self.agent("w1:p2")
        self.assertEqual((other["session"]["id"], other["model"], other["read_error"]), ("s-2", "other-model", None))
        self.agents.pop()
        self.poll()
        alone = self.agent("w1:p1")
        self.assertEqual((alone["session"]["id"], alone["model"], alone["title"], alone["read_error"]),
                         ("s-1", "trial-model", "Log title", None), "alone, the pane is linked again")

    def test_send_carries_the_message_through_herdr(self):
        with mock.patch.object(herdr, "send") as send:
            self.poller.send("w1:p1", "hello")
        send.assert_called_once_with("w1:p1", "hello")

    def test_raw_returns_herdr_s_agent_its_reader_and_its_session(self):
        self.agents.append(raw("w1:p3", "codex", "idle"))
        self.assertIsNone(self.poller.raw("w1:p1"))
        self.poll()
        agent, reader, session = self.poller.raw("w1:p1")
        self.assertEqual(agent["pane_id"], "w1:p1")
        self.assertIs(reader, self.claude)
        self.assertEqual(session["path"], HOME + "/logs/s-1.jsonl", "the routes' path is not shortened")
        self.assertEqual(self.poller.raw("w1:p3")[1:], (None, None))
        self.assertIsNone(self.poller.raw("w9:p9"))


class Mirror(Case):
    TERMINAL = {"pane_id": "w1:p9", "terminal_id": "term_w1:p9", "workspace_id": "w1", "tab_id": "w1:t1",
                "focused": False, "agent_status": "unknown", "revision": 1}       # a pane without an agent

    def test_herdr_s_snapshot_is_served_as_is(self):
        self.assertIsNone(self.poller.state()["snapshot"], "before the first poll")
        self.more = {"panes": [self.TERMINAL], "novelty": {"from": ["Herdr", 2]}}
        state = self.poll()
        self.assertEqual(state["snapshot"], self._snapshot(), "its own keys, nothing translated, nothing removed")
        self.assertEqual(state["snapshot"]["novelty"], {"from": ["Herdr", 2]}, "a new key passes without code")
        self.assertEqual([p["pane_id"] for p in state["snapshot"]["panes"]], ["w1:p9"], "a terminal without an agent")
        self.assertEqual([a["id"] for a in state["agents"]], ["w1:p1", "w1:p2"], "the translated list is unchanged")

    def test_without_herdr_the_snapshot_is_none(self):
        self.poll()
        self.failure = herdr.Unavailable("connection refused")
        self.assertIsNone(self.poll()["snapshot"])
        self.failure = None
        self.assertIsNotNone(self.poll()["snapshot"])

    def test_a_snapshot_read_without_herdr_being_connected_is_not_served(self):
        self.version.side_effect = herdr.Unavailable("timed out")      # the snapshot is read, the version is not
        state = self.poll()
        self.assertEqual((state["herdr"]["connected"], state["snapshot"]), (False, None))

    def test_a_change_of_the_snapshot_alone_pushes_the_state(self):
        self.poll()
        version, _ = self.poller.wait(None, 0)
        self.more = {"panes": [self.TERMINAL]}          # a terminal opens: no agent changes
        self.poll()
        self.assertEqual(self.poller.wait(None, 0)[0], version + 1)
        self.poll()
        self.assertEqual(self.poller.wait(None, 0)[0], version + 1, "the same snapshot pushes nothing")


class Failures(Case):
    def test_herdr_unavailable_no_agent_made_up_then_back(self):
        self.poll()
        self.failure = herdr.Unavailable("connection refused")
        state = self.poll()
        self.assertEqual(state["agents"], [])
        self.assertEqual(state["herdr"], {"connected": False, "version": None, "protocol": None})
        self.assertIn("connection refused", state["error"])
        self.assertEqual(self.poller.raw("w1:p1")[2]["id"], "s-1", "the routes keep the last successful poll")
        self.failure = None
        state = self.poll()
        self.assertIsNone(state["error"])
        self.assertEqual(state["herdr"], {"connected": True, "version": "0.9.3", "protocol": 22})
        self.assertEqual([a["id"] for a in state["agents"]], ["w1:p1", "w1:p2"])
        self.assertEqual(self.version.call_count, 2, "the version is read again after a failure, not at each poll")

    def test_a_failure_of_herdr_makes_nobody_go_or_appear(self):
        self.poll()
        self.failure = herdr.Unavailable("timed out")
        self.poll()
        self.failure = None
        self.status("w1:p1", "blocked")
        state = self.poll()
        self.assertEqual([e["kind"] for e in state["events"]], ["blocked"])

    def test_a_refusal_or_an_unexpected_failure_is_said_without_raising(self):
        for failure in (herdr.Refused("invalid_request", "unknown variant"), ValueError("unexpected shape")):
            self.failure = failure
            state = self.poll()
            self.assertEqual(state["agents"], [])
            self.assertFalse(state["herdr"]["connected"])
            self.assertTrue(state["error"])

    def test_a_hostile_snapshot_gives_no_made_up_agent(self):
        self.agents = [None, 3, "text", {"agent": "claude", "agent_status": "working"}, {"pane_id": 7},
                       raw("w1:p1", "claude", "idle"), raw("w1:p1", "claude", "working"),
                       {"pane_id": "w1:p4", "focused": "yes", "cwd": 12, "name": ["x"], "agent": 5},
                       {"pane_id": "w1:p5", "agent": ["claude"]}, {"pane_id": "w1:p6", "agent": {"claude": 1}}]
        state = self.poll()
        self.assertIsNone(state["error"])
        self.assertEqual([a["id"] for a in state["agents"]], ["w1:p1", "w1:p4", "w1:p5", "w1:p6"])
        self.assertEqual(self.agent("w1:p1")["state"], "idle", "a duplicate identifier counts only once")
        bare = self.agent("w1:p4")
        self.assertEqual(bare["state"], "unknown")
        self.assertEqual({bare[k] for k in ("name", "harness", "title", "cwd", "workspace", "focused")}, {None})
        for pane in ("w1:p5", "w1:p6"):         # a harness that is not a text designates no reader
            self.assertEqual((self.agent(pane)["harness"], self.poller.raw(pane)[1]), (None, None))

    def test_agents_that_are_not_a_list_are_a_failure_and_nobody_goes(self):
        self.poll()
        real = self.agents
        for hostile in ("not a list", {"w1:p1": real[0]}, 3, None):
            with self.subTest(hostile):
                self.agents = hostile
                state = self.poll()
                self.assertTrue(state["error"])
                self.assertEqual((state["agents"], state["herdr"]["connected"], state["snapshot"]), ([], False, None))
                self.assertEqual(self.poller.raw("w1:p1")[2]["id"], "s-1", "the routes keep the last poll")
        self.agents = real
        state = self.poll()
        self.assertIsNone(state["error"])
        self.assertEqual(state["events"], [], "nobody is gone, nobody appeared")


class Tracking(Case):
    def test_since_dates_the_state_change_seen_by_something(self):
        self.poll()
        self.assertIsNone(self.agent("w1:p1")["since"], "at the first poll, something saw nothing start")
        self.poll()
        self.assertIsNone(self.agent("w1:p1")["since"])
        self.status("w1:p1", "idle")
        self.poll()
        seen = guards.iso(self.now)
        self.assertEqual(self.agent("w1:p1")["since"], seen)
        self.assertIsNone(self.agent("w1:p2")["since"])
        self.poll(60)
        self.assertEqual(self.agent("w1:p1")["since"], seen, "the date holds as long as the state holds")
        self.agents.append(raw("w1:p3", "claude", "working"))
        self.poll()
        appeared = guards.iso(self.now)
        self.assertEqual(self.agent("w1:p3")["since"], appeared, "a new agent is dated from its appearance")
        self.poll()
        self.assertEqual(self.agent("w1:p3")["since"], appeared)

    def test_no_event_at_the_first_poll(self):
        self.assertEqual(self.poll()["events"], [])

    def test_the_first_successful_poll_after_a_start_in_failure_notes_nothing(self):
        self.failure = herdr.Unavailable("socket missing")
        self.poll()
        self.failure = None
        self.assertEqual(self.poll()["events"], [])

    def test_the_five_kinds_of_events(self):
        self.agents[1]["name"] = "lookout"
        self.poll()
        steps = [
            (lambda: self.status("w1:p1", "blocked"), "blocked", "w1:p1"),      # working → blocked
            (lambda: self.status("w1:p1", "working"), "state", "w1:p1"),        # blocked → working
            (lambda: self.status("w1:p1", "done"), "done", "w1:p1"),            # working → done
            (lambda: self.status("w1:p1", "idle"), "state", "w1:p1"),           # done → idle
            (lambda: self.status("w1:p2", "working"), "state", "w1:p2"),        # idle → working
            (lambda: self.status("w1:p2", "idle"), "done", "w1:p2"),            # working → idle
            (lambda: self.status("w1:p2", "unknown"), "state", "w1:p2"),        # idle → unknown
            (lambda: self.agents.append(raw("w1:p3", "codex", "blocked")), "appeared", "w1:p3"),
            (lambda: self.agents.pop(1), "gone", "w1:p2"),
        ]
        for n, (action, kind, agent) in enumerate(steps, 1):
            action()
            events = self.poll()["events"]
            self.assertEqual(len(events), n)
            last = events[-1]
            self.assertEqual((last["n"], last["kind"], last["agent"]), (n, kind, agent))
            self.assertEqual(last["t"], guards.iso(self.now))
            name = {"w1:p1": "claude", "w1:p2": "lookout", "w1:p3": "codex"}[agent]
            self.assertTrue(last["text"].startswith(name + " "), last["text"])
        self.assertEqual(len(self.poll()["events"]), len(steps), "without a change, no event")

    def test_an_agent_that_was_waiting_and_stops_is_done(self):
        self.poll()
        for status in ("done", "idle"):
            self.status("w1:p1", "blocked")
            self.poll()
            self.status("w1:p1", status)
            last = self.poll()["events"][-1]
            self.assertEqual((last["kind"], last["text"]), ("done", "claude is done"), status)

    def test_a_hundred_events_at_most_and_n_only_grows(self):
        self.poll()
        for i in range(130):
            self.status("w1:p1", "working" if i % 2 else "idle")
            self.poll()
        numbers = [e["n"] for e in self.poller.state()["events"]]
        self.assertEqual(numbers, list(range(31, 131)))

    def test_the_version_only_goes_up_if_the_served_state_changes(self):
        self.poll()
        version, state = self.poller.wait(None, 0)
        self.poll()
        self.assertEqual(self.poller.wait(None, 0)[0], version)
        self.assertNotEqual(self.poller.state()["generated"], state["generated"], "the poll's time, though, moves on")
        self.claude.reads["s-1"] = read(model="trial-model")
        self.poll()
        self.assertEqual(self.poller.wait(None, 0)[0], version + 1)
        self.failure = herdr.Unavailable("connection refused")
        self.poll()
        self.poll()
        self.assertEqual(self.poller.wait(None, 0)[0], version + 2, "a failure that lasts pushes nothing either")

    def test_wait_wakes_up_on_a_change(self):
        self.poll()
        version, _ = self.poller.wait(None, 0)
        self.status("w1:p1", "blocked")
        thread = threading.Timer(0.1, self.poll)
        thread.start()
        self.addCleanup(thread.join)
        start = time.monotonic()
        new, state = self.poller.wait(version, 5)
        self.assertLess(time.monotonic() - start, 3)
        self.assertEqual(new, version + 1)
        self.assertEqual(self.agent("w1:p1", state)["state"], "blocked")

    def test_wait_returns_at_the_timeout(self):
        self.poll()
        version, state = self.poller.wait(None, 0)
        start = time.monotonic()
        self.assertEqual(self.poller.wait(version, 0.15), (version, state))
        self.assertGreaterEqual(time.monotonic() - start, 0.1)

    def test_polls_that_stop_are_said_and_no_agent_is_given_any_more(self):
        fresh = self.poll()
        self.now += STALE
        self.assertEqual(self.poller.state(), fresh, "at the limit, the state is still served as is")
        self.now += 1
        state = self.poller.state()
        self.assertEqual(state["error"],
                         f"no poll for more than {STALE} s: something's loop is blocked or stopped")
        self.assertEqual((state["agents"], state["snapshot"]), ([], None), "nothing stale is given")
        self.assertEqual(state["herdr"], {"connected": False, "version": None, "protocol": None})
        self.assertEqual(state["generated"], fresh["generated"], "the time stays that of the last poll")
        self.assertEqual(list(state), list(fresh))
        self.now += 600
        self.assertEqual(self.poller.state(), state, "the sentence carries no figure that would go stale in its turn")
        self.assertIsNotNone(self.poller.raw("w1:p1"), "the conversation stays served, as during a failure")
        self.assertEqual(self.poll()["agents"], fresh["agents"], "the poll that resumes gives everything back")
        self.assertIsNone(self.poller.state()["error"])

    def test_the_age_is_counted_from_the_end_of_the_poll(self):
        def slow(session, now):             # a poll that lasts almost as long as the threshold is not a failure
            self.now += STALE - 1
            return read()
        self.claude.read = slow
        self.poll()
        self.now += STALE
        self.assertIsNone(self.poller.state()["error"])

    def test_a_first_poll_that_does_not_finish_is_said_too(self):
        before = self.poller.state()
        self.now += STALE
        self.assertEqual(self.poller.wait(None, 0), (0, before))
        self.now += 1
        self.assertIn("no poll for", self.poller.state()["error"])

    def test_polls_that_stop_wake_whoever_waits_only_once(self):
        self.poll()
        version, _ = self.poller.wait(None, 0)
        self.now += STALE + 1
        stopped, state = self.poller.wait(version, 0)
        self.assertNotEqual(stopped, version)
        self.assertIn("no poll for", state["error"])
        self.now += 60
        self.assertEqual(self.poller.wait(stopped, 0), (stopped, state), "the same failure is not pushed twice")
        self.poll()
        resumed, state = self.poller.wait(stopped, 0)
        self.assertEqual(resumed, version, "the same state as before the stop: the same version, and yet pushed")
        self.assertIsNone(state["error"])

    def test_polls_that_resume_on_the_same_state_wake_whoever_waits(self):
        self.poll()
        self.now += STALE + 1
        stopped, _ = self.poller.wait(None, 0)
        thread = threading.Timer(0.1, self.poll)
        thread.start()
        self.addCleanup(thread.join)
        start = time.monotonic()
        resumed, state = self.poller.wait(stopped, 5)
        self.assertLess(time.monotonic() - start, 3, "the wait ended with the poll, not at its timeout")
        self.assertNotEqual(resumed, stopped)
        self.assertIsNone(state["error"])

    def test_a_poll_that_changes_nothing_does_not_end_a_wait(self):
        self.poll()
        version, state = self.poller.wait(None, 0)
        thread = threading.Timer(0.05, self.poll)
        thread.start()
        self.addCleanup(thread.join)
        start = time.monotonic()
        self.assertEqual(self.poller.wait(version, 0.3)[0], version)
        self.assertGreaterEqual(time.monotonic() - start, 0.25, "woken by the poll, it went back to waiting")

    def test_a_clock_that_jumps_is_not_a_poll_that_stops(self):
        ticks = [0.0]           # the machine slept an hour: the date jumped, the time it spent running did not
        poller = Poller(clock=lambda: self.now, ticks=lambda: ticks[0])
        fresh = poller.poll()
        self.now += 3600
        self.assertEqual(poller.state(), fresh)
        ticks[0] += STALE + 1
        self.assertIn("no poll for", poller.state()["error"])


def shapes(value, kind="state", seen=None):
    """{kind of object: the key sequences met} in a state or a conversation. A kind bears the name of the key that
    leads to the object. The snapshot is not visited: its keys are Herdr's."""
    seen = {} if seen is None else seen
    if isinstance(value, dict):
        seen.setdefault(kind, set()).add(tuple(value))
        for key, child in value.items():
            if key != "snapshot":
                shapes(child, key, seen)
    elif isinstance(value, list):
        for child in value:
            shapes(child, kind, seen)
    return seen


class Example(Case):
    """`page/example.json`, which the example mode serves, does not lie about the shape of a state."""

    # The required keys of a snapshot, from `herdr api schema --json` (Herdr 0.9.3, protocol 22).
    HERDR = {"workspaces": {"workspace_id", "number", "label", "focused", "pane_count", "tab_count", "active_tab_id",
                            "agent_status"},
             "tabs": {"tab_id", "workspace_id", "number", "label", "focused", "pane_count", "agent_status"},
             "panes": {"pane_id", "terminal_id", "workspace_id", "tab_id", "focused", "agent_status", "revision"},
             "layouts": {"workspace_id", "tab_id", "zoomed", "area", "focused_pane_id", "panes", "splits"},
             "agents": {"terminal_id", "agent_status", "workspace_id", "tab_id", "pane_id", "focused", "revision"}}

    def setUp(self):
        super().setUp()
        data = json.loads((ROOT / "page" / "example.json").read_text(encoding="utf-8"))
        self.example, self.conversations = data["state"], data["conversations"]

    def real(self):
        """A state that `Poller` builds, where each kind of object appears: two agents whose fake readers say
        everything, an event, an extension reported by the real loader."""
        subagent = {"id": "a", "name": "Explore", "type": "general-purpose", "parent": None, "state": "working",
                    "model": "trial-model", "start": "2027-01-15T10:00:00+01:00", "end": None}
        everything = dict(title="Log title", model="trial-model", effort="high",
                          context={"tokens": 1200, "window": 200000, "percent": 1}, cost=0.5,
                          tool={"name": "Bash", "since": "2027-01-15T10:00:00+01:00"},
                          todos=[{"text": "Write the tests", "status": "in_progress", "phase": None}],
                          goal={"objective": "Finish", "status": "active", "tokens": 1200, "seconds": 60},
                          subagents=[subagent], activity="2027-01-15T10:00:00+01:00")
        question = {"question": "Which one?", "options": ["This one", "That one"], "multi": False}
        self.claude.reads["s-1"] = read(**everything, request={"kind": "permission", "tool": "Bash"})
        self.omp.reads["s-2"] = read(**everything, request={"kind": "question", "questions": [question]})
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "empty.py").write_text("", encoding="utf-8")
            reported = extensions.load(folder)[1]
        self.poller = Poller({"claude": self.claude, "omp": self.omp}, reported, clock=lambda: self.now,
                             ticks=lambda: self.now)
        self.poll()
        self.status("w1:p1", "blocked")
        return self.poll()

    def test_the_keys_of_the_example_are_those_of_a_real_state(self):
        real, example = shapes(self.real()), shapes(self.example)
        self.assertEqual(set(example), set(real), "the example shows each kind of object, and makes none up")
        for kind, keys in example.items():         # each object of the example has the keys of a real one, in order
            self.assertLessEqual(keys, real[kind], kind)
        self.assertIs(self.example["example"], True)

    def test_the_agents_of_the_example_are_those_the_core_draws_from_its_snapshot(self):
        from_herdr = ("id", "name", "harness", "state", "title", "cwd", "workspace", "focused")
        self.snapshot.side_effect = lambda: self.example["snapshot"]
        with mock.patch.dict(os.environ, {"HOME": "/Users/example"}):       # the example's home directory
            drawn = Poller(clock=lambda: self.now, ticks=lambda: self.now).poll()
        self.assertIsNone(drawn["error"])
        self.assertEqual([{key: a[key] for key in from_herdr} for a in self.example["agents"]],
                         [{key: a[key] for key in from_herdr} for a in drawn["agents"]])

    def test_the_snapshot_of_the_example_has_the_shape_of_herdr_s(self):
        snapshot = self.example["snapshot"]
        self.assertLessEqual({"version", "protocol", *self.HERDR}, set(snapshot))
        for kind, required in self.HERDR.items():
            for item in snapshot[kind]:
                self.assertLessEqual(required, set(item), kind)
        self.assertEqual(len(snapshot["workspaces"]), 2)
        without_agent = [p for p in snapshot["panes"] if p.get("agent") is None]
        self.assertTrue(without_agent, "a terminal without an agent")
        self.assertEqual({p["pane_id"] for p in snapshot["panes"]} - {p["pane_id"] for p in without_agent},
                         {a["pane_id"] for a in snapshot["agents"]}, "each agent has its pane")
        self.assertEqual({t["tab_id"] for t in snapshot["tabs"]}, {p["tab_id"] for p in snapshot["panes"]})
        self.assertEqual({t["tab_id"] for t in snapshot["tabs"]}, {l["tab_id"] for l in snapshot["layouts"]})

    def test_the_example_covers_the_cases_and_stays_within_the_vocabulary(self):
        agents = self.example["agents"]
        were_read = [a for a in agents if a["session"] and not a["read_error"]]
        loaded = {x["harness"] for x in self.example["extensions"] if x["error"] is None}
        self.assertEqual({a["state"] for a in agents}, {"working", "blocked", "done", "idle", "unknown"})
        self.assertTrue(any(a["tool"] and a["todos"] and a["subagents"] for a in were_read))
        self.assertTrue(any(a["request"] and a["goal"] for a in were_read))
        self.assertTrue(any(a["state"] == "blocked" and a["request"] is None for a in were_read),
                        "one that waits for you although its log does not say for what")
        self.assertTrue(any(x["error"] for x in self.example["extensions"]), "an extension in error")
        for a in agents:
            if a in were_read:
                self.assertIn(a["harness"], loaded, "a log that is read is read by a loaded extension")
            else:       # without an extension, or log not read: nothing of what comes from a log is said
                self.assertEqual({a[key] for key in ("session",) + SESSION_KEYS}, {None}, a["id"])
        self.assertTrue(any(a["read_error"] for a in agents), "an agent whose log was not read")
        self.assertTrue(any(a["harness"] not in loaded and not a["read_error"] for a in agents),
                        "one without an extension")
        todos = [t for a in were_read for t in a["todos"] or []]
        subagents = [s for a in were_read for s in a["subagents"] or []]
        self.assertLessEqual({t["status"] for t in todos}, {"pending", "in_progress", "done", "blocked"})
        self.assertLessEqual({s["state"] for s in subagents}, {"working", "done", "failed", "unknown"})
        self.assertLessEqual({a["goal"]["status"] for a in were_read if a["goal"]}, {"active", "paused"})
        self.assertLessEqual({a["request"]["kind"] for a in were_read if a["request"]}, {"question", "permission"})
        self.assertLessEqual({e["kind"] for e in self.example["events"]},
                             {"appeared", "gone", "blocked", "done", "state"})

    def test_each_agent_linked_to_a_session_has_its_conversation(self):
        self.assertEqual(set(self.conversations), {a["id"] for a in self.example["agents"] if a["session"]})
        seen = shapes(list(self.conversations.values()), "conversation")
        self.assertEqual(seen, {"conversation": {("turns", "older", "before")},
                                "turns": {("id", "t", "from", "text", "replies", "tools", "end")},
                                "replies": {("t", "text")}, "tools": {("name", "target")}})
        turns = [t for c in self.conversations.values() for t in c["turns"]]
        self.assertLessEqual({t["from"] for t in turns}, {"user", "system"})
        self.assertEqual({(c["older"], c["before"]) for c in self.conversations.values()}, {(False, None)},
                         "an example conversation is whole: nothing older, no cursor")


class Loop(unittest.TestCase):
    def test_the_loop_polls_until_the_stop(self):
        stop, polls = threading.Event(), []

        class Counter:
            def poll(self):
                polls.append(1)
                if len(polls) == 3:
                    stop.set()
                return {"error": None}

        loop(Counter(), 0.01, stop)
        self.assertEqual(len(polls), 3)

    def test_the_loop_says_each_change_of_the_error_and_only_a_change(self):
        def told(*errors):
            """What `say` receives when the polls give these errors, one after the other."""
            stop, left, said = threading.Event(), list(errors), []

            class Fake:
                def poll(self):
                    error = left.pop(0)
                    if not left:
                        stop.set()
                    return {"error": error}

            loop(Fake(), 0.001, stop, say=said.append)
            return said

        down, broken = "Herdr does not answer: socket missing (~/herdr.sock)", "poll failed: ValueError: no"
        self.assertEqual(told(None, None, None), [], "nothing to say while all goes well")
        self.assertEqual(told(down, down, down), [down], "an outage is said once, however long it lasts")
        self.assertEqual(told(None, down, down, None, None, broken, down, None),
                         [down, None, broken, down, None])


if __name__ == "__main__":
    unittest.main()
