#!/bin/bash
# Shares the quick-chat mock host; run after the other simulator scenarios.
set -euo pipefail
cd "$(dirname "$0")/.."
WP_QUICKCHAT_PREVIEW_SCENARIO=unread-avatar bash Tests/run-quickchat-preview-v126.sh "${1:-WeChatPet-Preview}"
