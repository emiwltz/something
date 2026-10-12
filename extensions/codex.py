"""The Codex reader.

Herdr gives only the thread's identifier: Codex's SQLite index leads to its log (a "rollout"), followed line by
line without ever parsing a tool output. The log says the model, the effort, the context, the plan, the running
tool and the conversation; Codex's databases say the title, the goal and the subagents. Nothing is ever written.
"""
import itertools
import os
import re
import sqlite3
import threading
from pathlib import Path

from something import guards
from extensions import _reading as reading

HARNESS = "codex"
ROOT = Path.home() / ".codex"     # sessions/: the logs; state_<n>.sqlite: the index; goals_<n>.sqlite: the goals

STATUSES = {"pending": "pending", "in_progress": "in_progress", "completed": "done"}
GOALS = {"active": "active", "paused": "paused", "blocked": "paused", "usage_limited": "paused",
         "budget_limited": "paused"}      # stopped, a goal still exists: only `complete`, finished, is not returned
MARKS = {"task_started": "open", "task_complete": "done", "turn_aborted": "aborted"}      # what a turn becomes
CALLS = ("function_call", "custom_tool_call")
OUTPUTS = ("function_call_output", "custom_tool_call_output")
ACTIONS = {               # kind of a completed item → (the field that names the tool, the field that says its target)
    "CommandExecution": (None, "command"), "FileChange": (None, "changes"), "ImageView": (None, "path"),
    "McpToolCall": ("tool", "server"), "FunctionCallOutput": ("name", "namespace"), "Extension": ("kind", "query"),
    "CollabAgentToolCall": ("tool", None),
}
ITEMS = ("UserMessage", "AgentMessage", *ACTIONS)     # the completed items that make the conversation
CHILDREN = """
    WITH RECURSIVE children(id, parent) AS (
        SELECT child_thread_id, NULL FROM thread_spawn_edges WHERE parent_thread_id = ?
        UNION
        SELECT e.child_thread_id, e.parent_thread_id
        FROM thread_spawn_edges e JOIN children ON e.parent_thread_id = children.id)
    SELECT children.id, children.parent, t.rollout_path, t.agent_path, t.agent_nickname, t.agent_role, t.created_at
    FROM children JOIN threads t ON t.id = children.id"""
RECENT = 2 * 3600         # a subagent silent for longer is no longer listed
ALIVE = 120               # without an end mark, a subagent that has written more recently is working
ALIVE_TOOL = 15 * 60      # the same delay when one of its tools is open: a tool can last
SUBAGENTS_MAX = 50
FOLLOWED_MAX = 1000       # logs followed at a time; beyond that, everything is forgotten and read again
TIMEOUT = 0.2             # seconds to wait, at most, for a database that Codex holds locked
HEAD = 512                # characters of the start of a line: its kind, its payload's and its `call_id` are there

_ID = re.compile(r"[\w-]+")                           # a thread identifier: never a piece of a path
_TYPE = re.compile(r'"type"\s*:\s*"(\w+)"')
_CALL = re.compile(r'"call_id"\s*:\s*"([^"\\]+)"')
_followed = {}    # path of a log → what it has said so far (see _follow)
_lock = threading.Lock()      # `read` comes from the poll's thread, `turns` from the server's: one follows at a time


def session(agent):
    """The session of a pane according to Herdr: {"id", "path"}, or None. Herdr gives only the thread's identifier:
    its log is the one Codex's index knows for it, otherwise the only file of sessions/ that carries its name.
    Without an identifier, without a safe log, or with a log outside Codex's folder, nothing is linked."""
    ref = guards.as_dict(guards.as_dict(agent).get("agent_session"))
    ident = guards.text(ref.get("value"))
    if ref.get("kind") != "id" or not _ID.fullmatch(ident or ""):
        return None
    known = _database("state", "SELECT rollout_path FROM threads WHERE id = ?", ident)
    found = [Path(os.path.normpath(path)) for path, in known or [] if guards.text(path)]    # ".." climbs nowhere
    found = found or list((ROOT / "sessions").glob(f"*/*/*/rollout-????-??-??T??-??-??-{ident}.jsonl"))
    if len(found) != 1 or found[0].suffix != ".jsonl" or ROOT not in found[0].parents:
        return None
    return {"id": ident, "path": str(found[0])}


