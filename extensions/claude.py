"""The Claude Code reader.

Claude Code does not tell Herdr which session lives in a pane, but its registry files each live session under the
pid of its process (sessions/<pid>.json), and Herdr knows which processes run in the pane: the pid links them.
If Herdr does not say them, the folder then the title; an ambiguous link links nothing. The rest comes from the log
(projects/), from its tasks (tasks/) and from the logs of its subagents. Everything is read, nothing written.
"""
import os
import re
from pathlib import Path

from something import guards, herdr
from extensions import _reading as reading

HARNESS = "claude"
HERDR = {"pane.process_info"}         # the read of Herdr that says the processes of a pane
ROOT = Path.home() / ".claude"        # the tests replace it

TIMEOUT = 1               # seconds left to Herdr to say the processes of a pane; beyond that, we do without it
RECENT = 2 * 3600         # a subagent silent for longer no longer appears
SUBAGENTS_MAX = 50        # subagents returned, at most
ALIVE = 120               # without an end mark, a subagent silent for longer is no longer said to be working
ALIVE_TOOL = 15 * 60      # the same threshold when one of its tools runs: the log is only written when it returns
SMALL = 64 * 1024         # a whole JSON record, or the end of a subagent's log
TAIL_MAX = 4 * 1024 * 1024    # the end of the log read again when the first (reading.TAIL) carries no message
USAGE = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
STATUSES = {"pending": "pending", "in_progress": "in_progress", "completed": "done"}
OUTCOMES = {"started": None, "result": "done", "failed": "failed"}      # the lines of a workflow's log
TARGETS = ("file_path", "command", "pattern", "url", "query", "description", "skill", "scriptPath", "subject")

_ID = re.compile(r"[\w-]+")           # a session identifier: never a piece of a path
_CACHE = {}                           # (function, path) → (fingerprint of the file, value)
_FOLLOWED = {}                        # path of the log → what _followed has already read from it


def session(agent):
    """`agent`: Herdr's raw dictionary. Returns {"id", "path"} (absolute path of the log), or None if the pane does
    not safely link to a session. When Herdr says the processes of the pane, they alone link: the live session of
    one of them, if there is one and only one, otherwise None (a Claude Code that is starting does not have its
    record yet: the folder would designate another pane's session). When Herdr does not say them, the folder, then
    the terminal's title: None when no session lives in this folder, or several that the title does not tell apart."""
    agent = guards.as_dict(agent)
    registry, pids = _registry(), _pids(agent.get("pane_id"))
    if pids:                          # Herdr says the processes of the pane: they alone link, with no fallback
        candidates = [e for e in registry if e["pid"] in pids]
    else:                             # Herdr could say nothing: the folder's sessions, that the title tells apart
        folders = {_real(agent.get("cwd")), _real(agent.get("foreground_cwd"))} - {None}
        candidates = [e for e in registry if _real(e.get("cwd")) in folders]
    candidates = [{"id": e["sessionId"], "path": _log(e)} for e in candidates]
    if len(candidates) > 1 and not pids:
        title = guards.text(agent.get("terminal_title_stripped"))
        followed = [_followed(c["path"]) for c in candidates]
        candidates = [c for c, s in zip(candidates, followed) if title and title in (s["custom"], s["ai"])]
    return candidates[0] if len(candidates) == 1 else None


def read(session, now):
    """Everything the log says, under the README's keys. All the keys are present; an unknown value is None.
    Does not raise for unexpected content; raises OSError if the log is gone."""
    path = session["path"]
    written = _present(path)[1] / 1e9
    tail, followed = _memo(_tail, path), _followed(path)
    open_tools = list(tail["open"].values())      # in the order of the calls, which is the order they run in
    entry = next((e for e in _registry() if e["sessionId"] == session["id"]), {})
    tasks = _tasks(session["id"])
    return {
        "title": followed["custom"] or followed["ai"],
        "model": tail["model"],
        "effort": tail["effort"],
        "context": None if tail["tokens"] is None else {"tokens": tail["tokens"], "window": None, "percent": None},
        "cost": followed["cost"],
        "tool": {"name": open_tools[0]["name"], "since": open_tools[0]["since"]} if open_tools else None,
        "request": _request(open_tools, entry),
        "todos": _todos(followed["reminder"] if tasks is None else tasks),
        "goal": None,
        "subagents": _subagents(path, now),
        "activity": guards.iso(written),
    }


