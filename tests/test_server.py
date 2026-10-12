"""The server: each route, the guards, the refusals and the net. A real server on 127.0.0.1, on a free port, a real
`Poller` fed by a fake Herdr (functions of `something.herdr` replaced) and a fake reader. At the end, the same
server on the example.
"""
import copy
import http.client
import io
import json
import os
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import herdr, server as module       # noqa: E402
from something.__main__ import PAGES, Example       # noqa: E402
from something.poll import SESSION_KEYS, Poller     # noqa: E402

TURNS = {"turns": [{"id": "t1", "t": "2027-01-15T10:00:00+01:00", "from": "user", "text": "Hello",
                    "replies": [{"t": "2027-01-15T10:00:05+01:00", "text": "Hello to you"}],
                    "tools": [{"name": "Bash", "target": "ls"}], "end": "2027-01-15T10:00:06+01:00"}],
         "older": True, "before": "t1"}


def raw(pane, harness, status):
    """An agent of `session.snapshot.agents`, reduced to the required fields and to those something reads."""
    return {"terminal_id": "term_" + pane, "agent_status": status, "workspace_id": "w1", "tab_id": "w1:t1",
            "pane_id": pane, "focused": False, "revision": 3, "agent": harness, "cwd": "/tmp/trial",
            "terminal_title_stripped": "Title of the pane"}


class Case(unittest.TestCase):
    """The server opened for a test, on a temporary pages folder, then closed."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        for path, content in {"page/index.html": "<p>blank page</p>", "page/something.js": "var something = {};",
                              "page/sub/style.css": "p { margin: 0 }", "page/notes.txt": "type not served",
                              "page/.cache/secret.html": "CACHE", "private.html": "PRIVATE"}.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(content, encoding="utf-8")
        os.symlink(root / "private.html", root / "page" / "link.html")

        self.stderr = io.StringIO()
        self.agents = [raw("w1:p1", "claude", "working"), raw("w1:p2", "claude", "idle"),
                       raw("w1:p3", "codex", "idle")]
        self.turns = mock.Mock(return_value=TURNS)
        session = {"id": "s-1", "path": "/tmp/trial/s-1.jsonl"}         # only the first pane links to it
        self.reader = SimpleNamespace(
            session=lambda agent: session if agent["pane_id"] == "w1:p1" else None,
            read=lambda session, now: dict.fromkeys(("title",) + SESSION_KEYS), turns=self.turns)
        # A new object at each read, as the socket returns one: the state serves the snapshot as is.
        self.snapshot = mock.Mock(side_effect=lambda: copy.deepcopy({"workspaces": [], "agents": self.agents}))
        self.send = mock.Mock()
        version = mock.Mock(return_value={"version": "0.9.3", "protocol": 22})
        # The socket something would call does not exist: if the server stopped going through the three functions
        # replaced here, a test could not send its text to a real Herdr.
        aimed = mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": str(root / "no-herdr.sock")})
        for patch in [aimed] + [mock.patch.object(target, name, fake) for target, name, fake in (
                (sys, "stderr", self.stderr), (herdr, "snapshot", self.snapshot), (herdr, "version", version),
                (herdr, "send", self.send))]:
            patch.start()
            self.addCleanup(patch.stop)

        self.poller = Poller({"claude": self.reader})
        self.poller.poll()
        self.http = module.server(self.served(), 0, root / "page")     # 0: a free port, given by the system
        self.port = self.http.server_port
        self.host = f"127.0.0.1:{self.port}"
        thread = threading.Thread(target=self.http.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 2)
        self.addCleanup(self.http.server_close)
        self.addCleanup(self.http.shutdown)

    def served(self):
        """What the server serves: the poller, except for the tests of the example mode."""
        return self.poller

    def request(self, method, path, body=None, headers=None, host=True):
        """(code, headers, body) of a request; `host` True sends the server's own, None no Host header."""
        host = self.host if host is True else host
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.putrequest(method, path, skip_host=True)
            for name, value in {**({"Host": host} if host else {}), **(headers or {})}.items():
                connection.putheader(name, value)
            if body is not None:
                connection.putheader("Content-Length", str(len(body)))
            connection.endheaders(body)
            response = connection.getresponse()
            # Every answer, whatever its code and its type: no page of another site shows it in a frame.
            self.assertEqual(response.getheader("Content-Security-Policy"), "frame-ancestors 'self'", path)
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    def refusal(self, code, *request, **options):
        """Checks that a request is refused with `code` in the shape {"error": sentence}; returns the sentence."""
        received, headers, body = self.request(*request, **options)
        self.assertEqual(received, code, body)
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertEqual(headers["Cache-Control"], "no-store")
        obj = json.loads(body)
        self.assertEqual(list(obj), ["error"])
        self.assertTrue(isinstance(obj["error"], str) and obj["error"])
        return obj["error"]

    def post(self, body, **headers):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        return "POST", "/api/message", body, {"X-Something": "1", **headers}


