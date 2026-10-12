"""The entry point: `--once`, `--example`, the port that does not open, the start of the server
(127.0.0.1, on a free port).

Neither a real Herdr nor a real log: the functions of `something.herdr` are replaced, the designated socket does not
exist, and the loading of the extensions is replaced: no reader reads the machine's sessions.
"""
import contextlib
import http.client
import io
import json
import os
import socket
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import something.__main__ as module     # noqa: E402
from something import herdr             # noqa: E402

SNAPSHOT = {"workspaces": [{"workspace_id": "w1", "label": "trial"}],
            "agents": [{"terminal_id": "term_1", "agent_status": "working", "workspace_id": "w1", "tab_id": "w1:t1",
                        "pane_id": "w1:p1", "focused": True, "revision": 3, "agent": "codex"}]}
REPORTED = [{"name": "trial", "harness": "trial", "error": None}]       # what loading says about the extensions


def listener(port=0):
    """A socket bound to this port, as the server binds it; OSError if someone already listens there. Port 0: a
    free port, given by the system."""
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", port))
    except OSError:
        s.close()
        raise
    return s


class Case(unittest.TestCase):
    def setUp(self):
        self.output, self.errors = io.StringIO(), io.StringIO()
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": "/no/where/herdr.sock"}))
        self.load = stack.enter_context(mock.patch.object(module.extensions, "load", return_value=({}, REPORTED)))
        stack.enter_context(mock.patch.object(herdr, "version", return_value={"version": "0.9.3", "protocol": 22}))
        self.snapshot = stack.enter_context(mock.patch.object(herdr, "snapshot", return_value=SNAPSHOT))
        stack.enter_context(contextlib.redirect_stdout(self.output))
        stack.enter_context(contextlib.redirect_stderr(self.errors))


class Once(Case):
    def test_once_writes_the_state_and_returns_zero(self):
        self.assertEqual(module.main(["--once"]), 0)
        state = json.loads(self.output.getvalue())
        self.assertEqual(list(state), ["generated", "example", "herdr", "error", "agents", "events", "extensions",
                                       "snapshot"])
        self.assertEqual((state["error"], state["example"], state["extensions"]), (None, False, REPORTED))
        self.assertEqual(state["snapshot"], SNAPSHOT)
        self.assertEqual([(a["id"], a["harness"], a["state"], a["workspace"]) for a in state["agents"]],
                         [("w1:p1", "codex", "working", "trial")])
        self.assertIn("\n  ", self.output.getvalue(), "the JSON is indented")
        self.snapshot.assert_called_once()

    def test_once_returns_one_when_herdr_does_not_answer(self):
        self.snapshot.side_effect = herdr.Unavailable("socket missing")
        self.assertEqual(module.main(["--once"]), 1)
        state = json.loads(self.output.getvalue())
        self.assertIn("socket missing", state["error"])
        self.assertEqual(state["agents"], [])

    def test_the_example_is_written_without_herdr_or_extension(self):
        self.assertEqual(module.main(["--example", "--once"]), 0)
        state = json.loads(self.output.getvalue())
        self.assertIs(state["example"], True)
        self.assertEqual(len(state["agents"]), 6)
        self.snapshot.assert_not_called()
        self.load.assert_not_called()