def read(session, now):
    """Everything the session says, under the README's keys; None for what it does not say. Codex writes no cost
    in dollars, nor the permission it is waiting for. Raises OSError if the log is gone."""
    name = _database("state", "SELECT name FROM threads WHERE id = ?", session["id"])
    with _lock:
        s = _follow(session["path"])
        call = next(reversed(s["calls"].values()), None)
        return {
            "title": guards.text(name[0][0]) if name else None,
            "model": s["model"],
            "effort": s["effort"],
            "context": _context(s["context"]),
            "cost": None,
            "tool": {"name": call["name"], "since": guards.iso(call["since"])} if call else None,
            "request": _request(s["calls"]),
            "todos": _todos(s["plan"]),
            "goal": _goal(session["id"]),
            "subagents": _subagents(session["id"], now),
            "activity": guards.iso(s["fingerprint"][1] / 1e9),
        }


def turns(session, limit=20, before=None):
    """{"turns", "older", "before"}: the last `limit` turns of the conversation, or those that precede the turn of
    identifier `before`. The followed state knows at which byte each turn starts: only the requested span is read
    again, however big the log. If it exceeds reading.CONVERSATION_MAX, fewer turns are returned, one at least.
    Raises LookupError if no turn carries the identifier `before`, OSError if the log is gone."""
    path = session["path"]
    with _lock:
        s = _follow(path)
        ids = [ident for ident, _ in s["messages"]]
        offsets = [offset for _, offset in s["messages"]] + [s["position"]]   # where each turn starts, then the end
    if before is not None and before not in ids:
        raise LookupError("no turn carries this identifier")
    end = len(ids) if before is None else ids.index(before)
    start = max(0, end - max(1, limit))
    while start < end - 1 and offsets[end] - offsets[start] > reading.CONVERSATION_MAX:
        start += 1
    lines = itertools.takewhile(lambda pair: pair[1] <= offsets[end], reading.lines_from(path, offsets[start]))
    returned = _turns(line for line, _ in lines)
    return {"turns": returned, "older": start > 0, "before": returned[0]["id"] if start > 0 and returned else None}


# Codex's databases

def _database(name, query, *values):
    """The rows a query returns on Codex's database `<name>_<n>.sqlite`; None if it is missing or cannot be read.
    The number changes with Codex's version: the database with the highest number is read, read-only and without
    creating anything next to it (reading.database)."""
    databases = sorted(ROOT.glob(name + "_*.sqlite"), key=lambda file: (len(file.name), file.name))
    try:
        with reading.database(databases[-1], TIMEOUT) as connection:
            return connection.execute(query, values).fetchall()
    except (sqlite3.Error, IndexError):       # unreadable, or missing
        return None


def _goal(ident):
    """The goal opened by `/goal`, or None: finished or removed, there is none any more. It is read in the goals
    database: the log notes each step forward of a goal, but not its removal, nor always its pausing. None too
    when that database cannot be read: the state has no other word for a goal (README, "The state")."""
    goals = _database("goals", "SELECT objective, status, tokens_used, time_used_seconds FROM thread_goals"
                               " WHERE thread_id = ?", ident)
    objective, status, tokens, seconds = goals[0] if goals else (None, None, None, None)
    if guards.text(objective) is None or status not in GOALS:
        return None
    return {"objective": guards.clip(objective, 4000), "status": GOALS[status],
            "tokens": _integer(tokens), "seconds": _integer(seconds)}


