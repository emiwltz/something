"""The OpenCode reader.

OpenCode keeps all its sessions in a SQLite database, and its Herdr integration says which one lives in a pane by
its identifier "ses_…". Each call opens the database read-only, reads through the indexes what it returns, and
closes it. A database that is missing, locked or of another shape is said by an OSError: never a silent empty state.
"""
import itertools
import json
import sqlite3
from contextlib import contextmanager
from pathlib import Path

from something import guards
from extensions import _reading as reading

HARNESS = "opencode"
ROOT = Path.home() / ".local" / "share" / "opencode"              # opencode.db: all the sessions
MODELS = Path.home() / ".cache" / "opencode" / "models.json"      # the context windows, by provider

TIMEOUT = 1               # seconds of waiting in front of a locked database
STATUSES = {"pending": "pending", "in_progress": "in_progress", "completed": "done"}
RECENT = 2 * 3600         # silent for longer: a subagent is no longer listed, a tool is no longer running
ALIVE = 120               # without an end mark, a subagent that wrote more recently than that is working
ALIVE_TOOL = 15 * 60      # the same delay when one of its tools is open: a tool can last
SUBAGENTS_MAX = 50
TOKENS = ("tokens.input", "tokens.output", "tokens.reasoning", "tokens.cache.read", "tokens.cache.write")
TARGETS = ("filePath", "command", "pattern", "url", "description", "name", "query")    # of a tool call
NEVER = 1 << 62           # a date no message reaches: the bound of a read from the end
BLANKS = "".join(filter(str.isspace, map(chr, range(0x3001))))    # those of str.strip: the database judges as _turns
# The last write of a session `s`: its own row is only touched again at the end of a reply from the model.
WRITTEN = """max(s.time_updated, (SELECT ifnull(max(time_updated), 0) FROM message WHERE session_id = s.id),
               (SELECT ifnull(max(time_updated), 0) FROM part WHERE session_id = s.id))"""

_cache = {}       # fingerprints of the database → {session identifier: what _read_session drew from it}
_windows = {}     # (path of models.json, its fingerprint) → {(provider, model): window}


def session(agent):
    """A pane's session according to Herdr: {"id", "path"} (the path is the database's). None if Herdr gives no
    session identifier, or if the database does not know it."""
    ref = guards.as_dict(guards.as_dict(agent).get("agent_session"))
    ident = guards.text(ref.get("value"))
    if ref.get("kind") != "id" or ident is None:
        return None
    with _database() as db:
        known = db.execute("SELECT 1 FROM session WHERE id = ?", (ident,)).fetchone()
    return {"id": ident, "path": str(ROOT / "opencode.db")} if known else None


def read(session, now):
    """Everything the database says of the session, under the README's keys; None for what it does not say. The
    database is read again only if it changed, itself or the "-wal" log through which OpenCode writes to it. A tool
    left open in a session silent for two hours is no longer said to be running: the reply was abandoned. A question
    asked stays, though: the agent can wait for it a long time. Raises OSError if the database cannot be read."""
    path = ROOT / "opencode.db"
    mark = reading.fingerprint(path), reading.fingerprint(f"{path}-wal")
    if mark not in _cache:
        _cache.clear()                # the database changed: everything read from it is stale
    cached = _cache.setdefault(mark, {})
    if session["id"] not in cached:
        with _database() as db:
            cached[session["id"]] = _read_session(db, session["id"])
    state, children = cached[session["id"]]
    if state["request"] is None and now - (reading.seconds(state["activity"]) or 0) >= RECENT:
        state = {**state, "tool": None}
    return {**state, "subagents": _subagents(children, now)}


