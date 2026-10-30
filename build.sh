#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-device}"
EDITION="${2:-single}"
usage() { echo 'usage: ./build.sh [device|deb|preview|preview-embedded] [single|zhouyou|aria]' >&2; exit 2; }
# Each edition keeps the file names and storage of its earlier releases, so an
# injected package replaces the previous version of that same edition.
case "$EDITION" in
  single)  EDITION_ID=0; VERSION=1.5.3; BUILD_NUMBER=1503; EDITION_LABEL=Zhour; PRODUCT=Zhour ;;
  zhouyou) EDITION_ID=1; VERSION=1.3.0; BUILD_NUMBER=1300; EDITION_LABEL=周游专属包; PRODUCT=WeChatPet ;;
  aria)    EDITION_ID=2; VERSION=5.3.0; BUILD_NUMBER=5300; EDITION_LABEL="Aria专属（游定制最终版）"; PRODUCT=WeChatPet ;;
  *) usage ;;
esac
COUPLE=0; [[ "$EDITION" != single ]] && COUPLE=1
if [[ "$MODE" == deb || "$MODE" == preview-embedded ]] && (( COUPLE )); then
  echo "$MODE builds the single edition only; use device or preview for $EDITION" >&2; exit 2
fi
# Never package an opt-in diagnostic endpoint in a device release.
if [[ ( "$MODE" == device || "$MODE" == deb ) && -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then
  echo 'Release build blocked: unset WP_RUNTIME_DIAGNOSTIC_URL before packaging.' >&2
  exit 3
fi
mkdir -p build
SOURCES=(Sources/*.m)
INCLUDES=(-ISources)
if (( COUPLE )); then
  for file in Sources/Couple/*.m; do
    # Aria retired the weekday check-in reminder.
    [[ "$EDITION" == aria && "$file" == */WPWorkCheckinReminder.m ]] || SOURCES+=("$file")
  done
  INCLUDES+=(-ISources/Couple)
fi
EXTRA=(-DWP_BUILD_VERSION="$BUILD_NUMBER" -DWP_EDITION_ID="$EDITION_ID" "-DWP_VERSION_STRING=@\"$VERSION\"")
if [[ -n "${WP_RUNTIME_DIAGNOSTIC_URL:-}" ]]; then EXTRA+=("-DWP_RUNTIME_DIAGNOSTIC_URL=@\"${WP_RUNTIME_DIAGNOSTIC_URL}\""); fi
COMMON=(-fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations "${INCLUDES[@]}" -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework UniformTypeIdentifiers -lz)

# Resources each edition ships. The single edition downloads its Petdex pet at
# build time; the couple editions bundle their own pets and pairing endpoint.
RESOURCE_EXCLUDES=(--exclude=Yue2Pet --exclude=PetCorrections --exclude=couple-header-icon.png --exclude=BackendConfig.json --exclude=DefaultPet --exclude=AriaPet)
if [[ "$EDITION" == zhouyou ]]; then
  RESOURCE_EXCLUDES=(--exclude=Yue2Pet --exclude=AriaPet --exclude='DefaultPet/row-*.png')
elif [[ "$EDITION" == aria ]]; then
  RESOURCE_EXCLUDES=(--exclude=Yue2Pet --exclude='AriaPet/*.webp' --exclude='AriaPet/spritesheet.png' --exclude='DefaultPet/row-*.png')
fi
if (( COUPLE )); then
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
fi
# Copies this edition's resources into a resource bundle directory.
stage_resources() {
  local bundle="$1" device="$2"
  local excludes=("${RESOURCE_EXCLUDES[@]}")
  # The full development atlas stays out of device packages; previews keep it.
  if (( COUPLE )) && [[ "$device" == 1 ]]; then excludes+=(--exclude='DefaultPet/spritesheet.png'); fi
  rsync -a "${excludes[@]}" Resources/ "$bundle/"
  if (( COUPLE )); then
    python3 Tools/deduplicate-bundled-rows.py "$bundle"
    cp "$BACKEND_CONFIG" "$bundle/BackendConfig.json"
  else
    python3 Tools/prepare-single-lulu.py "$bundle/DefaultPet"
  fi
}
edition_json() {
  if [[ "$EDITION" == aria ]]; then
    printf '{"edition":"%s","version":"%s","revision":"r1","build":%s,"privateFeatures":true,"stealthAvailable":false,"defaultPet":"AriaPet"}\n' "$EDITION_LABEL" "$VERSION" "$BUILD_NUMBER"
  else
    printf '{"edition":"%s","version":"%s","revision":"r1","build":%s,"privateFeatures":%s}\n' "$EDITION_LABEL" "$VERSION" "$BUILD_NUMBER" "$( (( COUPLE )) && echo true || echo false )"
  fi
}

if [[ "$MODE" == device ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/inject"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/$PRODUCT.bundle"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/$PRODUCT.dylib "${SOURCES[@]}" -o "$STAGE/$PRODUCT.dylib"
  stage_resources "$STAGE/$PRODUCT.bundle" 1
  case "$EDITION" in
    single)  RESOURCE_ID=dev.zhour.wechatpet.single.resources; BUNDLE_NAME=Zhour ;;
    zhouyou) RESOURCE_ID=dev.zhour.wechatpet.resources; BUNDLE_NAME=WeChatPet ;;
    aria)    RESOURCE_ID=dev.zhour.wechatpet.resources; BUNDLE_NAME="$EDITION_LABEL" ;;
  esac
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $RESOURCE_ID" "$STAGE/$PRODUCT.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $BUNDLE_NAME" "$STAGE/$PRODUCT.bundle/Info.plist"
  if [[ "$EDITION" == aria ]]; then /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $EDITION_LABEL" "$STAGE/$PRODUCT.bundle/Info.plist"; fi
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$STAGE/$PRODUCT.bundle/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$STAGE/$PRODUCT.bundle/Info.plist"
  edition_json > "$STAGE/$PRODUCT.bundle/Edition.json"
  xcrun strip -x "$STAGE/$PRODUCT.dylib"
  codesign --force --sign - "$STAGE/$PRODUCT.dylib"
  case "$EDITION" in
    single)  PACKAGE="build/$EDITION_LABEL-$VERSION-TrollFools.zip" ;;
    zhouyou) PACKAGE="build/WeChatPet-$EDITION_LABEL-$VERSION-TrollFools.zip" ;;
    aria)    PACKAGE="build/${EDITION_LABEL}${VERSION}-TrollFools.zip" ;;
  esac
  rm -f "$PACKAGE"
  (cd "$STAGE" && /usr/bin/zip -qr "../../$(basename "$PACKAGE")" "$PRODUCT.dylib" "$PRODUCT.bundle")
  file "$STAGE/$PRODUCT.dylib"
  otool -L "$STAGE/$PRODUCT.dylib"
  echo "$PACKAGE"
