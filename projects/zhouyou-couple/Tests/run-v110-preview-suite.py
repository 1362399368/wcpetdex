#!/usr/bin/env python3
"""Run release checks sequentially in the iOS preview app, never in WeChat."""
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEVICE = sys.argv[1]
APP = Path(sys.argv[2]) if len(sys.argv) > 2 else Path((ROOT / 'build/preview-signed-path.txt').read_text().strip())
BUNDLE = 'dev.zhour.wechatpet.preview'

def sim(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)

sim('install', DEVICE, str(APP))
container = Path(sim('get_app_container', DEVICE, BUNDLE, 'data').stdout.strip())
data = container / 'Library/Application Support/WeChatPet'
summary = {}
for scenario, report_name in [('self-test', 'test'), ('update-self-test', 'update'),
                              ('zhouyou-self-test', 'zhouyou'), ('yue2-self-test', 'yue2'),
                              ('local-preview-self-test', 'local-preview')]:
    report_path = data / (report_name + '-report.json')
    if report_path.exists():
        report_path.unlink()
    sim('launch', '--terminate-running-process', DEVICE, BUNDLE, '--' + scenario)
    deadline = time.monotonic() + 100
    report = None
    while time.monotonic() < deadline:
        try:
            candidate = json.loads(report_path.read_text())
            if candidate.get('finished'):
                report = candidate
                break
        except (OSError, ValueError):
            pass
        time.sleep(1)
    if report is None:
        raise RuntimeError(f'{scenario} did not finish')
    checks = report.get('results', report)
    failed = [k for k, v in checks.items() if isinstance(v, (bool, int)) and not v]
    target = ROOT / 'Tests' / (('preview' if report_name == 'test' else report_name) + '-v110-report.json')
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    count = report.get('caseCount', len(checks))
    summary[scenario] = {'caseCount': count, 'failed': failed, 'passed': not failed and report.get('allPassed', True)}
    print(scenario, summary[scenario], flush=True)
    if failed or not report.get('allPassed', True):
        raise RuntimeError(f'{scenario} failed: {failed}')
    for name in {'test': ['memory-report.json'], 'yue2': ['yue2-memory-report.json']}.get(report_name, []):
        memory = data / name
        if memory.exists():
            (ROOT / 'Tests' / name.replace('-report', '-v110-report')).write_bytes(memory.read_bytes())
    if report_name == 'update':
        for screenshot in data.glob('comfort*-v110.png'):
            (ROOT / 'Tests' / screenshot.name).write_bytes(screenshot.read_bytes())
sim('io', DEVICE, 'screenshot', str(ROOT / 'Tests/ui-v110-final.png'))
(ROOT / 'Tests/preview-suite-v110-report.json').write_text(json.dumps(summary, indent=2))
print('All standalone preview scenarios passed.', flush=True)
