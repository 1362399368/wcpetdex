# Changelog — Zhouyou edition

This is a release-note summary, not reconstructed Git commit history. Original source snapshots did not contain a `.git` directory.

## 1.2.6 (build 1207, 2026-10-26)

- Fixed the barrage metadata retry queue so an older retry cannot evict a newly received message when the 12-entry inbox is full.
- Added regression case `BS12601MetadataRetryDoesNotEvictFreshInbox`.
- Saved validation: 834 simulator preview checks, 46 quick-chat checks, 35 unread-avatar checks, and package integrity/signature checks. Real-device overnight recovery remained unverified.

## 1.2.5 (build 1206, 2026-10-25)

- Fixed avatars reverting to placeholders when the quick-chat list is reopened or a reused cell receives a stale offscreen callback. Added bounded retry and caching behavior.
- Kept native message callbacks and new-message monitoring as complementary barrage sources, with stable-ID deduplication and a bounded metadata retry.
- Removed custom chat sheet height locking and height memory; retained the native approximately 75% initial sheet.
- Saved validation: 833 simulator preview checks, 46 quick-chat checks, and 35 unread-avatar checks. Real WeChat injection paths were not fully checked.

## 1.2.4 (2026-10-25)

- Added graded memory-pressure cleanup for the barrage, shared avatar caching, unread-avatar synchronization, and interaction-history clearing.
- Improved settings panel routing and the native chat sheet fallback.
- The saved 1.2.4 note describes 773 simulator checks. Its validation is historical and does not verify the current snapshot.

## 1.2.3 (2026-10-25)

- Kept active barrage messages across temporary session-cache gaps and page transitions.
- Unified the pet, barrage, and unread-avatar overlay; refined native chat sheet behavior.
- Later releases deliberately removed the custom height memory described in this historical version.

Earlier 1.0.x and 1.1.x release notes were saved separately in the original working directories; they are not represented as Git commits in this repository.
