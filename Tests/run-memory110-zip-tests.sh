#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/wechatpet-zip110.XXXXXX")"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT
python3 - "$TEST_DIRECTORY" <<'PY'
import io,json,stat,struct,sys,zipfile
from pathlib import Path
root=Path(sys.argv[1]);cases=[]
def make(name,entries,valid=True,legacy=None,mutate=None,descriptor=False):
    class Nonseek(io.BytesIO):
        def seekable(self):return False
        def seek(self,*args):raise io.UnsupportedOperation()
    buf=Nonseek() if descriptor else io.BytesIO()
    with zipfile.ZipFile(buf,'w') as z:
        for filename,data,method in entries:
            info=zipfile.ZipInfo(filename);info.compress_type=method
            if name=='symlink':info.create_system=3;info.external_attr=(stat.S_IFLNK|0o777)<<16
            z.writestr(info,data)
    data=bytearray(buf.getvalue())
    if mutate:mutate(data)
    (root/(name+'.zip')).write_bytes(data);cases.append(dict(name=name,valid=valid,legacy=valid if legacy is None else legacy))
S=zipfile.ZIP_STORED;D=zipfile.ZIP_DEFLATED
make('stored',[('pet/pet.json',b'{}',S),('pet/image.png',b'pixels\x00\xff',S)])
make('deflated',[('pet.json',b'{}',D),('folder/atlas.png',b'pixel'*100000,D)])
make('descriptor',[('pet.json',b'{}',D),('atlas.png',b'pixel'*1000,D)],descriptor=True)
make('empty',[('pet.json',b'',D)])
make('folder',[('pet/',b'',S),('pet/pet.json',b'{}',D)])
make('large-entry',[('atlas.png',b'x'*(20*1024*1024),D)])
make('crc-failure',[('pet.json',b'{}',S)],False,mutate=lambda b:b.__setitem__(38,b[38]^1))
make('traversal',[('../escape',b'bad',S)],False)
make('absolute',[('/escape',b'bad',S)],False)
make('backslash',[('pet\\escape',b'bad',S)],False)
make('symlink',[('link',b'../escape',S)],False)
make('duplicate',[('pet.json',b'{}',S),('pet.json',b'{}',S)],False)
make('canonical-alias',[('a/../pet.json',b'{}',S)],False)
make('file-directory-collision',[('item',b'file',S),('item/child',b'file',S)],False,legacy=True)
make('truncated-deflate',[('pet.json',b'hello'*100,D)],False,mutate=lambda b:b.__setitem__(b.index(b'PK\x01\x02')-1,b[b.index(b'PK\x01\x02')-1]^0xff))
def encryption(b):
    for sig,off in [(b'PK\x03\x04',6),(b'PK\x01\x02',8)]:b[b.index(sig)+off]|=1
make('encrypted',[('pet.json',b'{}',S)],False,mutate=encryption)
def wrongcount(b):
    i=b.index(b'PK\x05\x06');struct.pack_into('<HH',b,i+8,2,2)
make('wrong-entry-count',[('pet.json',b'{}',S)],False,mutate=wrongcount)
(root/'cases.json').write_text(json.dumps(cases))
PY
xcrun --sdk macosx clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness -ISources -framework Foundation Sources/WPZipArchive.m Tests/Memory110ZipTests.m -lz -o "$TEST_DIRECTORY/zip-tests"
"$TEST_DIRECTORY/zip-tests" "$TEST_DIRECTORY"
