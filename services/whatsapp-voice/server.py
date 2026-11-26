"""Optional user-hosted speech endpoint. Requires an already-downloaded local Whisper model.
Bind to loopback and use an authenticated HTTPS reverse proxy if connecting from Supabase.
No audio or transcription is written to disk, no runtime model download, no external API.
"""
import hmac
import io
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BYTES = 2 * 1024 * 1024
MAX_SAMPLES = 60 * 16000
MAX_TEXT = 512

def transcribe_ogg(payload, model):
    import av
    import numpy as np
    if not payload.startswith(b"OggS"):
        raise ValueError("invalid audio")
    chunks, count = [], 0
    with av.open(io.BytesIO(payload), format="ogg") as source:
        if len(source.streams.audio) != 1:
            raise ValueError("one audio stream required")
        resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
        def append(frame):
            nonlocal count
            data = frame.to_ndarray().reshape(-1)
            count += len(data)
            if count > MAX_SAMPLES:
                raise ValueError("audio duration exceeds 60 seconds")
            chunks.append(data.copy())
        for frame in source.decode(audio=0):
            for out in resampler.resample(frame):
                append(out)
        for out in resampler.resample(None):
            append(out)
    if not chunks:
        raise ValueError("empty audio")
    segments, _ = model.transcribe(np.concatenate(chunks), beam_size=1, vad_filter=True,
                                   condition_on_previous_text=False, max_new_tokens=128)
    parts, length = [], 0
    for segment in segments:
        part = segment.text.strip()
        length += len(part) + 1
        if length > MAX_TEXT:
            raise ValueError("transcript too long; send a shorter note")
        parts.append(part)
    result = " ".join(parts).strip()
    if not result:
        raise ValueError("speech not detected")
    return result

def make_handler(token, transcribe):
    lease = threading.BoundedSemaphore(1)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def setup(self):
            super().setup()
            self.connection.settimeout(10)
        def reply(self, status, payload):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_POST(self):
            if self.path != "/transcribe":
                return self.reply(404, {"error": "not found"})
            auth = self.headers.get("Authorization", "")
            if not hmac.compare_digest(auth.encode("utf-8"), ("Bearer " + token).encode("utf-8")):
                return self.reply(403, {"error": "forbidden"})
            if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "audio/ogg":
                return self.reply(415, {"error": "unsupported media"})
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                size = 0
            if size < 1 or size > MAX_BYTES or self.headers.get("Transfer-Encoding"):
                return self.reply(413, {"error": "invalid size"})
            if not lease.acquire(blocking=False):
                return self.reply(429, {"error": "busy"})
            try:
                payload = self.rfile.read(size)
                if len(payload) != size or not payload.startswith(b"OggS"):
                    return self.reply(400, {"error": "invalid audio"})
                try:
                    result = transcribe(payload)
                    if not isinstance(result, str) or not 1 <= len(result.strip()) <= MAX_TEXT:
                        raise ValueError("invalid transcript")
                except Exception:
                    return self.reply(422, {"error": "unable to transcribe"})
                self.reply(200, {"text": result.strip()})
            finally:
                lease.release()
    return Handler

def main():
    token = os.environ.get("WA_VOICE_SERVICE_TOKEN", "")
    model_dir = os.environ.get("WA_WHISPER_MODEL_DIR", "")
    if len(token) < 32 or not model_dir or not Path(model_dir).is_dir():
        raise SystemExit("Set a strong WA_VOICE_SERVICE_TOKEN and existing local WA_WHISPER_MODEL_DIR.")
    from faster_whisper import WhisperModel
    model = WhisperModel(model_dir, device="cpu", compute_type="int8", local_files_only=True, cpu_threads=4)
    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("WA_VOICE_PORT", "8091"))),
                                 make_handler(token, lambda audio: transcribe_ogg(audio, model)))
    server.serve_forever()

if __name__ == "__main__":
    main()
