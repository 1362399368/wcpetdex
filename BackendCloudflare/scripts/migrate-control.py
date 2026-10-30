#!/usr/bin/env python3
"""Safely freeze, export, or unfreeze the pair's Cloudflare Durable Object.

The administrator secret is read from PETPAIR_MIGRATION_ADMIN_TOKEN or a hidden
terminal prompt. It is never accepted as a command-line argument or printed.
"""

import argparse
import getpass
import json
import os
import pathlib
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

MAX_SNAPSHOT_BYTES = 64 * 1024 * 1024
ROUTES = {
    "freeze": ("POST", "/admin/migration/freeze"),
    "export": ("GET", "/admin/migration/export"),
    "unfreeze": ("POST", "/admin/migration/unfreeze"),
}


def base_url(value):
    parsed = urllib.parse.urlsplit(value)
    local_http = parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1")
    if (parsed.scheme != "https" and not local_http):
        raise argparse.ArgumentTypeError("Use an HTTPS base URL (local loopback may use HTTP).")
    if not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise argparse.ArgumentTypeError("Use only the service origin, without credentials, path, query, or fragment.")
    return value.rstrip("/")


def secret():
    value = os.environ.get("PETPAIR_MIGRATION_ADMIN_TOKEN")
    if not value:
        if not sys.stdin.isatty():
            raise ValueError("Set PETPAIR_MIGRATION_ADMIN_TOKEN or run from a terminal for a hidden prompt.")
        value = getpass.getpass("Migration administrator token: ")
    if len(value) < 32 or any(char.isspace() for char in value):
        raise ValueError("Migration administrator token must be at least 32 characters, without whitespace.")
    return value


def call(origin, action, token):
    method, path = ROUTES[action]
    request = urllib.request.Request(origin + path, method=method,
                                     headers={"Authorization": "Bearer " + token,
                                              "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status != 200:
                raise ValueError("Server returned HTTP %d." % response.status)
            payload = response.read(MAX_SNAPSHOT_BYTES + 1)
    except urllib.error.HTTPError as error:
        # Do not print a response body that might contain private data.
        raise ValueError("Server returned HTTP %d." % error.code) from None
    except urllib.error.URLError as error:
        raise ValueError("Could not reach the service: %s." % error.reason) from None
    if len(payload) > MAX_SNAPSHOT_BYTES:
        raise ValueError("Snapshot exceeds the 64 MiB safety limit.")
    try:
        return json.loads(payload)
    except (ValueError, UnicodeDecodeError):
        raise ValueError("Server returned invalid JSON.") from None


def save_snapshot(path, snapshot):
    if (not isinstance(snapshot, dict) or snapshot.get("format") != "petpair-migration-v1" or
            snapshot.get("pair_key") != "our-private-pair-v1" or not isinstance(snapshot.get("events"), list)):
        raise ValueError("Server returned an unexpected migration format.")
    destination = pathlib.Path(path).expanduser().absolute()
    if destination.exists():
        raise ValueError("Output already exists; choose a new filename to preserve the earlier export.")
    if not destination.parent.is_dir():
        raise ValueError("Output directory does not exist.")
    content = (json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    descriptor, temporary = tempfile.mkstemp(prefix=".petpair-export-", dir=destination.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description="Manage a frozen Cloudflare pet pair migration snapshot.")
    parser.add_argument("action", choices=ROUTES)
    parser.add_argument("--base-url", required=True, type=base_url, help="HTTPS service origin, without a path")
    parser.add_argument("--output", help="New private JSON file, required for export")
    args = parser.parse_args(argv)
    if args.action == "export" and not args.output:
        parser.error("export requires --output")
    if args.action != "export" and args.output:
        parser.error("--output applies only to export")
    try:
        token = secret()
        result = call(args.base_url, args.action, token)
        if args.action == "export":
            output = save_snapshot(args.output, result)
            print("Saved %d events to %s (private file, mode 0600)." % (len(result["events"]), output))
        elif isinstance(result, dict) and result.get("frozen") is (args.action == "freeze"):
            print("Migration state: %s." % ("frozen" if result["frozen"] else "active"))
        else:
            raise ValueError("Server returned an unexpected migration state.")
    except ValueError as error:
        print("Migration operation failed: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
