import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.startup_readiness import port_is_available, wait_for_setup_endpoint


def test_port_check_rejects_an_existing_listener():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        assert not port_is_available("0.0.0.0", listener.getsockname()[1])


@pytest.mark.parametrize(
    ("payload", "valid"),
    [
        ({"setup_required": True}, True),
        ({"setup_required": False}, True),
        ({"setup_required": "true"}, False),
        ({"status": "ok"}, False),
    ],
)
def test_setup_endpoint_requires_valid_response(payload, valid):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode())

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/auth/setup/status"
        if valid:
            wait_for_setup_endpoint(url, timeout=1)
        else:
            with pytest.raises(TimeoutError):
                wait_for_setup_endpoint(url, timeout=0.1)
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


def test_unreachable_backend_reports_timeout():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with pytest.raises(TimeoutError):
        wait_for_setup_endpoint(f"http://127.0.0.1:{port}/auth/setup/status", timeout=0.1)