def turns(session, limit=20, before=None):
    """{"turns", "older", "before"}: the last `limit` turns of the conversation, or those that precede the turn of
    identifier `before`. The database returns only this page: the messages that open its turns (received, with a
    non-blank text, as _turns knows them), then what was said from the oldest one to the bound. Raises LookupError
    if `before` is not a message of the session."""
    ident, limit, bound = session["id"], max(1, limit), (NEVER, "")
    with _database() as db:
        if before is not None:
            row = db.execute("SELECT time_created FROM message WHERE id = ? AND session_id = ?",
                             (before, ident)).fetchone()
            if row is None:
                raise LookupError("none of this session's turns carries this identifier")
            bound = (row[0], before)
        openers = db.execute(f"""
            SELECT m.time_created, m.id FROM message m
            WHERE m.session_id = ? AND (m.time_created, m.id) < (?, ?) AND {_json('m.data', 'role')} = 'user'
              AND EXISTS (SELECT 1 FROM part p WHERE p.message_id = m.id AND {_json('p.data', 'type')} = 'text'
                          AND {_json('p.data', 'text', fn='json_type')} = 'text'
                          AND trim({_json('p.data', 'text')}, ?) <> '')
            ORDER BY m.time_created DESC, m.id DESC LIMIT ?""", (ident, *bound, BLANKS, limit + 1)).fetchall()
        older, openers = len(openers) > limit, openers[:limit]
        rows = db.execute(f"""
            SELECT m.id, m.time_created, {_json('m.data', 'role', 'finish', 'error.name', 'time.completed')},
                   {_json('p.data', 'type', 'text', 'synthetic', 'tool', *('state.input.' + c for c in TARGETS))}
            FROM message m LEFT JOIN part p ON p.message_id = m.id
            WHERE m.session_id = ? AND (m.time_created, m.id) >= (?, ?) AND (m.time_created, m.id) < (?, ?)
            ORDER BY m.time_created, m.id, p.id""", (ident, *openers[-1], *bound)).fetchall() if openers else []
    return {"turns": _turns(rows), "older": older, "before": openers[-1][1] if older else None}


# The database

@contextmanager
def _database():
    """OpenCode's database, opened read-only for the time of a call, never kept, without creating a file next to
    it (reading.database). Missing, locked, or without an expected table or column (OpenCode has already changed
    its storage): an OSError says so."""
    path = ROOT / "opencode.db"
    try:
        with reading.database(path, TIMEOUT) as connection:
            yield connection
    except sqlite3.Error as e:
        raise OSError(f"OpenCode's database cannot be read ({e}): {guards.tilde(str(path))}") from e


def _json(column, *paths, fn="json_extract"):
    """The SQL that draws these paths from a JSON column: the value of a single path, a JSON array of several
    (with `fn="json_type"`: the JSON type of the value, "text" for a string). This way the database returns only
    what is useful, never a tool's output (up to 4 MB), and a column that is not JSON is worth NULL instead of
    making the query fail."""
    return "{2}(CASE WHEN json_valid({0}) THEN {0} END, {1})".format(
        column, ", ".join(f"'$.{path}'" for path in paths), fn)


def _values(array, n):
    """The n values of an array returned by _json, typed as OpenCode wrote them; n times None if it is missing."""
    try:
        values = json.loads(array)
    except (ValueError, TypeError, RecursionError):
        values = None
    return values if isinstance(values, list) and len(values) == n else [None] * n


# What the database says of a session

def _read_session(db, ident):
    """(the session's state without its subagents, its descendants as _subagents expects them).
    FileNotFoundError if the session is no longer in the database."""
    row = db.execute(f"""SELECT title, {_json('model', 'providerID', 'id', 'variant')}, cost, {WRITTEN}
                         FROM session s WHERE id = ?""", (ident,)).fetchone()
    if row is None:
        raise FileNotFoundError("the session is no longer in OpenCode's database")
    title, chosen, cost, written = row
    provider, model, effort = _values(chosen, 3)
    chosen = _name(provider, model)         # the chosen model; without it, the one that replied last
    last, opened = _last(db, ident)
    todos = db.execute("SELECT content, status FROM todo WHERE session_id = ? ORDER BY position", (ident,))
    return {
        "title": guards.text(title),
        "model": chosen or last.get("model"),
        "effort": guards.text(effort) if chosen else last.get("effort"),
        "context": _context(db, ident),
        # 0: a subscription or a free model, the cost is not known; nor is one too small to be written
        "cost": round(guards.number(cost) or 0, 4) or None,
        "tool": {"name": opened[-1][0], "since": guards.iso(reading.seconds(opened[-1][1]))} if opened else None,
        "request": _request(opened),
        "todos": [{"text": text, "status": STATUSES[status], "phase": None}
                  for text, status in todos if guards.text(text) and status in STATUSES],
        "goal": None,
        "activity": guards.iso(reading.seconds(written)),
    }, _children(db, ident)


