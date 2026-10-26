#!/usr/bin/env python3
"""Publish local artifacts only after the current Aria build has passed its checks."""
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'Tests'
OUTPUT = ROOT.parents[1] / 'outputs'
PACKAGE = ROOT / 'build/Aria专属（游定制最终版）5.2.0-TrollFools.zip'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
read = lambda name: json.loads((TESTS / name).read_text())
scenes = ['unified-dock', 'source-adapter', 'optimization', 'barrage', 'preview', 'update', 'recovery']
preview = {}
for name in scenes:
    result = read(name + '-aria520-report.json')
    assert result.get('allPassed') and result.get('finished'), name
    assert not result.get('missingRequiredChecks'), name
    checks = result.get('results', result)
    assert not [key for key, value in checks.items() if isinstance(value, (int, bool)) and not value], name
    build = result['validationBuild']
    assert build['version'] == '5.2.0' and build['build'] == '5200', name
    preview[name] = {'caseCount': result['caseCount'], 'allPassed': True, 'executableSHA256': build['executableSHA256']}
assert len({item['executableSHA256'] for item in preview.values()}) == 1, 'Mixed preview binaries'
separate = {}
for name in ['quickchat-preview', 'unread-avatar']:
    result = read(name + '-aria520-report.json')
    assert result['allPassed'] and all(result['results'].values()), name
    assert result['validationBuild']['version'] == '5.2.0' and result['validationBuild']['build'] == '5200', name
    separate[name] = {'caseCount': result['caseCount'], 'allPassed': True, 'executableSHA256': result['validationBuild']['executableSHA256']}

foundation = {}
coordinator = json.loads((ROOT / 'build/coordinator-aria520.log').read_text())
history = json.loads((ROOT / 'build/history-v038-aria520.log').read_text())
assert coordinator['allPassed'] and coordinator['caseCount'] == 10
assert history['allPassed'] and history['caseCount'] == 36
foundation.update(coordinator={'caseCount': 10, 'allPassed': True}, history={'caseCount': 36, 'allPassed': True})
for name, filename, needle, count in [
    ('startupRetention', 'startup-retention-aria520.log', 'startup-and-retention: 5 passed', 5),
    ('nativeRefreshGate', 'native-refresh-gate-aria520.log', '7 regression groups passed', 7),
    ('historyRetention', 'history-retention-aria520.log', '7 regression groups passed', 7),
    ('backend', 'backend-aria520.log', 'pass 17', 17),
]:
    assert needle in (ROOT / 'build' / filename).read_text(), name
    foundation[name] = {'count': count, 'allPassed': True, 'log': 'build/' + filename}

package = read('package-aria520-report.json')
art = read('aria-art-v520-report.json')
assert package['allPassed'] and package['sha256'] == sha(PACKAGE)
assert art['allPassed'] and art['validFramesPreserved'] == 286
binary = ROOT / 'build/aria/inject/WeChatPet.dylib'
assert all(path.stat().st_mtime <= binary.stat().st_mtime for path in (ROOT / 'Sources').glob('*') if path.is_file()), 'Device binary predates source'

paths = set()
for name in ['Sources', 'Preview', 'Resources', 'Config', 'Tools']:
    paths.update(path for path in (ROOT / name).rglob('*') if path.is_file() and '__pycache__' not in path.parts)
paths.update(path for path in TESTS.iterdir() if path.suffix in {'.m', '.sh', '.py'})
paths.update(ROOT / name for name in ['build.sh', 'README.md', '交接给其他AI.md'])
manifest = {'version': '5.2.0', 'build': 5200, 'baseVersion': '1.2.5', 'files': {str(path.relative_to(ROOT)): sha(path) for path in sorted(paths)}}
manifest_path = TESTS / 'source-manifest-aria520.json'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
report = {
    'name': 'Aria专属（游定制最终版）', 'version': '5.2.0', 'build': 5200, 'baseVersion': '1.2.5',
    'finalizedAtUTC': datetime.now(timezone.utc).isoformat(), 'allAutomatedChecksPassed': True,
    'standalonePreview': preview, 'standalonePreviewCaseCount': sum(item['caseCount'] for item in preview.values()),
    'separateMockHosts': separate, 'foundationAndBackend': foundation, 'package': package, 'art': art,
    'sourceManifestSHA256': sha(manifest_path), 'serverDeploymentChanged': False,
    'realDeviceValidation': {'completed': False, 'pending': ['真实微信原生小窗、键盘和消息引用', '长时间后台与过夜恢复', '实际私聊/群聊消息回调、头像与弹幕']},
}
report_path = TESTS / 'release-aria520-report.json'
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')

