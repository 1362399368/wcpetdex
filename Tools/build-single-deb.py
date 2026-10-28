#!/usr/bin/env python3
"""Package an already built standalone zhour-single dylib as a Debian tweak."""
import argparse
import gzip
import io
import plistlib
from pathlib import Path
import tarfile

PACKAGE_ID = 'dev.zhour.wechatpet.single'
BINARY = 'zhour-single.dylib'
FILTER = 'zhour-single.plist'


def tar_gzip(files):
    tar_bytes = io.BytesIO()
    with tarfile.open(fileobj=tar_bytes, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name, data, mode in files:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    result = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=result, mtime=0, compresslevel=9) as compressed:
        compressed.write(tar_bytes.getvalue())
    return result.getvalue()


def ar_entry(name, data):
    if len(name) > 15 or '\n' in name:
        raise ValueError('Invalid archive member name')
    header = (f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n').encode('ascii')
    assert len(header) == 60
    return header + data + (b'\n' if len(data) % 2 else b'')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dylib', type=Path, required=True, help='already built signed standalone dylib')
    parser.add_argument('--output', type=Path, required=True, help='output .deb path')
    parser.add_argument('--scheme', choices=('rootful', 'rootless'), required=True)
    parser.add_argument('--version', default='1.3.3')
    args = parser.parse_args()
    if not args.dylib.is_file():
        parser.error('dylib file does not exist')
    if not args.version or any(c in args.version for c in '\r\n '):
        parser.error('invalid package version')
    binary = args.dylib.read_bytes()
    if not binary:
        parser.error('dylib is empty')
    architecture = 'iphoneos-arm64' if args.scheme == 'rootless' else 'iphoneos-arm'
    prefix = './var/jb' if args.scheme == 'rootless' else '.'
    base = prefix + '/Library/MobileSubstrate/DynamicLibraries/'
    plist = plistlib.dumps({'Filter': {'Bundles': ['com.tencent.xin']}}, fmt=plistlib.FMT_XML, sort_keys=True)
    control = ('Package: ' + PACKAGE_ID + '\n'
               'Name: zhour-single\n'
               'Version: ' + args.version + '\n'
               'Architecture: ' + architecture + '\n'
               'Description: Standalone WeChat desktop pet\n'
               'Section: Tweaks\n'
               'Maintainer: zhour\n'
               'Depends: firmware (>= 16.3)\n').encode('utf-8')
    members = [('debian-binary', b'2.0\n'),
               ('control.tar.gz', tar_gzip([('./control', control, 0o644)])),
               ('data.tar.gz', tar_gzip([(base+BINARY, binary, 0o644), (base+FILTER, plist, 0o644)]))]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(b'!<arch>\n' + b''.join(ar_entry(name, data) for name, data in members))
    print(f'Built {args.output} ({args.scheme}, {architecture})')


if __name__ == '__main__':
    main()
