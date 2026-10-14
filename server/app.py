"""Small, read-only alerts proxy. stdlib only. Never logs API tokens.
Run behind HTTPS (Caddy config supplied), not directly on the public internet.
"""
from __future__ import annotations
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "https://api.alerts.in.ua/v1/iot/active_air_raid_alerts_by_oblast.json"
STATUS = {"A": "active", "P": "partial", "N": "clear"}
MIN_INTERVAL = 15.0
MAX_BYTES = 16_384


def parse_feed(payload: bytes) -> list[str]:
    if len(payload) > MAX_BYTES:
        raise ValueError("response too large")
    code = json.loads(payload)
    if not isinstance(code, str) or len(code) != 27 or any(c not in STATUS for c in code):
        raise ValueError("unexpected upstream format")
    return [STATUS[c] for c in code]


def fetch_upstream(token: str) -> bytes:
    if not token:
        raise ValueError("missing API token")
    request = urllib.request.Request(UPSTREAM, headers={
        "Authorization": f"Bearer {token}", "Accept": "application/json",
        "User-Agent": "SvitanokPrototype/0.1"
    })
    with urllib.request.urlopen(request, timeout=8) as response:
        if response.status != 200:
            raise ValueError("unexpected HTTP status")
        return response.read(MAX_BYTES + 1)


class FeedCache:
    def __init__(self, token: str, fetcher=fetch_upstream, clock=time.time):
        self.token = token
        self.fetcher = fetcher
        self.clock = clock
        self.lock = threading.Lock()
        self.cached = None
        self.next_allowed = float("-inf")
        self.failures = 0

    def get(self):
        with self.lock:
            now = self.clock()
            if now < self.next_allowed:
                if self.cached is not None and 0 <= now - self.cached["fetchedAt"] <= MIN_INTERVAL:
                    return 200, self.cached
                return 503, {"error": "upstream_unavailable", "retryAfter": max(1, int(self.next_allowed - now))}
            self.next_allowed = now + MIN_INTERVAL
            try:
                statuses = parse_feed(self.fetcher(self.token))
                checked = self.clock()
                self.cached = {"fetchedAt": checked, "statuses": statuses, "source": "alerts.in.ua"}
                self.failures = 0
                self.next_allowed = checked + MIN_INTERVAL
                return 200, self.cached
            except Exception as exc:
                self.cached = None  # never turn a network failure into 'clear'
                self.failures += 1
                backoff = min(300, MIN_INTERVAL * 2 ** min(self.failures - 1, 5))
                if isinstance(exc, urllib.error.HTTPError) and exc.code == 429:
                    try:
                        backoff = min(300, max(backoff, float(exc.headers.get("Retry-After", "60"))))
                    except (ValueError, TypeError):
                        backoff = max(backoff, 60)
                self.next_allowed = self.clock() + backoff
                # Only the type is logged: no URLs, response bodies or token values.
                logging.warning("Upstream unavailable (%s)", type(exc).__name__)
                return 503, {"error": "upstream_unavailable", "retryAfter": int(backoff)}


def make_handler(cache: FeedCache):
    class Handler(BaseHTTPRequestHandler):
        server_version = "SvitanokProxy/0.1"
        def do_GET(self):
            if self.path == "/health":
                # Liveness only. /v1/status is the actual data-readiness check.
                self.reply(200, {"service": "svitanok", "version": "0.1"})
            elif self.path == "/v1/status":
                code, body = cache.get()
                self.reply(code, body)
            else:
                self.reply(404, {"error": "not_found"})
        def reply(self, code, body):
            data = json.dumps(body, ensure_ascii=False, allow_nan=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(data)))
            if code == 503:
                self.send_header("Retry-After", str(body["retryAfter"]))
            self.end_headers()
            self.wfile.write(data)
        def log_message(self, format, *args):
            # Avoid URLs with query strings entering access logs.
            return
    return Handler


def main():
    token = os.environ.get("ALERTS_TOKEN", "").strip()
    if not token:
        raise SystemExit("Set ALERTS_TOKEN in the server environment; do not put it in the app.")
    host = os.environ.get("BIND_HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer((host, port), make_handler(FeedCache(token)))
    print(f"Svitanok proxy listening on {host}:{port}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    main()
