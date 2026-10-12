"""The pi reader.

pi gives Herdr the path of its session log, the ancestor of OMP's: the reader draws from it the title, the model,
the effort, the context, the cost, the running tool and the conversation. The log is followed line by line, each
line is parsed only once. pi has no todos, no question, no goal, no subagents; those one of its extensions would
add are not read. Nothing is ever written.
"""
import os
from pathlib import Path

from something import guards
from extensions import _reading as reading

HARNESS = "pi"
ROOT = Path.home() / ".pi" / "agent"    # sessions/: the logs; models-store.json: the context windows

TARGETS = ("command", "pattern", "path", "url", "query")    # the argument that says what a tool call is about

_followed = {}    # path of a log → what it has said so far (see _follow)
_windows = {}     # (path of models-store.json, its fingerprint) → {(provider, model): window}


def session(agent):
    """The session of a pane according to Herdr: {"id", "path"}, or None if nothing safely points to a log of
    pi. Herdr gives the path of the log, which pi names "<date>_<identifier>.jsonl"."""
    ref = guards.as_dict(guards.as_dict(agent).get("agent_session"))
    value = guards.text(ref.get("value"))
    if value is None or ref.get("kind") != "path":
        return None
    path = Path(os.path.normpath(value))
    if path.suffix != ".jsonl" or ROOT / "sessions" not in path.parents:   # no file outside pi's sessions
        return None
    return {"id": path.stem.partition("_")[2] or path.stem, "path": str(path)}


def read(session, now):
    """Everything the log says about the agent, under the README's keys; None for what it does not say. A zero
    cost is None: pi counts zero for a free model as for a price it does not know. Raises OSError if the log does
    not exist."""
    s = _follow(session["path"])
    tool = next(iter(s["tools"].values()), None)      # the first call left without a result
    return {
        "title": s["title"],
        "model": "/".join(s["model"]) if s["model"] else None,
        "effort": s["effort"],
        "context": _context(s["context"]),
        "cost": round(s["cost"], 4) or None,
        "tool": {"name": tool[0], "since": guards.iso(tool[1])} if tool else None,
        "request": None, "todos": [], "goal": None, "subagents": [],      # pi has none
        "activity": guards.iso(s["fingerprint"][1] / 1e9),
    }


def turns(session, limit=20, before=None):
    """{"turns", "older", "before"}: the last `limit` turns of the current branch, or those that precede the turn
    of identifier `before`, read from the end of the log (reading.page). Raises LookupError if `before` is not in
    what is read, OSError if the log does not exist."""
    return reading.page(session["path"], _turns, limit, before)


# Following a log

def _present(path):
    """The fingerprint of the log; FileNotFoundError if it does not exist, or not yet: pi only writes it at the
    first message."""
    fingerprint = reading.fingerprint(path)
    if fingerprint is None:
        raise FileNotFoundError("the log does not exist: " + str(guards.tilde(path)))
    return fingerprint


def _follow(path):
    """What the log has said so far. Only the lines added since the last read are parsed; if the log has shrunk
    or has been replaced by another file, everything is forgotten and the read starts again from zero."""
    fingerprint = _present(path)
    s = _followed.get(path)
    if s is None or fingerprint[0] < s["position"] or fingerprint[2] != s["inode"]:
        s = _followed[path] = {
            "fingerprint": None, "position": 0, "inode": fingerprint[2],
            "title": None, "effort": None, "cost": 0.0,
            "model": None,        # (provider, model): the last one chosen, or the last one that answered
            "context": None,      # (tokens, (provider, model)) of the last measure
            "tools": {},          # the model's calls left without a result: identifier → (name, start)
        }
    if s["fingerprint"] != fingerprint:
        for line, s["position"] in reading.lines_from(path, s["position"]):     # the position follows the read
            _note(s, guards.as_dict(guards.json_object(line)))
        s["fingerprint"] = fingerprint
    return s


