#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-device}"
EDITION="${2:-single}"
if [[ "$EDITION" != single ]]; then echo 'this source package builds the single edition only' >&2; exit 2; fi
# Never package an opt-in diagnostic endpoint in a device release.
if [[ ( "$MODE" == device || "$MODE" == deb ) && -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then
  echo 'Release build blocked: unset WP_RUNTIME_DIAGNOSTIC_URL before packaging.' >&2
  exit 3
fi
mkdir -p build
SOURCES=(Sources/*.m)
VERSION=1.5.0
RELEASE_TAG=1.5.0
BUILD_NUMBER=1500
EDITION_DEFINE=0
EDITION_LABEL=Zhour
EXTRA=(-DWP_BUILD_VERSION="$BUILD_NUMBER" -DWP_EDITION_ARIA="$EDITION_DEFINE" '-DWP_VERSION_STRING=@"1.5.0"')
if [[ -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then EXTRA+=("-DWP_RUNTIME_DIAGNOSTIC_URL=@\"${WP_RUNTIME_DIAGNOSTIC_URL}\""); fi
COMMON=(-fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework UniformTypeIdentifiers -lz)
if [[ "$MODE" == device ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/inject"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/Zhour.bundle"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/Zhour.dylib "${SOURCES[@]}" -o "$STAGE/Zhour.dylib"
  rsync -a --exclude=Yue2Pet --exclude=PetCorrections --exclude=couple-header-icon.png --exclude=BackendConfig.json --exclude=DefaultPet Resources/ "$STAGE/Zhour.bundle/"
  python3 Tools/prepare-single-lulu.py "$STAGE/Zhour.bundle/DefaultPet"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.zhour.wechatpet.single.resources' "$STAGE/Zhour.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleName string Zhour' "$STAGE/Zhour.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$STAGE/Zhour.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$STAGE/Zhour.bundle/Info.plist"
  printf '{"edition":"%s","version":"%s","revision":"r1","build":%s,"privateFeatures":false}\n' "$EDITION_LABEL" "$VERSION" "$BUILD_NUMBER" > "$STAGE/Zhour.bundle/Edition.json"
  xcrun strip -x "$STAGE/Zhour.dylib"
  codesign --force --sign - "$STAGE/Zhour.dylib"
  PACKAGE="build/$EDITION_LABEL-$RELEASE_TAG-TrollFools.zip"
  rm -f "$PACKAGE"
  (cd "$STAGE" && /usr/bin/zip -qr "../../$(basename "$PACKAGE")" Zhour.dylib Zhour.bundle)
  file "$STAGE/Zhour.dylib"
  otool -L "$STAGE/Zhour.dylib"
elif [[ "$MODE" == deb ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/deb"
  mkdir -p "$STAGE"
  python3 Tools/build-embedded-resources.py "$STAGE/resources.bin"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/Zhour.dylib -Wl,-sectcreate,__DATA,__wpresources,"$STAGE/resources.bin" "${SOURCES[@]}" -o "$STAGE/Zhour.dylib"
  xcrun strip -x "$STAGE/Zhour.dylib"
  codesign --force --sign - "$STAGE/Zhour.dylib"
  for scheme in rootful rootless; do
    python3 Tools/build-single-deb.py --dylib "$STAGE/Zhour.dylib" --output "build/Zhour-$RELEASE_TAG-$scheme.deb" --scheme "$scheme" --version "$VERSION"
  done
elif [[ "$MODE" == preview || "$MODE" == preview-embedded ]]; then
  PREVIEW_FIXTURES=(Preview/SingleMain.m Preview/WPCollectorChecks.m Preview/WPThumbnailOptimizationChecks.m Preview/WPRankingUIChecks.m Preview/WPMenuConfigurationChecks.m Preview/WPQuickAvatarGestureChecks.m Preview/WPHomePresentationChecks.m Preview/WPAdvisorProviderChecks.m Preview/WPAdvisorStatusChecks.m Preview/WPAdvisorTaskCenterChecks.m Preview/WPAdvisorContinuousChecks.m Preview/WPAdvisorReplyChecks.m Preview/WPAdvisorContextChecks.m Preview/WPAdvisorIncomingHookChecks.m)
  if [[ "${WP_SOURCE_HOOK_FIXTURE:-1}" == 1 ]]; then PREVIEW_FIXTURES+=(Preview/WPContactMocks.m Preview/WPWeChatMocks.m); fi
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  APP=build/WeChatPetPreview.app
  mkdir -p "$APP"
  # The host has no UIScene lifecycle; iOS 27 simulators stop such apps when
  # they record the iOS 27 SDK, so the link records SDK 18 instead.
  rm -rf "$APP/Zhour.bundle" "$APP/SinglePet-zhour.bundle" "$APP/zhour-single.bundle"
  PREVIEW_RESOURCE_LINK=(-Wno-unused-command-line-argument)
  if [[ "$MODE" == preview-embedded ]]; then
    python3 Tools/build-embedded-resources.py build/preview-embedded-resources.bin
    PREVIEW_RESOURCE_LINK=(-Wl,-sectcreate,__DATA,__wpresources,build/preview-embedded-resources.bin)
  else
    mkdir -p "$APP/Zhour.bundle"
  fi
  xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.3-simulator -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -DWP_PREVIEW_HOST=1 -Wl,-export_dynamic -Wl,-platform_version,ios-simulator,16.3,18.0 "${PREVIEW_RESOURCE_LINK[@]}" "${SOURCES[@]}" "${PREVIEW_FIXTURES[@]}" -o "$APP/WeChatPetPreview"
  if [[ "$MODE" == preview ]]; then
    rsync -a --exclude=Yue2Pet --exclude=PetCorrections --exclude=couple-header-icon.png --exclude=BackendConfig.json --exclude=DefaultPet Resources/ "$APP/Zhour.bundle/"
    python3 Tools/prepare-single-lulu.py "$APP/Zhour.bundle/DefaultPet"
  fi
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
  echo 'usage: ./build.sh [device|deb|preview|preview-embedded] [single]' >&2
  exit 2
fi
