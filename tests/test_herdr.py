"""Herdr's socket: what `something/herdr.py` sends, what it returns, and how it fails."""
import os
import socket
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import herdr
from tests.fake_herdr import FakeHerdr

# The exact shapes of the real Herdr 0.9.3; the values are invented.
PONG = {"type": "pong", "version": "0.9.3", "protocol": 22, "capabilities": {"health_check": True}}
AGENT = {"terminal_id": "term_1", "agent_status": "working", "workspace_id": "w1", "tab_id": "w1:t1",
         "pane_id": "w1:p1", "focused": True, "revision": 3, "agent": "claude", "cwd": "/tmp/trial"}
SNAPSHOT = {"version": "0.9.3", "protocol": 22, "focused_workspace_id": "w1", "focused_tab_id": "w1:t1",
            "focused_pane_id": "w1:p1", "workspaces": [], "tabs": [], "panes": [], "layouts": [], "agents": [AGENT]}


def point_at(test, path):
    """Points something at `path` for the time of the test."""
    patch = mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": path})
    patch.start()
    test.addCleanup(patch.stop)


class WithFakeHerdr(unittest.TestCase):
    def mount(self, responses):
        fake = FakeHerdr(responses)
        self.addCleanup(fake.stop)
        point_at(self, fake.path)
        return fake


class Call(WithFakeHerdr):
    def test_one_request_and_its_response(self):
        fake = self.mount({"ping": PONG})
        self.assertEqual(herdr.call("ping"), PONG)
        self.assertEqual(len(fake.received), 1)
        request = fake.received[0]
        self.assertEqual((request["method"], request["params"]), ("ping", {}))
        self.assertIsInstance(request["id"], str)

    def test_one_connection_per_request(self):
        fake = self.mount({"ping": PONG, "session.snapshot": {"type": "session_snapshot", "snapshot": SNAPSHOT}})
        herdr.call("ping")
        herdr.call("session.snapshot")
        self.assertEqual([r["method"] for r in fake.received], ["ping", "session.snapshot"])

    def test_a_response_longer_than_one_recv(self):
        long = dict(SNAPSHOT, agents=[dict(AGENT, pane_id=f"w1:p{i}", cwd="x" * 500) for i in range(600)])
        self.mount({"session.snapshot": {"type": "session_snapshot", "snapshot": long}})
        self.assertEqual(herdr.snapshot(), long)

    def test_an_error_of_herdr_is_a_refusal_with_its_code(self):
        self.mount({"agent.prompt": herdr.Refused("agent_blocked", "agent w1:p1 is blocked")})
        with self.assertRaises(herdr.Refused) as raised:
            herdr.call("agent.prompt", {"target": "w1:p1", "text": "hello"})
        self.assertEqual(raised.exception.code, "agent_blocked")
        self.assertEqual(raised.exception.message, "agent w1:p1 is blocked")

    def test_an_error_without_a_code_is_still_a_refusal(self):
        self.mount({"ping": b'{"id":"something","error":{}}\n'})
        with self.assertRaises(herdr.Refused) as raised:
            herdr.call("ping")
        self.assertIsInstance(raised.exception.code, str)
        self.assertIsInstance(raised.exception.message, str)

    def test_three_methods_allowed_and_not_one_more(self):
        self.assertEqual(herdr.METHODS, {"ping", "session.snapshot", "agent.prompt"})

    def test_an_extension_opens_only_one_read_and_no_action(self):
        self.assertEqual(herdr.READS, {"pane.process_info"}, "allowing another one means changing the core")
        before = set(herdr.opened)
        try:
            for refused in ("agent.prompt", "agent.send_keys", "pane.close", "pane.read", "agent.read"):
                with self.assertRaises(ValueError):
                    herdr.open_reads({refused})
            self.assertEqual(herdr.opened, before)
            herdr.open_reads({"pane.process_info"})
            self.assertIn("pane.process_info", herdr.opened)
        finally:
            herdr.opened.clear()
            herdr.opened.update(before)

    def test_a_method_off_the_list_sends_nothing(self):
        fake = self.mount({})
        for method in ("agent.send_keys", "agent.focus", "pane.send_text", "agent.list", "", None):
            with self.assertRaises(ValueError):
                herdr.call(method, {"target": "w1:p1"})
        self.assertEqual(fake.received, [])


