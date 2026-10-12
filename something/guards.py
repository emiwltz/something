"""Take a value that comes from elsewhere without ever raising.

What Herdr answers, what a request carries, what an agent writes in its session: a field can be missing, or have
another type than expected. These guards return the expected value or None, never an exception, and format what the
state shows: a date, a clipped text, a shortened path. The core and the extensions both use them. What reads session
files lives with the extensions: `extensions/_reading.py`.
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def json_object(line):
    """The JSON object of a line, or None if it is empty, cut, badly encoded or not an object."""
    try:
        o = json.loads(line)
    except (ValueError, RecursionError):
        return None
    return o if isinstance(o, dict) else None


def as_dict(x):
    """The dictionary, or an empty one if it is not a dictionary."""
    return x if isinstance(x, dict) else {}


def as_list(x):
    """The list, or an empty one if it is not a list."""
    return x if isinstance(x, list) else []


def text(x):
    """The text, or None if it is not one or if it is empty."""
    return x if isinstance(x, str) and x else None


def number(x):
    """A finite, non-negative number, or None (a boolean is not a number)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    return x if x == x and 0 <= x < 1e15 else None


def iso(seconds):
    """Unix seconds as an ISO 8601 date in local time, or None."""
    if number(seconds) is None:
        return None
    try:
        return datetime.fromtimestamp(seconds, timezone.utc).astimezone().isoformat(timespec="seconds")
    except (ValueError, OverflowError, OSError):
        return None


def clip(value, n):
    """A text brought down to n characters at most, edge whitespace removed; "…" marks the cut."""
    t = value.strip() if isinstance(value, str) else ""
    return t if len(t) <= n else t[: n - 1].rstrip() + "…"


def tilde(path):
    """A path with the home directory written "~", or None if it is not a text."""
    if not isinstance(path, str) or not path:
        return None
    home = str(Path.home())
    if path == home:
        return "~"
    return "~" + path[len(home):] if path.startswith(home + os.sep) else path
