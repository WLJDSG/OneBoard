#!/usr/bin/env python3
"""集成回归：强退模拟父应用后，真实代理应自行释放端口（不使用用户配置）。"""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time


def listening(port):
    with socket.socket() as connection:
        connection.settimeout(0.2)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def parent(binary, directory, port):
    with open(directory / "stdout", "wb") as output, open(directory / "stderr", "wb") as errors:
        child = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=output, stderr=errors)
        (directory / "pid").write_text(str(child.pid))
        child.stdin.write(json.dumps({"listenPort": port, "providers": []}).encode())
        child.stdin.close()
        child.wait()


def test(binary):
    with tempfile.TemporaryDirectory(prefix="oneboard-proxy-parent-") as name:
        directory = Path(name)
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]
        process = subprocess.Popen([sys.executable, __file__, "--parent", binary, name, str(port)])
        try:
            deadline = time.monotonic() + 15
            while not listening(port):
                if process.poll() is not None or time.monotonic() > deadline:
                    raise AssertionError("Test proxy did not start")
                time.sleep(0.1)
            process.kill()
            process.wait(timeout=5)
            deadline = time.monotonic() + 8
            while listening(port):
                if time.monotonic() > deadline:
                    raise AssertionError("Orphaned proxy retained listening port")
                time.sleep(0.1)
            print("PASS: proxy released its port after parent SIGKILL")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            if listening(port) and (directory / "pid").exists():
                os.kill(int((directory / "pid").read_text()), signal.SIGTERM)


if __name__ == "__main__":
    if sys.argv[1] == "--parent":
        parent(sys.argv[2], Path(sys.argv[3]), int(sys.argv[4]))
    else:
        test(str(Path(sys.argv[1]).resolve()))
