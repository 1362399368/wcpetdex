#!/usr/bin/env python3
"""Freeze evidence and copy only a fully verified v1.2.5 release."""
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
    report = read(name + '-v125-report.json')
    assert report.get('allPassed') and report.get('finished'), name
    assert not report.get('missingRequiredChecks'), name
    checks = report.get('results', report)
    assert not [k for k, v in checks.items() if isinstance(v, (bool, int)) and not v], name
    build = report['validationBuild']
    assert build['version'] == '1.2.5' and build['build'] == '1206', name
    evidence[name] = {'caseCount': report['caseCount'], 'allPassed': True, 'executableSHA256': build['executableSHA256']}
assert len({x['executableSHA256'] for x in evidence.values()}) == 1, 'Mixed preview builds'
separate = {}
for name in ['quickchat-preview', 'unread-avatar']:
    report = read(name + '-v125-report.json')
    assert report['allPassed'] and all(report['results'].values()), name
    assert report['validationBuild']['build'] == '1206', name
    separate[name] = {'caseCount': report['caseCount'], 'allPassed': True, 'executableSHA256': report['validationBuild']['executableSHA256']}

coordinator = read('recovery-coordinator-v124-report.json')
assert coordinator['allPassed'] and coordinator['caseCount'] == 10
history = read('interaction-v038-report.json')
assert history['allPassed'] and history['caseCount'] == 36
logs = {
    'startupRetention': ('startup-retention-v125.log', 'startup-and-retention: 5 passed', 5),
    'nativeRefreshGate': ('native-refresh-gate-v125.log', '7 regression groups passed', 7),
    'historyRetention': ('history-retention-v125.log', '7 regression groups passed', 7),
    'backend': ('backend-v125.log', 'pass 17', 17),
}
foundation = {'coordinator': {'caseCount': 10, 'allPassed': True}, 'historyV038': {'caseCount': 36, 'allPassed': True}}
for name, (file, expected, count) in logs.items():
    assert expected in (root / 'build' / file).read_text(), name
    foundation[name] = {'count': count, 'allPassed': True, 'log': 'build/' + file}

package = root / 'build/WeChatPet-周游专属包-1.2.5-TrollFools.zip'
package_report = read('package-v125-report.json')
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
manifest = {'version': '1.2.5', 'revision': 'r1', 'build': 1206,
            'files': {str(p.relative_to(root)): sha(p) for p in sorted(paths)}}
manifest_path = tests / 'source-manifest-v125.json'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
report = {'version': '1.2.5', 'revision': 'r1', 'build': 1206,
          'finalizedAtUTC': datetime.now(timezone.utc).isoformat(), 'allPassed': True,
          'standalonePreview': evidence, 'standalonePreviewCaseCount': sum(x['caseCount'] for x in evidence.values()),
          'separateMockHosts': separate, 'foundationAndBackend': foundation,
          'package': package_report, 'cloudflarePriorHealthEvidence': cloud, 'serverDeploymentChangedIn125': False,
          'decodedAnimationRows': read('compact-memory-v125-report.json'),
          'sourceManifestSHA256': sha(manifest_path),
          'realDeviceValidation': {'completed': False, 'pending': ['实际微信版本原生小窗、键盘与消息引用', '长时间后台及过夜恢复', '真实私聊/群聊的弹幕、昵称与头像触摸']}}
(tests / 'release-v125-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')

