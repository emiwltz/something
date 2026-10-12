"""One poll: Herdr and the session logs, brought together in the state served to the page.

Herdr says which agents exist and in what state; the harness's reader, an extension, says the rest. `Poller` keeps
the last state, dates the changes and draws the events from them. Herdr's snapshot is also served as is: what Herdr
adds shows up without changing this code. A failure kills nothing: Herdr missing is said in `error`, an unreadable
log in `read_error`, a blocked or dead loop in `error` too, and nothing is made up. The shape of the state:
README.md, "The state".
"""
import json
import threading
import time

from . import guards, herdr

SESSION_KEYS = ("model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents", "activity")
EVENTS_MAX = 100
STALE = 20      # seconds without a finished poll before the served state says so: more than a slow Herdr's worst poll
SAYS = {"appeared": "appeared", "gone": "is gone", "blocked": "is waiting for your answer", "done": "is done",
        "working": "is working", "idle": "is idle", "unknown": "is in an unknown state"}


class Poller:
    """The last polled state, and what it takes to follow it. Thread-safe: the loop calls `poll`, the server the
    rest."""

    def __init__(self, readers=None, extensions=(), clock=time.time, ticks=time.monotonic):
        """`readers`: one reader per harness; `extensions`: what loading says about them (extensions.load).
        Without a reader, the core polls Herdr alone. `clock` dates what happens; `ticks` counts how long ago
        the last poll ended, on a clock that does not jump when the machine sleeps or is set to another time."""
        self._readers, self._extensions, self._clock, self._ticks = readers or {}, list(extensions), clock, ticks
        self._lock = threading.Condition()
        self._version = 0
        self._state = {"generated": None, "example": False,
                       "herdr": {"connected": False, "version": None, "protocol": None},
                       "error": "no poll has been done yet", "agents": [], "events": [],
                       "extensions": self._extensions, "snapshot": None}
        self._raws = {}           # id → (Herdr's raw agent, reader, session) at the last successful poll
        self._herdr = None        # what `ping` said; None as long as Herdr is not reached
        self._known = None        # id → {state, since, name} at the last successful poll; None before the first
        self._events = []
        self._n = 0
        self._done = ticks()      # when the last poll ended; before the first, when it all started

    def poll(self):
        """Does a poll, stores the state and returns it. Never raises: a failure is said in `error`."""
        now = self._clock()
        snapshot, agents, raws, error = None, [], {}, None
        try:
            snapshot = herdr.snapshot()
            if self._herdr is None:
                self._herdr = herdr.version()
            agents, raws = self._agents(snapshot, now)
        except herdr.Unavailable as e:
            error = f"Herdr does not answer: {e}"
        except Exception as e:      # a refusal, a response of unexpected shape: the failure is said, nothing is made up
            error = guards.clip(f"poll failed: {type(e).__name__}: {e}", 200)
        with self._lock:
            if error is None:
                self._track(agents, now)
                self._raws = raws       # a failure leaves them: the conversation stays served
            else:
                self._herdr = None
            state = {"generated": guards.iso(now), "example": False,
                     "herdr": {"connected": error is None, **(self._herdr or {"version": None, "protocol": None})},
                     "error": error, "agents": agents, "events": list(self._events),
                     "extensions": self._extensions, "snapshot": snapshot if error is None else None}
            if _undated(state) != _undated(self._state):
                self._version += 1
            self._state, self._done = state, self._ticks()
            self._lock.notify_all()     # also without a change: after a stall, the same state is news
            return state

    def state(self):
        """The last state. Before the first poll: an empty state, whose `error` says no poll has been done.
        Without a finished poll for STALE seconds: see `_served`."""
        with self._lock:
            return self._served()[1]

    def wait(self, version, timeout):
        """Blocks until a state of another version than `version`, `timeout` seconds at most; returns (version,
        state). With `version` None, returns the present state right away. Polls that stop change the version, once:
        whoever follows the state learns it at the end of its wait, and that they resumed at the first poll."""
        with self._lock:
            self._lock.wait_for(lambda: self._served()[0] != version, timeout)
            return self._served()

    def _served(self):
        """(version, state) to serve. Without a finished poll for STALE seconds, the loop is blocked or dead: the
        version marks it, `error` says it, and no agent is given as present any more, as when Herdr does not answer.
        `generated` stays the time of the last poll."""
        if self._ticks() - self._done <= STALE:
            return self._version, self._state
        error = f"no poll for more than {STALE} s: something's loop is blocked or stopped"
        return "stopped", {**self._state, "herdr": {"connected": False, "version": None, "protocol": None},
                           "agents": [], "snapshot": None, "error": error}

    def raw(self, ident):
        """(Herdr's raw agent, reader or None, session or None) of the agent `ident`, or None if it is unknown."""
        with self._lock:
            return self._raws.get(ident)

    def send(self, ident, text):
        """Carries a message to the agent `ident`: see herdr.send, whose refusals and failures go up."""
        herdr.send(ident, text)

    def _agents(self, snapshot, now):
        """(agents of the state, raws by identifier) from a snapshot of Herdr."""
        workspaces = {w.get("workspace_id"): guards.text(w.get("label"))
                      for w in map(guards.as_dict, guards.as_list(snapshot.get("workspaces")))}
        if not isinstance(snapshot.get("agents", []), list):       # neither "no agent" nor made-up disappearances
            raise ValueError("the snapshot's agents are not a list")
        agents, raws = [], {}
        for raw in map(guards.as_dict, guards.as_list(snapshot.get("agents"))):
            ident = guards.text(raw.get("pane_id"))
            if ident is None or ident in raws:
                continue            # without an identifier of its own, an agent cannot be designated
            reader = self._readers.get(guards.text(raw.get("agent")))
            agent, session = _agent(raw, workspaces.get(raw.get("workspace_id")), reader, now)
            agents.append(agent)
            raws[ident] = (raw, reader, session)
        linked = [a["session"]["id"] for a in agents if a["session"]]
        for a in agents:            # a session linked to several panes: nothing says which, none is linked
            if a["session"] and linked.count(a["session"]["id"]) > 1:
                raw, reader, _ = raws[a["id"]]
                a.update(dict.fromkeys(("session",) + SESSION_KEYS),
                         read_error="several panes compete for this session",
                         title=guards.text(raw.get("terminal_title_stripped")))
                raws[a["id"]] = (raw, reader, None)
        return agents, raws

    def _track(self, agents, now):
        """Dates the state changes and notes the events, from what the previous poll had seen.
        The first successful poll notes nothing: it is the starting point."""
        before, self._known = self._known, {}
        for a in agents:
            name = a["name"] or a["harness"] or a["id"]
            seen = (before or {}).get(a["id"])
            if seen and seen["state"] == a["state"]:
                a["since"] = seen["since"]
            elif seen:
                a["since"] = guards.iso(now)
                if a["state"] == "blocked":
                    self._note("blocked", a["id"], name, now)
                elif seen["state"] in ("working", "blocked") and a["state"] in ("done", "idle"):
                    self._note("done", a["id"], name, now)
                else:
                    self._note("state", a["id"], name, now, says=a["state"])
            elif before is not None:
                a["since"] = guards.iso(now)
                self._note("appeared", a["id"], name, now)
            self._known[a["id"]] = {"state": a["state"], "since": a["since"], "name": name}
        for ident, seen in (before or {}).items():
            if ident not in self._known:
                self._note("gone", ident, seen["name"], now)

    def _note(self, kind, ident, name, now, says=None):
        """Adds an event; its sentence is the kind's, or the new state's for the kind "state"."""
        self._n += 1
        self._events.append({"n": self._n, "t": guards.iso(now), "kind": kind, "agent": ident,
                             "text": f"{name} {SAYS[says or kind]}"})
        del self._events[:-EVENTS_MAX]


