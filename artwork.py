"""Bound MPRIS artwork before Qt sees it; no third-party dependencies or temp files."""

import base64
import os
import signal
import stat
import struct
import sys
import urllib.parse
import urllib.request
import zlib

MAX_BYTES = 2 * 1024 * 1024
MAX_PIXELS = 4_000_000
MAX_SIDE = 8192
DEADLINE = 5
MAX_URL = 4096


class Rejected(ValueError):
    pass


def interrupt(_signum, _frame):
    raise Rejected("cancelled or timed out")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Rejected("redirects are not supported")


def read_bounded(stream):
    # Read one byte past the budget to detect unannounced/chunked overflow.
    result = bytearray()
    while len(result) <= MAX_BYTES:
        chunk = stream.read(min(65536, MAX_BYTES + 1 - len(result)))
        if not chunk:
            return bytes(result)
        result.extend(chunk)
    raise Rejected("encoded artwork exceeds byte budget")


def fetch(url):
    if not url or len(url) > MAX_URL or any(ord(c) < 32 or ord(c) == 127 for c in url):
        raise Rejected("invalid artwork URL")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme == "file":
        if parsed.netloc not in ("", "localhost") or parsed.query or parsed.fragment:
            raise Rejected("nonlocal file URL")
        path = urllib.request.url2pathname(parsed.path)
        if not os.path.isabs(path):
            raise Rejected("relative artwork path")
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
                raise Rejected("not a bounded regular file")
            return read_bounded(stream)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username is not None or parsed.password is not None:
        raise Rejected("only HTTPS and local files are supported")
    # Do not inherit proxies, cookies or authentication, and never follow redirects.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, headers={"Accept": "image/png, image/jpeg", "Accept-Encoding": "identity"})
    with opener.open(request, timeout=DEADLINE) as response:
        if response.status != 200 or response.headers.get("Content-Encoding", "identity").lower() != "identity":
            raise Rejected("unsupported response")
        length = response.headers.get("Content-Length")
        if length is not None and (not length.isascii() or not length.isdecimal() or int(length) > MAX_BYTES):
            raise Rejected("invalid or oversized response length")
        return read_bounded(response)


def dimensions(data):
    # Inspect raster headers only: no decoder runs before the pixel check.
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(data) < 33 or data[8:16] != b"\x00\x00\x00\rIHDR":
            raise Rejected("invalid PNG header")
        if zlib.crc32(data[12:29]) != struct.unpack(">I", data[29:33])[0]:
            raise Rejected("invalid PNG header checksum")
        width, height = struct.unpack(">II", data[16:24])
        return "image/png", width, height
    if not data.startswith(b"\xff\xd8"):
        raise Rejected("only PNG and JPEG are supported")
    offset = 2
    while offset < len(data):
        if data[offset] != 0xFF:
            raise Rejected("invalid JPEG marker")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = data[offset]
        offset += 1
        if marker in (0x00, 0xD8, 0xD9, 0xDA) or 0xD0 <= marker <= 0xD7:
            raise Rejected("missing JPEG dimensions")
        if offset + 2 > len(data):
            break
        length = int.from_bytes(data[offset:offset + 2], "big")
        if length < 2 or offset + length > len(data):
            break
        if marker in (0xC0, 0xC2):
            if length < 8 or data[offset + 2] != 8:
                raise Rejected("unsupported JPEG frame")
            height, width = struct.unpack(">HH", data[offset + 3:offset + 7])
            components = data[offset + 7]
            if components not in (1, 3, 4) or length != 8 + 3 * components:
                raise Rejected("invalid JPEG frame")
            return "image/jpeg", width, height
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            raise Rejected("unsupported JPEG coding")
        offset += length
    raise Rejected("missing JPEG dimensions")


def encode(data):
    if len(data) > MAX_BYTES:
        raise Rejected("encoded artwork exceeds byte budget")
    mime, width, height = dimensions(data)
    if not (0 < width <= MAX_SIDE and 0 < height <= MAX_SIDE and width * height <= MAX_PIXELS):
        raise Rejected("artwork exceeds pixel budget")
    return "data:" + mime + ";base64," + base64.b64encode(data).decode("ascii")


def main():
    signal.signal(signal.SIGALRM, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    signal.setitimer(signal.ITIMER_REAL, DEADLINE)
    try:
        if len(sys.argv) != 2:
            return 1
        result = encode(fetch(sys.argv[1]))
        sys.stdout.write(result)
        return 0
    except (Exception, KeyboardInterrupt):
        # No untrusted URL, server response or metadata is logged or displayed.
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


if __name__ == "__main__":
    sys.exit(main())
