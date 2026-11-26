import unittest
import threading
import urllib.request
import urllib.error
import json
from http.server import ThreadingHTTPServer
from server import make_handler

class SpeechEndpointTest(unittest.TestCase):
    def setUp(self):
        self.token = "test-secret-" + "x" * 32
        self.calls = []
        def transcribe(data):
            self.calls.append(data)
            return "test transcript"
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.token, transcribe))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:%d/transcribe" % self.server.server_address[1]
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
    def post(self, data=b"OggS\x00\x01", token=None, mime="audio/ogg"):
        req = urllib.request.Request(self.url, data=data, headers={"Authorization": "Bearer " + (self.token if token is None else token), "Content-Type": mime})
        try:
            with urllib.request.urlopen(req, timeout=3) as res:
                return res.status, json.load(res)
        except urllib.error.HTTPError as exc:
            return exc.code, json.load(exc)
    def test_valid_preview(self):
        self.assertEqual(self.post(), (200, {"text": "test transcript"}))
        self.assertEqual(len(self.calls), 1)
    def test_reject_bad_auth_mime_and_audio(self):
        self.assertEqual(self.post(token="wrong")[0], 403)
        self.assertEqual(self.post(mime="image/jpeg")[0], 415)
        self.assertEqual(self.post(data=b"not ogg")[0], 400)
        self.assertEqual(self.calls, [])

if __name__ == "__main__":
    unittest.main()
