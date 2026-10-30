#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-device}"
EDITION="${2:-aria}"
if [[ "$EDITION" != aria ]]; then echo 'this source package builds the Aria edition only' >&2; exit 2; fi
mkdir -p build
SOURCES=(Sources/*.m)
VERSION=5.2.0
RELEASE_TAG=5.2.0
BUILD_NUMBER=5200
EDITION_DEFINE=1
EDITION_LABEL="Aria专属（游定制最终版）"
EXTRA=(-DWP_BUILD_VERSION="$BUILD_NUMBER" -DWP_EDITION_ARIA="$EDITION_DEFINE" '-DWP_VERSION_STRING=@"5.2.0"')
if [[ -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then EXTRA+=("-DWP_RUNTIME_DIAGNOSTIC_URL=@\"${WP_RUNTIME_DIAGNOSTIC_URL}\""); fi
COMMON=(-fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework UniformTypeIdentifiers -lz)
BACKEND_CONFIG="${WP_BACKEND_CONFIG:-Config/backend.example.json}"
python3 - "$BACKEND_CONFIG" <<'PY'
import json,sys,urllib.parse
config=json.load(open(sys.argv[1]))
assert config.get('schemaVersion')==1, 'Unsupported backend config schema'
for name,value in config.get('endpoints',{}).items():
    parsed=urllib.parse.urlsplit(value)
    assert parsed.hostname and parsed.path=='/v1/ws' and not parsed.username and not parsed.password and not parsed.query and not parsed.fragment, 'Invalid backend endpoint'
    assert parsed.scheme=='wss' or (name=='development' and parsed.scheme=='ws' and parsed.hostname in ['127.0.0.1','localhost','::1']), 'Production requires WSS'
assert 'production' in config['endpoints'], 'Production endpoint missing'
PY
if [[ "$MODE" == device ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/inject"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/WeChatPet.bundle"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/WeChatPet.dylib "${SOURCES[@]}" -o "$STAGE/WeChatPet.dylib"
  rsync -a --exclude=Yue2Pet --exclude='AriaPet/*.webp' --exclude='AriaPet/spritesheet.png' --exclude='DefaultPet/row-*.png' --exclude='DefaultPet/spritesheet.png' Resources/ "$STAGE/WeChatPet.bundle/"
  python3 Tools/deduplicate-bundled-rows.py "$STAGE/WeChatPet.bundle"
  cp "$BACKEND_CONFIG" "$STAGE/WeChatPet.bundle/BackendConfig.json"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.zhour.wechatpet.resources' "$STAGE/WeChatPet.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $EDITION_LABEL" "$STAGE/WeChatPet.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $EDITION_LABEL" "$STAGE/WeChatPet.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$STAGE/WeChatPet.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$STAGE/WeChatPet.bundle/Info.plist"
  printf '{"edition":"%s","version":"%s","revision":"r1","build":%s,"privateFeatures":true,"stealthAvailable":false,"baseVersion":"1.2.5","defaultPet":"AriaPet"}\n' "$EDITION_LABEL" "$VERSION" "$BUILD_NUMBER" > "$STAGE/WeChatPet.bundle/Edition.json"
  codesign --force --sign - "$STAGE/WeChatPet.dylib"
  PACKAGE="build/${EDITION_LABEL}${RELEASE_TAG}-TrollFools.zip"
  rm -f "$PACKAGE"
  (cd "$STAGE" && /usr/bin/zip -qr "../../$(basename "$PACKAGE")" WeChatPet.dylib WeChatPet.bundle)
  file "$STAGE/WeChatPet.dylib"
  otool -L "$STAGE/WeChatPet.dylib"
elif [[ "$MODE" == preview ]]; then
  PREVIEW_FIXTURES=(Preview/main.m Preview/WP*Checks.m)
  if [[ "${WP_SOURCE_HOOK_FIXTURE:-1}" == 1 ]]; then PREVIEW_FIXTURES+=(Preview/WPContactMocks.m Preview/WPWeChatMocks.m); fi
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  APP=build/WeChatPetPreview.app
  # The host has no UIScene lifecycle; iOS 27 simulators stop such apps when
  # they record the iOS 27 SDK, so the link records SDK 18 instead.
  rm -rf "$APP/WeChatPet.bundle"
  mkdir -p "$APP/WeChatPet.bundle"
  xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.3-simulator -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -DWP_PREVIEW_HOST=1 -Wl,-export_dynamic -Wl,-platform_version,ios-simulator,16.3,18.0 "${SOURCES[@]}" "${PREVIEW_FIXTURES[@]}" -o "$APP/WeChatPetPreview"
  rsync -a --exclude=Yue2Pet --exclude='AriaPet/*.webp' --exclude='AriaPet/spritesheet.png' --exclude='DefaultPet/row-*.png' Resources/ "$APP/WeChatPet.bundle/"
  python3 Tools/deduplicate-bundled-rows.py "$APP/WeChatPet.bundle"
  python3 - "$APP/WeChatPet.bundle/Yue2Pet.zip" <<'PY'
import sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(Path('Resources/Yue2Pet').glob('*')):
        if file.is_file():archive.write(file,file.name)
PY
  cp Assets/YueSources/Memory110Evidence/anger-seam/known-old-assets.zip "$APP/WeChatPet.bundle/AtlasCorrectionFixture.zip"
  cp "$BACKEND_CONFIG" "$APP/WeChatPet.bundle/BackendConfig.json"
  cp Preview/Info.plist "$APP/Info.plist"
  xattr -cr "$APP"
  # File Provider can immediately re-add Finder metadata in Documents. Sign a
  # byte-only staging copy so its resource forks cannot race with codesign.
  SIGN_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/wechatpet-preview-sign.XXXXXX")"
  python3 - "$APP" "$SIGN_STAGE/WeChatPetPreview.app" <<'PY'
import shutil,sys
shutil.copytree(sys.argv[1],sys.argv[2],copy_function=shutil.copyfile)
PY
  codesign --force --sign - "$SIGN_STAGE/WeChatPetPreview.app"
  cp -R "$SIGN_STAGE/WeChatPetPreview.app/_CodeSignature" "$APP/"
  echo "$SIGN_STAGE/WeChatPetPreview.app" > build/preview-signed-path.txt
else
  echo 'usage: ./build.sh [device|preview] [aria]' >&2
  exit 2
fi
