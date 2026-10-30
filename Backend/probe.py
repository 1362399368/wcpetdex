#!/usr/bin/env python3
"""Run on the target network. Checks connectivity without sending an interaction."""
from __future__ import annotations

import argparse
import asyncio
import ipaddress
import json
import socket
import sys
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import aiohttp

from migration import read_tokens


def endpoints(url, allow_local_http=False):
    parsed = urlsplit(url)
    if (parsed.scheme not in ("wss", "ws") or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.path != "/v1/ws" or parsed.query or parsed.fragment):
        raise ValueError("use wss://hostname/v1/ws without credentials or query parameters")
    if parsed.scheme != "wss" and not (allow_local_http and parsed.hostname in ("127.0.0.1", "localhost", "::1")):
        raise ValueError("TLS is required outside an explicitly allowed local test")
    port = parsed.port or (443 if parsed.scheme == "wss" else 80)
    health = urlunsplit(("https" if parsed.scheme == "wss" else "http", parsed.netloc, "/health", "", ""))
    return parsed.hostname, port, health


async def probe(url, token=None, allow_local_http=False, websocket=False):
    host, port, health_url = endpoints(url, allow_local_http)
    report = {"ok": False, "endpoint": url, "scope": "authorized_websocket" if websocket else "health_and_unauthorized_websocket",
              "notes": ["Environment HTTP proxies are disabled; a VPN/TUN, transparent proxy or DNS override may still intercept traffic."], "checks": []}
    try:
        answers = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(host, port, type=socket.SOCK_STREAM), 10)
        addresses = sorted({answer[4][0] for answer in answers})
        report["checks"].append({"stage": "dns", "ok": True, "addresses": addresses})
        if any(ipaddress.ip_address(address) in ipaddress.ip_network("198.18.0.0/15") for address in addresses):
            report["notes"].append("DNS returned the 198.18.0.0/15 benchmark range, often used by proxy fake-IP DNS; this is not proof of direct mainland routing.")
    except (OSError, asyncio.TimeoutError):
        report["checks"].append({"stage": "dns", "ok": False, "error": "dns_failed_or_timeout"})
        return report
    # trust_env=False avoids environment proxies so the result describes this network's direct route.
    timeout = aiohttp.ClientTimeout(total=15, connect=10)
    async with aiohttp.ClientSession(timeout=timeout, trust_env=False) as session:
        try:
            async with session.get(health_url, allow_redirects=False) as response:
                try:
                    payload = await response.json()
                except (ValueError, aiohttp.ContentTypeError):
                    payload = None
                healthy = response.status == 200 and isinstance(payload, dict) and payload.get("ok") is True
                report["checks"].append({"stage": "https_health", "ok": healthy, "http_status": response.status})
                if not healthy:
                    return report
        except aiohttp.ClientConnectorCertificateError:
            report["checks"].append({"stage": "https_health", "ok": False, "error": "tls_certificate_invalid"})
            return report
        except (aiohttp.ClientError, asyncio.TimeoutError, OSError) as error:
            report["checks"].append({"stage": "https_health", "ok": False, "error": type(error).__name__})
            return report
        try:
            async with session.ws_connect(url, max_msg_size=16384) as ws:
                report["checks"].append({"stage": "unauthorized_websocket", "ok": False, "error": "unexpected_anonymous_connection"})
                return report
        except aiohttp.WSServerHandshakeError as error:
            denied = error.status == 401
            report["checks"].append({"stage": "unauthorized_websocket", "ok": denied, "http_status": error.status})
            if not denied:
                return report
        except (aiohttp.ClientError, asyncio.TimeoutError, OSError) as error:
            report["checks"].append({"stage": "unauthorized_websocket", "ok": False, "error": type(error).__name__})
            return report
        if not websocket:
            report["ok"] = True
            return report
        if not token:
            report["checks"].append({"stage": "websocket", "ok": False, "error": "device_token_required"})
            return report
        try:
            async with session.ws_connect(url, headers={"Authorization": "Bearer " + token}, max_msg_size=16384) as ws:
                ready = await asyncio.wait_for(ws.receive_json(), 10)
                connected = isinstance(ready, dict) and ready.get("type") == "ready" and ready.get("protocol") == 2
                report["checks"].append({"stage": "websocket", "ok": connected, "protocol": ready.get("protocol") if isinstance(ready, dict) else None})
                report["ok"] = connected
                # No interaction, receipt, status or user data is sent. Do not drain queued events.
        except aiohttp.WSServerHandshakeError as error:
            report["checks"].append({"stage": "websocket", "ok": False, "http_status": error.status})
        except (aiohttp.ClientError, asyncio.TimeoutError, OSError, ValueError) as error:
            report["checks"].append({"stage": "websocket", "ok": False, "error": type(error).__name__})
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--tokens-file", type=Path, help="existing DEVICE_A_TOKEN/DEVICE_B_TOKEN JSON; never put a token in a URL or argument")
    parser.add_argument("--member", choices=("A", "B"), default="A")
    parser.add_argument("--websocket", action="store_true", help="explicit authenticated probe; replaces this device's current live connection")
    parser.add_argument("--allow-local-http", action="store_true")
    args = parser.parse_args()
    try:
        if args.websocket and not args.tokens_file:
            raise ValueError("--websocket requires --tokens-file")
        token = read_tokens(args.tokens_file)[args.member] if args.websocket else None
        report = asyncio.run(probe(args.url, token, args.allow_local_http, args.websocket))
    except (OSError, ValueError):
        print("Invalid endpoint or token-file configuration; secret values were not printed.", file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
