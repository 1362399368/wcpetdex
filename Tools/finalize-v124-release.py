#!/usr/bin/env python3
"""Freeze evidence and copy only a fully verified v1.2.4 r2 release."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
tests = root / 'Tests'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda n: json.loads((tests / n).read_text())
scenes = ['unified-dock', 'source-adapter', 'optimization', 'barrage', 'preview', 'update', 'recovery']
evidence = {}
for name in scenes:
    report = read(name + '-v124-report.json')
    assert report.get('allPassed') and report.get('finished'), name
    assert not report.get('missingRequiredChecks'), name
    checks = report.get('results', report)
    assert not [k for k, v in checks.items() if isinstance(v, (bool, int)) and not v], name
    build = report['validationBuild']
    assert build['version'] == '1.2.4' and build['build'] == '1205', name
    evidence[name] = {'caseCount': report['caseCount'], 'allPassed': True, 'executableSHA256': build['executableSHA256']}
assert len({x['executableSHA256'] for x in evidence.values()}) == 1, 'Mixed preview builds'
separate = {}
for name in ['quickchat-preview', 'unread-avatar']:
    report = read(name + '-v124-report.json')
    assert report['allPassed'] and all(report['results'].values()), name
    assert report['validationBuild']['build'] == '1205', name
    separate[name] = {'caseCount': report['caseCount'], 'allPassed': True, 'executableSHA256': report['validationBuild']['executableSHA256']}

coordinator = read('recovery-coordinator-v124-report.json')
assert coordinator['allPassed'] and coordinator['caseCount'] == 10
history = read('interaction-v038-report.json')
assert history['allPassed'] and history['caseCount'] == 36
logs = {
    'startupRetention': ('startup-retention-v124-r2.log', 'startup-and-retention: 5 passed', 5),
    'nativeRefreshGate': ('native-refresh-gate-v124-r2.log', '7 regression groups passed', 7),
    'historyRetention': ('history-retention-v124-r2.log', '7 regression groups passed', 7),
    'backend': ('backend-v124-r2.log', 'pass 17', 17),
}
foundation = {'coordinator': {'caseCount': 10, 'allPassed': True}, 'historyV038': {'caseCount': 36, 'allPassed': True}}
for name, (file, expected, count) in logs.items():
    assert expected in (root / 'build' / file).read_text(), name
    foundation[name] = {'count': count, 'allPassed': True, 'log': 'build/' + file}

package = root / 'build/WeChatPet-周游专属包-1.2.4-r2-TrollFools.zip'
package_report = read('package-v124-report.json')
assert package_report['allPassed'] and package_report['sha256'] == sha(package)
binary = root / 'build/personal/inject/WeChatPet.dylib'
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in (root / 'Sources').glob('*') if p.is_file()), 'Rebuild device binary after source edits'
cloud = read('cloudflare-retention-v124-report.json')
assert cloud['allPassed']

paths = set()
for directory in ['Sources', 'Preview', 'Config', 'Tools', 'BackendCloudflare/src']:
    paths.update(p for p in (root / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
paths.update(p for p in tests.iterdir() if p.suffix in {'.m', '.sh', '.py'})
paths.update(root / name for name in ['build.sh', 'README.md', '交接给其他AI.md'])
manifest = {'version': '1.2.4', 'revision': 'r2', 'build': 1205,
            'files': {str(p.relative_to(root)): sha(p) for p in sorted(paths)}}
manifest_path = tests / 'source-manifest-v124-r2.json'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
report = {'version': '1.2.4', 'revision': 'r2', 'build': 1205,
          'finalizedAtUTC': datetime.now(timezone.utc).isoformat(), 'allPassed': True,
          'standalonePreview': evidence, 'standalonePreviewCaseCount': sum(x['caseCount'] for x in evidence.values()),
          'separateMockHosts': separate, 'foundationAndBackend': foundation,
          'package': package_report, 'cloudflare': cloud,
          'decodedAnimationRows': read('compact-memory-v124-report.json'),
          'sourceManifestSHA256': sha(manifest_path),
          'realDeviceValidation': {'completed': False, 'pending': ['实际微信版本原生小窗、键盘与消息引用', '长时间后台及过夜恢复', '真实私聊/群聊的弹幕、昵称与头像触摸']}}
(tests / 'release-v124-r2-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')

old_bytes = package_report['previousPackageBytes']
delta = old_bytes - package.stat().st_size
changelog = f'''周游专属包 1.2.4 r2（构建 1205）更新日志

独立桌宠插件，不含 Plove。沿用配对身份、服务器配置和令牌设置。

修复与稳定性
1. 修复前后台状态设置中的无限递归，避免该路径触发闪退。
2. 前台恢复拆成窗口校准、消息捕获、人物渲染、未读监测、历史维护和配对连接多个阶段；合并重复窗口通知及消息通知，限制会话读取分片与队列数量。
3. 暂时失焦、切换微信页面时保留屏幕内弹幕；内存警告清理等待消息、下载及缓存，已播放的弹幕继续完成。真正进入后台停止显示及临时任务。
4. 原生小窗兼容自定义容器与延迟加载，确认目标聊天实际可见后才算成功；错误联系人失败时撤回本次新建窗口。全屏入口也不再把“已调用接口”误报为打开成功。
5. 修正快捷聊天列表初始行高和新消息插入后的滚动锚点；共享头像请求，避免重复下载与过期结果回填。
6. 修正头像飞入结束后触摸区域未立即恢复的问题。同一批弹幕完成后，仅最新有效未读消息触发一次完成效果；已读状态和正在聊天的联系人继续按统一规则处理。

设置与交互
1. 外观设置移入桌宠设置；点击最上方“当前桌宠”直接打开已下载的本地桌宠库，不先发起在线目录请求。
2. 弹幕新增可独立开启的昵称显示，可选昵称或备注优先；与消息正文显示开关独立。
3. 弹幕完成效果可选：桌宠头顶弹跳、头像飞入、淡入、关闭动画。
4. 桌宠在左侧贴边隐藏或锁定位置时，快捷聊天列表自动在右侧出现；其他情况默认左侧。
5. UIKit 原生小窗默认75%，保留自选高度；停留0.5秒固定，快上滑展开、快下滑关闭。微信完全自定义的小窗保留其原生高度交互。
6. 版本与诊断中加入恢复重试和暂停桌宠入口。

内存与资源
1. 动画29个逻辑行共用24份唯一PNG，删除5份完全相同的图片副本；不重绘、不降低分辨率、不改帧映射和时序。
2. 全部286帧在模拟器中与原始图逐像素核对通过。空闲、在线、愤怒单行解码像素缓冲分别约936、312、468 KiB，仍按动作加载。
3. 共享头像缓存最多16张、约1.5 MiB，最多2个并发任务；内存警告后有冷却期，减少马上重新加载。
4. 当前ZIP {package.stat().st_size:,}字节（约{package.stat().st_size / 1e6:.2f} MB），比1.2.3减少{delta:,}字节（{delta / old_bytes:.1%}）。这些是包体和像素缓冲数据，不代表实际微信进程运存降幅。

互动记录
本地互动记录按消息时间保留72小时，启动、前台恢复及到期时清理；同步清理由过期记录产生的提醒状态，保存失败会回滚。Cloudflare现有互动队列保留24小时、在线时间记录保留72小时，由到期维护清理；健康入口复查通过。配对绑定和令牌保留。

本次验证
完整iOS模拟器预览{report['standalonePreviewCaseCount']}项通过，使用同一个1.2.4/1205构建；独立快捷聊天{separate['quickchat-preview']['caseCount']}项、未读头像{separate['unread-avatar']['caseCount']}项通过。
Foundation恢复协调器10项、历史36项通过；启动与清理5组、原生刷新门7组、三天保留7组通过；后端17项通过。实际ZIP完整性、arm64二进制签名、无预览夹具、无Plove、动画像素和配置保留检查全部通过。
上述为自动检查及模拟器微信服务夹具；尚未在实际注入后的微信完成键盘/引用、真实会话、长时间后台和过夜验证，不保证所有微信版本的私有小窗接口均兼容。

安装
使用本ZIP替换旧桌宠插件注入，避免同时加载两份WeChatPet.dylib；保留原数据。兼容环境为iOS16.3及以上arm64。

SHA256
{sha(package)}
'''
output = root.parents[1] / 'outputs'
output.mkdir(exist_ok=True)
destination = output / package.name
shutil.copyfile(package, destination)
assert sha(destination) == sha(package)
log_path = output / '周游专属包-1.2.4-r2-更新日志.txt'
log_path.write_text(changelog)
print(json.dumps({'package': str(destination), 'changelog': str(log_path), 'previewCases': report['standalonePreviewCaseCount'], 'sha256': sha(package)}, ensure_ascii=False, indent=2))
