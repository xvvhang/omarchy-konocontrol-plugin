"""Regression tests use an isolated local TLS server, never public services."""

import base64
import http.server
import os
from pathlib import Path
import signal
import shutil
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zlib

import artwork

JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/"
    "2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/"
    "wAARCAABAAEDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCf/"
    "EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/ADoDFU3/2Q=="
)


def png(width=1, height=1):
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
            + chunk(b"IEND", b""))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    started = threading.Event()
    disconnected = threading.Event()

    def log_message(self, *_args):
        pass

    def do_GET(self):
        try:
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/normal")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self.send_response(200)
            if self.path == "/announced-overflow":
                self.send_header("Content-Length", str(artwork.MAX_BYTES + 1))
            elif self.path == "/normal":
                self.send_header("Content-Length", str(len(png())))
            elif self.path == "/trickle":
                self.send_header("Content-Length", "10000")
            else:
                self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            if self.path == "/normal":
                self.wfile.write(png())
            elif self.path == "/trickle":
                self.started.set()
                # Each byte arrives far below the socket's inactivity timeout;
                # only a whole-operation deadline can stop this transfer.
                for _ in range(100):
                    self.wfile.write(b"x")
                    self.wfile.flush()
                    time.sleep(0.1)
            elif self.path == "/chunked-overflow":
                for _ in range(artwork.MAX_BYTES // 65536 + 1):
                    self.wfile.write(b"10000\r\n" + b"x" * 65536 + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
        except (OSError, ssl.SSLError):
            if self.path == "/trickle":
                self.disconnected.set()
        finally:
            self.close_connection = True


class ArtworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="konocontrol-art-test-")
        cls.directory = Path(cls.temp.name)
        cert, key = cls.directory / "cert.pem", cls.directory / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            "-keyout", str(key), "-out", str(cert),
        ], check=True, capture_output=True)
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"https://localhost:{cls.server.server_port}"
        cls.env = dict(os.environ, SSL_CERT_FILE=str(cert))

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temp.cleanup()

    def run_helper(self, url):
        return subprocess.run([sys.executable, "-B", str(Path(artwork.__file__)), url],
                              env=self.env, capture_output=True, timeout=8)

    def assert_rejected(self, url):
        result = self.run_helper(url)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")

    def test_normal_https_art(self):
        result = self.run_helper(self.base + "/normal")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"data:image/png;base64," + base64.b64encode(png()))

    def test_oversized_responses(self):
        for path in ("/announced-overflow", "/chunked-overflow"):
            with self.subTest(path=path):
                self.assert_rejected(self.base + path)

    def test_trickle_total_deadline(self):
        Handler.disconnected.clear()
        start = time.monotonic()
        self.assert_rejected(self.base + "/trickle")
        self.assertLess(time.monotonic() - start, artwork.DEADLINE + 2)
        self.assertTrue(Handler.disconnected.wait(2), "deadline must close the connection")

    def test_cancellation(self):
        Handler.started.clear()
        Handler.disconnected.clear()
        with subprocess.Popen([sys.executable, "-B", str(Path(artwork.__file__)), self.base + "/trickle"],
                              env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
            try:
                self.assertTrue(Handler.started.wait(3))
                process.send_signal(signal.SIGTERM)
                out, err = process.communicate(timeout=2)
                self.assertNotEqual(process.returncode, 0)
                self.assertEqual((out, err), (b"", b""))
                self.assertTrue(Handler.disconnected.wait(2), "cancellation must close the connection")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_redirect_rejected(self):
        self.assert_rejected(self.base + "/redirect")

    def test_local_files(self):
        path = self.directory / "art.png"
        path.write_bytes(png())
        self.assertEqual(self.run_helper(path.as_uri()).returncode, 0)
        path.write_bytes(png(3000, 3000))
        self.assert_rejected(path.as_uri())
        path.write_bytes(b"x" * (artwork.MAX_BYTES + 1))
        self.assert_rejected(path.as_uri())
        link = self.directory / "link.png"
        link.symlink_to(path)
        self.assert_rejected(link.as_uri())
        fifo = self.directory / "fifo"
        os.mkfifo(fifo)
        self.assert_rejected(fifo.as_uri())

    def test_format_and_pixel_budget(self):
        self.assertEqual(artwork.dimensions(JPEG), ("image/jpeg", 1, 1))
        for data in (b"<svg/>", b"GIF89a", b"", png(0, 1), png(8193, 1), png(2001, 2000)):
            with self.subTest(data=data[:24]):
                with self.assertRaises(artwork.Rejected):
                    artwork.encode(data)
        # Baseline and progressive JPEG SOF header fixtures; only header parsing
        # is tested here, malformed compressed pixels are still rejected by Qt.
        for marker in (0xC0, 0xC2):
            def jpeg(width, height):
                return b"\xff\xd8\xff" + bytes([marker]) + struct.pack(">HBHHB", 11, 8, height, width, 1) + b"\x01\x11\x00"
            self.assertEqual(artwork.dimensions(jpeg(52, 52)), ("image/jpeg", 52, 52))
            with self.assertRaises(artwork.Rejected):
                artwork.encode(jpeg(3000, 3000))

    def test_url_policy(self):
        for url in ("http://localhost/art", "data:image/png;base64,AAAA", "file://remote/art", "https://user:pass@localhost/art", "https://localhost/\nart", "x" * 4097):
            with self.subTest(url=url[:60]):
                self.assert_rejected(url)

    def test_qml_never_loads_metadata_url(self):
        directory = Path(artwork.__file__).parent
        card = (directory / "MediaCard.qml").read_text()
        self.assertIn("url: artwork.dataUrl", card)
        self.assertNotIn("source: root.hasTrack", card)
        bridge = (directory / "BoundedArt.qml").read_text()
        self.assertIn("root.requested === root.url", bridge)
        self.assertIn("Component.onDestruction: worker.signal(9)", bridge)
        self.assertIn("interval: 6000", bridge)

    @unittest.skipUnless(shutil.which("quickshell"), "Quickshell is not installed")
    def test_qml_bridge_and_image_decode(self):
        directory = Path(artwork.__file__).parent
        image = self.directory / "qml-art.png"
        image.write_bytes(png())
        jpeg = self.directory / "qml-art.jpg"
        jpeg.write_bytes(JPEG)
        config = self.directory / "shell.qml"
        config.write_text('''import QtQuick
import Quickshell
import "''' + directory.as_uri() + '''" as Plugin
ShellRoot {
  property int decoded: 0
  Plugin.BoundedArt { id: loader; url: "''' + image.as_uri() + '''" }
  Image {
    source: loader.dataUrl
    sourceSize: Qt.size(104, 104)
    asynchronous: true
    onStatusChanged: if (status === Image.Ready) {
      if (decoded++ === 0) { loader.url = "''' + jpeg.as_uri() + '''"; return }
      console.log("BOUNDED_ART_DECODE_OK")
      Qt.quit()
    }
  }
  Timer { interval: 4000; running: true; onTriggered: Qt.quit() }
}
''')
        result = subprocess.run(["quickshell", "--no-color", "--path", str(config)],
                                env=dict(self.env, QT_QPA_PLATFORM="offscreen"),
                                capture_output=True, timeout=8)
        output = result.stdout + result.stderr
        self.assertIn(b"BOUNDED_ART_DECODE_OK", output, output.decode(errors="replace"))

    @unittest.skipUnless(shutil.which("quickshell"), "Quickshell is not installed")
    def test_qml_url_change_cancels_download(self):
        image = self.directory / "replacement.png"
        image.write_bytes(png())
        Handler.disconnected.clear()
        config = self.directory / "cancel.qml"
        config.write_text('''import QtQuick
import Quickshell
import "''' + Path(artwork.__file__).parent.as_uri() + '''" as Plugin
ShellRoot {
  Plugin.BoundedArt {
    id: loader
    url: "''' + self.base + '''/trickle"
    onDataUrlChanged: if (dataUrl !== "") {
      console.log("BOUNDED_ART_REPLACEMENT_OK")
      Qt.quit()
    }
  }
  Timer { interval: 500; running: true; onTriggered: loader.url = "''' + image.as_uri() + '''" }
  Timer { interval: 4000; running: true; onTriggered: Qt.quit() }
}
''')
        result = subprocess.run(["quickshell", "--no-color", "--path", str(config)],
                                env=dict(self.env, QT_QPA_PLATFORM="offscreen"),
                                capture_output=True, timeout=8)
        output = result.stdout + result.stderr
        self.assertIn(b"BOUNDED_ART_REPLACEMENT_OK", output, output.decode(errors="replace"))
        self.assertTrue(Handler.disconnected.wait(2))


if __name__ == "__main__":
    unittest.main()