notes = f'''Aria专属（游定制最终版）5.2.0
构建号：5200；基于周游专属包 1.2.5。独立 TrollFools 桌宠插件包。

本次定制
1. 删除隐身开关、隐身状态、隐藏在线网络请求和对应的发送限制；升级时清理旧隐身偏好。在线/最后在线显示、正常互动发送仍可使用。
2. 保留 Aria 专属桌宠：29 个动作行、286 个有效帧、15fps 动作元数据，专属贴边姿势、拖动镜像与静止节奏保留。与旧 Aria 1.1.0 专属资源逐像素比对通过，新增当前渲染器的逐帧检查。
3. 继承 1.2.5 的全部其他功能：快捷聊天、最新未读头像、聊天弹幕和发言人昵称/备注、结束动画、自动侧栏、情侣互动与记录、配对与连接、外观/手势、自选桌宠、本地及在线宠物库、恢复协调和轻量恢复入口。
4. 继承 1.2.5 的头像反复展开缓存修复、头像失败退避、弹幕混合接收补偿、延迟会话信息重试、队列与缓存上限、当前聊天及隐私过滤。
5. 保留原生小窗初始约75%及原生交互；按1.2.5行为，不加入自定义定高、半秒固定和高度记忆。
6. 配对和Keychain存储、生产服务配置、互动数据格式保持兼容；本次未部署服务器。普通“隐藏桌宠”设置保留，可从微信设置恢复。

安装
用 TrollFools 替换旧桌宠插件，导入本次完整ZIP，避免同时加载两份 WeChatPet.dylib；保留原微信与插件数据。
包内为 WeChatPet.dylib 与配套 WeChatPet.bundle，不含 Plove。
首次使用默认显示Aria专属桌宠。已有的自选桌宠保持；若需切回，进入“桌宠设置→当前桌宠→已下载”选择Aria专属桌宠。

数据保留
本地桌宠互动历史保留72小时；云端互动队列24小时、在线时间戳72小时。没有微信聊天正文持久化数据库。

本构建的验证
完整模拟器预览 {report['standalonePreviewCaseCount']} 项通过；独立快捷聊天 {separate['quickchat-preview']['caseCount']} 项、未读头像 {separate['unread-avatar']['caseCount']} 项通过。
恢复协调10项、历史36项、启动清理5组、刷新门7组、历史保留7组、后端17项通过。
实际ZIP {package['caseCount']} 项发布检查通过，包括arm64设备二进制、签名、5.2.0/5200、无隐身实现、无测试代码、专属资源及1.2.5核心实现保留。
这些是自动检查与模拟微信服务夹具；本轮尚未在真实注入微信完成键盘/引用、真实消息接收与过夜稳定性验证。

ZIP大小：{PACKAGE.stat().st_size:,}字节（约{PACKAGE.stat().st_size / 1_000_000:.2f} MB）；包体大小不代表微信运行内存。
SHA256：{sha(PACKAGE)}
'''
OUTPUT.mkdir(parents=True, exist_ok=True)
destination = OUTPUT / PACKAGE.name
shutil.copyfile(PACKAGE, destination)
assert sha(destination) == sha(PACKAGE)
log = OUTPUT / 'Aria专属（游定制最终版）5.2.0-更新与安装说明.txt'
log.write_text(notes)
shutil.copyfile(report_path, OUTPUT / 'Aria-5.2.0-验证记录.json')
print(json.dumps({'package': str(destination), 'notes': str(log), 'previewCases': report['standalonePreviewCaseCount'], 'sha256': sha(PACKAGE)}, ensure_ascii=False, indent=2))
