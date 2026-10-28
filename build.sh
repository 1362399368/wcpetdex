#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-device}"
EDITION="${2:-single}"
if [[ "$EDITION" != single ]]; then echo 'this source package builds the single edition only' >&2; exit 2; fi
# Never package an opt-in diagnostic endpoint in a device release.
if [[ "$MODE" == device && -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then
  echo 'Release build blocked: unset WP_RUNTIME_DIAGNOSTIC_URL before packaging.' >&2
  exit 3
fi
mkdir -p build
SOURCES=(Sources/*.m)
VERSION=1.2.8
RELEASE_TAG=1.2.8
BUILD_NUMBER=1209
EDITION_DEFINE=0
EDITION_LABEL=zhour-single
EXTRA=(-DWP_BUILD_VERSION="$BUILD_NUMBER" -DWP_EDITION_ARIA="$EDITION_DEFINE" '-DWP_VERSION_STRING=@"1.2.8"')
if [[ -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then EXTRA+=("-DWP_RUNTIME_DIAGNOSTIC_URL=@\"${WP_RUNTIME_DIAGNOSTIC_URL}\""); fi
COMMON=(-fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework UniformTypeIdentifiers -lz)
if [[ "$MODE" == device ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/inject"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/zhour-single.bundle"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/zhour-single.dylib "${SOURCES[@]}" -o "$STAGE/zhour-single.dylib"
  rsync -a --exclude=Yue2Pet --exclude=PetCorrections --exclude=couple-header-icon.png --exclude=BackendConfig.json --exclude=DefaultPet Resources/ "$STAGE/zhour-single.bundle/"
  python3 Tools/prepare-single-lulu.py "$STAGE/zhour-single.bundle/DefaultPet"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.zhour.wechatpet.single.resources' "$STAGE/zhour-single.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleName string zhour-single' "$STAGE/zhour-single.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$STAGE/zhour-single.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$STAGE/zhour-single.bundle/Info.plist"
  printf '{"edition":"%s","version":"%s","revision":"r1","build":%s,"privateFeatures":false}\n' "$EDITION_LABEL" "$VERSION" "$BUILD_NUMBER" > "$STAGE/zhour-single.bundle/Edition.json"
  codesign --force --sign - "$STAGE/zhour-single.dylib"
  PACKAGE="build/$EDITION_LABEL-$RELEASE_TAG-TrollFools.zip"
  rm -f "$PACKAGE"
  (cd "$STAGE" && /usr/bin/zip -qr "../../$(basename "$PACKAGE")" zhour-single.dylib zhour-single.bundle)
  file "$STAGE/zhour-single.dylib"
  otool -L "$STAGE/zhour-single.dylib"
elif [[ "$MODE" == preview ]]; then
  PREVIEW_FIXTURES=(Preview/SingleMain.m)
  if [[ "${WP_SOURCE_HOOK_FIXTURE:-1}" == 1 ]]; then PREVIEW_FIXTURES+=(Preview/WPContactMocks.m Preview/WPWeChatMocks.m); fi
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  APP=build/WeChatPetPreview.app
  # The host has no UIScene lifecycle; iOS 27 simulators stop such apps when
  # they record the iOS 27 SDK, so the link records SDK 18 instead.
  rm -rf "$APP/zhour-single.bundle"
  mkdir -p "$APP/zhour-single.bundle"
  xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.3-simulator -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -DWP_PREVIEW_HOST=1 -Wl,-export_dynamic -Wl,-platform_version,ios-simulator,16.3,18.0 "${SOURCES[@]}" "${PREVIEW_FIXTURES[@]}" -o "$APP/WeChatPetPreview"
  rsync -a --exclude=Yue2Pet --exclude=PetCorrections --exclude=couple-header-icon.png --exclude=BackendConfig.json --exclude=DefaultPet Resources/ "$APP/zhour-single.bundle/"
  python3 Tools/prepare-single-lulu.py "$APP/zhour-single.bundle/DefaultPet"
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
  echo 'usage: ./build.sh [device|preview] [single]' >&2
  exit 2
fi
