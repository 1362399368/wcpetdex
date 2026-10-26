<p align="center">
  <img src="Resources/couple-header-icon.png" alt="WeChatPet-Zhouyou" width="100">
</p>

<h1 align="center">WeChatPet-Zhouyou</h1>

<p align="center">
  <img alt="版本 1.2.8" src="https://img.shields.io/badge/%E7%89%88%E6%9C%AC-1.2.8-blue">
  <a href="LICENSE">
    <img alt="许可证 MIT" src="https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-green">
  </a>
  <img alt="系统 iOS 16.3 及以上" src="https://img.shields.io/badge/%E7%B3%BB%E7%BB%9F-iOS%2016.3%2B-black?logo=apple">
  <img alt="微信 8.0.79" src="https://img.shields.io/badge/%E5%BE%AE%E4%BF%A1-8.0.79-07C160?logo=wechat&logoColor=white">
</p>

<p align="center">
  <strong>微信里的双人桌宠</strong><br/>
  一只会走路、会眨眼的桌宠住在微信界面上，帮你看未读、开聊天，还能给另一半发「想你了」。

  通过 TrollFools 注入 iOS 微信 · 周游专属包
</p>

<p align="center">
  <a href="#界面预览">界面预览</a> ·
  <a href="#主要功能">主要功能</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#开发">开发</a>
</p>

## 界面预览

<p align="center">默认桌宠「玥」的行走、互动、表情和贴边动作，每秒 30 帧</p>

<p align="center">
  <img src="Assets/Yue2Sources/Review/walking.gif" alt="行走" width="400">
  <img src="Assets/Yue2Sources/Review/interactions.gif" alt="互动" width="400">
</p>
<p align="center">
  <img src="Assets/Yue2Sources/Review/expressions.gif" alt="表情" width="400">
  <img src="Assets/Yue2Sources/Review/edge.gif" alt="贴边" width="400">
</p>

## 主要功能

1. **桌宠悬浮在微信上**，默认角色「玥」有 29 组动作；大小、不透明度、位置可调，拖到屏幕边缘会收起。
2. **换桌宠**，可以浏览 Petdex 在线桌宠库下载，也可以导入自己的桌宠包（`pet.json` 加透明 PNG/WebP 图集）。
3. **便捷聊天**，点桌宠展开左侧最近聊天栏，聊天以约 75% 高度的小窗或全屏打开。
4. **未读提醒**，桌宠头顶显示最新一条未读聊天的头像，点一下进入聊天；新消息以半透明弹幕飘过。折叠群聊和免打扰会话不提醒。
5. **手势和快捷菜单**，单击、双击可各自指定动作；长按桌宠滑出圆弧菜单，松手即可发「想你了」「生气了」、一键已读或进入朋友圈。
6. **双人互动**，两台手机配对后互发「想你了」「生气了」「摸摸头」，对方桌宠播放对应动画；离线时排队，回到微信后补达。摇晃桌宠打开互动记录。
7. **上班打卡提醒**，北京时间周一至周五 08:50–08:55 随机挑一个时间，给选定的对象发一条打卡提醒，每天最多一次。
8. **提醒强度可控**，提醒分「仅头像」「轻动作」「完整提醒」三档，支持安静时段（可跨午夜）和只对指定联系人触发动作。

## 快速开始

先在 Mac 上编译出插件包，再用 TrollFools 注入微信，最后在微信设置里打开插件页。双人互动需要额外自建服务，不用这个功能可以跳过第四步。

### 一、编译插件包

需要 macOS、Xcode（含 iOS SDK）和 Python 3。

```bash
./build.sh device personal
```

产物是压缩包 `build/WeChatPet-周游专属包-1.2.8-TrollFools.zip`，里面是动态库 `WeChatPet.dylib` 和资源包 `WeChatPet.bundle`。

### 二、注入微信

手机需要已装好 TrollStore 和 TrollFools，系统 iOS 16.3 及以上。把上一步的压缩包传到手机，在 TrollFools 里选中微信，注入这个压缩包。

### 三、打开插件设置

打开微信「我 → 设置」，列表里会多出「周游专属包」，所有功能都在这里开关。插件暂停后，也从这里恢复。

### 四、配置双人互动（可选）

双人互动需要自己搭一个加密 WebSocket 服务（地址以 `wss://` 开头），仓库里有两种实现：

- `Backend/`：Python 加 SQLite，自带 Docker Compose、Caddy 和 systemd 部署配置，用法见 [Backend/README.md](Backend/README.md)。
- `BackendCloudflare/`：Cloudflare Workers 加 Durable Objects，`BackendPages/` 是它前面的 Cloudflare Pages 网关。

服务跑起来后生成一组配对令牌，两台手机各填一个。编译时把服务地址写进配置：

```bash
cp Config/backend.example.json Config/backend.json
# 把 production 一项改成你自己的 wss://你的域名/v1/ws
WP_BACKEND_CONFIG=Config/backend.json ./build.sh device personal
```

> [!WARNING]
> `Config/backend.example.json` 里的地址故意不可用，不配置自己的服务就编译，配对功能连不上。`Config/backend.json` 已被 Git 忽略，不要提交。

## 使用须知

- 插件运行在微信进程里，微信切到后台或锁屏后会被 iOS 暂停。弹幕、双人互动和打卡提醒都要等回到微信前台才处理，没有锁屏推送。
- 插件调用的是微信私有接口，目前按 8.0.79 的运行时适配。换了微信版本后，设置页会显示「当前微信版本未适配」，相关功能不可用。
- 打卡提醒只记录「已调用发送接口」，不代表对方已收到，实际是否送达请在聊天里确认。
- 插件不保存聊天内容，弹幕消息只在内存里；双人互动服务不接入微信账号，只传固定的互动事件。
- 本仓库只构建周游专属包。

## 升级

拉取新代码后按「快速开始」第一步重新编译，再在 TrollFools 里重新注入新的压缩包。

## 开发

```bash
./build.sh preview personal                # 编译模拟器预览宿主
(cd BackendCloudflare && npm test)         # Cloudflare Workers 版服务测试，需 Node.js 22.13 及以上
(cd BackendPages && npm test)              # Cloudflare Pages 网关测试
(cd Backend && .venv/bin/python -m unittest -v test_server.py)  # Python 版服务测试，先按 Backend/README.md 建好虚拟环境
```

模拟器预览用的是模拟的微信服务，测试通过不代表真实微信可用，也不代表真机长时间运行没问题。其余测试脚本在 `Tests/` 目录，说明见 [Tests/README.md](Tests/README.md)。

所有改动走分支和拉取请求，分支命名和提交信息规范见 [贡献指南](CONTRIBUTING.md)，历史版本说明见 [更新日志](CHANGELOG.md)。

## 免责声明

本项目为第三方插件，与腾讯及微信无关，也与 TrollStore、TrollFools 及 Petdex 无关。向微信注入第三方插件可能违反微信的用户协议，使用风险自负。

## 许可证

<p align="center">
  源代码基于 <a href="LICENSE"><b>MIT 许可证</b></a> 开源。<br/>
  <code>Assets/</code> 和 <code>Resources/</code> 中的角色美术和桌宠图片不适用 MIT 许可证，详见 <a href="ASSET-LICENSE.md">ASSET-LICENSE.md</a>。<br/>
  <sub>© 2026 WeChatPet 贡献者</sub>
</p>