class Failures(WithFakeHerdr):
    def test_socket_missing(self):
        fake = FakeHerdr()
        fake.stop()                                # a stopped Herdr: its folder and its socket no longer exist
        self.assertFalse(os.path.exists(fake.path))
        point_at(self, fake.path)
        with self.assertRaises(herdr.Unavailable) as raised:
            herdr.call("ping")
        self.assertTrue(str(raised.exception).startswith("socket missing ("), raised.exception)

    def test_connection_refused(self):
        fake = FakeHerdr()
        self.addCleanup(fake.stop)
        leftover = fake.path + ".leftover"         # a socket file nobody listens to any more
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.bind(leftover)
        point_at(self, leftover)
        with self.assertRaises(herdr.Unavailable) as raised:
            herdr.call("ping")
        self.assertTrue(str(raised.exception).startswith("connection refused ("), raised.exception)

    def test_timeout(self):
        fake = FakeHerdr()
        self.addCleanup(fake.stop)
        mute = fake.path + ".mute"                 # a socket that accepts and never answers
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.bind(mute)
            s.listen()
            point_at(self, mute)
            with self.assertRaises(herdr.Unavailable) as raised:
                herdr.call("ping", timeout=0.2)
        self.assertTrue(str(raised.exception).startswith("timed out ("), raised.exception)

    def test_another_failure_is_said_in_the_system_s_words(self):
        # A socket path longer than the system takes: an error without a number, whose own sentence is all it says.
        point_at(self, "/no/where/" + "long/" * 60 + "herdr.sock")
        with self.assertRaises(herdr.Unavailable) as raised:
            herdr.call("ping")
        self.assertIn("too long (", str(raised.exception))
        self.assertNotIn("OSError", str(raised.exception))

    def test_unreadable_response(self):
        for raw in (b"this is not JSON\n", b'{"id":"something","result":{"type":"po', b"\xff\xfe\n", b"[1, 2]\n",
                    b'{"id":"something"}\n', b'{"id":"something","result":null}\n', b'{"id":"something","result":"pong"}\n'):
            with self.subTest(raw=raw):
                self.mount({"ping": raw})
                with self.assertRaises(herdr.Unavailable):
                    herdr.call("ping")

    def test_connection_closed_without_a_response(self):
        self.mount({"ping": b""})
        with self.assertRaises(herdr.Unavailable):
            herdr.call("ping")

    def test_a_failure_says_nothing_of_the_content(self):
        self.mount({"ping": b'{"id":"something","result":"session title"}\n'})
        with self.assertRaises(herdr.Unavailable) as raised:
            herdr.call("ping")
        self.assertNotIn("session title", str(raised.exception))


class Reads(WithFakeHerdr):
    def test_version(self):
        self.mount({"ping": PONG})
        self.assertEqual(herdr.version(), {"version": "0.9.3", "protocol": 22})

    def test_unreadable_version_is_none(self):
        for pong in ({"type": "pong"}, {"version": 9, "protocol": "22"}, {"version": "", "protocol": True},
                     {"version": None, "protocol": 22.5}):
            with self.subTest(pong=pong):
                self.mount({"ping": pong})
                self.assertEqual(herdr.version(), {"version": None, "protocol": None})

    def test_snapshot(self):
        fake = self.mount({"session.snapshot": {"type": "session_snapshot", "snapshot": SNAPSHOT}})
        self.assertEqual(herdr.snapshot(), SNAPSHOT)
        self.assertEqual(fake.received[0]["params"], {})

    def test_a_missing_snapshot_is_not_an_empty_snapshot(self):
        for result in ({"type": "session_snapshot"}, {"snapshot": None}, {"snapshot": []}):
            with self.subTest(result=result):
                self.mount({"session.snapshot": result})
                with self.assertRaises(herdr.Unavailable):
                    herdr.snapshot()


class Send(WithFakeHerdr):
    def test_send_sends_the_target_and_the_text_without_waiting(self):
        fake = self.mount({"agent.prompt": {"type": "agent_prompted", "agent": AGENT}})
        text = "first line\nsecond line, with an accent: é"
        self.assertIsNone(herdr.send("w1:p1", text))
        self.assertEqual(fake.received[0]["method"], "agent.prompt")
        self.assertEqual(fake.received[0]["params"], {"target": "w1:p1", "text": text})

    def test_sending_to_a_waiting_agent_is_refused(self):
        self.mount({"agent.prompt": lambda p: herdr.Refused("agent_blocked", f"agent {p['target']} is blocked")})
        with self.assertRaises(herdr.Refused) as raised:
            herdr.send("w1:p1", "hello")
        self.assertEqual(raised.exception.code, "agent_blocked")


class State(unittest.TestCase):
    def test_each_known_state(self):
        self.assertEqual([herdr.state(s) for s in ("working", "blocked", "done", "idle")],
                         ["working", "blocked", "done", "idle"])

    def test_everything_else_is_unknown(self):
        for raw in ("unknown", None, 3, 0, True, "", "IDLE", "waiting", ["idle"], {"idle": 1}):
            with self.subTest(raw=raw):
                self.assertEqual(herdr.state(raw), "unknown")


class SocketPath(unittest.TestCase):
    def test_the_environment_variable_wins(self):
        with mock.patch.dict(os.environ, {"HERDR_SOCKET_PATH": "/tmp/elsewhere.sock"}):
            self.assertEqual(herdr.socket_path(), "/tmp/elsewhere.sock")

    def test_otherwise_the_default_session(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("HERDR_SOCKET_PATH", None)
            self.assertEqual(herdr.socket_path(), os.path.expanduser("~/.config/herdr/herdr.sock"))


if __name__ == "__main__":
    unittest.main()