def turns(session, limit=20, before=None):
    """{"turns": [...], "older": bool, "before": cursor | None}. The last `limit` turns, or those that precede the
    turn of identifier `before`, read from the end of the log (reading.page). LookupError if `before` is not in
    what is read, OSError if the log is gone."""
    return reading.page(session["path"], _turns, limit, before)


# ── The link: the processes of the pane and the registry of live sessions ──

def _pids(pane):
    """The pids of the foreground processes of a pane, according to Herdr. No pid if Herdr does not say them (read
    not opened, failure, refusal, response of another shape): the link is then made without them."""
    if guards.text(pane) is None:
        return set()                  # without an identifier, the question would not designate this pane
    try:
        info = herdr.call("pane.process_info", {"pane_id": pane}, TIMEOUT).get("process_info")
    except (herdr.Unavailable, herdr.Refused, ValueError):
        return set()
    pids = [guards.as_dict(p).get("pid") for p in guards.as_list(guards.as_dict(info).get("foreground_processes"))]
    return {pid for pid in pids if type(pid) is int}


def alive(pid):
    """True if a process carries this pid. The tests replace this function."""
    try:
        os.kill(pid, 0)               # signal 0 sends nothing: it only asks whether the process exists
    except PermissionError:
        return True
    except (OSError, OverflowError):
        return False
    return True


def _registry():
    """The interactive sessions of the registry whose process is alive. A background session has no pane.
    Only the <pid>.json files are opened: the .key files next to them are secrets."""
    sessions = []
    for file in (ROOT / "sessions").glob("*.json"):
        entry = _record(file) if file.stem.isdigit() else {}
        pid = entry.get("pid")
        if (entry.get("kind") == "interactive" and _ID.fullmatch(guards.text(entry.get("sessionId")) or "")
                and type(pid) is int and pid > 0 and alive(pid)):
            sessions.append(entry)
    return sessions


def _log(entry):
    """The path of the log of a session of the registry: in the folder named after its cwd, otherwise in the only
    project folder that holds it (a moved session keeps its identifier)."""
    name = entry["sessionId"] + ".jsonl"
    expected = ROOT / "projects" / re.sub(r"[/. ]", "-", str(entry.get("cwd"))) / name
    elsewhere = [] if expected.is_file() else list((ROOT / "projects").glob("*/" + name))
    return str(elsewhere[0] if len(elsewhere) == 1 else expected)


def _present(path):
    """(size, date) of the log; FileNotFoundError if it does not exist, or not yet: a session that has just
    opened has written nothing."""
    mark = reading.fingerprint(path)
    if mark is None:
        raise FileNotFoundError("the session's log does not exist: " + str(guards.tilde(path)))
    return mark


def _real(path):
    """The real path of a folder, or None if it is not a path."""
    try:
        return os.path.realpath(path) if guards.text(path) else None
    except (OSError, ValueError):
        return None


def _record(path):
    """The object of a small JSON file (registry, subagent record, task), or {} if it cannot be read."""
    try:
        with open(path, "rb") as f:
            return guards.as_dict(guards.json_object(f.read(SMALL)))
    except OSError:
        return {}


def _memo(compute, path):
    """`compute(path)`, kept as long as the file changes neither size nor date."""
    key, mark = (compute.__name__, path), reading.fingerprint(path)
    if key not in _CACHE or _CACHE[key][0] != mark:
        if len(_CACHE) >= 1000:
            _CACHE.clear()            # a simple bound: everything is computed again at the next poll
        _CACHE[key] = (mark, compute(path))
    return _CACHE[key][1]