class Pages(Case):
    def test_the_root_serves_the_blank_page(self):
        code, headers, body = self.request("GET", "/")
        self.assertEqual((code, body), (200, b"<p>blank page</p>"))
        self.assertEqual(headers["Content-Type"], "text/html; charset=utf-8")
        self.assertEqual(headers["Cache-Control"], "no-store")

    def test_page_files_are_served_with_their_type(self):
        code, headers, body = self.request("GET", "/something.js?v=2")
        self.assertEqual((code, body), (200, b"var something = {};"))
        self.assertTrue(headers["Content-Type"].startswith("text/javascript"))
        code, headers, _ = self.request("GET", "/sub/style.css")
        self.assertEqual(code, 200)
        self.assertTrue(headers["Content-Type"].startswith("text/css"))

    def test_nothing_is_served_outside_page(self):
        for path in ("/missing.html", "/sub", "/sub/", "/notes.txt",                   # missing, folder, unknown type
                     "/.cache/secret.html", "/%2ecache/secret.html",                   # hidden component
                     "/../private.html", "/sub/../../private.html", "/%2e%2e/private.html",    # traversal
                     "/..%2fprivate.html", "//../private.html", "/link.html",          # encoded, doubled, by a link
                     "/index.html%00.js", "/api/unknown"):
            code, _, body = self.request("GET", path)
            self.assertEqual(code, 404, path)
            self.assertEqual(list(json.loads(body)), ["error"], path)