def _subagents(ident, now):
    """The subagents to show, or None if the index cannot be read. A subagent is a child thread, which the index
    links to its parent (thread_spawn_edges) and which has its own log. A "guardian" thread, Codex's automatic
    review, is not registered there: it is not a subagent."""
    children = _database("state", CHILDREN, ident)
    if children is None:
        return None
    recent = []
    for child in children:
        written = reading.fingerprint(child[2])
        if written and now - written[1] / 1e9 < RECENT:
            recent.append((written[1] / 1e9, child))
    seen = []
    for written, child in sorted(recent, key=lambda r: r[0])[-SUBAGENTS_MAX:]:
        thread, parent, path, agent_path, nickname, role, start = child
        try:
            s = _follow(path)
        except OSError:     # the log has just disappeared
            continue
        if s["turn"] in ("done", "failed"):
            state = s["turn"]
        elif s["turn"] != "aborted" and now - written < (ALIVE_TOOL if s["calls"] else ALIVE):
            state = "working"
        else:   # never "done" without a mark: interrupted, or silent, it is "unknown"
            state = "unknown"
        seen.append((guards.number(start) or 0, {
            "id": thread, "name": (guards.text(agent_path) or "").rpartition("/")[2] or guards.text(nickname),
            "type": guards.text(role), "parent": parent, "state": state, "model": s["model"],
            "start": guards.iso(start), "end": guards.iso(s["end"]) if state in ("done", "failed") else None}))
    return [v[1] for v in sorted(seen, key=lambda v: v[0])]


# Following a log

def _follow(path):
    """What the log has said so far; FileNotFoundError if it does not exist. Only the lines added since the last
    read are read; if the log has shrunk or has been replaced by another file, everything is forgotten and the
    read starts again from zero. To be called while holding `_lock`."""
    fingerprint = reading.fingerprint(path)
    if fingerprint is None:
        _followed.pop(path, None)
        raise FileNotFoundError("the log no longer exists: " + str(guards.tilde(path)))
    s = _followed.get(path)
    if s is None or fingerprint[0] < s["position"] or fingerprint[2] != s["inode"]:
        if len(_followed) >= FOLLOWED_MAX:
            _followed.clear()
        s = _followed[path] = {
            "fingerprint": None, "position": 0, "inode": fingerprint[2],
            "model": None, "effort": None,
            "context": None,                  # (tokens, window) of the last measure
            "plan": [],                       # the steps of the last `update_plan`, as the log writes them
            "calls": {},                      # tools called and not yet returned, by call_id
            "messages": [],                   # (identifier, byte where it starts) of each turn of the conversation
            "turn": None, "end": None,        # what the last turn became (MARKS, or "failed"), and when
        }
    if s["fingerprint"] != fingerprint:
        for line, after in reading.lines_from(path, s["position"]):
            _note(s, line)                    # `position` is still the byte where this line starts
            s["position"] = after
        s["fingerprint"] = fingerprint
    return s


def _kinds(line):
    """(kind of the line, kind of its payload, kind of the item it carries), read in its head without parsing it;
    None for what it does not have."""
    return (_TYPE.findall(line[:HEAD]) + [None] * 3)[:3]


def _payload(line):
    """(the payload of a line, its date in seconds)."""
    o = guards.as_dict(guards.json_object(line))
    return guards.as_dict(o.get("payload")), reading.seconds(o.get("timestamp"))


def _note(s, line):
    """Stores in the followed state `s` what a log line says. The last to speak is right. Only the useful lines,
    all short, are parsed: a tool output can weigh 6 MB, and its head is enough."""
    kind, payload, item_kind = _kinds(line)
    if kind == "compacted":
        s["context"] = None                   # the measure from before no longer holds; the next reply will give it
    elif kind == "turn_context":
        p, _ = _payload(line)
        if guards.text(p.get("model")):       # each turn says both again; without a model, the line says nothing
            s["model"], s["effort"] = p["model"], guards.text(p.get("effort"))
    elif kind == "response_item" and payload in OUTPUTS:
        back = _CALL.search(line[:HEAD])
        s["calls"].pop(back and back.group(1), None)
    elif kind == "response_item" and payload in CALLS:
        p, t = _payload(line)
        ident, name = guards.text(p.get("call_id")), guards.text(p.get("name"))
        arguments = guards.as_dict(guards.json_object(guards.text(p.get("arguments")) or ""))
        if name == "update_plan" and isinstance(arguments.get("plan"), list):
            s["plan"] = arguments["plan"]     # each call gives the whole plan again
        if ident and name:
            s["calls"][ident] = {"name": name, "since": t, "arguments": arguments}
    elif kind == "event_msg" and payload == "token_count":
        info = guards.as_dict(_payload(line)[0].get("info"))
        tokens = guards.number(guards.as_dict(info.get("last_token_usage")).get("input_tokens"))
        if tokens:                            # without usage, or at zero: nothing is measured, the last measure stays
            s["context"] = (int(tokens), _integer(info.get("model_context_window")))
    elif kind == "event_msg" and payload in MARKS:
        p, t = _payload(line)
        s["calls"].clear()                    # a turn opens or closes: no tool of the old one runs any more
        s["turn"], s["end"] = "failed" if isinstance(p.get("error"), dict) else MARKS[payload], t
    elif kind == "event_msg" and item_kind == "UserMessage":
        for turn in _turns([line]):           # the conversation's rule: a message without text opens no turn
            s["messages"].append((turn["id"], s["position"]))


