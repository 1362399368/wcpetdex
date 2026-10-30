# 1.2.5（1206）验证

`run-v125-preview-suite.py` 顺序执行 unified-dock、source-adapter、optimization、barrage、基础、update、recovery 场景。启动前校验签名预览目录中Info.plist版本/构建号；每份报告带实际可执行文件SHA256。source-adapter含CH124/QC124；optimization含S124；barrage含真实memory warning、昵称和飞入触摸；recovery含R124/RN124/CR124。

独立快捷聊天与未读头像使用 `run-quickchat-preview.sh` / `run-unread-avatar-preview.sh`，输出v125报告。这些是微信服务夹具，不能证明真实微信私有接口兼容。

Foundation检查：

```sh
bash Tests/run-startup-and-retention-tests.sh
bash Tests/run-v038-history.sh
bash Tests/run-recovery-coordinator-v124-tests.sh
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPNativeRefreshGate.m Tests/native-refresh-gate-v124-tests.m -o build/native-refresh-gate-v124-tests
build/native-refresh-gate-v124-tests
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPCoupleHistory.m Tests/history-retention-v124-tests.m -o build/history-retention-v124-tests
build/history-retention-v124-tests /tmp/wechatpet-retention-1205
```

BackendCloudflare内用Node22.13+运行 `node --test test/*.test.mjs`。已有部署不为重打包再次部署；只读复查health。最终以 `release-v125-report.json` 汇总各报告的真实caseCount和来源，不将模拟器进程总内存当作插件增量内存。

设备构建后运行 `verify-v125-release.py` 检查实际ZIP、签名、后端配置、动画像素、逻辑帧映射、无Plove以及无预览夹具。源码清单在source-manifest-v125.json。真机过夜、实际键盘和引用场景尚未完成时必须如实列出。

1.2.5新增：QC125暖缓存/复用/失败重试；BS125索引/混合来源/延迟消息；B125准入去重/暂停/布局；CH125删除高度记忆并保留原生代理；RN125安全轮询；LA125数据库头像回退。
