#!/usr/bin/env python3
"""Check the public-key resource obfuscation and all embedded content hashes."""
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
key = sha256(b'SinglePet-zhour public artwork obfuscation v2').hexdigest()
with TemporaryDirectory() as tmp:
    path = Path(tmp) / 'resources.bin'
    subprocess.run([sys.executable, str(root/'Tools/build-embedded-resources.py'), str(path)], check=True)
    data = path.read_bytes()
    assert data[:8] == b'WPSENC2\0' and len(data) <= 8*1024*1024+40
    assert b'DefaultPet/pet.json' not in data and b'\x89PNG\r\n\x1a\n' not in data
    plain = subprocess.run(['openssl','enc','-d','-aes-256-cbc','-K',key,'-iv',data[8:24].hex()], input=data[24:], stdout=subprocess.PIPE, check=True).stdout
    assert plain[:8] == b'WPSRES1\0' and int.from_bytes(plain[8:12],'little') == 11
    cursor=12; names=set()
    for i in range(11):
        n=int.from_bytes(plain[cursor:cursor+2],'little'); length=int.from_bytes(plain[cursor+2:cursor+6],'little')
        expected=plain[cursor+6:cursor+38]; cursor+=38
        name=plain[cursor:cursor+n].decode(); cursor+=n
        body=plain[cursor:cursor+length]; cursor+=length
        assert sha256(body).digest() == expected and name not in names
        names.add(name)
    assert cursor==len(plain) and names=={'DefaultPet/pet.json','petdex-manifest-snapshot.json',*(f'DefaultPet/lulu-row-{i:02}.png' for i in range(9))}
print('PASS: obfuscated resource archive decrypts with verified content hashes')
