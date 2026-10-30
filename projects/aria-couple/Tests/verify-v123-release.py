#!/usr/bin/env python3
"""Check the actual injection archive, preserved configuration and unchanged art."""
import hashlib,json,plistlib,subprocess,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];previous=root.parent/'WeChatPet-Zhouyou-1.2.2'
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
protected=['Config/backend.json','Sources/WPCommon.h','Sources/WPCoupleClient.h','Sources/WPCoupleClient.m','Sources/WPCoupleHistory.h','Sources/WPCoupleHistory.m','Sources/WPBackendConfiguration.h','Sources/WPBackendConfiguration.m']
checks={p:digest(root/p)==digest(previous/p) for p in protected}
checks['commonAndPairingConfigurationUnchanged']=(root/'Sources/WPCommon.m').read_bytes()==(previous/'Sources/WPCommon.m').read_bytes()
files=[p for p in (previous/'Resources').rglob('*') if p.is_file()]
checks['sourceArtAndResourcesByteIdentical']=all((root/p.relative_to(previous)).is_file() and digest(root/p.relative_to(previous))==digest(p) for p in files)
package=root/'build/WeChatPet-周游专属包-1.2.3-TrollFools.zip'
with zipfile.ZipFile(package) as z:
 names=z.namelist();checks['zipIntegrity']=z.testzip() is None
 checks['singleStandaloneDylib']=sorted(n for n in names if n.endswith('.dylib'))==['WeChatPet.dylib']
 checks['onlyPluginAndResourceBundle']=all(n=='WeChatPet.dylib' or n.startswith('WeChatPet.bundle/') for n in names)
 checks['noPlove']=not any('plove' in n.lower() for n in names)
 checks['29CompactRows']=len([n for n in names if '/DefaultPet/compact-row-' in n and n.endswith('.png')])==29
 checks['noFullAtlasOrLegacyDefaultRows']=not any(n=='WeChatPet.bundle/DefaultPet/spritesheet.png' or ('/DefaultPet/row-' in n and n.endswith('.png')) for n in names)
 checks['allPackagedArtByteIdentical']=all(z.read(n)==(previous/'Resources'/n.removeprefix('WeChatPet.bundle/')).read_bytes() for n in names if n.endswith('.png'))
 checks['oldYue2CorrectionsRetained']=len([n for n in names if '/PetCorrections/' in n and n.endswith('.png')])==4
 edition=json.loads(z.read('WeChatPet.bundle/Edition.json'));info=plistlib.loads(z.read('WeChatPet.bundle/Info.plist'))
 checks['editionVersionBuild']=edition['edition']=='周游专属包' and edition['version']=='1.2.3' and info['CFBundleVersion']=='1203'
 checks['backendPayloadUnchanged']=z.read('WeChatPet.bundle/BackendConfig.json')==(previous/'Config/backend.json').read_bytes()
 image=z.read('WeChatPet.dylib');checks['signedBinaryMatchesArchive']=image==(root/'build/personal/inject/WeChatPet.dylib').read_bytes()
 checks['newComponentsCompiled']=all(x in image for x in [b'WPMessageBarrageSource',b'WPMessageBarrageController',b'WPQuickChatSettingsController',b'WPCaptureProtectedView',b'WPQuickChatPrepareAvatar',b'WPPagedLegacyDirectory',b'WPUnreadDockState',b'WPResizableChatController',b'WPBarrageDisplayArea',b'WPChatConversationIsVisible',b'WPChatPresentationDidChangeNotification'])
 checks['noPreviewFixtureCode']=all(x not in image for x in [b'INTEGRATION_PRIVATE_BODY',b'WPAsset121RunPreviewChecks',b'WPQuickChat121PreviewChecks',b'BS54_observedThreeArgumentEntryAloneDelivers',b'WPUnifiedDock122RunPreviewChecks',b'WPBarrage122PreviewChecks',b'WPUnreadDock122PreviewChecks',b'WPBarrage123PreviewChecks',b'WPChat123RunPreviewChecks'])
checks['strictCodeSignature']=subprocess.run(['codesign','--verify','--strict',str(root/'build/personal/inject/WeChatPet.dylib')],capture_output=True).returncode==0
old=previous/'build/WeChatPet-周游专属包-1.2.2-TrollFools.zip'
report={'checks':checks,'allPassed':all(checks.values()),'packageBytes':package.stat().st_size,'previousPackageBytes':old.stat().st_size if old.exists() else 5340977,'sha256':digest(package)}
(root/'Tests/package-v123-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if not report['allPassed']:raise SystemExit(1)
