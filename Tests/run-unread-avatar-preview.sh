#!/bin/bash
# Shares the quick-chat mock host; scenarios must run sequentially.
set -euo pipefail
cd "$(dirname "$0")/.."
WP_QUICKCHAT_PREVIEW_SCENARIO=unread-avatar bash Tests/run-quickchat-preview.sh "${1:-WeChatPet-Preview}"
