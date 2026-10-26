#!/usr/bin/env python3
"""Check the actual injection archive, preserved configuration, new components and unchanged art for v1.2.4."""
import hashlib, json, plistlib, subprocess, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
previous = root.parent / 'WeChatPet-Zhouyou-1.2.3'
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

protected = [
    'Config/backend.json',
    'Sources/WPCommon.h',
    'Sources/WPCommon.m',
    'Sources/WPCoupleClient.h',
    'Sources/WPBackendConfiguration.h',
    'Sources/WPBackendConfiguration.m',
]
checks = {f"protected_{p}": digest(root / p) == digest(previous / p) for p in protected}
client=(root/'Sources/WPCoupleClient.m').read_text()
old_client=(previous/'Sources/WPCoupleClient.m').read_text()
start='- (BOOL)configureURL:'
end='- (void)clearConfiguration'
checks['pairIdentityAndTokenConfigurationPreserved']=client[client.index(start):client.index(end)]==old_client[old_client.index(start):old_client.index(end)]
checks['statusQueriesYieldInBoundedBatches']='offset+8' in client and '16*NSEC_PER_MSEC' in client and 'queryPendingStatuses:' in client


files = [p for p in (previous / 'Resources').rglob('*') if p.is_file()]
checks['sourceArtAndResourcesByteIdentical'] = all(
    (root / p.relative_to(previous)).is_file() and digest(root / p.relative_to(previous)) == digest(p)
    for p in files
)

package = root / 'build/WeChatPet-周游专属包-1.2.4-r2-TrollFools.zip'
with zipfile.ZipFile(package) as z:
    names = z.namelist()
    checks['zipIntegrity'] = z.testzip() is None
    checks['singleStandaloneDylib'] = sorted(n for n in names if n.endswith('.dylib')) == ['WeChatPet.dylib']
    checks['onlyPluginAndResourceBundle'] = all(n == 'WeChatPet.dylib' or n.startswith('WeChatPet.bundle/') for n in names)
    checks['noPlove'] = not any('plove' in n.lower() for n in names)
    manifest=json.loads(z.read('WeChatPet.bundle/DefaultPet/pet.json'))
    old_manifest=json.loads((previous/'Resources/DefaultPet/pet.json').read_text())
    paths=manifest['wpBundledCompactRowAtlasPaths']
    checks['29LogicalRowsWith24UniqueFiles'] = len(paths)==29 and len(set(paths))==24
    checks['allLogicalRowPixelsUnchanged'] = all(
        z.read('WeChatPet.bundle/DefaultPet/'+actual)==(previous/'Resources/DefaultPet'/original).read_bytes()
        for original,actual in zip(old_manifest['wpBundledCompactRowAtlasPaths'],paths)
    )
    checks['animationFrameMapsUnchanged'] = all(manifest.get(k)==old_manifest.get(k) for k in ['frameCounts','wpBundledCompactFrameMaps','passiveAnimations','semanticRows','frameRate'])
    checks['noFullAtlasOrLegacyDefaultRows'] = not any(
        n == 'WeChatPet.bundle/DefaultPet/spritesheet.png' or ('/DefaultPet/row-' in n and n.endswith('.png'))
        for n in names
    )
    checks['allPackagedArtByteIdentical'] = all(
        z.read(n) == (previous / 'Resources' / n.removeprefix('WeChatPet.bundle/')).read_bytes()
        for n in names if n.endswith('.png')
    )
    checks['oldYue2CorrectionsRetained'] = len([n for n in names if '/PetCorrections/' in n and n.endswith('.png')]) == 4
    edition = json.loads(z.read('WeChatPet.bundle/Edition.json'))
    info = plistlib.loads(z.read('WeChatPet.bundle/Info.plist'))
    checks['editionVersionBuild'] = (
        edition['edition'] == '周游专属包'
        and edition['version'] == '1.2.4'
        and info['CFBundleVersion'] == '1205' and info['CFBundleShortVersionString']=='1.2.4'
        and edition['revision']=='r2' and edition['build']==1205
    )
    checks['backendPayloadUnchanged'] = (
        z.read('WeChatPet.bundle/BackendConfig.json') == (previous / 'Config/backend.json').read_bytes()
    )
    image = z.read('WeChatPet.dylib')
    checks['signedBinaryMatchesArchive'] = image == (root / 'build/personal/inject/WeChatPet.dylib').read_bytes()
    checks['newComponentsCompiled'] = all(
        x in image for x in [
            b'WPRecoveryCoordinator',
            b'WPNativeRefreshGate',
            b'WPQuickChatNotifyNativeMessage',
            b'setRecoveryPaused:',
            b'WPSharedChatAvatarRequest',
            b'WPRequestSharedChatAvatar',
            b'WPCachedSharedChatAvatar',
            b'WPPurgeSharedChatAvatars',
            b'WPMessageBarrageSource',
            b'WPMessageBarrageController',
            b'WPQuickChatSettingsController',
            b'WPCaptureProtectedView',
            b'WPQuickChatPrepareAvatar',
            b'WPPagedLegacyDirectory',
            b'WPUnreadDockState',
            b'WPResizableChatController',
            b'WPBarrageDisplayArea',
            b'WPChatConversationIsVisible',
            b'WPChatPresentationDidChangeNotification',
            b'purgeRecordsOlderThanThreeDays',
            b'clearAllHistory',
        ]
    )
    checks['noPreviewFixtureCode'] = all(
        x not in image for x in [
            b'WPQuickChat124RunPreviewChecks',
            b'WPChat124RunPreviewChecks',
            b'WPSettings124PreviewChecks',
            b'WPBarrage124RunOverlayPreviewChecks',
            b'WPRecovery124RunPreviewChecks',
            b'WPRecoveryNotify124RunPreviewChecks',
            b'previewDisplayNameProvider',
            b'INTEGRATION_PRIVATE_BODY',
            b'WPAsset121RunPreviewChecks',
            b'WPQuickChat121PreviewChecks',
            b'BS54_observedThreeArgumentEntryAloneDelivers',
            b'WPUnifiedDock122RunPreviewChecks',
            b'WPBarrage122PreviewChecks',
            b'WPUnreadDock122PreviewChecks',
            b'WPBarrage123PreviewChecks',
            b'WPChat123RunPreviewChecks',
        ]
    )

checks['strictCodeSignature'] = (
    subprocess.run(['codesign', '--verify', '--strict', str(root / 'build/personal/inject/WeChatPet.dylib')],
                   capture_output=True).returncode == 0
)

old = previous / 'build/WeChatPet-周游专属包-1.2.3-TrollFools.zip'
report = {
    'checks': checks,
    'allPassed': all(checks.values()),
    'packageBytes': package.stat().st_size,
    'previousPackageBytes': old.stat().st_size if old.exists() else 5348156,
    'sha256': digest(package)
}

(root / 'Tests/package-v124-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
if not report['allPassed']:
    raise SystemExit(1)
