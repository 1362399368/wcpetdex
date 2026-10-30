#!/usr/bin/env python3
"""Verify package contents and protected state against the previous release."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
previous=root.parent/'WeChatPet-Zhouyou-1.1.1'
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
protected=json.loads((root/'Tests/protected-v111-baseline.json').read_text())
checks={name:digest(root/name)==value for name,value in protected.items()}
resources=list((previous/'Resources').rglob('*'))
checks['allAnimationAndResourceBytesUnchanged']=all((root/p.relative_to(previous)).is_file() and digest(root/p.relative_to(previous))==digest(p) for p in resources if p.is_file())
package=root/'build/WeChatPet-周游专属包-1.2.0-TrollFools.zip'
with zipfile.ZipFile(package) as archive:
    names=archive.namelist()
    checks['zipIntegrity']=archive.testzip() is None
    checks['onlySingleStandalonePlugin']=sorted(name for name in names if name.endswith('.dylib'))==['WeChatPet.dylib']
    checks['onlyPluginAndResourceBundle']=all(name=='WeChatPet.dylib' or name.startswith('WeChatPet.bundle/') for name in names)
    checks['noPlove']=not any('plove' in name.lower() for name in names)
    checks['compact29RowsPreserved']=len([name for name in names if '/DefaultPet/compact-row-' in name and name.endswith('.png')])==29
    checks['legacyDecodedRowsNotPackaged']=not any('/DefaultPet/row-' in name and name.endswith('.png') for name in names)
    edition=json.loads(archive.read('WeChatPet.bundle/Edition.json'))
    info=plistlib.loads(archive.read('WeChatPet.bundle/Info.plist'))
    checks['editionAndVersion']=edition['edition']=='周游专属包' and edition['version']=='1.2.0' and info['CFBundleVersion']=='1200'
    image=archive.read('WeChatPet.dylib')
    checks['compiledBarrageIncluded']=b'WPMessageBarrageController' in image and b'WPMessageBarrageSource' in image
    checks['previewMessagesNotInPlugin']=b'INTEGRATION_PRIVATE_BODY' not in image and b'barrage-fixture-' not in image
signature=subprocess.run(['codesign','--verify','--strict',str(root/'build/personal/inject/WeChatPet.dylib')],capture_output=True,text=True)
checks['signatureVerified']=signature.returncode==0
report={'checks':checks,'allPassed':all(checks.values()),'packageBytes':package.stat().st_size,'sha256':digest(package)}
(root/'Tests/package-v120-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
if not report['allPassed']:raise SystemExit(1)
