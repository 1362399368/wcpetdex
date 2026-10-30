#!/bin/bash
# Quick chat end-to-end checks in the iOS simulator against mock WeChat
# session services (Preview/WPQuickChatMocks.m). Not a WeChat or device test.
# The preview host uses the app-delegate window lifecycle; iOS 27 stops apps
# linked against the iOS 27 SDK without scenes, so the link records SDK 18.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 17}"
SCENARIO="${WP_QUICKCHAT_PREVIEW_SCENARIO:-quickchat}"
if [[ "$SCENARIO" != quickchat && "$SCENARIO" != unread-avatar ]]; then echo 'Unsupported preview scenario' >&2; exit 2; fi
REPORT_TARGET="Tests/quickchat-preview-v126-report.json"
if [[ "$SCENARIO" == unread-avatar ]]; then REPORT_TARGET="Tests/unread-avatar-v126-report.json"; fi
BUNDLE=dev.zhour.wechatpet.quickchatpreview
APP=build/WeChatPetQuickChatPreview.app
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
rm -rf "$APP" && mkdir -p "$APP/WeChatPet.bundle"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.3-simulator -isysroot "$SDK" -fobjc-arc -fblocks -O0 -Wno-deprecated-declarations -ISources \
  -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework UniformTypeIdentifiers -lz \
  -Wl,-platform_version,ios-simulator,16.3,18.0 \
  -DWP_EDITION_ARIA=0 -DWP_PREVIEW_HOST=1 Sources/*.m Preview/main.m Preview/WP*Checks.m Preview/WPContactMocks.m Preview/WPQuickChatMocks.m -o "$APP/WeChatPetPreview"
rsync -a --exclude=Yue2Pet Resources/ "$APP/WeChatPet.bundle/"
cp Config/backend.json "$APP/WeChatPet.bundle/BackendConfig.json"
cp Preview/Info.plist "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE" "$APP/Info.plist"
xattr -cr "$APP"
SIGN_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/wechatpet-quickchat-sign.XXXXXX")"
python3 - "$APP" "$SIGN_STAGE/WeChatPetQuickChatPreview.app" <<'PY'
import shutil,sys
shutil.copytree(sys.argv[1],sys.argv[2],copy_function=shutil.copyfile)
PY
codesign --force --sign - "$SIGN_STAGE/WeChatPetQuickChatPreview.app"
APP="$SIGN_STAGE/WeChatPetQuickChatPreview.app"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
DATA="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Library/Application Support/WeChatPet"
rm -f "$DATA/$SCENARIO-report.json"
xcrun simctl launch "$DEVICE" "$BUNDLE" "--$SCENARIO-self-test" >/dev/null
for _ in $(seq 1 90); do [[ -f "$DATA/$SCENARIO-report.json" ]] && break; sleep 1; done
mkdir -p Tests/ui-v126
cp "$DATA/$SCENARIO-report.json" "$REPORT_TARGET"
cp "$DATA"/"$SCENARIO"-*.png Tests/ui-v126/ 2>/dev/null || true
if [[ "$SCENARIO" == quickchat && -f "$DATA/quickchat-regression-diagnostics.json" ]]; then cp "$DATA/quickchat-regression-diagnostics.json" Tests/quickchat-diagnostics-v126.json; fi
if [[ "$SCENARIO" == unread-avatar && -f "$DATA/unread-avatar-preferences.json" ]]; then cp "$DATA/unread-avatar-preferences.json" Tests/unread-avatar-preferences-v126.json; fi
python3 - "$REPORT_TARGET" "$APP" <<'PY'
import json
import sys
import hashlib
import plistlib
from pathlib import Path
from datetime import datetime, timezone
app=Path(sys.argv[2]);info=plistlib.loads((app/"Info.plist").read_bytes())
assert str(info.get("CFBundleShortVersionString"))=="1.2.6" and str(info.get("CFBundleVersion"))=="1207"
result = json.load(open(sys.argv[1]))
result["validationBuild"]={"version":"1.2.6","build":"1207","fixtureHost":"quickchat","validatedAtUTC":datetime.now(timezone.utc).isoformat(),"executableSHA256":hashlib.sha256((app/info["CFBundleExecutable"]).read_bytes()).hexdigest()}
Path(sys.argv[1]).write_text(json.dumps(result,ensure_ascii=False,indent=2))
failed = [k for k, v in result['results'].items() if not v]
print(f"{sys.argv[1]}: {result['caseCount'] - len(failed)}/{result['caseCount']} passed", failed or '')
assert result['allPassed']
PY
