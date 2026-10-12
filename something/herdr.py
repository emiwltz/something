"""Herdr's socket: one request, one response.

something never runs the `herdr` command. It talks to its Unix socket, one JSON line per message and one connection per
request. The core calls only three methods there: `ping` and `session.snapshot` to read, `agent.prompt` to write.
An extension can open one more, a read: `pane.process_info`.
"""
import json
import os
import socket

from . import guards

METHODS = frozenset({"ping", "session.snapshot", "agent.prompt"})    # what the core calls, and nothing else
# What an extension may ask to open: a read of Herdr, never an action. Allowing another one means changing the core.
READS = frozenset({"pane.process_info"})
opened = set()       # the reads that the loaded extensions asked for
STATES = frozenset({"working", "blocked", "done", "idle"})    # Herdr's own words; anything else: "unknown"
FAILURES = {FileNotFoundError: "socket missing", ConnectionRefusedError: "connection refused",
            socket.timeout: "timed out"}


class Unavailable(Exception):
    """Herdr does not answer: socket missing, refused, timeout, unreadable response. The message says which."""


class Refused(Exception):
    """Herdr answered with an error. `code` is its code ("agent_blocked", for instance), `message` its text."""

    def __init__(self, code, message):
        super().__init__(f"{code}: {message}")
        self.code, self.message = code, message


def socket_path():
    """The path of the socket: $HERDR_SOCKET_PATH, otherwise the default session's."""
    return os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")


def open_reads(methods):
    """Opens reads of Herdr at an extension's request. ValueError if one is not in READS: Herdr has no read-only
    mode, and this list bounds what an extension can declare."""
    refused = sorted(set(methods) - READS)
    if refused:
        raise ValueError(f"Herdr method not allowed to an extension: {', '.join(refused)}")
    opened.update(methods)


def call(method, params=None, timeout=5):
    """Sends a request and returns the `result` of the response. Raises Unavailable if Herdr does not answer,
    Refused if it answers with an error, ValueError (without sending anything) for a method something may not call."""
    if method not in METHODS and method not in opened:
        raise ValueError(f"Herdr method not allowed: {method!r}")
    request = json.dumps({"id": "something", "method": method, "params": params or {}}) + "\n"
    path = socket_path()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(path)
            s.sendall(request.encode())
            buffer = b""
            while not buffer.endswith(b"\n"):      # a long response arrives in several chunks
                chunk = s.recv(65536)
                if not chunk:
                    break
                buffer += chunk
    except OSError as e:
        reason = FAILURES.get(type(e), e.strerror or str(e) or type(e).__name__)
        raise Unavailable(f"{reason} ({guards.tilde(path)})") from e
    if not buffer:
        raise Unavailable("connection closed without a response")
    response = guards.as_dict(guards.json_object(buffer.decode("utf-8", "replace")))
    error, result = response.get("error"), response.get("result")
    if isinstance(error, dict):
        raise Refused(guards.text(error.get("code")) or "unknown",
                      guards.text(error.get("message")) or "refused without explanation")
    if not isinstance(result, dict):
        raise Unavailable("unreadable response")
    return result


def version():
    """Herdr's version and its protocol's; None for what `ping` does not say."""
    pong = call("ping")
    protocol = pong.get("protocol")
    return {"version": guards.text(pong.get("version")),
            "protocol": protocol if type(protocol) is int else None}


def snapshot():
    """Herdr's whole tree in one read: workspaces, tabs, panes and agents."""
    snap = call("session.snapshot").get("snapshot")
    if not isinstance(snap, dict):
        raise Unavailable("unreadable snapshot")
    return snap


def send(target, text):
    """Carries a message to an agent: Herdr types the text in its pane, then Enter. `target`: the pane's
    identifier. The response confirms the sending, not the start of a turn. Refused with code `agent_blocked` if the
    agent is waiting."""
    call("agent.prompt", {"target": target, "text": text})


def state(raw):
    """An `agent_status` of Herdr, kept in Herdr's words. What something does not know is "unknown", never "idle"."""
    return raw if isinstance(raw, str) and raw in STATES else "unknown"