class Service(Case):
    def code(self, *options):
        """The exit code of `main`, run in a daemon thread and awaited five seconds at most: if it wrongly opened
        a server, the test would fail instead of blocking the suite. The loop is not started: no thread
        outlives the test to call Herdr after it."""
        codes = []
        with mock.patch.object(module, "loop", lambda poller, say: None):
            thread = threading.Thread(target=lambda: codes.append(module.main(list(options))), daemon=True)
            thread.start()
            thread.join(5)
        self.assertEqual(len(codes), 1, "main did not return its exit code " + self.errors.getvalue())
        return codes[0]

    def test_a_taken_port_is_said_clearly(self):
        with listener() as occupant:
            occupant.listen()
            port = str(occupant.getsockname()[1])
            self.assertEqual(self.code("--port", port), 1)
        said = self.errors.getvalue()
        self.assertIn(f"something: port {port} does not open (", said)
        self.assertIn("Another program holds it", said)
        self.assertTrue(said.endswith("Choose another one with `--port`.\n"), said)
        self.assertEqual(said.count("\n"), 1, "one sentence, no traceback")
        self.assertEqual(self.output.getvalue(), "")
        self.snapshot.assert_not_called()

    def test_a_port_out_of_range_is_said_too_and_nobody_is_said_to_hold_it(self):
        for port in ("70000", "-1"):
            with self.subTest(port):
                self.assertEqual(self.code("--port", port), 1)
                self.assertIn(f"something: port {port} does not open (", self.errors.getvalue())
        self.assertIn("Choose another one with `--port`.", self.errors.getvalue())
        self.assertNotIn("holds it", self.errors.getvalue())
        self.assertNotIn("Traceback", self.errors.getvalue())
        self.assertEqual(self.output.getvalue(), "")
        self.snapshot.assert_not_called()

    def serve(self, *options):
        """Runs `main` with these options, on a free port; returns (the port, the state it serves), then stops
        it."""
        opened, codes, polled, real, started = [], [], threading.Event(), module.server, []

        def open_server(*arguments):
            opened.append(real(*arguments))
            return opened[0]

        def one_poll(poller, say):  # no thread outlives the test to call Herdr after it
            started.append((say, self.output.getvalue()))
            poller.poll()
            polled.set()

        with mock.patch.object(module, "server", open_server), mock.patch.object(module, "loop", one_poll):
            thread = threading.Thread(target=lambda: codes.append(module.main([*options, "--port", "0"])),
                                      daemon=True)      # a test that fails midway does not hold up the suite
            thread.start()
            self.addCleanup(thread.join, 5)
            self.assertTrue(polled.wait(5))
            (say, written), = started
            self.assertIs(say, module.outage, "the loop is given what says an outage in the terminal")
            self.assertIn("http://127.0.0.1:", written, "the address is written before the first poll can speak")
            deadline = time.monotonic() + 5
            while "http://" not in self.output.getvalue() and time.monotonic() < deadline:
                time.sleep(0.01)
            port = opened[0].server_port
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            self.addCleanup(connection.close)
            connection.request("GET", "/api/state")
            response = connection.getresponse()
            state = json.loads(response.read())
            self.assertEqual(response.status, 200)
            opened[0].shutdown()            # what Ctrl+C does: serve_forever returns
            thread.join(5)
        self.assertEqual(codes, [0])
        listener(port).close()              # the port is given back
        return port, state

    def test_the_server_starts_serves_the_state_and_stops(self):
        port, state = self.serve()
        self.assertEqual(self.output.getvalue(), f"something: http://127.0.0.1:{port}/\n")
        self.assertEqual((state["example"], [a["id"] for a in state["agents"]]), (False, ["w1:p1"]))

    def test_an_outage_and_its_end_are_said_in_the_terminal(self):
        module.outage("Herdr does not answer: socket missing (~/herdr.sock)")
        module.outage(None)
        module.outage("poll failed: Refused: internal_error: two\nlines and \x1b[31ma colour")     # Herdr's own words
        self.assertEqual(self.errors.getvalue(),
                         "something: Herdr does not answer: socket missing (~/herdr.sock). Still trying.\n"
                         "something: back to normal.\n"
                         "something: poll failed: Refused: internal_error: two lines and  [31ma colour."
                         " Still trying.\n")
        self.assertEqual(self.output.getvalue(), "")

    def test_a_terminal_that_is_gone_does_not_stop_the_polls(self):
        # The loop calls `outage` in its own thread: if it raised, no poll would follow.
        class Gone:
            def __init__(self, failure):
                self.failure = failure

            def write(self, text):
                raise self.failure

            def flush(self):
                raise self.failure

        for failure in (BrokenPipeError(32, "Broken pipe"), OSError(5, "Input/output error"),
                        ValueError("I/O operation on closed file")):
            with self.subTest(failure), mock.patch.object(sys, "stderr", Gone(failure)):
                module.outage("Herdr does not answer: socket missing (~/herdr.sock)")
                module.outage(None)

    def test_the_example_mode_says_so_and_does_not_reach_herdr(self):
        port, state = self.serve("--example")
        self.assertEqual(self.output.getvalue(), f"something: http://127.0.0.1:{port}/ (example data)\n")
        self.assertIs(state["example"], True)
        self.snapshot.assert_not_called()
        self.load.assert_not_called()


if __name__ == "__main__":
    unittest.main()