class Guards(Case):
    def test_the_server_listens_only_on_127_0_0_1(self):
        self.assertEqual(self.http.server_address[0], "127.0.0.1")

    def test_the_server_opens_without_looking_a_name_up(self):
        # http.server asks the system for the name of the address when it binds: see Server.server_bind.
        lookup = mock.Mock(side_effect=AssertionError("a name was looked up"))
        with mock.patch.multiple(socket, getfqdn=lookup, gethostbyaddr=lookup, gethostname=lookup, getnameinfo=lookup):
            again = module.server(self.poller, 0, self.http.pages)
        self.addCleanup(again.server_close)
        self.assertEqual((again.server_name, again.server_port), again.server_address)
        # What the library sets besides the name is kept: the address can be taken again right after a stop.
        self.assertTrue(again.socket.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR))

    def test_a_non_local_host_is_refused(self):
        for host in ("something.example", f"something.example:{self.port}", "127.0.0.1:9999", "127.0.0.1", None):
            for path in ("/api/state", "/", "/api/stream"):
                self.refusal(403, "GET", path, host=host)
        self.refusal(403, *self.post({"agent": "w1:p1", "text": "hello"}), host="something.example")
        self.send.assert_not_called()

    def test_both_local_hosts_are_served(self):
        for host in (self.host, f"localhost:{self.port}"):
            self.assertEqual(self.request("GET", "/api/state", host=host)[0], 200)

    def test_on_port_80_the_names_alone_are_the_server_too(self):
        # A browser leaves ":80" out of the Host and of the Origin. Opening port 80 takes rights a test does not
        # have: the server of the test is given the addresses a server on port 80 accepts.
        self.assertEqual(module._hosts(8780), ["127.0.0.1:8780", "localhost:8780"])
        self.http.hosts = module._hosts(80)
        for host in ("127.0.0.1", "localhost", "127.0.0.1:80"):
            self.assertEqual(self.request("GET", "/api/state", host=host, headers={"Origin": "http://" + host})[0],
                             200)
        self.refusal(403, "GET", "/api/state", host="something.example")
        self.refusal(403, "GET", "/api/state", host="127.0.0.1", headers={"Origin": "http://something.example"})

    def test_a_non_local_origin_is_refused(self):
        for origin in ("http://something.example", f"https://{self.host}", "http://127.0.0.1:9999", "null", ""):
            self.refusal(403, "GET", "/api/state", headers={"Origin": origin})
            self.refusal(403, *self.post({"agent": "w1:p1", "text": "hello"}, Origin=origin))
        self.send.assert_not_called()
        for origin in (f"http://{self.host}", f"http://localhost:{self.port}"):
            self.assertEqual(self.request("GET", "/api/state", headers={"Origin": origin})[0], 200)

    def test_a_method_not_allowed_is_refused(self):
        for method, path in (("POST", "/api/state"), ("POST", "/"), ("POST", "/api/stream"), ("GET", "/api/message"),
                             ("PUT", "/api/state"), ("DELETE", "/index.html"), ("PATCH", "/api/message"),
                             ("OPTIONS", "/api/message")):
            self.refusal(405, method, path)
        self.send.assert_not_called()

    def test_an_unreadable_request_gets_an_error_of_the_same_shape(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as s:
            s.sendall(b"utter nonsense\r\n\r\n")
            received = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                received += chunk
        self.assertEqual(list(json.loads(received[received.index(b"{"):])), ["error"])
        self.assertNotIn(b"<html", received.lower())

    def test_an_internal_failure_returns_500_without_a_traceback(self):
        with mock.patch.object(self.poller, "state", side_effect=RuntimeError("internal detail")):
            sentence = self.refusal(500, "GET", "/api/state")
        self.assertEqual(sentence, "internal server error")
        self.assertIn("internal detail", self.stderr.getvalue(), "the detail goes to stderr")
        self.assertEqual(self.request("GET", "/api/state")[0], 200, "the server still serves")

    def test_a_client_gone_before_the_refusal_leaves_no_trace(self):
        gone = threading.Event()

        def late(*_):
            gone.wait(5)
            raise LookupError("t404")

        self.turns.side_effect = late
        before = set(threading.enumerate())
        s = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))     # closing cuts short (RST)
        s.sendall(f"GET /api/conversation?agent=w1:p1&before=t404 HTTP/1.1\r\nHost: {self.host}\r\n\r\n".encode())
        deadline = time.monotonic() + 5
        while not self.turns.called and time.monotonic() < deadline:
            time.sleep(0.01)
        thread, = set(threading.enumerate()) - before
        s.close()
        gone.set()
        thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertNotIn("Traceback", self.stderr.getvalue())
        self.assertEqual(self.request("GET", "/api/state")[0], 200, "the server still serves")

    def test_a_silent_client_is_dropped_at_the_timeout_without_response_or_trace(self):
        self.assertEqual(module.Handler.timeout, 30)
        with mock.patch.object(module.Handler, "timeout", 0.2):
            with socket.create_connection(("127.0.0.1", self.port), timeout=5) as s:
                s.sendall(f"POST /api/message HTTP/1.1\r\nHost: {self.host}\r\nX-Something: 1\r\n"
                          "Content-Length: 10\r\n\r\n".encode())            # ten bytes announced, none sent
                self.assertEqual(s.recv(4096), b"", "the server closes the connection")
        self.assertEqual(self.stderr.getvalue(), "")
        self.send.assert_not_called()

    def test_the_access_log_only_says_refusals(self):
        self.request("GET", "/api/state")
        self.request("GET", "/")
        self.assertEqual(self.stderr.getvalue(), "")
        self.request("GET", "/missing.html")
        self.assertIn("'GET /missing.html HTTP/1.1' 404", self.stderr.getvalue())

    def test_the_access_log_carries_no_control_character(self):
        # What a client writes in its request line ends up in the terminal: an escape sequence stays text there,
        # also on a Python whose library does not escape it (3.9.6, the one macOS ships).
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as s:
            s.sendall(b"GET /\x1b[2Jmissing\x07.html HTTP/1.1\r\nHost: " + self.host.encode() + b"\r\n\r\n")
            self.assertIn(b" 404 ", s.recv(4096))
        deadline = time.monotonic() + 5
        while "404" not in self.stderr.getvalue() and time.monotonic() < deadline:
            time.sleep(0.01)
        logged = self.stderr.getvalue()
        self.assertIn("missing", logged)
        self.assertEqual([c for c in logged if ord(c) < 32 and c != "\n"], [])