def _name(provider, model):
    """The name "provider/model", as OpenCode writes it, or None if one of the two is missing."""
    return f"{provider}/{model}" if guards.text(provider) and guards.text(model) else None


def _outcome(finish, error):
    """What a reply says of the end of the turn: failed if it carries an error (an abort is one), done if the
    model stopped by itself, None if it goes on or if nothing says so."""
    return "failed" if guards.text(error) else "done" if finish == "stop" else None


def _last(db, ident):
    """(the model's last reply, its tools still open). Of the reply: {"model", "effort", "outcome", "end"}, or {}
    if there is none. Of each tool: [name, start, questions asked]. A running tool is always in the last reply,
    even if a message has been received since; but that message restarts the turn, and the reply no longer says
    its end."""
    row = db.execute(f"""
        SELECT id, {_json('data', 'providerID', 'modelID', 'variant', 'finish', 'error.name', 'time.completed')},
               EXISTS (SELECT 1 FROM message r WHERE r.session_id = m.session_id
                       AND (r.time_created, r.id) > (m.time_created, m.id) AND {_json('r.data', 'role')} = 'user')
        FROM message m WHERE session_id = ? AND {_json('data', 'role')} = 'assistant'
        ORDER BY time_created DESC, id DESC LIMIT 1""", (ident,)).fetchone()
    if row is None:
        return {}, []
    provider, model, effort, finish, error, completed = _values(row[1], 6)
    outcome = None if row[2] else _outcome(finish, error)
    opened = db.execute(f"""
        SELECT {_json('data', 'tool', 'state.time.start', 'state.input.questions')} FROM part
        WHERE message_id = ? AND {_json('data', 'state.status')} IN ('pending', 'running')
        ORDER BY id""", (row[0],))
    opened = [tool for tool in (_values(row[0], 3) for row in opened) if guards.text(tool[0])]
    return {"model": _name(provider, model), "effort": guards.text(effort), "outcome": outcome,
            "end": guards.iso(reading.seconds(completed)) if outcome else None}, opened


def _context(db, ident):
    """The context, counted as OpenCode counts it: all the tokens (input, output, reasoning, cache) of the last
    reply that produced some; an interrupted reply, with zero tokens, measures nothing. Their share of the window
    is given when models.json knows that of the model that replied."""
    row = db.execute(f"""
        SELECT {_json('data', 'providerID', 'modelID', *TOKENS)} FROM message
        WHERE session_id = ? AND {_json('data', 'tokens.output')} > 0
        ORDER BY time_created DESC, id DESC LIMIT 1""", (ident,)).fetchone()
    provider, model, *tokens = _values(row and row[0], 2 + len(TOKENS))
    if None in map(guards.number, tokens):
        return None
    tokens = int(sum(tokens))
    window = _known_windows().get((guards.text(provider), guards.text(model)))
    percent = min(100, round(100 * tokens / window)) if window else None
    return {"tokens": tokens, "window": window, "percent": percent}


def _known_windows():
    """{(provider, model): context window} according to models.json, read again only when it changes; {} if it
    cannot be read. The window of one model changes from one provider to another: its name alone is not enough."""
    key = (str(MODELS), reading.fingerprint(MODELS))
    if key not in _windows:
        try:
            catalog = guards.as_dict(guards.json_object(MODELS.read_bytes()))
        except OSError:
            catalog = {}
        table = {}
        for provider, entry in catalog.items():
            for name, model in guards.as_dict(guards.as_dict(entry).get("models")).items():
                window = guards.number(guards.as_dict(guards.as_dict(model).get("limit")).get("context"))
                if window:
                    table[(provider, name)] = int(window)
        _windows.clear()
        _windows[key] = table
    return _windows[key]


