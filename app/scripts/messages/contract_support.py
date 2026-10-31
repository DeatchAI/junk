"""JSON-RPC client for read-only probes against synthetic Messages databases."""
import json
import selectors
import subprocess
import time


class ImsgFixtureRPC:
    def __init__(self, helper, database):
        self.process = subprocess.Popen([str(helper), "rpc", "--db", str(database)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.backlog = []

    def __enter__(self):
        return self

    def request(self, identifier, method, params):
        # Probe clients deliberately exclude every mutation method.
        if method not in {"initialize", "status", "chats.get", "chats.list", "messages.history", "watch.subscribe"}:
            raise ValueError("Only fixture reads and watch subscriptions are supported")
        value = dict(jsonrpc="2.0", id=identifier, method=method, params=params)
        self.process.stdin.write((json.dumps(value) + "\n").encode())
        self.process.stdin.flush()

    def receive(self, predicate):
        for index, value in enumerate(self.backlog):
            if predicate(value):
                return self.backlog.pop(index)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                break
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("imsg ended before the expected fixture response")
            value = json.loads(line)
            if predicate(value):
                if "error" in value:
                    raise RuntimeError(str(value["error"]))
                return value
            self.backlog.append(value)
        raise TimeoutError("imsg did not emit the expected fixture event")

    def __exit__(self, *_):
        self.selector.close()
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.process.stdout.close()
