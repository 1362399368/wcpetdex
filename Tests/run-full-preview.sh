#!/bin/bash
# Full UIKit regression in the simulator preview host, not in WeChat.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-WeChatPet-Preview}"
BUNDLE=dev.zhour.wechatpet.preview
./build.sh preview personal
APP="$(cat build/preview-signed-path.txt)"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
DATA="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Library/Application Support/WeChatPet"
rm -f "$DATA/test-report.json"
xcrun simctl launch "$DEVICE" "$BUNDLE" --self-test >/dev/null
for _ in $(seq 1 90); do
  [[ -f "$DATA/test-report.json" ]] && python3 - "$DATA/test-report.json" <<'PY' && break
import json,sys
try:
    report=json.load(open(sys.argv[1]))
    assert report.get('finished')
except (OSError,ValueError,AssertionError):
    sys.exit(1)
PY
  sleep 2
done
if [[ ! -f "$DATA/test-report.json" ]]; then echo 'Full preview did not produce a report' >&2; exit 1; fi
cp "$DATA/test-report.json" Tests/preview-v110-report.json
python3 - <<'PY'
import json
report=json.load(open('Tests/preview-v110-report.json'))
failed=[name for name,value in report.items() if value is False]
print(f"preview-v110-report.json: {report['caseCount']-len(failed)}/{report['caseCount']} passed")
if failed: print('Failed: '+', '.join(failed))
assert report['finished'] and report['allPassed'] and not failed
PY