# ── The log: what must be followed in full, and what its end is enough to say ──

def _followed(path):
    """What can be written anywhere in the log: the titles, the cost, the last reminder of the tasks.
    Only the lines added since the previous call are read; a log that has shrunk, or that another file has
    replaced, is read again from the start."""
    mark = reading.fingerprint(path) or (0, 0, None)      # missing: like an empty log
    s = _FOLLOWED.get(path)
    if s is None or mark[0] < s["position"] or mark[2] != s["inode"]:
        if len(_FOLLOWED) >= 100:
            _FOLLOWED.clear()
        s = _FOLLOWED[path] = {"custom": None, "ai": None, "cost": None, "reminder": None, "position": 0,
                               "inode": mark[2]}
    for line, s["position"] in reading.lines_from(path, s["position"]):         # the position follows the reading
        o = guards.as_dict(guards.json_object(line))
        kind, attached = o.get("type"), guards.as_dict(o.get("attachment"))
        if kind == "custom-title":
            s["custom"] = guards.text(o.get("customTitle")) or s["custom"]
        elif kind == "ai-title":
            s["ai"] = guards.text(o.get("aiTitle")) or s["ai"]
        elif kind == "cost-state" and guards.number(o.get("totalCostUSD")) is not None:
            s["cost"] = o["totalCostUSD"]
        elif attached.get("type") == "task_reminder" and isinstance(attached.get("content"), list):
            s["reminder"] = attached["content"]
    return s


def _tail(path, size=reading.TAIL):
    """What the end of a log says. If it carries no message from the assistant (big tool results fill it), a
    longer end is read."""
    seen = _scan(reading.tail_lines(path, size))
    return seen if seen["model"] else _scan(reading.tail_lines(path, TAIL_MAX))


def _scan(lines):
    """The last known model, effort and context, the tools called and not yet returned, and what the last
    conversation line says of the end (`ending`: done, failed or None)."""
    seen = {"model": None, "effort": None, "tokens": None, "open": {}, "ending": None}
    for line in lines:
        o = guards.as_dict(guards.json_object(line))
        kind, message = o.get("type"), guards.as_dict(o.get("message"))
        blocks = [guards.as_dict(b) for b in guards.as_list(message.get("content"))]
        if kind == "assistant":
            done = message.get("stop_reason") == "end_turn"
            seen["ending"] = "failed" if o.get("isApiErrorMessage") is True else "done" if done else None
            model = guards.text(message.get("model"))
            if model and model != "<synthetic>":        # a made-up line (interruption, error) measures nothing
                usage = guards.as_dict(message.get("usage"))
                parts = [guards.number(usage.get(c)) for c in USAGE]
                seen["model"] = model
                seen["effort"] = guards.text(o.get("effort")) or seen["effort"]
                tokens = None if None in parts else int(sum(parts))
                if tokens != 0:                         # a usage of zero measures nothing: the measure before stays
                    seen["tokens"] = tokens
            for b in blocks:
                name, ident = guards.text(b.get("name")), guards.text(b.get("id"))
                if b.get("type") == "tool_use" and name and ident:
                    since = guards.iso(reading.seconds(o.get("timestamp")))
                    seen["open"][ident] = {"name": name, "since": since, "input": guards.as_dict(b.get("input"))}
        elif kind == "user":
            returned = [guards.text(b.get("tool_use_id")) for b in blocks if b.get("type") == "tool_result"]
            for ident in returned:
                seen["open"].pop(ident, None)
            if not returned and o.get("isMeta") is not True:
                seen["open"].clear()                    # a new turn: no tool of the old one runs any more
            seen["ending"] = "done" if o.get("toolEndsTurn") is True else None
        elif kind == "system" and o.get("subtype") == "turn_duration":
            seen["open"].clear()
        elif kind == "system" and o.get("subtype") == "compact_boundary":
            seen["tokens"] = None                       # reduced context: unknown until the next message
    return seen


