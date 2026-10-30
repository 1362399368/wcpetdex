# 双人互动服务（尚未部署）

两个独立设备令牌对应同一对情侣。令牌通过 WebSocket 的 Authorization 请求头发送，服务端只保存 SHA-256 摘要。服务不接入微信账号，不读取微信聊天。

## 本地测试

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest -v test_server.py
export PETPAIR_ADMIN_TOKEN="$(openssl rand -hex 32)"
.venv/bin/python server.py
```

默认只监听 `127.0.0.1:8765`。配置 `PETPAIR_DB` 可改变 SQLite 文件路径，默认 `data/petpair.sqlite3`。将数据库目录设为当前服务用户可读写。外网使用必须先在自己的域名上配置 HTTPS 反向代理并支持 WebSocket Upgrade，再在插件中填 `wss://你的域名/v1/ws`。不要关闭 TLS 证书验证。上述本地地址无法直接供两台手机远程连接。

## 生成一组配对令牌

服务运行后，在另一个已设好同一个 `PETPAIR_ADMIN_TOKEN` 的终端执行：

```sh
curl -fsS -X POST http://127.0.0.1:8765/v1/pairs \
  -H "Authorization: Bearer $PETPAIR_ADMIN_TOKEN"
```

返回 `devices` 两项，每台手机各填一项的 `token`。管理令牌只用于服务端生成配对，不填进插件。设备令牌相当于本设备密码，应分别保存；它们不会写入访问日志，响应禁止缓存。正式上线应在反向代理限制配对端点只允许本机或管理员访问。

## 投递含义

- `accepted` 表示服务端已写入数据库；`state=online` 表示对方有连接，`state=queued` 表示离线排队。
- 对方收到事件并执行客户端回调后发送 `ack`，服务端向发送端推送 `delivered`。这不等于人已经看见。
- 未确认事件会在重连后补发，事件 ID 防止重复播放。客户端先持久保存收件再确认，重启后仍按事件ID去重。
- 离线事件保留 24 小时，每人最多 100 条；每 3 秒允许发送一条新事件，重复 ID 不重复入队。
- 微信进入后台后连接可能被 iOS 暂停；此版本依赖下次回到微信补达，没有锁屏推送。

## 当前范围

支持固定的“我想你了”和“我生气了”事件，ready包含protocol=2，status用于发送端重连后恢复待送达状态。未部署公网服务，也未实现运营后台、令牌吊销 UI、推送通知。首次双机联调需要准备自己的 HTTPS/WSS 服务地址。若设备令牌泄露，可停止服务并删除该配对记录后重新生成；已有记录及队列应由管理员通过数据库维护。
