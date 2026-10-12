"""something's routes: the page, the state, its stream, an agent's conversation, the message to an agent.

The server listens on 127.0.0.1 only and refuses any host and any origin that are not local. An error always has
the shape {"error": "sentence"}; no request ends with a Python traceback. The contract: README.md, "The routes".
"""
import json
import os
import socket
import traceback
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
from urllib.parse import parse_qs, unquote

from . import guards, herdr

ROUTES = {"/api/state": ("GET", "_state"), "/api/stream": ("GET", "_stream"),
          "/api/conversation": ("GET", "_conversation"), "/api/message": ("POST", "_message")}
TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
         ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml",
         ".png": "image/png", ".jpg": "image/jpeg", ".woff2": "font/woff2"}
BODY_MAX = 16 * 1024          # bytes of a message's body
DRAIN_MAX = 1024 * 1024       # what is still read of a body that is too big before refusing it
TEXT_MAX = 4000               # characters of a message
TURNS, TURNS_MAX = 20, 50     # turns of a conversation: by default, at most
HEARTBEAT = 15                # seconds without a change before a comment on the stream
GONE = (ConnectionError, socket.timeout)      # the client left, or its connection stayed blocked


class HttpError(Exception):
    """A refusal to return as is: HttpError(HTTP code, sentence)."""


def server(poller, port, pages):
    """Opens the server on 127.0.0.1. `poller`: a `Poller`, or what offers its `state`, `wait`, `raw` and `send`;
    `pages`: the folder served at the root. Raises OSError if the port is taken or forbidden, OverflowError if it
    is outside 0 to 65535."""
    s = Server(("127.0.0.1", port), Handler)
    s.poller, s.pages, s.hosts = poller, os.path.realpath(pages), _hosts(s.server_port)
    return s


def _hosts(port):
    """The addresses a request may name for a server on this port. A browser leaves ":80" out of what it asks:
    on that port, the two names alone are this server too."""
    names = ["127.0.0.1", "localhost"]
    return [f"{name}:{port}" for name in names] + (names if port == 80 else [])


