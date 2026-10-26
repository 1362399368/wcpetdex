# Changelog — Aria edition

This is a release-note summary, not reconstructed Git commit history. Original source snapshots did not contain a `.git` directory.

## 5.2.0 (build 5200, 2026-10-25)

- Rebased the independent Aria package on Zhouyou 1.2.5, retaining its quick chat, barrage, unread avatar, pairing, pet library, and recovery behavior.
- Removed stealth settings, network requests, and send restrictions while preserving ordinary online status.
- Preserved Aria's 29 animation rows, 286 effective frames, edge poses, direction mirroring, and timing.
- Saved validation: 862 simulator preview checks, 46 quick-chat checks, 35 unread-avatar checks, and 42 release checks. Real-device WeChat and overnight tests remained outstanding.

## 1.1.0 (2026-10-24)

- Removed redundant animation atlases and unused default assets from the installation package; retained the 29 rows and 286 frames.
- Added position locking, separate portrait/landscape positions, reminder modes, quiet hours, selected contacts, and unread peek behavior.
- Reduced temporary image/ZIP processing memory and improved animation fallback behavior.

## 1.0.0 (2026-10-24)

- Converted animation rows to lossless WebP and retained a PNG fallback; kept animation pixels and frame timing.
- Added on-demand transparent hit masks and bounded avatar decoding.
- An optional historical bundle contained a user-provided Plove binary; that third-party bundle is not part of this source snapshot.

## 0.3.12 (2026-10-20)

- Fixed Aria preview visibility and added memory limits for atlases, avatar loading, downloads, and ZIP import.

## 0.3.11 (2026-10-20)

- Added directional mirroring, relationship-card avatar fallback, a WeChat settings entry, and the simplified quick-chat sidebar.
