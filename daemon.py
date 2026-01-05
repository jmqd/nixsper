#!/usr/bin/env python3
import logging
import queue
import socket
import subprocess
import threading

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

HOST = "127.0.0.1"
PORT = 65432
MODEL_SIZE = "large-v3"
DEVICE = "cuda"
COMPUTE_TYPE = "float16"
SAMPLE_RATE = 16000
CHANNELS = 1
BLOCK_MS = 100
BUF_SIZE = 1024

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("nixsper")


class DictationEngine:
    def __init__(self):
        logger.info(f"Loading {MODEL_SIZE} on {DEVICE}...")
        self.model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
        self.queue = queue.Queue()
        self.capturing = threading.Event()

        threading.Thread(target=self._stream_audio, daemon=True).start()
        logger.info("Dictation engine ready.")

    def _audio_callback(self, indata, frames, time, status):
        """Sounddevice callback to capture audio chunks."""
        if status:
            logger.warning(f"Audio status: {status}")
        if self.capturing.is_set():
            self.queue.put(indata.copy())

    def _stream_audio(self):
        """Keeps the audio device open and ready in the background."""
        try:
            with sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                callback=self._audio_callback,
            ):
                while True:
                    sd.sleep(BLOCK_MS)
        except Exception as e:
            logger.error(f"Audio stream error: {e}")

    def start(self):
        """Begin capturing audio."""
        with self.queue.mutex:
            self.queue.queue.clear()
        self.capturing.set()
        logger.info("Recording started.")

    def stop(self):
        """Stop capturing and process the audio."""
        self.capturing.clear()
        logger.info("Recording stopped. Transcribing...")
        self._process_audio()

    def _process_audio(self):
        if self.queue.empty():
            logger.info("No audio captured.")
            return

        chunks = []
        while not self.queue.empty():
            chunks.append(self.queue.get())

        # Flatten and normalize audio
        audio = np.concatenate(chunks, axis=0).flatten().astype(np.float32)

        segments, _ = self.model.transcribe(audio, beam_size=5, language="en")
        text = " ".join(s.text for s in segments).strip()

        if text:
            logger.info(f"Recognized: {text}")
            self._type_text(text)
        else:
            logger.info("No speech detected.")

    def _type_text(self, text):
        try:
            cmd = ["xdotool", "type", "--clearmodifiers", "--delay", "0", f"{text} "]
            subprocess.run(cmd, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            logger.error(f"Typing failed: {e}")


def run_server():
    engine = DictationEngine()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        s.listen()
        logger.info(f"Listening on {HOST}:{PORT}")

        while True:
            try:
                conn, _ = s.accept()
                with conn:
                    cmd = conn.recv(BUF_SIZE).decode().strip().upper()
                    if cmd == "START":
                        engine.start()
                    elif cmd == "STOP":
                        engine.stop()
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
            except Exception as e:
                logger.error(f"Server error: {e}")


if __name__ == "__main__":
    run_server()