class State(Case):
    def test_state_returns_the_state_of_the_poller(self):
        code, headers, body = self.request("GET", "/api/state")
        self.assertEqual(code, 200)
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertEqual(headers["Cache-Control"], "no-store")
        state = json.loads(body)
        self.assertEqual(state, json.loads(json.dumps(self.poller.state())))
        self.assertEqual([a["id"] for a in state["agents"]], ["w1:p1", "w1:p2", "w1:p3"])

    def open_stream(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        self.addCleanup(connection.close)
        connection.request("GET", "/api/stream")
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.getheader("Content-Type"), "text/event-stream")
        self.assertEqual(response.getheader("Cache-Control"), "no-store")
        self.assertEqual(response.getheader("Content-Security-Policy"), "frame-ancestors 'self'")
        return connection, response

    def block(self, response):
        """The lines of the stream's next block, up to the empty line."""
        lines = []
        while True:
            line = response.readline().decode()
            if line in ("\n", ""):
                return lines
            lines.append(line.rstrip("\n"))

    def pushed_state(self, response):
        event, data = self.block(response)
        self.assertEqual(event, "event: state")
        self.assertTrue(data.startswith("data: "))
        return json.loads(data[len("data: "):])

    def test_the_stream_pushes_the_state_then_each_change(self):
        _, response = self.open_stream()
        first = self.pushed_state(response)
        self.assertEqual(first["agents"][0]["state"], "working")
        self.poller.poll()                               # nothing changes: nothing is pushed
        self.agents[0]["agent_status"] = "blocked"
        self.poller.poll()
        second = self.pushed_state(response)
        self.assertEqual(second["agents"][0]["state"], "blocked")
        self.assertEqual([e["kind"] for e in second["events"]], ["blocked"])

    def test_the_stream_beats_when_nothing_changes(self):
        with mock.patch.object(module, "HEARTBEAT", 0.1):
            _, response = self.open_stream()
            self.pushed_state(response)
            self.assertEqual(self.block(response), [": heartbeat"])

    def test_the_read_timeout_does_not_cut_a_quiet_stream(self):
        with mock.patch.object(module.Handler, "timeout", 0.2), mock.patch.object(module, "HEARTBEAT", 0.5):
            _, response = self.open_stream()
            self.pushed_state(response)
            for _ in range(2):                           # two silences longer than the timeout
                self.assertEqual(self.block(response), [": heartbeat"])

    def test_the_thread_of_the_stream_ends_when_the_client_leaves(self):
        before = set(threading.enumerate())
        connection, response = self.open_stream()
        self.pushed_state(response)
        thread, = set(threading.enumerate()) - before
        response.close()
        connection.close()
        deadline = time.monotonic() + 5
        while thread.is_alive() and time.monotonic() < deadline:
            self.agents[0]["agent_status"] = "idle" if self.agents[0]["agent_status"] == "working" else "working"
            self.poller.poll()                           # each change makes the thread write, and it sees the leaving
            time.sleep(0.02)
        self.assertFalse(thread.is_alive())
        self.assertEqual(self.stderr.getvalue(), "", "a client that leaves is not a failure")

    def test_the_stream_ends_when_the_server_stops(self):
        with mock.patch.object(module, "HEARTBEAT", 0.1):
            _, response = self.open_stream()
            self.pushed_state(response)
            self.http.shutdown()
            self.http.server_close()
            response.read()                              # returns: the server closed the stream


