#!/usr/bin/env python3
"""Compile the real catalog methods and check bounded local HTTP + alpha parity.

Requires macOS/Xcode command-line tools and Python's standard library only.
All compilation, fixtures, server traffic, and downloads stay in a unique temp
directory or localhost. No production service or paired-device token is used.
"""

import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/WPPetCatalog.m"
TEMPLATE = ROOT / "Tests/catalog-v102-harness.m"
REPORT = ROOT / "Tests/catalog-v102-report.json"


def extracted_harness():
    source = SOURCE.read_text()
    scanner = source[source.index("static NSArray<NSNumber *> *WPFrameCounts("):
                     source.index("\n/// Only official asset hosts")]
    scanner = scanner.replace("WPFrameCounts(", "WPFrameCountsActual(", 1)
    model = source[source.index("@interface WPCatalogRequest"):
                   source.index("@interface WPPetCatalog ()")]
    methods = source[source.index("- (instancetype)init {"):
                     source.index("- (void)loadPetsWithCompletion:")]
    harness = TEMPLATE.read_text()
    for marker, text in (("FRAME_COUNTS", scanner), ("REQUEST_MODEL", model),
                         ("REQUEST_METHODS", methods)):
        token = "// @ACTUAL_" + marker + "@"
        if harness.count(token) != 1:
            raise RuntimeError("Missing or repeated template marker: " + token)
        harness = harness.replace(token, text)
    return harness


class LocalServer(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    lock = threading.Lock()
    active = 0
    maximum_active = 0
    paths = []

    def log_message(self, *_args):
        pass

    def do_GET(self):
        with self.lock:
            type(self).active += 1
            type(self).maximum_active = max(self.maximum_active, self.active)
            self.paths.append(self.path)
        try:
            # Ensure successful transfers overlap so the concurrency check
            # distinguishes the intended limit from an accidental serial path.
            if self.path.startswith("/valid/"):
                time.sleep(0.1)
            if self.path == "/oversize":
                self.send_response(200)
                self.send_header("Content-Length", str(32 * 1024 * 1024 + 1))
                self.end_headers()
                self.wfile.write(b"x" * 4096)
                self.wfile.flush()
                return
            if self.path == "/unknown-length":
                self.send_response(200)
                self.end_headers()
                chunk = b"x" * (64 * 1024)
                for _ in range(529):
                    self.wfile.write(chunk)
                return
            body = b"test" if self.path.startswith("/valid/") else b""
            self.send_response(500 if self.path == "/http500" else 200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # Expected when production code cancels an oversized body early.
            pass
        finally:
            with self.lock:
                type(self).active -= 1


def main():
    with tempfile.TemporaryDirectory(prefix="wechatpet-catalog-v0312-") as temporary:
        directory = Path(temporary)
        harness = directory / "catalog-harness.m"
        binary = directory / "catalog-harness"
        result_file = directory / "result.json"
        harness.write_text(extracted_harness())
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra",
                        "-Wno-unused-parameter", str(harness), "-framework", "Foundation",
                        "-framework", "ImageIO", "-framework", "CoreGraphics", "-o", str(binary)],
                       check=True)
        server = LocalServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([str(binary), str(ROOT / "Resources/DefaultPet/spritesheet.png"),
                                     str(directory), str(server.server_port), str(result_file)],
                                    timeout=40, capture_output=True, text=True)
        finally:
            server.shutdown()
            server.server_close()
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        if not result_file.exists():
            raise RuntimeError("Catalog harness did not produce a report")
        report = json.loads(result_file.read_text())
        expected = {f"/valid/{index}" for index in range(8)} | {
            "/oversize", "/unknown-length", "/http500", "/empty"}
        report["network"]["observedMaximumConcurrentRequests"] = Handler.maximum_active
        report["network"]["receivedExactlyExpectedRequests"] = (
            len(Handler.paths) == 12 and set(Handler.paths) == expected)
        report["network"]["allPassed"] = bool(
            report["network"]["allPassed"] and Handler.maximum_active == 2
            and report["network"]["receivedExactlyExpectedRequests"])
        report["sourceSHA256"] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        report["caseCount"] = report["alpha"]["caseCount"] + report["network"]["caseCount"] + 2
        report["allPassed"] = bool(result.returncode == 0 and report["alpha"]["allPassed"]
                                   and report["network"]["allPassed"])
        REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"catalog-v102: {report['caseCount']} checks; "
              f"max concurrency={Handler.maximum_active}; allPassed={report['allPassed']}")
        return 0 if report["allPassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