def _note(s, o):
    """Stores in the followed state `s` what a line of the log says. The last to speak is right."""
    kind, m = o.get("type"), guards.as_dict(o.get("message"))
    role = m.get("role") if kind == "message" else None
    # The cost: like pi, that of every line that carries a usage (reply, tool, summary, `usage` line).
    usage = guards.as_dict(m.get("usage") or o.get("usage"))
    s["cost"] += guards.number(guards.as_dict(usage.get("cost")).get("total")) or 0
    if kind == "model_change":
        s["model"] = _pair(o.get("provider"), o.get("modelId"))
    elif kind == "thinking_level_change":
        s["effort"] = guards.text(o.get("thinkingLevel"))
    elif kind == "session_info":
        s["title"] = guards.clip(o.get("name"), 200) or None    # an empty name removes the title
    elif kind == "compaction":
        s["context"] = None                   # the measure from before no longer holds; the next reply will give it
    elif role == "user":
        s["tools"].clear()                    # a new turn: no tool of the old one is running any more
    elif role == "toolResult":
        s["tools"].pop(guards.text(m.get("toolCallId")), None)
    elif role == "assistant":
        called = _pair(m.get("provider"), m.get("model"))
        s["model"] = called or s["model"]
        s["effort"] = guards.text(m.get("thinkingLevel")) or s["effort"]    # written since pi 1.0.0
        if m.get("stopReason") in ("error", "aborted"):
            return                            # a failed reply measures nothing and starts no tool
        tokens = guards.number(usage.get("totalTokens"))
        if tokens:                            # a zero usage measures nothing: the measure from before stays
            s["context"] = (int(tokens), called)
        for b in map(guards.as_dict, guards.as_list(m.get("content"))):
            ident, name = guards.text(b.get("id")), guards.text(b.get("name"))
            if b.get("type") == "toolCall" and ident and name:
                s["tools"][ident] = (name, reading.seconds(o.get("timestamp")))


# Shaping what the followed state has kept

def _pair(provider, model):
    """(provider, model), or None if one of the two is missing."""
    pair = (guards.text(provider), guards.text(model))
    return pair if all(pair) else None


def _context(measure):
    """The tokens of the context, and their share of the window if the catalog knows that of the model that
    answered."""
    if measure is None:
        return None
    tokens, called = measure
    window = _known_windows().get(called)
    percent = min(100, round(100 * tokens / window)) if window else None
    return {"tokens": tokens, "window": window, "percent": percent}


def _known_windows():
    """{(provider, model): context window} according to models-store.json, the catalog pi keeps up to date, read
    again only when it changes; {} if it cannot be read. models.json, which can carry API keys, is never
    opened."""
    file = ROOT / "models-store.json"
    key = (str(file), reading.fingerprint(file))
    if key not in _windows:
        try:
            catalog = guards.as_dict(guards.json_object(file.read_bytes()))
        except OSError:
            catalog = {}
        table = {}
        for provider, entry in catalog.items():
            for m in map(guards.as_dict, guards.as_list(guards.as_dict(entry).get("models"))):
                name, window = guards.text(m.get("id")), guards.number(m.get("contextWindow"))
                if name and window:
                    table[(provider, name)] = int(window)
        _windows.clear()
        _windows[key] = table
    return _windows[key]


# The conversation

def _turns(lines):
    """The turns these lines tell, on the current branch. A turn goes from one message of the user to the next:
    it gathers the model's replies and its tool calls. pi does not note where a message comes from: every `user`
    message is from the user. The reasoning and the tool results are not returned."""
    objects = [guards.as_dict(guards.json_object(line)) for line in lines]
    branch, seen = _branch(objects), []
    for o in objects:
        m = guards.as_dict(o.get("message"))
        if o.get("type") != "message" or m.get("role") not in ("user", "assistant"):
            continue
        if guards.text(o.get("id")) and o["id"] not in branch:
            continue                          # a line of a branch that was left; a line without `id` is kept
        t = guards.iso(reading.seconds(o.get("timestamp")))
        content = m.get("content")            # a string, or a list of blocks
        blocks = [guards.as_dict(b) for b in guards.as_list(content)]
        text = content if isinstance(content, str) else "\n".join(
            b["text"] for b in blocks if b.get("type") == "text" and isinstance(b.get("text"), str))
        if m.get("role") == "user":
            if text.strip() and guards.text(o.get("id")):
                seen.append({"id": o["id"], "t": t, "from": "user", "text": guards.clip(text, 4000),
                             "replies": [], "tools": [], "end": None})
        elif seen:
            turn = seen[-1]
            if text.strip():
                turn["replies"].append({"t": t, "text": guards.clip(text, 8000)})
            for b in blocks:
                if b.get("type") == "toolCall" and guards.text(b.get("name")):
                    args = guards.as_dict(b.get("arguments"))
                    target = next((args[c] for c in TARGETS if guards.text(args.get(c))), None)
                    turn["tools"].append({"name": b["name"], "target": guards.clip(target, 160) or None})
            turn["end"] = t if m.get("stopReason") == "stop" else None
    return seen


def _branch(objects):
    """The identifiers of the lines of the current branch. pi's log is a tree: after going back (/tree), the
    lines of the branch that was left stay in the file. The current branch starts from the last line that carries
    an `id` and goes up from `parentId` to `parentId`, as long as the parent is among the lines read."""
    parents = {o["id"]: guards.text(o.get("parentId")) for o in objects if guards.text(o.get("id"))}
    branch, ident = set(), next(reversed(parents), None)
    while ident in parents and ident not in branch:      # neither beyond what is read, nor in circles
        branch.add(ident)
        ident = parents[ident]
    return branch
