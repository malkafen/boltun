#!/usr/bin/env python3
"""Minimal Chrome DevTools Protocol client (stdlib only) for Mattermost Desktop: one connection per page target.
Usage as a script: cdp.py <url part> [js file]  evaluates JS (stdin or file) in the first page whose URL contains it."""
import base64, json, os, socket, struct, sys, urllib.request

PORT = int(os.environ.get("MM_CDP_PORT", "9229"))
LOCAL = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def targets(port=PORT):
    return [p for p in json.load(LOCAL.open(f"http://127.0.0.1:{port}/json", timeout=5)) if p["type"] == "page"]


class CDP:
    def __init__(self, match, port=PORT):
        page = next(p for p in targets(port) if match(p))
        self.url = page["url"]
        path = page["webSocketDebuggerUrl"].split(str(port), 1)[1]
        self.s = socket.create_connection(("127.0.0.1", port))
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
        buf = b""
        while b"\r\n\r\n" not in buf: buf += self.s.recv(4096)
        self.n = 0

    def _recv(self, k):
        b = b""
        while len(b) < k:
            c = self.s.recv(k - len(b))
            if not c: raise EOFError
            b += c
        return b

    def _frame(self):
        data = b""
        while True:
            h = self._recv(2); fin = h[0] & 0x80; ln = h[1] & 0x7f
            if ln == 126: ln = struct.unpack(">H", self._recv(2))[0]
            elif ln == 127: ln = struct.unpack(">Q", self._recv(8))[0]
            data += self._recv(ln)
            if fin: return data

    def call(self, method, **params):
        self.n += 1
        msg = json.dumps({"id": self.n, "method": method, "params": params}).encode()
        mask = os.urandom(4); hdr = bytes([0x81])
        ln = len(msg)
        hdr += bytes([0x80 | ln]) if ln < 126 else (bytes([0x80 | 126]) + struct.pack(">H", ln) if ln < 65536 else bytes([0x80 | 127]) + struct.pack(">Q", ln))
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(msg)))
        while True:
            r = json.loads(self._frame())
            if r.get("id") == self.n: return r

    def eval(self, js, timeout=600):
        self.s.settimeout(timeout + 30)
        r = self.call("Runtime.evaluate", expression=js, awaitPromise=True, returnByValue=True, timeout=timeout * 1000)
        res = r.get("result", {})
        if "exceptionDetails" in res: raise RuntimeError(json.dumps(res["exceptionDetails"])[:2000])
        return res.get("result", {}).get("value")

    def close(self):
        try: self.s.close()
        except OSError: pass


if __name__ == "__main__":
    c = CDP(lambda p: sys.argv[1] in p["url"])
    print(json.dumps(c.eval(sys.stdin.read() if len(sys.argv) < 3 else open(sys.argv[2]).read()), ensure_ascii=False, indent=1))
