import json
import os
import sys
import threading
import unittest
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app import FeedCache, parse_locations, make_handler, LOCATIONS

class LocationTests(unittest.TestCase):
    def feed(self, changes=None):
        rows = ['N'] * (max(LOCATIONS) + 1)
        for uid, status in (changes or {}).items(): rows[uid] = status
        return json.dumps(''.join(rows)).encode()
    def test_catalog_unique_known_ids(self):
        self.assertEqual(len(LOCATIONS), 1622)
        self.assertTrue({36, 37, 155} <= LOCATIONS)
    def test_gaisyn_not_vinnytsia(self):
        result = parse_locations(self.feed({37:'R'}))
        self.assertEqual(result[37], 'active'); self.assertEqual(result[36], 'clear')
    def test_vinnytsia_not_gaisyn(self):
        result = parse_locations(self.feed({36:'R'}))
        self.assertEqual(result[36], 'active'); self.assertEqual(result[37], 'clear')
    def test_community_separate_uid(self):
        result = parse_locations(self.feed({155:'Y'}))
        self.assertEqual(result[155], 'active'); self.assertEqual(result[36], 'clear')
    def test_blank_is_unknown(self): self.assertEqual(parse_locations(self.feed({36:' '}))[36], 'unknown')
    def test_partial_preserved(self): self.assertEqual(parse_locations(self.feed({36:'P'}))[36], 'partial')
    def test_short_oblast_feed_rejected(self):
        with self.assertRaises(ValueError): parse_locations(b'"NNNNNNNNNNNNNNNNNNNNNNNNNNN"')
    def test_truncated_full_feed_rejected(self):
        with self.assertRaises(ValueError): parse_locations(json.dumps('N'*max(LOCATIONS)).encode())
    def test_error_body_rejected(self):
        with self.assertRaises(ValueError): parse_locations(b'{"error":"no token"}')
    def test_unknown_char_rejected(self):
        with self.assertRaises(ValueError): parse_locations(self.feed({36:'X'}))
    def test_all_catalog_ids_resolve_independently(self):
        for uid in LOCATIONS:
            data = parse_locations(self.feed({uid:'R'}))
            self.assertEqual(data[uid], 'active')
            self.assertEqual(data.count('active'), 1)

class LocationHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        rows=['N']*(max(LOCATIONS)+1); rows[37]='R'; rows[155]='Y'
        cls.cache=FeedCache('test', fetcher=lambda _:json.dumps('N'*27).encode())
        cls.detailed=FeedCache('test', fetcher=lambda _:json.dumps(''.join(rows)).encode(), parser=parse_locations)
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(cls.cache,cls.detailed))
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
        cls.base=f'http://127.0.0.1:{cls.server.server_port}'
    @classmethod
    def tearDownClass(cls): cls.server.shutdown();cls.server.server_close();cls.thread.join()
    def get(self,q):
        with urllib.request.urlopen(self.base+'/v2/status'+q) as r:return json.load(r)
    def test_vinnytsia_clear_when_gaisyn_active(self):self.assertEqual(self.get('?uid=36')['locationStatus'],'clear')
    def test_gaisyn_active(self):self.assertEqual(self.get('?uid=37')['locationStatus'],'active')
    def test_correct_uid_returned(self):self.assertEqual(self.get('?uid=155')['locationUID'],155)
    def test_no_oblast_substitution(self):self.assertNotIn('statuses',self.get('?uid=36'))
    def test_reject_invalid_requests(self):
        for q in ['', '?uid=', '?uid=-1','?uid=9999','?uid=36&uid=37','?uid=36&token=secret','?uid=../../etc/passwd']:
            with self.assertRaises(urllib.error.HTTPError) as e:self.get(q)
            self.assertEqual(e.exception.code,400)
    def test_same_fetched_timestamp_all_uids(self):self.assertEqual(self.get('?uid=36')['fetchedAt'],self.get('?uid=37')['fetchedAt'])
