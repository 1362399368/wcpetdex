#!/usr/bin/env python3
"""Publish a verified 1.2.6 device archive and a concise evidence report."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil


root = Path(__file__).resolve().parents[1]
tests = root / 'Tests'
output = root.parents[1] / 'outputs'
package = root / 'build/WeChatPet-周游专属包-1.2.6-TrollFools.zip'


def read(name: str) -> dict:
    return json.loads((tests / name).read_text())


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


scenes = ['unified-dock', 'source-adapter', 'optimization', 'barrage', 'preview', 'update', 'recovery']
preview = {}
for name in scenes:
    report = read(f'{name}-v126-report.json')
    assert report.get('allPassed') and report.get('finished') and not report.get('missingRequiredChecks'), name
    assert report['validationBuild']['version'] == '1.2.6' and report['validationBuild']['build'] == '1207', name
    preview[name] = report['caseCount']
adapter = read('source-adapter-v126-report.json')
assert adapter['results']['BS12601MetadataRetryDoesNotEvictFreshInbox'] == 1
separate = {}
for name in ['quickchat-preview', 'unread-avatar']:
    report = read(f'{name}-v126-report.json')
    assert report.get('allPassed') and all(report['results'].values()), name
    assert report['validationBuild']['version'] == '1.2.6' and report['validationBuild']['build'] == '1207', name
    separate[name] = report['caseCount']
package_report = read('package-v126-report.json')
assert package_report['allPassed'] and package_report['sha256'] == sha(package)
binary = root / 'build/personal/inject/WeChatPet.dylib'
assert all(path.stat().st_mtime <= binary.stat().st_mtime for path in (root / 'Sources').glob('*') if path.is_file())

manifest_files = []
for directory in ['Sources', 'Preview', 'Config', 'Tools', 'BackendCloudflare/src']:
    manifest_files.extend(path for path in (root / directory).rglob('*') if path.is_file())
manifest_files.extend(path for path in tests.iterdir() if path.suffix in {'.m', '.sh', '.py'})
manifest_files.extend(root / name for name in ['build.sh', 'README.md', '交接给其他AI.md'])
manifest = {'version': '1.2.6', 'build': 1207,
            'files': {str(path.relative_to(root)): sha(path) for path in sorted(set(manifest_files))}}
(tests / 'source-manifest-v126.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
evidence = {
    'version': '1.2.6', 'build': 1207, 'finalizedAtUTC': datetime.now(timezone.utc).isoformat(),
    'allPassed': True, 'standalonePreview': preview, 'standalonePreviewCaseCount': sum(preview.values()),
    'separatePreview': separate, 'package': package_report,
    'sourceManifestSHA256': sha(tests / 'source-manifest-v126.json'),
    'realDeviceValidation': {'completed': False, 'pending': ['实际微信收消息与小窗交互', '过夜恢复']},
}
(tests / 'release-v126-report.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')

output.mkdir(exist_ok=True)
destination = output / package.name
shutil.copyfile(package, destination)
assert sha(destination) == sha(package)
notes = f'''周游专属包 1.2.6（构建 1207）更新日志

修复弹幕元数据暂不可用时，旧消息重试可能挤掉刚到达的新消息。接收队列满时放弃旧重试并清理其状态；未满时维持原有有界重试。其余 1.2.5 功能、桌宠素材、配对和后端配置保留。

验证：7 个独立模拟器场景共 {sum(preview.values())} 项、快捷聊天 {separate['quickchat-preview']} 项、未读头像 {separate['unread-avatar']} 项通过。新增 BS12601 检查先在旧逻辑上失败，修复后通过。安装包完整性、签名、版本和资源保留检查通过。真机微信收消息及过夜恢复尚未验证。

安装：替换旧版插件后注入微信，不要同时加载两份 WeChatPet.dylib。保留原有数据。

SHA256: {sha(package)}
'''
(output / '周游专属包-1.2.6-更新日志.txt').write_text(notes)
print(json.dumps({'package': str(destination), 'sha256': sha(destination), 'previewCases': sum(preview.values()),
                  'quickchatCases': separate['quickchat-preview'], 'unreadAvatarCases': separate['unread-avatar']}, ensure_ascii=False))
