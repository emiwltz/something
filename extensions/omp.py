"""The OMP reader.

Links a pane of Herdr to its OMP session log and draws from it what the README promises: model, effort, context,
cost, tool, question, todos, goal, subagents, conversation. A log is followed line by line: each line is parsed
only once, even if it weighs 50 MB. Nothing is ever written.
"""
import json
import os
import sqlite3
from pathlib import Path

from something import guards
from extensions import _reading as reading

HARNESS = "omp"
ROOT = Path.home() / ".omp" / "agent"   # sessions/: the logs; models.db: the context windows

STATUSES = {"pending": "pending", "in_progress": "in_progress", "completed": "done", "blocked": "blocked"}
RECENT = 2 * 3600         # a subagent silent for longer is no longer listed
ALIVE = 120               # without an end mark, a subagent that has written more recently is working
ALIVE_TOOL = 15 * 60      # the same delay when one of its tools is open: a tool can last
SUBAGENTS_MAX = 50

_followed = {}    # path of a log → what it has said so far (see _follow)
_windows = {}     # (path of models.db, its fingerprint, that of its -wal) → {(provider, model): window}


def session(agent):
    """The session of a pane according to Herdr: {"id", "path"}, or None if nothing safely points to a log of
    OMP. Herdr gives the path of the log, or the identifier that ends its name."""
    ref = guards.as_dict(guards.as_dict(agent).get("agent_session"))
    value, sessions = guards.text(ref.get("value")), ROOT / "sessions"
    found = []
    if value and ref.get("kind") == "path":
        path = Path(os.path.normpath(value))
        if path.suffix == ".jsonl" and sessions in path.parents:   # no file outside OMP's sessions
            found = [path]
    elif value and ref.get("kind") == "id":
        found = [p for p in sessions.glob("*/*.jsonl") if p.stem.rpartition("_")[2] == value]
    if len(found) != 1:
        return None
    return {"id": found[0].stem.rpartition("_")[2], "path": str(found[0])}


def read(session, now):
    """Everything the log says about the agent, under the README's keys; None for what it does not say. Raises
    OSError if the log is gone."""
    path = session["path"]
    s = _follow(path)
    if s is None:
        raise FileNotFoundError("the log no longer exists: " + str(guards.tilde(path)))
    subagents, sub_cost = _subagents(path, now)
    costs = [c for c in (s["cost"], sub_cost) if c is not None]
    tool = next(reversed(s["tools"].values()), None)
    return {
        "title": _title(path),
        "model": _model(s),
        "effort": s["effort"],
        "context": _context(s["context"]),
        "cost": round(sum(costs), 4) or None,       # no cost read, or one too small to be written: never zero
        "tool": {"name": tool[0], "since": guards.iso(tool[1])} if tool else None,
        "request": _request(s),
        "todos": _todos(s["phases"]),
        "goal": _goal(*s["goal"]),
        "subagents": subagents,
        "activity": guards.iso(s["fingerprint"][1] / 1e9),
    }


def turns(session, limit=20, before=None):
    """{"turns", "older", "before"}: the last `limit` turns of the conversation, or those that precede the turn
    of identifier `before`, read from the end of the log (reading.page). Raises LookupError if `before` is not in
    what is read, OSError if the log is gone."""
    return reading.page(session["path"], _turns, limit, before)


# Following a log

def _follow(path):
    """What the log has said so far, or None if it does not exist. Only the lines added since the last read are
    parsed; if the log has shrunk or has been replaced by another file, everything is forgotten and the read
    starts again from zero."""
    fingerprint = reading.fingerprint(path)
    if fingerprint is None:
        _followed.pop(path, None)
        return None
    s = _followed.get(path)
    if s is None or fingerprint[0] < s["position"] or fingerprint[2] != s["inode"]:
        s = _followed[path] = {
            "fingerprint": None, "position": 0, "inode": fingerprint[2],
            "start": None, "type": None,              # of a subagent: when it was born, its kind
            "model": None, "called": None,            # the chosen model; the (provider, model) that just answered
            "effort": None, "cost": None,
            "context": None,                          # (tokens, (provider, model)) of the last measure
            "tools": {}, "questions": {},             # open tools and arguments of the `ask` calls, by toolCallId
            "phases": [], "goal": (None, {}),         # the todos and the goal, as the log writes them
            "done": False, "end": None,               # does the last reply mark an end, and when
            "exited": False,                          # does the last line say that the program has stopped
        }
    if s["fingerprint"] != fingerprint:
        for line, s["position"] in reading.lines_from(path, s["position"]):     # the position follows the read
            _note(s, guards.as_dict(guards.json_object(line)))
        s["fingerprint"] = fingerprint
    return s