class Server(ThreadingHTTPServer):
    """The listening server, opened without asking the system for a name."""

    def server_bind(self):
        """http.server looks the name of the address up here, for a `server_name` that something never reads. On
        some machines that question goes to the network and holds the start for many seconds."""
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class Handler(BaseHTTPRequestHandler):
    """One request: the guard, the route, and the net that gives any refusal, any failure, the shape of an error."""

    timeout = 30                    # seconds of a read or a write blocked on the connection

    def _request(self):
        path = self.path.partition("?")[0]
        method, route = ROUTES.get(path, ("GET", None))
        try:
            origin = self.headers.get("Origin")
            if self.headers.get("Host") not in self.server.hosts or (
                    origin is not None and origin not in ["http://" + host for host in self.server.hosts]):
                raise HttpError(403, "host or origin refused: something only answers the pages it serves")
            if self.command != method:
                raise HttpError(405, "method not allowed")
            if route:
                getattr(self, route)()
            else:
                self._file(path)
        except HttpError as e:
            self._error(*e.args)
        except GONE:
            pass
        except Exception:
            traceback.print_exc()   # the detail stays on stderr
            self._error(500, "internal server error")

    do_GET = do_POST = _request

    def send_error(self, code, message=None, explain=None):
        """The library's refusals (unreadable request, unknown method) take the shape of ours."""
        if code == 501:
            self._error(405, "method not allowed")
        else:
            self._error(400, "invalid request")

    def log_error(self, *args):
        pass                        # a connection the browser opens ahead, then leaves silent, is not a failure

    def log_request(self, code="-", size="-"):
        if isinstance(code, int) and code >= 400:       # the access log only says refusals and failures
            # ascii(): what a client wrote reaches the terminal as text, whatever the version of Python
            self.log_message("%s %s", ascii(self.requestline), code)

    def end_headers(self):
        # A browser asks for a frame without an Origin, so the guard above lets it through: another site could lay
        # the page, invisible, over its own content and steer a click onto a button that sends a message. Only a
        # page at this same address may show an answer in a frame.
        self.send_header("Content-Security-Policy", "frame-ancestors 'self'")
        super().end_headers()

    def _respond(self, code, type_, body):
        self.send_response(code)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj):
        self._respond(code, TYPES[".json"], json.dumps(obj).encode())

    def _error(self, code, sentence):
        try:
            self._json(code, {"error": sentence})
        except GONE:
            pass                    # nobody is there any more to read the refusal

    def _file(self, path):
        page = _page(self.server.pages, path)
        if page is None:
            raise HttpError(404, "unknown file")
        self._respond(200, *page)

    def _state(self):
        self._json(200, self.server.poller.state())

    def _stream(self):
        """Pushes the state right away, then at each change, as long as the client is there and the server open."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        version = None
        while self.server.socket.fileno() >= 0:         # as long as the server has not closed its listening socket
            seen, state = self.server.poller.wait(version, HEARTBEAT)
            if seen == version:
                self.wfile.write(b": heartbeat\n\n")
            else:
                self.wfile.write(b"event: state\ndata: " + json.dumps(state).encode() + b"\n\n")
            version = seen

    def _conversation(self):
        q = {key: values[0] for key, values in parse_qs(self.path.partition("?")[2]).items()}
        _, reader, session = self._agent(q.get("agent"))
        if reader is None:
            raise HttpError(404, "something has no reader for this agent's harness: no conversation")
        if not callable(getattr(reader, "turns", None)):
            raise HttpError(404, "this harness's reader cannot return the conversation")
        if session is None:
            raise HttpError(404, "this agent is not linked to any session: no conversation")
        try:
            limit = int(q.get("turns", TURNS))
        except ValueError:
            limit = 0
        if limit < 1:
            raise HttpError(400, '"turns" must be a whole number, 1 at least')
        try:
            page = reader.turns(session, min(limit, TURNS_MAX), q.get("before"))
        except LookupError:
            if "before" not in q:
                raise               # no cursor was asked for: it is a failure of the reader
            raise HttpError(404, '"before" does not designate any turn of this conversation') from None
        except OSError as e:
            raise HttpError(502, f"the log cannot be read: {e.strerror or type(e).__name__}") from None
        self._json(200, {"agent": q["agent"], **page})

    def _message(self):
        if self.headers.get("X-Something") != "1":
            raise HttpError(403, 'the "X-Something: 1" header is missing')
        body = self._body()
        agent, text = body.get("agent"), body.get("text")
        if not isinstance(agent, str) or not isinstance(text, str):
            raise HttpError(400, '"agent" and "text" are required, two texts')
        text = text.strip()
        if not text:
            raise HttpError(400, "the message is empty")
        if len(text) > TEXT_MAX:
            raise HttpError(400, "the message exceeds 4,000 characters")
        if any(unicodedata.category(c) == "Cc" and c not in "\n\t" for c in text):
            raise HttpError(400, "the message contains a control character")
        self._agent(agent)
        try:
            self.server.poller.send(agent, text)
        except herdr.Refused as e:
            if e.code == "agent_blocked":
                raise HttpError(409, "this agent is waiting for an answer in its pane: "
                                     "something does not write over a question") from None
            raise HttpError(502, f"Herdr refuses the message: {e.message}") from None
        except herdr.Unavailable as e:
            raise HttpError(502, f"Herdr does not answer: {e}") from None
        self._json(200, {"ok": True})

    def _agent(self, ident):
        """What the poller knows of the agent `ident` (see Poller.raw), or the 404 refusal."""
        found = self.server.poller.raw(ident) if isinstance(ident, str) else None
        if found is None:
            raise HttpError(404, "unknown agent")
        return found

    def _body(self):
        """The body of the request, a JSON object of 16 KB at most."""
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            length = -1
        if length < 0:
            raise HttpError(400, "the body's length is missing or unreadable")
        if length > BODY_MAX:
            # Read what the client is already sending: closing on an unread body would cut its connection before
            # it has received the refusal.
            self.rfile.read(min(length, DRAIN_MAX))
            raise HttpError(413, "the body exceeds 16 KB")
        obj = guards.json_object(self.rfile.read(length))
        if obj is None:
            raise HttpError(400, "the body must be a JSON object")
        return obj


def _page(pages, path):
    """(type, content) of the file of `pages` that a request's path designates; None for a hidden component, an
    unknown type, a file that is missing or outside the folder once links are followed."""
    parts = [p for p in unquote(path).split("/") if p] or ["index.html"]
    type_ = TYPES.get(os.path.splitext(parts[-1])[1].lower())
    if type_ is None or any(p.startswith(".") for p in parts):
        return None
    try:
        target = os.path.realpath(os.path.join(pages, *parts))
        if not target.startswith(pages + os.sep):
            return None
        with open(target, "rb") as f:
            return type_, f.read()
    except (OSError, ValueError):
        return None