# Shaping what the followed state has kept

def _integer(x):
    n = guards.number(x)
    return None if n is None else int(n)


def _context(measure):
    """The tokens sent at the last call of the model, and their share of the window Codex announces."""
    if measure is None:
        return None
    tokens, window = measure
    percent = min(100, round(100 * tokens / window)) if window else None
    return {"tokens": tokens, "window": window or None, "percent": percent}


def _request(calls):
    """The question of a `request_user_input` left unanswered, or None. Each question waits for one choice only."""
    for call in reversed(list(calls.values())):
        if call["name"] != "request_user_input":
            continue
        questions = []
        for q in map(guards.as_dict, guards.as_list(call["arguments"].get("questions"))):
            options = [guards.text(guards.as_dict(o).get("label")) for o in guards.as_list(q.get("options"))]
            if guards.text(q.get("question")):
                questions.append({"question": q["question"], "options": [o for o in options if o], "multi": False})
        return {"kind": "question", "questions": questions}
    return None


def _todos(plan):
    """The steps of the plan, which Codex keeps with the `update_plan` tool: they are its todos."""
    todos = []
    for step in map(guards.as_dict, plan):
        text, status = guards.text(step.get("step")), STATUSES.get(guards.text(step.get("status")))
        if text and status:
            todos.append({"text": text, "status": status, "phase": None})
    return todos


# The conversation

def _turns(lines):
    """The turns these lines tell. A turn goes from one user message to the next: it gathers the model's replies and
    its actions, which Codex writes as completed items (`item_completed`). The reasoning is not returned, nor the
    messages the agents exchange, whose text is encrypted. The lines before the first message are ignored."""
    told = []
    for line in lines:
        kind, payload, item_kind = _kinds(line)
        useful = payload == "task_complete" or (payload == "item_completed" and item_kind in ITEMS)
        if kind != "event_msg" or not useful:
            continue
        p, t = _payload(line)
        item, t = guards.as_dict(p.get("item")), guards.iso(t)
        item_kind = guards.text(item.get("type"))
        blocks = [guards.as_dict(b) for b in guards.as_list(item.get("content"))]
        text = "\n\n".join(b["text"] for b in blocks if isinstance(b.get("text"), str))
        if item_kind == "UserMessage":
            if text.strip() and guards.text(item.get("id")):
                told.append({"id": item["id"], "t": t, "from": "user", "text": guards.clip(text, 4000),
                             "replies": [], "tools": [], "end": None})
        elif told:
            turn = told[-1]
            if item_kind == "AgentMessage" and text.strip():
                turn["replies"].append({"t": t, "text": guards.clip(text, 8000)})
            elif item_kind in ACTIONS:
                turn["tools"].append(_action(item_kind, item))
            turn["end"] = t if p.get("type") == "task_complete" else None
    return told


def _action(item_kind, item):
    """{"name", "target"} of a completed item that is an action of the model. Without a tool name, it carries the
    name of its kind."""
    name_field, target_field = ACTIONS[item_kind]
    target = item.get(target_field)
    if isinstance(target, list):
        target = target[-1] if target else None       # a command: ["/bin/zsh", "-lc", "…"]
    elif isinstance(target, dict):
        target = next(iter(target), None)             # changed files, stored by path
    return {"name": guards.text(item.get(name_field)) or item_kind, "target": guards.clip(target, 160) or None}
