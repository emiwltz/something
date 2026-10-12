"""A fake Herdr for the tests: a Unix socket that talks like the real one, in a temporary folder.

    with FakeHerdr({"ping": {"type": "pong", "version": "0.9.3", "protocol": 22}}) as fake:
        os.environ["HERDR_SOCKET_PATH"] = fake.path        # up to the test to set it, and to remove it
        ...
        fake.received                                      # the requests received, in order

`responses` says what to answer to each method:
- a dictionary: the `result`;
- an exception: an error of Herdr (`code` = its `code` attribute, `message` = its `message` attribute or its text);
- a function: called with `params`, it returns or raises one of the shapes of this list;
- bytes: sent as is, for an unreadable response, or `b""` for a connection closed without a response.
A method missing from `responses` gets the `invalid_request` error, as on the real Herdr.
"""
import json
import os
import shutil
import socket
import tempfile
import threading


class FakeHerdr:
    def __init__(self, responses=None):
        self.responses = dict(responses or {})
        self.received = []
        # /tmp and not the system's temporary folder: macOS limits a Unix socket path to 104 bytes.
        self._folder = tempfile.mkdtemp(prefix="fake-herdr-", dir="/tmp")
        self.path = os.path.join(self._folder, "h.sock")
        self._stopped = threading.Event()
        self._listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._listener.bind(self.path)
        self._listener.listen()
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.stop()

    def stop(self):
        """Stops the thread, closes the socket and deletes the folder. No effect the second time."""
        if self._stopped.is_set():
            return
        self._stopped.set()
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as wake:
                wake.connect(self.path)            # gets the thread out of its accept()
        except OSError:
            pass
        self._thread.join(2)
        self._listener.close()
        shutil.rmtree(self._folder, ignore_errors=True)

    def _serve(self):
        while True:
            connection, _ = self._listener.accept()
            with connection:
                if self._stopped.is_set():
                    return
                try:
                    self._answer(connection)
                except Exception:
                    pass                           # client gone, unreadable request or response: on to the next

    def _answer(self, connection):
        connection.settimeout(2)
        buffer = b""
        while not buffer.endswith(b"\n"):
            chunk = connection.recv(65536)
            if not chunk:
                return
            buffer += chunk
        request = json.loads(buffer)
        self.received.append(request)
        method = request.get("method")
        planned = self.responses.get(method, _Unknown(method))
        if callable(planned):
            try:
                planned = planned(request.get("params"))
            except Exception as e:
                planned = e
        if isinstance(planned, bytes):
            connection.sendall(planned)
            return
        response = {"id": request.get("id")}
        if isinstance(planned, Exception):
            response["error"] = {"code": getattr(planned, "code", "internal_error"),
                                 "message": getattr(planned, "message", None) or str(planned)}
        else:
            response["result"] = planned
        connection.sendall((json.dumps(response) + "\n").encode())


class _Unknown(Exception):
    """The real Herdr's response to a method it does not know."""
    code = "invalid_request"

    def __init__(self, method):
        super().__init__(f"unknown variant `{method}`")