def _request(open_tools, entry):
    """What the agent waits for: the question it asks (the log carries it), otherwise a permission (only the
    registry says it). Either way it is about the first tool left without a result: the next ones have not
    started, and a question among them is not asked yet."""
    for tool in open_tools[:1]:
        if tool["name"] == "AskUserQuestion":
            questions = []
            for q in map(guards.as_dict, guards.as_list(tool["input"].get("questions"))):
                options = [guards.as_dict(option).get("label") for option in guards.as_list(q.get("options"))]
                if guards.text(q.get("question")):
                    questions.append({"question": q["question"], "options": [o for o in options if guards.text(o)],
                                      "multi": q.get("multiSelect") is True})
            return {"kind": "question", "questions": questions}
    if entry.get("status") == "waiting" and entry.get("waitingFor") == "permission prompt":
        return {"kind": "permission", "tool": open_tools[0]["name"] if open_tools else None}
    return None


# ── The tasks ──

def _tasks(ident):
    """The tasks of tasks/<session>, in the order of their number; None if the session does not have this folder."""
    folder = ROOT / "tasks" / ident
    try:
        files = [f for f in os.listdir(folder) if f.endswith(".json")]
    except OSError:
        return None
    return [_record(folder / f) for f in sorted(files, key=lambda f: (len(f), f))]      # "2" before "10"


def _todos(tasks):
    """From Claude Code's tasks (files of tasks/, or reminder of the log) to the todos of the state. A task with an
    unknown status is dropped; a pending task that another one, not yet done, holds back is said blocked."""
    tasks = [t for t in map(guards.as_dict, guards.as_list(tasks))
             if guards.text(t.get("subject")) and guards.text(t.get("status")) in STATUSES]
    unfinished = [t.get("id") for t in tasks if t["status"] != "completed"]
    todos = []
    for t in tasks:
        blocked = t["status"] == "pending" and any(b in unfinished for b in guards.as_list(t.get("blockedBy")))
        todos.append({"text": t["subject"], "status": "blocked" if blocked else STATUSES[t["status"]], "phase": None})
    return todos


# ── The subagents: those of the Agent tool and those of the workflows ──

def _subagents(path, now):
    """The subagents that wrote less than two hours ago, the fifty most recent at most, by start.
    Each has its log under <session>/subagents/; a workflow adds a journal.jsonl there that says who is done."""
    recent = []
    for f in Path(path[:-len(".jsonl")], "subagents").glob("**/agent-*.jsonl"):
        mark = reading.fingerprint(f)
        if mark and now - mark[1] / 1e9 < RECENT:
            recent.append((mark[1] / 1e9, str(f)))
    agents = []
    for written, f in sorted(recent)[-SUBAGENTS_MAX:]:
        a = _memo(_subagent, f)
        label, outcome = _memo(_workflow, os.path.join(os.path.dirname(f), "journal.jsonl")).get(a["id"], (None, None))
        threshold = ALIVE_TOOL if a["tool"] else ALIVE
        state = outcome or a["ending"] or ("working" if now - written < threshold else "unknown")
        agents.append({"id": a["id"], "name": label or a["name"], "type": a["type"], "parent": None, "state": state,
                       "model": a["model"], "start": a["start"],
                       "end": written if state in ("done", "failed") else None})
    agents.sort(key=lambda a: (a["start"] is None, a["start"] or 0))
    for a in agents:
        a["start"], a["end"] = guards.iso(a["start"]), guards.iso(a["end"])
    return agents


