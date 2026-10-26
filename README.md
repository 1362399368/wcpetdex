# WeChatPet-Aria 5.2.0

WeChat iOS desktop pet plugin source snapshot for the aria edition. The two editions are independent TrollFools packages. This repository was assembled from a source directory without Git history; older changes are summarized in [CHANGELOG.md](CHANGELOG.md) from saved release notes.

## Build

Requires macOS, Xcode, the iOS SDK, and Python 3. The source targets iOS 16.3 and later.

```sh
./build.sh preview aria
./build.sh device aria
```

`Config/backend.example.json` contains an intentionally nonfunctional service address. To enable pairing, create `Config/backend.json` from that example and set your own WSS endpoint, then build with `WP_BACKEND_CONFIG=Config/backend.json`. The personal configuration and device tokens are not included. The default build uses the example config and cannot connect to the original private service.

The simulator preview uses WeChat service fixtures. Passing those tests does not establish compatibility with every WeChat release or long term behavior on a real iPhone.

## License

Code is licensed under MIT; see [LICENSE](LICENSE). Character art and other pet images in `Assets/` and `Resources/` are included so the source can be built, but are **not** licensed under MIT. See [ASSET-LICENSE.md](ASSET-LICENSE.md). Third-party services and frameworks retain their own terms.
