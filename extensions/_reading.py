"""The readers' toolbox: read a session without ever raising, and without writing anything.

A coding agent writes its session to a JSONL file, or to a SQLite database, while it is being read: a line can be
cut, a file can weigh hundreds of MB. These helpers serve the extensions, which import them with
`from extensions import _reading as reading`; the core does not use them. The file's name starts with "_": something
does not load it as an extension. No helper raises for unexpected content: an unreadable line is skipped. The type
guards come from the core, `something.guards`.
"""
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

from something.guards import tilde

TAIL = 512 * 1024                     # what is read from the end of a log at each poll
CONVERSATION_MAX = 16 * 1024 * 1024   # the longest end of a log read again to return a conversation
BLOCK = 4 * 1024 * 1024               # what is loaded at a time from a log followed in full
SECONDS_MAX = 32503680000             # year 3000: beyond that, it is not a date


def seconds(value):
    """A log date (ISO text, Unix seconds or milliseconds) as Unix seconds, or None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        if not 0 <= value <= SECONDS_MAX * 1000:        # NaN included; an oversized integer does not divide
            return None
        v = value / 1000 if value > 1e11 else value
    else:
        try:
            v = datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
        except (ValueError, OverflowError, OSError):
            return None
    return v if 0 <= v <= SECONDS_MAX else None


def fingerprint(path):
    """(size, modification date, inode) of a file, or None if it does not exist: the key of any read cache.
    The inode changes when the file is replaced by another."""
    try:
        st = os.stat(path)
    except (OSError, ValueError, TypeError):
        return None
    return st.st_size, st.st_mtime_ns, st.st_ino


def tail_lines(path, size=TAIL):
    """The whole lines of the end of a file. The first line read is dropped if it may be cut, the last one too if
    it does not end with a newline. [] if the file cannot be read."""
    try:
        total = os.stat(path).st_size
        with open(path, "rb") as f:
            f.seek(max(0, total - size))
            raw = f.read()
    except (OSError, ValueError, TypeError):
        return []
    lines = raw.split(b"\n")
    if lines and lines[-1]:
        lines = lines[:-1]         # line being written
    if total > size:
        lines = lines[1:]          # line perhaps cut at the start of the window
    return [l.decode("utf-8", "replace") for l in lines if l]


def lines_from(path, position=0):
    """Yields (line, position after it) for each whole line written from `position` on. The file is read in
    blocks, never loaded in full; a line longer than a block is put back together, the line being written is not
    returned. Nothing if the file cannot be read. Used to follow a whole log without reading it again at each poll:
    the caller keeps the position, and starts again from zero if the file has shrunk or changed inode."""
    try:
        with open(path, "rb") as f:
            f.seek(position)
            rest = b""
            for block in iter(lambda: f.read(BLOCK), b""):
                *whole, rest = (rest + block).split(b"\n")
                for line in whole:
                    position += len(line) + 1
                    if line:
                        yield line.decode("utf-8", "replace"), position
    except (OSError, ValueError, TypeError):
        return


def page(path, turns, limit=20, before=None):
    """{"turns", "older", "before"}: the last `limit` turns of a log, or those that precede the turn of identifier
    `before`. `turns(lines)` returns the turns that lines carry, from the oldest to the most recent. The end of the
    log is read first, then an end four times longer as long as it is not enough, up to CONVERSATION_MAX: beyond
    that, older turns may exist (`older`) but are not read. FileNotFoundError if the log does not exist, LookupError
    if `before` is not in what is read."""
    mark = fingerprint(path)
    if mark is None:
        raise FileNotFoundError(f"the session's log does not exist: {tilde(str(path))}")
    total, size, limit = mark[0], TAIL, max(1, limit)
    while True:
        read = turns(tail_lines(path, size))
        end = len(read) if before is None else next((i for i, turn in enumerate(read) if turn["id"] == before), None)
        if size >= min(total, CONVERSATION_MAX) or (end is not None and end > limit):
            break
        size = min(size * 4, CONVERSATION_MAX)
    if end is None:
        raise LookupError("none of the turns read carries this identifier")
    returned = read[max(0, end - limit):end]
    older = end > len(returned) or total > size
    return {"turns": returned, "older": older, "before": returned[0]["id"] if older and returned else None}


@contextmanager
def database(path, timeout=1):
    """A SQLite database opened read-only for the time of a `with` block, without writing anything next to it. A
    database nobody holds (no -shm file, no filled -wal file) is read as immutable: otherwise SQLite would create
    its -shm and -wal files in another program's folder. Raises sqlite3.Error if it does not open."""
    path = Path(path)
    held = os.path.exists(f"{path}-shm") or (fingerprint(f"{path}-wal") or (0,))[0] > 0
    connection = sqlite3.connect(path.as_uri() + ("?mode=ro" if held else "?mode=ro&immutable=1"),
                                 uri=True, timeout=timeout)
    try:
        yield connection
    finally:
        connection.close()