class Conversation(Case):
    def test_the_conversation_of_an_agent(self):
        code, _, body = self.request("GET", "/api/conversation?agent=w1%3Ap1")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body), {"agent": "w1:p1", **TURNS})
        session, limit, before = self.turns.call_args[0]
        self.assertEqual((session["id"], limit, before), ("s-1", 20, None))

    def test_turns_and_before_are_passed_on_fifty_turns_at_most(self):
        self.request("GET", "/api/conversation?agent=w1:p1&turns=7&before=t9")
        self.assertEqual(self.turns.call_args[0][1:], (7, "t9"))
        self.request("GET", "/api/conversation?agent=w1:p1&turns=500")
        self.assertEqual(self.turns.call_args[0][1:], (50, None))

    def test_agent_unknown_without_a_reader_or_without_a_session(self):
        unknown = self.refusal(404, "GET", "/api/conversation?agent=w9:p9")
        self.refusal(404, "GET", "/api/conversation")
        no_session = self.refusal(404, "GET", "/api/conversation?agent=w1:p2")
        no_reader = self.refusal(404, "GET", "/api/conversation?agent=w1:p3")
        self.assertEqual(len({unknown, no_session, no_reader}), 3, "each refusal says its reason")
        self.turns.assert_not_called()

    def test_a_reader_without_turns_says_so(self):
        others = {self.refusal(404, "GET", f"/api/conversation?agent={agent}")
                  for agent in ("w9:p9", "w1:p2", "w1:p3")}
        del self.reader.turns                            # `turns` is optional in an extension
        self.assertNotIn(self.refusal(404, "GET", "/api/conversation?agent=w1:p1"), others,
                         "this refusal says its reason")

    def test_turns_not_a_whole_number(self):
        for turns in ("abc", "1.5", "0", "-3"):
            self.refusal(400, "GET", f"/api/conversation?agent=w1:p1&turns={turns}")
        self.turns.assert_not_called()

    def test_before_unknown(self):
        self.turns.side_effect = LookupError("t404")
        self.refusal(404, "GET", "/api/conversation?agent=w1:p1&before=t404")

    def test_without_before_a_failed_lookup_is_a_failure_of_the_reader(self):
        for failure in (KeyError("field"), IndexError("rank"), LookupError("other")):
            with self.subTest(failure):
                self.turns.side_effect = failure
                for path in ("/api/conversation?agent=w1:p1", "/api/conversation?agent=w1:p1&before="):
                    self.assertEqual(self.refusal(500, "GET", path), "internal server error")
                self.assertIn(type(failure).__name__, self.stderr.getvalue(), "the traceback goes to stderr")

    def test_unreadable_log(self):
        self.turns.side_effect = FileNotFoundError(2, "No such file or directory")
        self.refusal(502, "GET", "/api/conversation?agent=w1:p1")

    def test_during_a_herdr_outage_the_conversation_stays_served(self):
        self.snapshot.side_effect = herdr.Unavailable("connection refused")
        self.assertIn("Herdr does not answer", self.poller.poll()["error"])
        self.assertEqual(self.request("GET", "/api/conversation?agent=w1:p1")[0], 200)


