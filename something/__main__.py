"""Run something: `python3 -m something [--port N] [--once] [--example]`.

Without an option: the server on 127.0.0.1 and a poll every 2 s, until Ctrl+C. With `--once`: a single poll, the
state as JSON on the output, without a server. With `--example`: the example state, without Herdr or extensions.
"""
import argparse
import errno
import json
import sys
import threading
import time
from pathlib import Path

from . import extensions, guards
from .poll import Poller, loop
from .server import HttpError, server

PAGES = Path(__file__).resolve().parent.parent / "page"


class Example:
    """The example mode: the fixed state of `page/example.json`, under the methods of `Poller`, to build a page
    without running anything else. Nothing reaches Herdr, nothing changes, no message is sent."""

    def __init__(self):
        data = json.loads((PAGES / "example.json").read_text(encoding="utf-8"))
        self._state, self._conversations = data["state"], data["conversations"]

    def state(self):
        """The example, dated now."""
        return {**self._state, "generated": guards.iso(time.time())}

    poll = state     # the loop calls it again for nothing: the example does not change

    def wait(self, version, timeout):
        """Returns the state right away the first time (`version` None), then after the timeout: the stream beats."""
        if version is not None:
            time.sleep(timeout)
        return 0, self.state()

    def raw(self, ident):
        """Like Poller.raw: here the reader is the example, and the session the agent's conversation, if any."""
        agent = next((a for a in self._state["agents"] if a["id"] == ident), None)
        return agent and (agent, self, self._conversations.get(ident))

    def turns(self, conversation, limit, before):
        """Like a reader's `turns`: the conversation, whole. LookupError for any cursor."""
        if before is not None:
            raise LookupError(before)       # an example conversation is returned whole, without a cursor
        return conversation

    def send(self, ident, text):
        """Like Poller.send, except that it always refuses: HttpError 409."""
        raise HttpError(409, "no message is sent in example mode: these agents do not exist")


def outage(error):
    """Says in the terminal, in one line, a failure of the polls when it starts or changes, then its end (`error`
    None): a page is not always open to say it. Never raises."""
    said = "".join(c if c.isprintable() else " " for c in error or "")      # Herdr's own words can be in it
    try:
        print(f"something: {said}. Still trying." if error else "something: back to normal.", file=sys.stderr,
              flush=True)
    except (OSError, ValueError):
        pass        # the terminal is gone: the polls go on, and the page still says it


def main(arguments=None):
    """Returns the exit code: 0, or 1 if Herdr could not be polled (`--once`) or if the port does not open."""
    options = argparse.ArgumentParser(prog="python3 -m something",
                                      description="The link between Herdr and an HTML page.")
    options.add_argument("--port", type=int, default=8780, help="the server's port (8780 by default)")
    options.add_argument("--once", action="store_true", help="write the state as JSON, then exit")
    options.add_argument("--example", action="store_true", help="serve the example state, without Herdr or extensions")
    chosen = options.parse_args(arguments)
    poller = Example() if chosen.example else Poller(*extensions.load())
    if chosen.once:
        state = poller.poll()
        print(json.dumps(state, indent=2))
        return 1 if state["error"] else 0
    try:
        http = server(poller, chosen.port, PAGES)
    except (OSError, OverflowError) as e:       # taken, forbidden, or outside 0 to 65535
        taken = getattr(e, "errno", None) == errno.EADDRINUSE
        print(f"something: port {chosen.port} does not open ({getattr(e, 'strerror', None) or e}). "
              + ("Another program holds it, perhaps a something that is already running. " if taken else "")
              + "Choose another one with `--port`.", file=sys.stderr)
        return 1
    note = " (example data)" if chosen.example else ""
    print(f"something: http://127.0.0.1:{http.server_port}/{note}", flush=True)
    threading.Thread(target=loop, args=(poller,), kwargs={"say": outage}, daemon=True).start()
    try:
        http.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        http.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
