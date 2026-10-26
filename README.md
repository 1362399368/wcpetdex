# WeChatPet-Zhouyou 1.2.8

WeChat iOS desktop pet plugin source snapshot for the personal edition. The two editions are independent TrollFools packages. This repository was assembled from a source directory without Git history; older changes are summarized in [CHANGELOG.md](CHANGELOG.md) from saved release notes.

## Build

Requires macOS, Xcode, the iOS SDK, and Python 3. The source targets iOS 16.3 and later.

```sh
./build.sh preview personal
./build.sh device personal
```

`Config/backend.example.json` contains an intentionally nonfunctional service address. To enable pairing, create `Config/backend.json` from that example and set your own WSS endpoint, then build with `WP_BACKEND_CONFIG=Config/backend.json`. The personal configuration and device tokens are not included. The default build uses the example config and cannot connect to the original private service.

The simulator preview uses WeChat service fixtures. Passing those tests does not establish compatibility with every WeChat release or long term behavior on a real iPhone.

## Weekday check-in reminder

The personal edition can send a configured text to the selected partner's WeChat chat once per weekday. It chooses and saves a random second between 08:50:00 and 08:54:49 in the `Asia/Shanghai` time zone. If WeChat returns to the foreground after that second but before 08:55, it tries within the remaining window. The feature is enabled by default and can be changed under **情侣互动 → 上班打卡提醒**.

The plugin runs inside WeChat: iOS may suspend it when WeChat is backgrounded or the phone is locked, so no message is sent outside the time window. Sending opens the partner chat and uses WeChat's native text-send method after checking the active chat identity and method signature. The plugin records a call to that method, not server delivery. This private method needs validation on the installed WeChat build; a device build alone does not prove that a message will reach the recipient.

## License

Code is licensed under MIT; see [LICENSE](LICENSE). Character art and other pet images in `Assets/` and `Resources/` are included so the source can be built, but are **not** licensed under MIT. See [ASSET-LICENSE.md](ASSET-LICENSE.md). Third-party services and frameworks retain their own terms.
