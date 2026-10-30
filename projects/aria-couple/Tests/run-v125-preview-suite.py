#!/usr/bin/env python3
"""Run release checks sequentially in the iOS preview app for v1.2.5, never in WeChat."""
import json
import hashlib
import plistlib
from datetime import datetime, timezone
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEVICE = sys.argv[1] if len(sys.argv) > 1 else 'WeChatPet-Preview'
APP = Path(sys.argv[2]) if len(sys.argv) > 2 else Path((ROOT / 'build/preview-signed-path.txt').read_text().strip())
BUNDLE = 'dev.zhour.wechatpet.preview'

info=plistlib.loads((APP/'Info.plist').read_bytes())
if str(info.get('CFBundleShortVersionString'))!='1.2.5' or str(info.get('CFBundleVersion'))!='1206':
    raise RuntimeError('Preview app is not the current 1.2.5 / 1206 build; rebuild the signed preview first')
executable=APP/info.get('CFBundleExecutable','WeChatPetPreview')
build_evidence={'version':'1.2.5','build':'1206','validatedAtUTC':datetime.now(timezone.utc).isoformat(),
                'executableSHA256':hashlib.sha256(executable.read_bytes()).hexdigest()}
(ROOT/'Tests/preview-build-v125.json').write_text(json.dumps(build_evidence,indent=2))
required_checks={
    'source-adapter-self-test':['QC12499Completed','CH124NativeWrapperWithoutNavigationOpensSuccessfully','CH124WrongContactFailureRestoresOriginalHost','CH124FullscreenNoOpNeverReportsSuccess','CH124FullscreenSuccessRequiresExactVisibleTarget','QC12599Completed','CH125NativeSheetDelegateIsUntouched','CH125HalfSecondDoesNotSaveHeightOrStartCustomState','CH125NativeWrapperIgnoresLegacy60PercentHeight','CH125NextOpenAlwaysStarts75PercentWithoutHeightPreference','LA125DatabaseContactCacheSuppliesNativeHeadImage','BS12507HealthyHookStillAllowsUnobservedRouteFallback','BS12508HookAfterSafetyFallbackDoesNotDuplicate','BS12510ArrivalBeforeNativeWrapUpdateRetriesAndDeliversOnce','BS12511NativeMetadataRebuildLongerThanOneSecondStillDelivers'],
    'optimization-self-test':['S124CurrentPetTapOpensDownloadedLibrary','S124DownloadedLibraryDoesNotStartOnlineRequest'],
    'barrage-self-test':['B12401RealMemoryWarningPreservesAdmittedVisibleBodyAndMotion','B12404NameWithoutBodyUsesActualGroupSenderAndRemark','B12410ActualOverlayHitTestReachesFlyingAvatar','BI124CompletionStyle3RetainsSameUnreadIdentity','B12501RejectedUnknownDoesNotPoisonMessageIdentifier','B12504PositiveSourceAdmissionSurvivesImmediateMetadataGap','B12505ExplicitPrivacyDenialStillOverridesSourceAdmission','B12507ResumePlaysMessageAdmittedDuringInterruption','B12509RestoredLayoutPlaysPendingMessage'],
    'recovery-self-test':['RN124ForegroundTransitionIsFiniteAndIdempotent','RN124ServiceCanRecoverWithinSameActivation','CR124ReconnectQueriesAllStatusesAfterYielding','RN125NativeCallbackCannotDisableFastBarrageSafetyPoll'],
}

def sim(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)

sim('install', DEVICE, str(APP))
container = Path(sim('get_app_container', DEVICE, BUNDLE, 'data').stdout.strip())
data = container / 'Library/Application Support/WeChatPet'
summary = {}
requested = set(os.environ.get('WP_PREVIEW_SCENARIOS','unified-dock-self-test,source-adapter-self-test,optimization-self-test,barrage-self-test,self-test,update-self-test,recovery-self-test').split(',')) - {''}

for scenario, report_name in [('unified-dock-self-test','unified-dock'), ('source-adapter-self-test', 'source-adapter'), ('optimization-self-test', 'optimization'), ('barrage-self-test', 'barrage'), ('self-test', 'test'), ('update-self-test', 'update'), ('recovery-self-test','recovery')]:
    if requested and scenario not in requested: continue
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
    missing=[key for key in required_checks.get(scenario,[]) if key not in checks]
    report['validationBuild']=build_evidence
    report['missingRequiredChecks']=missing
    target = ROOT / 'Tests' / (('preview' if report_name == 'test' else report_name) + '-v125-report.json')
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    count = report.get('caseCount', len(checks))
    summary[scenario] = {'caseCount': count, 'failed': failed, 'missingRequiredChecks':missing, 'passed': not failed and not missing and report.get('allPassed', True)}
    print(scenario, summary[scenario], flush=True)
    (ROOT / 'Tests/preview-suite-v125-report.json').write_text(json.dumps(summary, indent=2))
    if (failed or missing or not report.get('allPassed', True)) and os.environ.get('WP_PREVIEW_KEEP_GOING')!='1':
        raise RuntimeError(f'{scenario} failed: {failed}; missing required current-build checks: {missing}')
    for name in {'test': ['memory-report.json'], 'update': ['compact-memory-report.json']}.get(report_name, []):
        memory = data / name
        if memory.exists():
            (ROOT / 'Tests' / name.replace('-report', '-v125-report')).write_bytes(memory.read_bytes())
    if report_name == 'unified-dock':
        screenshot = data / 'unified-dock-chat-v123.png'
        if not screenshot.exists():
            screenshot = data / 'unified-dock-chat.png'
        if screenshot.exists():
            (ROOT / 'Tests/unified-dock-chat-v125.png').write_bytes(screenshot.read_bytes())
    if report_name == 'update':
        for screenshot in data.glob('comfort*.png'):
            (ROOT / 'Tests' / screenshot.name).write_bytes(screenshot.read_bytes())

sim('io', DEVICE, 'screenshot', str(ROOT / 'Tests/ui-v125-final.png'))
(ROOT / 'Tests/preview-suite-v125-report.json').write_text(json.dumps(summary, indent=2))
if not all(item['passed'] for item in summary.values()):
    raise RuntimeError('Preview failures: '+', '.join(key for key,item in summary.items() if not item['passed']))
print('All standalone preview scenarios passed.', flush=True)
