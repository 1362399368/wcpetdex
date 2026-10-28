#!/usr/bin/env python3
"""Independently inspect both DEB layouts without requiring dpkg."""
import io
import plistlib
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def read_ar(data):
    assert data.startswith(b'!<arch>\n')
    pos = 8
    result = {}
    while pos < len(data):
        header = data[pos:pos+60]
        assert len(header) == 60 and header[58:60] == b'`\n'
        name = header[:16].decode('ascii').strip().removesuffix('/')
        size = int(header[48:58].decode('ascii').strip())
        body = data[pos+60:pos+60+size]
        assert len(body) == size and name not in result
        result[name] = body
        pos += 60 + size + (size % 2)
    assert pos == len(data)
    return result


def read_tar(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        members = archive.getmembers()
        assert all(m.isfile() and m.mode == 0o644 and m.uid == m.gid == 0 for m in members)
        return {m.name: archive.extractfile(m).read() for m in members}


with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    dylib = temp/'sample.dylib'
    binary = b'\xcf\xfa\xed\xfe' + b'example standalone dylib payload'
    dylib.write_bytes(binary)
    for scheme in ('rootful', 'rootless'):
        output = temp/(scheme + '.deb')
        subprocess.run([sys.executable, str(ROOT/'Tools/build-single-deb.py'), '--dylib', str(dylib), '--output', str(output), '--scheme', scheme], check=True)
        members = read_ar(output.read_bytes())
        assert list(members) == ['debian-binary', 'control.tar.gz', 'data.tar.gz']
        assert members['debian-binary'] == b'2.0\n'
        control = read_tar(members['control.tar.gz'])
        assert set(control) == {'./control'}
        architecture = 'iphoneos-arm64' if scheme == 'rootless' else 'iphoneos-arm'
        assert f'Architecture: {architecture}\n'.encode() in control['./control']
        assert b'Package: dev.zhour.wechatpet.single\n' in control['./control']
        data = read_tar(members['data.tar.gz'])
        base = ('./var/jb' if scheme == 'rootless' else '.') + '/Library/MobileSubstrate/DynamicLibraries/'
        assert set(data) == {base+'SinglePet-zhour.dylib', base+'SinglePet-zhour.plist'}
        assert data[base+'SinglePet-zhour.dylib'] == binary
        assert plistlib.loads(data[base+'SinglePet-zhour.plist']) == {'Filter': {'Bundles': ['com.tencent.xin']}}
        assert not any('.bundle' in name for name in data)
print('PASS: rootful/rootless DEB members, paths, metadata, permissions and filters')
