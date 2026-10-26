#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -fblocks -ISources -IPreview -framework Foundation Sources/WPRecoveryCoordinator.m Preview/WPRecovery124Checks.m Tests/recovery-coordinator-v124-tests.m -o build/recovery-coordinator-v124-tests
build/recovery-coordinator-v124-tests
