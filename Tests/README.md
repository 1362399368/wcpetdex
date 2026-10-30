# zhour-single 验证

这些命令面向本分支的单身版，旧版情侣服务器、互动历史、玥素材及对应发布检查不适用。旧版混合功能测试保留作参考，不列作本版通过的检查。

```sh
bash Tests/run-single-gesture-tests.sh
python3 Tests/test-single-lulu.py
./build.sh preview single
./build.sh device single
```

噜噜图片准备脚本需要 Pillow；未缓存时从 Petdex 官方地址下载并校验 SHA-256。图像测试比较全部 9 行与原始精灵图的像素。

双人版用 `./build.sh preview zhouyou` 或 `./build.sh preview aria` 构建同一测试宿主，报告写入 `Library/Application Support/WeChatPet/single-preview-report.json`，并额外包含 `Preview/WPCoupleEditionChecks.m` 的双人检查（存储标识、默认形象、手势默认值、菜单、隐身与打卡开关、设置入口、红点和发送互动）。发送走测试替身，不连接配对服务。

模拟器验证使用 `Preview/SingleMain.m`，运行测试宿主并传入 `--single-self-test`，结果写入测试宿主的 `Library/Application Support/WeChatPetSingle/single-preview-report.json`。报告检查资源包、默认噜噜、贴图、手势配置和手势设置入口。模拟器使用测试微信接口，不能证明真实微信私有接口、长时间内存表现或真机兼容性。

真机测试需要使用测试版插件替换旧版桌宠后注入；不应同时注入两版。检查桌宠渲染与动作、长按和摇晃设置、快捷聊天、弹幕、聊天小窗及微信前后台切换。