def _note(s, o):
    """Stores in the followed state `s` what a line of the log says. The last to speak is right."""
    kind, data = o.get("type"), guards.as_dict(o.get("data"))
    s["exited"] = kind == "custom" and o.get("customType") == "session_exit"
    if s["exited"]:
        s["tools"].clear()        # the program stopped: a tool it left open will never write its result
    if kind == "message":
        _note_message(s, guards.as_dict(o.get("message")), reading.seconds(o.get("timestamp")))
    elif kind == "custom" and o.get("customType") == "tool_execution_start":
        ident, name = guards.text(data.get("toolCallId")), guards.text(data.get("toolName"))
        if ident and name:
            s["tools"][ident] = (name, reading.seconds(data.get("startedAt")))
    elif kind == "custom" and o.get("customType") == "user_todo_edit" and isinstance(data.get("phases"), list):
        s["phases"] = data["phases"]          # the user edited the list by hand
    elif kind == "model_change":
        s["model"] = guards.text(o.get("model"))
    elif kind == "thinking_level_change":
        s["effort"] = guards.text(o.get("thinkingLevel"))
    elif kind == "mode_change":
        s["goal"] = (o.get("mode"), guards.as_dict(data.get("goal")))
    elif kind == "compaction":
        s["context"] = None                   # the measure from before no longer holds; the next reply will give it
    elif kind == "session":
        s["start"] = reading.seconds(o.get("timestamp"))
    elif kind == "session_init":
        s["type"] = guards.text(o.get("agent"))
        s["model"] = s["model"] or guards.text(o.get("resolvedModel"))


def _note_message(s, m, t):
    """A reply of the model carries the cost, the context measure and the questions; a result closes its tool; a
    message received closes those that never returned (OMP was killed while they ran)."""
    if m.get("role") == "assistant":
        usage = guards.as_dict(m.get("usage"))
        cost = guards.number(guards.as_dict(usage.get("cost")).get("total"))
        if cost:                  # OMP counts zero for a reply that failed or was cut short: it measures nothing
            s["cost"] = (s["cost"] or 0) + cost
        called = (guards.text(m.get("provider")), guards.text(m.get("model")))
        if all(called):
            s["called"] = called
        if guards.number(usage.get("totalTokens")):       # a zero usage (interrupted reply) measures nothing
            tokens = _integer(guards.as_dict(m.get("contextSnapshot")).get("promptTokens"))
            s["context"] = None if tokens is None else (tokens, called)
        calls = [guards.as_dict(b) for b in guards.as_list(m.get("content"))]
        s["questions"] = {b["id"]: b.get("arguments") for b in calls
                          if b.get("type") == "toolCall" and b.get("name") == "ask" and guards.text(b.get("id"))}
        s["done"], s["end"] = m.get("stopReason") == "stop", t
    elif m.get("role") == "user":
        s["tools"].clear()        # OMP hands a message over when no tool runs: one still open will never return
    elif m.get("role") == "toolResult":
        s["tools"].pop(guards.text(m.get("toolCallId")), None)
        if m.get("isError") is False:
            phases = guards.as_dict(m.get("details")).get("phases")
            if m.get("toolName") == "todo" and isinstance(phases, list):
                s["phases"] = phases          # each `todo` result gives the whole list again
            elif m.get("toolName") == "yield":
                s["done"], s["end"] = True, t   # a refused yield (isError) ends nothing: the agent tries again


# Shaping what the followed state has kept

def _integer(x):
    n = guards.number(x)
    return None if n is None else int(n)


def _title(path):
    """The title of the session: the first line of the log, which OMP rewrites in place."""
    with open(path, "rb") as f:
        head = guards.as_dict(guards.json_object(f.readline(4096)))
    return guards.text(head.get("title")) if head.get("type") == "title" else None


def _model(s):
    """As "provider/model": the chosen model, otherwise the one that answered last."""
    return s["model"] or ("/".join(s["called"]) if s["called"] else None)


def _context(measure):
    """The context's tokens, and their share of the window when models.db knows that of the model that answered."""
    if measure is None:
        return None
    tokens, called = measure
    window = _known_windows().get(called)
    percent = min(100, round(100 * tokens / window)) if window else None
    return {"tokens": tokens, "window": window, "percent": percent}


def _known_windows():
    """{(provider, model): context window} according to models.db, read again only when it changes; {} if it cannot
    be read. The window of a same model changes from one provider to another: its name alone is not enough."""
    file = ROOT / "models.db"
    key = (str(file), reading.fingerprint(file), reading.fingerprint(f"{file}-wal"))    # OMP writes through the -wal
    if key not in _windows:
        table = {}
        try:
            with reading.database(file) as connection:      # read-only, no -shm or -wal file left in OMP's folder
                rows = connection.execute("SELECT provider_id, models FROM model_cache").fetchall()
            for provider, models in rows:
                for m in guards.as_list(json.loads(models)):
                    m = guards.as_dict(m)
                    name, window = guards.text(m.get("id")), _integer(m.get("contextWindow"))
                    if name and window:
                        table[(str(provider).split(":")[0], name)] = window   # "openai-codex:0.159.0"
        except (sqlite3.Error, ValueError, TypeError):
            table = {}
        _windows.clear()
        _windows[key] = table
    return _windows[key]


