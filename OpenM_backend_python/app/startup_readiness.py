"""Verify that the local backend can start and serves its setup endpoint."""

import argparse
import json
import socket
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


def port_is_available(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            listener.bind((host, port))
        except OSError:
            return False
    return True


def wait_for_setup_endpoint(url: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    last_error = "no response"
    while time.monotonic() < deadline:
        try:
            with urlopen(url, timeout=min(2.0, max(0.1, deadline - time.monotonic()))) as response:
                status = json.load(response)
            if not isinstance(status, dict) or not isinstance(status.get("setup_required"), bool):
                raise ValueError("Invalid setup status response")
            return
        except (URLError, HTTPError, OSError, ValueError) as error:
            last_error = str(error)
            time.sleep(min(1.0, max(0.0, deadline - time.monotonic())))
    raise TimeoutError(f"Backend setup endpoint did not become ready: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check-port", "wait"))
    parser.add_argument("--port", type=int, default=8002)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if args.action == "check-port":
        if not port_is_available("0.0.0.0", args.port):
            print(f"Port {args.port} is already in use. Close the existing backend or free the port and try again.", file=sys.stderr)
            return 1
        return 0
    try:
        wait_for_setup_endpoint(f"http://127.0.0.1:{args.port}/auth/setup/status", args.timeout)
    except TimeoutError as error:
        print(error, file=sys.stderr)
        return 1
    print("Backend setup endpoint is ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