old_bytes = package_report['previousPackageBytes']
delta = old_bytes - package.stat().st_size
changelog = f'''周游专属包 1.2.5（构建 1206）更新日志

本次重点：修复快捷聊天重新打开变字母占位图、收到消息却缺少弹幕；移除高度固定和高度记忆。独立桌宠包，不含 Plove。

头像修复
1. 修复“打开快捷聊天→关闭→再次打开”时，隐藏状态绑定列表没有读取暖缓存，重新展开后又跳过已缓存头像的问题。已有真实头像可直接重新显示。
2. 修复 UIKit 旧的离屏回调清空已复用的可见头像；当前可见行保留头像，真正离屏的图片仍会释放。
3. 修复请求成功、缓存过期或队列拥挤累计到8次后永久停止加载的问题。成功清零失败次数，暂时失败按2至60秒退避重试。
4. 当前可见头像不会因共享缓存淘汰而立刻变回字母并重复下载。微信本地联系人缓存增加已知数据库回退入口，读到正确联系人后才使用其头像。
5. 保留共享缓存最多16张、约1.5 MiB及最多2个并发任务；关闭列表取消请求和定时工作。

弹幕修复
1. 原生消息钩子工作时继续保留新消息监测补偿，不再因某一条接收路线成功就停用其他路线的兜底；两条路线按稳定消息ID去重。
2. 弹幕启用时，监测保持有界的2秒补偿周期，不因一次原生回调切到8秒慢轮询。
3. 增加索引式、列表式会话读取，修复微信只有索引接口而弹幕只尝试按用户名查找，导致一直无法确认会话的情况。每批最多150行或约3毫秒，批次之间让出主线程。
4. 会话信息或最新消息尚未更新时，最多等待6秒；补偿队列最多12个会话，仅保存会话名和时间。继续排除旧消息和不符合现有过滤规则的会话。
5. 消息实际准入后才写入播放去重记录，避免暂时读取失败后连同正常重试也被拦截。来源已确认的会话，在随后短暂读取不到元数据时保留准入结果；明确的当前聊天、免打扰或隐私拒绝仍然生效。
6. 短暂失焦或布局尚未就绪时保留有界待播消息，恢复后播放；真正后台、关闭功能、暂停及既有静音/会话规则继续生效。

小窗调整
按本次要求删除“停留0.5秒固定任意高度”和“下次记住高度”。不再添加自定义拖动把手、手势、计时器，也不再接管原生sheet代理。小窗仍以约75%初始大小打开，展开、收起、关闭、键盘及消息菜单交由原生处理；打开时忽略并清理旧的记忆高度。

资源与配置
动画像素、帧映射、时序及已有修正资源保持不变。服务器配置、令牌设置及配对身份保持不变；本次没有部署服务器修改。原有互动记录清理策略保持。
ZIP共{package.stat().st_size:,}字节，约{package.stat().st_size/1e6:.2f} MB。包体大小不代表实际微信进程运存占用。

验证
完整iOS模拟器预览{report['standalonePreviewCaseCount']}项通过，包含重复展开头像、旧复用回调、混合接收路线、索引会话、消息/元数据延迟、重复去重、临时失焦、布局恢复和已移除高度功能的检查。
独立快捷聊天{separate['quickchat-preview']['caseCount']}项、未读头像{separate['unread-avatar']['caseCount']}项通过。Foundation恢复10项、历史36项、启动清理5组、刷新门7组、三天保留7组及后端17项通过。
实际ZIP完整性、arm64签名、版本1206、无Plove、无预览测试代码、动画像素和配置保留检查通过。
这些是自动检查及模拟器微信服务夹具；本轮没有在实际注入后的微信验证所有接收路线，也没有完成实机过夜测试。

安装
替换旧版桌宠插件后注入，避免同时加载两份WeChatPet.dylib；保留原数据。包内包含插件及配套资源。

SHA256
{sha(package)}
'''
output = root.parents[1] / 'outputs'
output.mkdir(exist_ok=True)
destination = output / package.name
shutil.copyfile(package, destination)
assert sha(destination) == sha(package)
log_path = output / '周游专属包-1.2.5-更新日志.txt'
log_path.write_text(changelog)
print(json.dumps({'package': str(destination), 'changelog': str(log_path), 'previewCases': report['standalonePreviewCaseCount'], 'sha256': sha(package)}, ensure_ascii=False, indent=2))