class Message(Case):
    def test_the_message_goes_to_the_pane(self):
        code, _, body = self.request(*self.post({"agent": "w1:p1", "text": "  Hello,\n\thow are you…  \n"}))
        self.assertEqual((code, json.loads(body)), (200, {"ok": True}))
        self.send.assert_called_once_with("w1:p1", "Hello,\n\thow are you…")

    def test_an_agent_without_a_reader_also_gets_a_message(self):
        self.assertEqual(self.request(*self.post({"agent": "w1:p3", "text": "x" * 4000}))[0], 200)
        self.send.assert_called_once_with("w1:p3", "x" * 4000)

    def test_without_the_x_something_header(self):
        body = json.dumps({"agent": "w1:p1", "text": "hello"}).encode()
        self.refusal(403, "POST", "/api/message", body)
        self.refusal(403, "POST", "/api/message", body, {"X-Something": "yes"})
        self.send.assert_not_called()

    def test_each_invalid_request_is_refused(self):
        invalid = [b"not json", b"", b"[1, 2]", b'"text"', b"\xff\xfe", {}, {"agent": "w1:p1"},
                   {"text": "hello"}, {"agent": "w1:p1", "text": 3}, {"agent": ["w1:p1"], "text": "hello"},
                   {"agent": "w1:p1", "text": ""}, {"agent": "w1:p1", "text": " \n\t "},
                   {"agent": "w1:p1", "text": "x" * 4001}, {"agent": "w1:p1", "text": "red \x1b[31m"},
                   {"agent": "w1:p1", "text": "nul \x00 inside"}, {"agent": "w1:p1", "text": "carriage\rreturn"},
                   {"agent": "w1:p1", "text": "c1 \x9b inside"}]
        for body in invalid:
            self.refusal(400, *self.post(body))
        self.refusal(400, "POST", "/api/message", None, {"X-Something": "1"})                  # without a length
        self.refusal(400, "POST", "/api/message", None, {"X-Something": "1", "Content-Length": "-5"})
        self.send.assert_not_called()

    def test_unknown_agent(self):
        self.refusal(404, *self.post({"agent": "w9:p9", "text": "hello"}))
        self.send.assert_not_called()

    def test_body_too_big(self):
        self.refusal(413, *self.post({"agent": "w1:p1", "text": "x" * 20000}))
        self.refusal(413, *self.post(b" " * 300000))
        self.send.assert_not_called()

    def test_the_agent_is_waiting_for_an_answer(self):
        self.send.side_effect = herdr.Refused("agent_blocked", "agent is blocked")
        self.refusal(409, *self.post({"agent": "w1:p1", "text": "hello"}))

    def test_another_refusal_from_herdr(self):
        self.send.side_effect = herdr.Refused("agent_not_ready", "agent is not ready")
        self.assertIn("agent is not ready", self.refusal(502, *self.post({"agent": "w1:p1", "text": "hello"})))

    def test_herdr_unavailable(self):
        self.send.side_effect = herdr.Unavailable("connection refused")
        self.assertIn("connection refused", self.refusal(502, *self.post({"agent": "w1:p1", "text": "hello"})))

    def test_during_a_herdr_outage_the_message_returns_502_and_not_unknown_agent(self):
        self.snapshot.side_effect = self.send.side_effect = herdr.Unavailable("connection refused")
        self.poller.poll()
        sentence = self.refusal(502, *self.post({"agent": "w1:p1", "text": "hello"}))
        self.assertTrue(sentence.startswith("Herdr does not answer"), sentence)


class ExampleMode(Case):
    """The same server on the example, which it does not tell apart from a poller. Nothing reaches Herdr."""

    def setUp(self):
        super().setUp()
        self.file = json.loads((PAGES / "example.json").read_text(encoding="utf-8"))
        for fake in (self.snapshot, self.send):
            fake.reset_mock()                            # the parent class's poller read the fake Herdr
            self.addCleanup(fake.assert_not_called)

    def served(self):
        return Example()

    def test_the_state_is_the_example_at_the_current_time(self):
        code, _, body = self.request("GET", "/api/state")
        state = json.loads(body)
        self.assertEqual((code, state["example"]), (200, True))
        self.assertEqual({**state, "generated": None}, {**self.file["state"], "generated": None})
        self.assertNotEqual(state["generated"], self.file["state"]["generated"])
        self.assertLess(abs(time.time() - datetime.fromisoformat(state["generated"]).timestamp()), 5)

    def test_the_stream_pushes_the_example_then_beats(self):
        with mock.patch.object(module, "HEARTBEAT", 0.1):
            connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
            self.addCleanup(connection.close)
            connection.request("GET", "/api/stream")
            response = connection.getresponse()
            event, data, _ = (response.readline().decode() for _ in range(3))
            self.assertEqual(event, "event: state\n")
            self.assertEqual(json.loads(data[len("data: "):])["agents"], self.file["state"]["agents"])
            self.assertEqual(response.readline(), b": heartbeat\n")

    def test_the_conversation_comes_from_the_file(self):
        code, _, body = self.request("GET", "/api/conversation?agent=w1K:p1")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body), {"agent": "w1K:p1", **self.file["conversations"]["w1K:p1"]})

    def test_no_conversation_without_a_session_nor_before_a_cursor(self):
        without = next(a["id"] for a in self.file["state"]["agents"] if a["session"] is None)
        self.refusal(404, "GET", f"/api/conversation?agent={without}")
        self.refusal(404, "GET", "/api/conversation?agent=w9:p9")
        self.refusal(404, "GET", "/api/conversation?agent=w1K:p1&before=t404")  # the example returns no cursor

    def test_no_message_is_sent(self):
        sentence = self.refusal(409, *self.post({"agent": "w1K:p1", "text": "hello"}))
        self.assertIn("example", sentence)
        self.refusal(404, *self.post({"agent": "w9:p9", "text": "hello"}))


if __name__ == "__main__":
    unittest.main()
