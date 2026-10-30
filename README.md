# Zhour

Zhour 是一款微信桌宠插件。默认形象是来自 Petdex 的噜噜，可以在微信里陪你查看消息、快捷进入聊天，也可以从桌宠库切换或导入其他形象。支持 WCPlugin 插件收纳；未检测到可用收纳时从微信设置进入。

- **快捷聊天**：点击桌宠打开会话列表，点头像进入聊天。
- **消息弹幕**：在微信界面显示消息提醒，可调整显示方式。
- **自由手势**：在快捷设置中统一调整单击、双击、长按、摇晃、贴边以及聊天头像操作。
- **长按菜单**：自行显示、隐藏和排序功能，并可设置最多三个带头像的快捷联系人。
- **桌宠外观**：调整桌宠大小和位置，使用桌宠库或导入外观包。
- **Telegram 交流**：可从设置首页进入 [Telegram 群](https://t.me/+TdjkYED5H4Q3ZTdh)。
- **聊天参谋**：配置模型服务后，可并行分析多个聊天、取消任务并查看本机记录；支持对指定私聊开启前台连续分析，保留恋爱聊天等预设。手势可选择每次选场景的参谋聊天，或使用固定预设的直接参谋。

聊天参谋在你主动分析或为联系人开启连续模式时，会把选取的聊天内容发送给你配置的模型服务；API Key 保存在本机钥匙串。每个账号最多保留最新 50 条建议结果，并在三天后清理；原始上下文仅短暂保留在内存。连续模式要求微信在前台，并依赖微信私有消息接口：先打开选定聊天以加载上下文；内存压力或重新启动后可能需要重新打开。在线桌宠库需要网络。

## 安装与构建

DEB 包的内置噜噜资源随插件携带，不需要另装 `.bundle`。首次使用默认显示噜噜，之前选过其他桌宠则沿用原选择。Rootless 和 Rootful 请按安装环境选择。注入 IPA 时请先移除旧版 `zhour-single`，避免同时加载两个版本。

开发构建需要 macOS、Xcode iOS SDK、Python 3、支持 WebP 的 Pillow 和 OpenSSL。运行 `./build.sh deb single` 构建两种 DEB；`./build.sh device single` 构建 ZIP；`./build.sh preview-embedded single` 可构建模拟器预览。插件依赖微信内部接口，请在实际设备与微信版本上测试。

## 双人互动版本

同一份源码还能构建两个双人互动版本，构建时用第二个参数选择：

| 参数 | 版本 | 默认形象 | 独有功能 | 产物 |
| --- | --- | --- | --- | --- |
| `single` | Zhour 1.5.3 | 噜噜 | 无配对 | `Zhour.dylib` + `Zhour.bundle`，或 DEB |
| `zhouyou` | 周游专属包 1.3.0 | 玥 | 配对互动、隐身、工作日上班打卡提醒 | `WeChatPet.dylib` + `WeChatPet.bundle` |
| `aria` | Aria专属版 5.3.0 | Aria | 配对互动 | `WeChatPet.dylib` + `WeChatPet.bundle` |

```sh
./build.sh device zhouyou
./build.sh device aria
./build.sh preview zhouyou
```

双人版只支持 `device` 和 `preview`，不出 DEB。两个双人版沿用此前版本的偏好域（`dev.zhour.wechatpet`）、数据目录（`WeChatPet`）、钥匙串和资源包名，注入时直接替换旧版即可保留配对、互动记录和已选桌宠；不要与 Zhour 同时注入。

双人互动需要自建加密 WebSocket 服务，仓库提供 `Backend/`（Python + SQLite）和 `BackendCloudflare/`（Workers + Durable Objects，`BackendPages/` 为其网关）两种实现。`Config/backend.example.json` 中的地址故意不可用，构建前复制为 `Config/backend.json` 填入自己的服务，再用 `WP_BACKEND_CONFIG=Config/backend.json ./build.sh device zhouyou` 构建；`Config/backend.json` 已被 Git 忽略。

双人版专属源码在 `Sources/Couple/`，只在双人版编译；共享源码里的接入点用 `WP_EDITION_COUPLE`、`WP_FEATURE_STEALTH`、`WP_FEATURE_WORK_CHECKIN` 区分，定义见 `Sources/WPEdition.h`。模拟器自检对三个版本都适用（见 `Tests/README.md`），双人版另加 `Preview/WPCoupleEditionChecks.m` 中的检查。

内嵌资源经过 AES 混淆并验证内容完整性，发布构建移除部分符号。密钥位于客户端及公开源码中，这些措施只能增加直接提取的难度，不能保证防复制或防破解。软件按本仓库 MIT 许可发布；噜噜由 Petdex 用户 gitcjp 提供，素材不在软件 MIT 许可范围内，公开再分发前请确认素材授权，详见 `ASSET-LICENSE.md`。