def _request(opened):
    """The question of an open `question` tool, or None. An awaited permission is written nowhere."""
    for name, _, asked in reversed(opened):
        if name != "question":
            continue
        questions = []
        for q in map(guards.as_dict, guards.as_list(asked)):
            options = [guards.text(guards.as_dict(o).get("label")) for o in guards.as_list(q.get("options"))]
            if guards.text(q.get("question")):
                questions.append({"question": q["question"], "options": [o for o in options if o],
                                  "multi": q.get("multiple") is True})
        return {"kind": "question", "questions": questions}
    return None


# The subagents: the sessions born of this one (`parent_id`), and theirs

def _children(db, ident):
    """[(last write, outcome, is a tool open, the subagent without its state)]: the fifty descendants that wrote
    most recently, by start. The state depends on the time: _subagents sets it."""
    rows = db.execute(f"""
        WITH RECURSIVE lineage(id) AS (
            SELECT id FROM session WHERE parent_id = ?
            UNION SELECT s.id FROM session s JOIN lineage ON s.parent_id = lineage.id)
        SELECT * FROM (
            SELECT s.id, s.parent_id, s.title, s.agent, {_json('s.model', 'providerID', 'id')}, s.time_created,
                   {WRITTEN} AS written
            FROM session s JOIN lineage USING (id) ORDER BY written DESC LIMIT {SUBAGENTS_MAX})
        ORDER BY time_created, id""", (ident,)).fetchall()
    children = []
    for child, parent, title, kind, chosen, created, written in rows:
        last, opened = _last(db, child)
        children.append((reading.seconds(written) or 0, last.get("outcome"), bool(opened), {
            "id": child, "name": guards.text(title), "type": guards.text(kind),
            "parent": None if parent == ident else parent,
            "model": _name(*_values(chosen, 2)) or last.get("model"),
            "start": guards.iso(reading.seconds(created)), "end": last.get("end")}))
    return children


def _subagents(children, now):
    """The subagents that wrote less than two hours ago. Without an end mark, "working" is only said of the one
    that has just written: it is not a proof, and beyond that it is "unknown"."""
    seen = []
    for written, outcome, tool, child in children:
        age = now - written
        if age < RECENT:
            alive = age < (ALIVE_TOOL if tool else ALIVE)
            seen.append({**child, "state": outcome or ("working" if alive else "unknown")})
    return seen


# The conversation

def _turns(rows):
    """The turns these rows tell, one per part, in order. A turn opens at each received message that carries a
    text, and gathers the replies and the tool calls up to the next one. A text OpenCode added itself (`synthetic`:
    an attached file, a nudge) is returned only if nothing was typed: the turn is then the system's. Reasoning and
    tool results are not returned."""
    found = []
    for (ident, created, message), parts in itertools.groupby(rows, key=lambda row: row[:3]):
        role, finish, error, completed = _values(message, 4)
        parts = [_values(row[3], 4 + len(TARGETS)) for row in parts]
        texts = [(p[1], p[2] is True) for p in parts if p[0] == "text" and isinstance(p[1], str) and p[1].strip()]
        t = guards.iso(reading.seconds(created))
        if role == "user" and texts:
            typed = [text for text, added in texts if not added]
            found.append({"id": ident, "t": t, "from": "user" if typed else "system",
                          "text": guards.clip("\n".join(typed or [text for text, _ in texts]), 4000),
                          "replies": [], "tools": [], "end": None})
        elif role == "assistant" and found:
            turn = found[-1]
            turn["replies"] += [{"t": t, "text": guards.clip(text, 8000)} for text, _ in texts]
            for kind, _, _, tool, *targets in parts:
                if kind == "tool" and guards.text(tool):
                    target = next((c for c in targets if guards.text(c)), None)
                    turn["tools"].append({"name": tool, "target": guards.clip(target, 160) or None})
            turn["end"] = guards.iso(reading.seconds(completed)) if _outcome(finish, error) else None
    return found