def _agent(raw, workspace, reader, now):
    """(agent of the state, session or None): what Herdr says of a pane, then what its log says if a reader links
    it to a session. A reader that raises, or that returns what JSON cannot write, leaves the session keys None and
    says so in `read_error`."""
    focused = raw.get("focused")
    agent = {
        "id": raw["pane_id"], "name": guards.text(raw.get("name")), "harness": guards.text(raw.get("agent")),
        "state": herdr.state(raw.get("agent_status")), "since": None,
        "title": guards.text(raw.get("terminal_title_stripped")), "cwd": guards.tilde(raw.get("cwd")),
        "workspace": workspace, "focused": focused if isinstance(focused, bool) else None,
        "session": None, **dict.fromkeys(SESSION_KEYS), "read_error": None,
    }
    session = None
    if reader:
        try:
            session = reader.session(raw)
            if session is None:
                agent["read_error"] = "the pane does not safely link to any session"
            else:
                linked = {"id": session["id"], "path": guards.tilde(session["path"])}
                json.dumps(linked, allow_nan=False)     # what JSON cannot write would bring the routes down
                agent["session"] = linked
                read = reader.read(session, now)
                merged = {key: read.get(key) for key in SESSION_KEYS}
                if isinstance(merged["cost"], float):
                    merged["cost"] = round(merged["cost"], 4)
                if merged["subagents"] is not None:         # a direct child has the pane as its parent
                    merged["subagents"] = [{**s, "parent": agent["id"] if s.get("parent") is None else s["parent"]}
                                           for s in merged["subagents"]]
                if read.get("title") is not None:
                    merged["title"] = read["title"]
                json.dumps(merged, allow_nan=False)
                agent.update(merged)
        except (Exception, SystemExit) as e:    # a reader that exits is broken like any other: the loop holds
            agent["read_error"] = guards.clip(f"{type(e).__name__}: {e}", 200)
    return agent, session


def _undated(state):
    """The state without the time of the poll: what is compared from one poll to the next."""
    return {key: value for key, value in state.items() if key != "generated"}


def loop(poller, interval=2.0, stop=None, say=None):
    """Does a poll every `interval` seconds, until `stop` (threading.Event) is set. `say`, if given, is called each
    time the `error` of the state changes: with the sentence, or with None when the polls work again. It runs in
    this thread and must not raise: the loop would end with it."""
    stop = stop or threading.Event()
    said = None
    while not stop.is_set():
        error = poller.poll()["error"]
        if say and error != said:
            say(error)
        said = error
        stop.wait(interval)
