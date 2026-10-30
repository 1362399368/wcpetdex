#!/bin/bash
# Chat advisor: transcript, prompt, parsing and input checks, then the request
# path and overlay card against a loopback mock. No real model is contacted.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-WeChatPet-Preview}"
BUNDLE=dev.zhour.wechatpet.preview
PORT="${WP_ADVISOR_MOCK_PORT:-18765}"
LOG="$(mktemp "${TMPDIR:-/tmp}/chat-advisor-requests.XXXXXX")"
./build.sh preview personal
APP="$(cat build/preview-signed-path.txt)"
python3 Tests/chat-advisor-mock-server.py "$PORT" "$LOG" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null || true; rm -f "$LOG"' EXIT
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
DATA="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Library/Application Support/WeChatPet"
xcrun simctl launch "$DEVICE" "$BUNDLE" --chat-advisor-self-test "--chat-advisor-base=http://127.0.0.1:$PORT/v1" >/dev/null
for _ in $(seq 1 90); do [[ -f "$DATA/chat-advisor-report.json" ]] && break; sleep 1; done
[[ -f "$DATA/chat-advisor-report.json" ]] || { echo 'Chat advisor checks did not finish' >&2; exit 1; }
cp "$DATA/chat-advisor-report.json" Tests/chat-advisor-report.json
mkdir -p Tests/ui-chat-advisor
cp "$DATA"/chat-advisor-*.png Tests/ui-chat-advisor/ 2>/dev/null || true
python3 - "$LOG" <<'PY'
import json, sys
report = json.load(open('Tests/chat-advisor-report.json'))
failed = [name for name, value in report['results'].items() if not value]
requests = [json.loads(line) for line in open(sys.argv[1], encoding='utf-8')]
posts = [r for r in requests if r['method'] == 'POST']
# What actually left the app: no WeChat usernames, the key only in the header.
leaked = [r for r in posts if 'wxid_' in json.dumps(r['body'], ensure_ascii=False)]
if not posts: failed.append('mockReceivedRequests')
if leaked: failed.append('requestBodiesFreeOfUsernames')
if not any(r['authorization'] == 'Bearer test-key-123' for r in posts): failed.append('bearerKeySent')
if any('test-key-123' in json.dumps(r['body'], ensure_ascii=False) for r in posts): failed.append('keyNotInBody')
total = report['caseCount'] + 4
print(f"chat-advisor-report.json: {total-len(failed)}/{total} passed, {len(posts)} chat requests seen by the mock")
if failed: print('Failed: ' + ', '.join(failed))
assert report['finished'] and not failed
PY
