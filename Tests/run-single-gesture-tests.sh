#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/zhour-single-gestures.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# WPCommon.h imports UIKit; this test supplies just its preferences interface
# and compiles the unchanged action implementation against Foundation.
sed 's/#import "WPCommon.h"/FOUNDATION_EXPORT NSUserDefaults *WPPreferences(void);/' Sources/WPTapActions.m > "$test_dir/WPTapActions.m"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -ISources -framework Foundation "$test_dir/WPTapActions.m" Tests/single-gesture-tests.m -o "$test_dir/tests"
"$test_dir/tests"