def _request(s):
    """The question of an open `ask`, or None. Its arguments are only written in the model's call."""
    for ident, (name, _) in reversed(s["tools"].items()):
        if name != "ask":
            continue
        questions = []
        for q in guards.as_list(guards.as_dict(s["questions"].get(ident)).get("questions")):
            q = guards.as_dict(q)
            options = [guards.text(guards.as_dict(o).get("label")) for o in guards.as_list(q.get("options"))]
            if guards.text(q.get("question")):
                questions.append({"question": q["question"], "options": [o for o in options if o],
                                  "multi": q.get("multi") is True})
        return {"kind": "question", "questions": questions}
    return None


def _todos(phases):
    """The tasks of the phases, in order: they are OMP's todos. A task without a text, or with a status that is
    not known, is dropped."""
    todos = []
    for phase in phases:
        phase = guards.as_dict(phase)
        for task in guards.as_list(phase.get("tasks")):
            text = guards.text(guards.as_dict(task).get("content"))
            status = STATUSES.get(guards.text(guards.as_dict(task).get("status")))
            if text and status:
                todos.append({"text": text, "status": status, "phase": guards.text(phase.get("name"))})
    return todos


def _goal(mode, goal):
    """The open goal according to the last mode_change line, or None: complete or abandoned, there is none left."""
    objective = guards.text(goal.get("objective"))
    active = mode == "goal" and goal.get("status") == "active"
    if objective is None or not (active or mode == "goal_paused"):
        return None
    return {"objective": guards.clip(objective, 4000), "status": "active" if active else "paused",
            "tokens": _integer(goal.get("tokensUsed")), "seconds": _integer(goal.get("timeUsedSeconds"))}


def _subagents(path, now):
    """(the subagents to show, the cost of all). Each has its log under "<log without .jsonl>/"; that of a
    subagent's subagent lives in a folder named after its parent and is called "Parent.Child"."""
    folder = Path(path).with_suffix("")
    followed = {}
    for file in folder.rglob("*.jsonl"):
        s = _follow(str(file))
        if s is not None:
            followed[file.relative_to(folder).with_suffix("")] = s
    ids = {rel.as_posix() for rel in followed}
    seen = []
    for rel, s in followed.items():
        age = now - s["fingerprint"][1] / 1e9
        if s["done"]:
            state = "done"
        elif not s["exited"] and age < (ALIVE_TOOL if s["tools"] else ALIVE):
            state = "working"
        else:   # never "done" without a mark: stopped without having yielded, or silent, it is "unknown"
            state = "unknown"
        if age >= RECENT:
            continue
        parent = next((p.as_posix() for p in rel.parents if p.as_posix() in ids), None)
        name = rel.name
        if parent and name.startswith(rel.parent.name + "."):
            name = name[len(rel.parent.name) + 1:]
        seen.append((age, s["start"] or 0, {
            "id": rel.as_posix(), "name": name, "type": s["type"], "parent": parent, "state": state,
            "model": _model(s), "start": guards.iso(s["start"]), "end": guards.iso(s["end"]) if s["done"] else None}))
    recent = sorted(seen, key=lambda v: v[0])[:SUBAGENTS_MAX]
    costs = [s["cost"] for s in followed.values() if s["cost"] is not None]
    return [v[2] for v in sorted(recent, key=lambda v: v[1])], sum(costs) if costs else None


# The conversation

def _turns(lines):
    """The turns these lines tell. A turn goes from one received message to the next: it gathers the model's
    replies and its tool calls. The reasoning and the tool results are not returned."""
    seen = []
    for line in lines:
        o = guards.as_dict(guards.json_object(line))
        m = guards.as_dict(o.get("message"))
        if o.get("type") != "message" or m.get("role") not in ("user", "assistant"):
            continue
        t = guards.iso(reading.seconds(o.get("timestamp")))
        blocks = [guards.as_dict(b) for b in guards.as_list(m.get("content"))]
        text = "\n".join(b["text"] for b in blocks if b.get("type") == "text" and isinstance(b.get("text"), str))
        if m.get("role") == "user":
            if text.strip() and guards.text(o.get("id")):
                sender = "user" if m.get("attribution") == "user" else "system"   # otherwise: a parent's brief
                seen.append({"id": o["id"], "t": t, "from": sender, "text": guards.clip(text, 4000),
                             "replies": [], "tools": [], "end": None})
        elif seen:
            turn = seen[-1]
            if text.strip():
                turn["replies"].append({"t": t, "text": guards.clip(text, 8000)})
            for b in blocks:
                if b.get("type") == "toolCall" and guards.text(b.get("name")):
                    args = guards.as_dict(b.get("arguments"))
                    target = guards.text(args.get("path")) or guards.text(args.get("command")) or b.get("intent")
                    turn["tools"].append({"name": b["name"], "target": guards.clip(target, 160) or None})
            turn["end"] = t if m.get("stopReason") == "stop" else None
    return seen