def _subagent(path):
    """What a subagent's files say about it: its .meta.json record, the start and the end of its log."""
    record, tail = _record(path[:-len("jsonl")] + "meta.json"), _tail(path, SMALL)
    try:
        with open(path, "rb") as f:
            start = guards.as_dict(guards.json_object(f.readline(reading.TAIL))).get("timestamp")
    except OSError:
        start = None
    return {"id": os.path.basename(path)[len("agent-"):-len(".jsonl")], "start": reading.seconds(start),
            "name": guards.text(record.get("description")), "type": guards.text(record.get("agentType")),
            "model": guards.text(record.get("model")) or tail["model"],
            "ending": tail["ending"], "tool": bool(tail["open"])}


def _workflow(path):
    """{agent identifier: (label, outcome)} from a workflow's log; the outcome is done, failed or None."""
    agents = {}
    for line, _ in reading.lines_from(path):
        o = guards.as_dict(guards.json_object(line))
        ident = guards.text(o.get("agentId"))
        if ident:
            label, outcome = agents.get(ident, (None, None))
            agents[ident] = (guards.text(o.get("label")) or label, OUTCOMES.get(guards.text(o.get("type")), outcome))
    return agents


# ── The conversation ──

def _turns(lines):
    """The turns these lines carry, from the oldest to the most recent. A message from the assistant is spread over
    several lines, one per block, that share `message.id`: their texts form a single reply. The reasoning is not
    returned. The lines before the first turn (a turn started higher up) are ignored."""
    turns, current = [], None       # `current`: the assistant's message that the last reply continues
    for line in lines:
        o = guards.as_dict(guards.json_object(line))
        t, opening = guards.iso(reading.seconds(o.get("timestamp"))), _opening(o)
        if opening and guards.text(o.get("uuid")):
            turns.append({"id": o["uuid"], "t": t, "from": opening[0], "text": guards.clip(opening[1], 4000),
                          "replies": [], "tools": [], "end": None})
            current = None
        elif turns and o.get("type") == "assistant":
            body = guards.as_dict(o.get("message"))
            ident = guards.text(body.get("id")) or guards.text(o.get("requestId")) or guards.text(o.get("uuid"))
            for b in map(guards.as_dict, guards.as_list(body.get("content"))):
                if b.get("type") == "text" and guards.text(b.get("text")):
                    if ident and ident == current:
                        turns[-1]["replies"][-1]["text"] += "\n\n" + b["text"]
                    else:
                        turns[-1]["replies"].append({"t": t, "text": b["text"]})
                        current = ident
                elif b.get("type") == "tool_use" and guards.text(b.get("name")):
                    args = guards.as_dict(b.get("input"))
                    target = next((args[c] for c in TARGETS if guards.text(args.get(c))), None)
                    turns[-1]["tools"].append({"name": b["name"], "target": guards.clip(target, 160) or None})
        elif turns and o.get("type") == "system" and o.get("subtype") == "turn_duration":
            turns[-1]["end"] = t
    for turn in turns:
        for reply in turn["replies"]:
            reply["text"] = guards.clip(reply["text"], 8000)
    return turns


def _opening(o):
    """(author, text) if the line opens a turn, otherwise None. Only a message of human origin is from the user;
    a notification, a local command or a compaction summary open a turn of the system. A message typed while the
    agent is working has no `user` line: it arrives as a `queued_command` attachment."""
    attached = guards.as_dict(o.get("attachment"))
    if attached.get("type") == "queued_command" and guards.as_dict(attached.get("origin")).get("kind") == "human":
        return "user", _text(attached.get("prompt"))
    content = guards.as_dict(o.get("message")).get("content")
    result = any(guards.as_dict(b).get("type") == "tool_result" for b in guards.as_list(content))
    if o.get("type") != "user" or o.get("isMeta") is True or result:
        return None
    return "user" if guards.as_dict(o.get("origin")).get("kind") == "human" else "system", _text(content)


def _text(content):
    """The text of a message content: a string, or the text blocks of a list of blocks."""
    if isinstance(content, str):
        return content
    blocks = [guards.as_dict(b) for b in guards.as_list(content)]
    return "\n\n".join(b["text"] for b in blocks if b.get("type") == "text" and guards.text(b.get("text")))