elif [[ "$MODE" == deb ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  STAGE="build/$EDITION/deb"
  mkdir -p "$STAGE"
  python3 Tools/build-embedded-resources.py "$STAGE/resources.bin"
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.3 -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -dynamiclib -Wl,-install_name,@rpath/Zhour.dylib -Wl,-sectcreate,__DATA,__wpresources,"$STAGE/resources.bin" "${SOURCES[@]}" -o "$STAGE/Zhour.dylib"
  xcrun strip -x "$STAGE/Zhour.dylib"
  codesign --force --sign - "$STAGE/Zhour.dylib"
  for scheme in rootful rootless; do
    python3 Tools/build-single-deb.py --dylib "$STAGE/Zhour.dylib" --output "build/Zhour-$VERSION-$scheme.deb" --scheme "$scheme" --version "$VERSION"
  done
elif [[ "$MODE" == preview || "$MODE" == preview-embedded ]]; then
  PREVIEW_FIXTURES=(Preview/SingleMain.m Preview/WPCollectorChecks.m Preview/WPThumbnailOptimizationChecks.m Preview/WPRankingUIChecks.m Preview/WPMenuConfigurationChecks.m Preview/WPQuickAvatarGestureChecks.m Preview/WPHomePresentationChecks.m Preview/WPAdvisorProviderChecks.m Preview/WPAdvisorStatusChecks.m Preview/WPAdvisorTaskCenterChecks.m Preview/WPAdvisorContinuousChecks.m Preview/WPAdvisorReplyChecks.m Preview/WPAdvisorContextChecks.m Preview/WPAdvisorIncomingHookChecks.m Preview/WPAdvisorOverlayChecks.m Preview/WPChoiceSheetChecks.m)
  if (( COUPLE )); then PREVIEW_FIXTURES+=(Preview/WPCoupleEditionChecks.m); fi
  if [[ "${WP_SOURCE_HOOK_FIXTURE:-1}" == 1 ]]; then PREVIEW_FIXTURES+=(Preview/WPContactMocks.m Preview/WPWeChatMocks.m); fi
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  APP=build/WeChatPetPreview.app
  mkdir -p "$APP"
  # The host has no UIScene lifecycle; iOS 27 simulators stop such apps when
  # they record the iOS 27 SDK, so the link records SDK 18 instead.
  rm -rf "$APP/Zhour.bundle" "$APP/SinglePet-zhour.bundle" "$APP/zhour-single.bundle" "$APP/WeChatPet.bundle"
  PREVIEW_RESOURCE_LINK=(-Wno-unused-command-line-argument)
  if [[ "$MODE" == preview-embedded ]]; then
    python3 Tools/build-embedded-resources.py build/preview-embedded-resources.bin
    PREVIEW_RESOURCE_LINK=(-Wl,-sectcreate,__DATA,__wpresources,build/preview-embedded-resources.bin)
  else
    mkdir -p "$APP/$PRODUCT.bundle"
  fi
  xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.3-simulator -isysroot "$SDK" "${COMMON[@]}" "${EXTRA[@]}" -DWP_PREVIEW_HOST=1 -Wl,-export_dynamic -Wl,-platform_version,ios-simulator,16.3,18.0 "${PREVIEW_RESOURCE_LINK[@]}" "${SOURCES[@]}" "${PREVIEW_FIXTURES[@]}" -o "$APP/WeChatPetPreview"
  if [[ "$MODE" == preview ]]; then
    stage_resources "$APP/$PRODUCT.bundle" 0
    if (( COUPLE )); then
      python3 - "$APP/$PRODUCT.bundle/Yue2Pet.zip" <<'PY'
import sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(Path('Resources/Yue2Pet').glob('*')):
        if file.is_file():archive.write(file,file.name)
PY
    fi
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
  usage
fi
