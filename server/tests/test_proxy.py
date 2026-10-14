import concurrent.futures
import io
import json
import logging
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app import FeedCache, parse_feed, make_handler, MAX_BYTES

class Clock:
    def __init__(self): self.now = 1000.0
    def __call__(self): return self.now

class ParserTests(unittest.TestCase):
    def test_all_clear(self): self.assertEqual(parse_feed(json.dumps("N" * 27).encode()), ["clear"] * 27)
    def test_all_active(self): self.assertEqual(parse_feed(json.dumps("A" * 27).encode()), ["active"] * 27)
    def test_all_partial(self): self.assertEqual(parse_feed(json.dumps("P" * 27).encode()), ["partial"] * 27)
    def test_empty(self):
        with self.assertRaises(ValueError): parse_feed(b'""')
    def test_short(self):
        with self.assertRaises(ValueError): parse_feed(json.dumps("N" * 26).encode())
    def test_long(self):
        with self.assertRaises(ValueError): parse_feed(json.dumps("N" * 28).encode())
    def test_invalid_code(self):
        with self.assertRaises(ValueError): parse_feed(json.dumps("N" * 26 + "X").encode())
    def test_lowercase(self):
        with self.assertRaises(ValueError): parse_feed(json.dumps("n" * 27).encode())
    def test_dictionary(self):
        with self.assertRaises(ValueError): parse_feed(b'{"error":"token expired"}')
    def test_list(self):
        with self.assertRaises(ValueError): parse_feed(b'[]')
    def test_null(self):
        with self.assertRaises(ValueError): parse_feed(b'null')
    def test_boolean(self):
        with self.assertRaises(ValueError): parse_feed(b'true')
    def test_malformed(self):
        with self.assertRaises(ValueError): parse_feed(b'<html>error</html>')
    def test_oversized(self):
        with self.assertRaises(ValueError): parse_feed(b' ' * (MAX_BYTES + 1))
    def test_invalid_encoding(self):
        with self.assertRaises(ValueError): parse_feed(b'\xff')
    def test_injected_whitespace(self):
        with self.assertRaises(ValueError): parse_feed(json.dumps("N" * 26 + " ").encode())

# Generate independent named tests for each documented region index.
def region_case(index):
    def test(self):
        data = list("N" * 27); data[index] = "P"
        parsed = parse_feed(json.dumps("".join(data)).encode())
        self.assertEqual(parsed[index], "partial")
        self.assertEqual(sum(x == "partial" for x in parsed), 1)
    return test
for i in range(27): setattr(ParserTests, f"test_region_slot_{i:02}", region_case(i))

class CacheTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(); self.calls = 0
        def fetch(token):
            self.calls += 1
            return json.dumps("N" * 27).encode()
        self.cache = FeedCache("test-private-value", fetcher=fetch, clock=self.clock)
    def test_valid_result(self):
        code, data = self.cache.get()
        self.assertEqual(code, 200); self.assertEqual(data["fetchedAt"], 1000)
        self.assertEqual(data["source"], "alerts.in.ua")
        self.assertNotIn("test-private-value", json.dumps(data))
    def test_caches_fifteen_seconds(self):
        first = self.cache.get(); self.clock.now += 14
        self.assertEqual(self.cache.get(), first); self.assertEqual(self.calls, 1)
    def test_new_fetch_after_window(self):
        self.cache.get(); self.clock.now += 15; self.cache.get(); self.assertEqual(self.calls, 2)
    def test_timestamp_not_refreshed_for_cache(self):
        self.cache.get(); self.clock.now += 5
        self.assertEqual(self.cache.get()[1]["fetchedAt"], 1000)
    def test_concurrent_requests_share_one_fetch(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
            results = list(pool.map(lambda _: self.cache.get(), range(200)))
        self.assertTrue(all(r[0] == 200 for r in results)); self.assertEqual(self.calls, 1)
    def test_timeout_returns_unavailable(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(TimeoutError())
        self.assertEqual(self.cache.get()[0], 503)
    def test_failure_discards_prior_clear(self):
        self.cache.get(); self.clock.now += 16
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(ConnectionError())
        self.assertEqual(self.cache.get()[0], 503); self.assertIsNone(self.cache.cached)
        self.assertEqual(self.cache.get()[0], 503)
    def test_failure_backoff(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(TimeoutError())
        self.cache.get(); self.clock.now += 15
        self.assertEqual(self.cache.get()[1]["retryAfter"], 30)
    def test_backoff_bounded(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(TimeoutError())
        for _ in range(20):
            code, data = self.cache.get()
            self.assertLessEqual(data["retryAfter"], 300)
            self.clock.now = self.cache.next_allowed
    def test_429_retry_after(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(urllib.error.HTTPError("", 429, "", {"Retry-After": "120"}, None))
        self.assertEqual(self.cache.get()[1]["retryAfter"], 120)
    def test_429_invalid_retry_header(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(urllib.error.HTTPError("", 429, "", {"Retry-After": "bad"}, None))
        self.assertEqual(self.cache.get()[1]["retryAfter"], 60)
    def test_secret_not_logged(self):
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(ValueError("test-private-value"))
        with self.assertLogs(level="WARNING") as logs: self.cache.get()
        self.assertNotIn("test-private-value", "".join(logs.output))
    def test_clock_backwards_does_not_serve_future(self):
        self.cache.get(); self.clock.now -= 30
        self.assertEqual(self.cache.get()[0], 503)
    def test_recovers_after_failure(self):
        good = self.cache.fetcher
        self.cache.fetcher = lambda _: (_ for _ in ()).throw(TimeoutError())
        self.cache.get(); self.clock.now += 16; self.cache.fetcher = good
        self.assertEqual(self.cache.get()[0], 200); self.assertEqual(self.cache.failures, 0)
    def test_invalid_payload_unavailable(self):
        self.cache.fetcher = lambda _: b'"not valid"'
        self.assertEqual(self.cache.get()[0], 503)

class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cache = FeedCache("fake", fetcher=lambda _: json.dumps("N" * 27).encode())
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(cls.cache))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True); cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
    @classmethod
    def tearDownClass(cls): cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def test_status_endpoint(self):
        with urllib.request.urlopen(self.base + "/v1/status") as r:
            self.assertEqual(r.status, 200); self.assertEqual(len(json.load(r)["statuses"]), 27)
    def test_no_store(self):
        with urllib.request.urlopen(self.base + "/v1/status") as r: self.assertEqual(r.headers["Cache-Control"], "no-store")
    def test_health(self):
        with urllib.request.urlopen(self.base + "/health") as r: self.assertEqual(json.load(r)["service"], "svitanok")
    def test_unknown_path(self):
        with self.assertRaises(urllib.error.HTTPError) as err: urllib.request.urlopen(self.base + "/other")
        self.assertEqual(err.exception.code, 404)
    def test_query_string_not_endpoint(self):
        with self.assertRaises(urllib.error.HTTPError) as err: urllib.request.urlopen(self.base + "/v1/status?token=secret")
        self.assertEqual(err.exception.code, 404)
    def test_post_disabled(self):
        with self.assertRaises(urllib.error.HTTPError) as err:
            urllib.request.urlopen(urllib.request.Request(self.base + "/v1/status", data=b'{}'))
        self.assertEqual(err.exception.code, 501)

if __name__ == "__main__": unittest.main(verbosity=2)
