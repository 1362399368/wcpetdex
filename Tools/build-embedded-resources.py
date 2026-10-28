#!/usr/bin/env python3
"""Build a bounded archive to embed in the standalone dylib's Mach-O section."""
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MAGIC = b'WPSRES1\0'
MAX_ARCHIVE = 8 * 1024 * 1024


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: build-embedded-resources.py OUTPUT')
    with TemporaryDirectory(prefix='zhour-single-resources-') as tmp:
        pet = Path(tmp) / 'DefaultPet'
        subprocess.run([sys.executable, str(ROOT / 'Tools/prepare-single-lulu.py'), str(pet)], check=True)
        entries = [(f'DefaultPet/lulu-row-{i:02}.png', pet / f'lulu-row-{i:02}.png') for i in range(9)]
        entries += [('DefaultPet/pet.json', pet / 'pet.json'),
                    ('petdex-manifest-snapshot.json', ROOT / 'Resources/petdex-manifest-snapshot.json')]
        archive = bytearray(MAGIC + struct.pack('<I', len(entries)))
        for name, path in entries:
            name_bytes = name.encode('utf-8')
            data = path.read_bytes()
            if not data or len(name_bytes) > 128 or len(data) > 4 * 1024 * 1024:
                raise SystemExit(f'invalid resource: {name}')
            archive += struct.pack('<HI', len(name_bytes), len(data)) + sha256(data).digest() + name_bytes + data
        if len(archive) > MAX_ARCHIVE:
            raise SystemExit('embedded resource archive exceeds 8 MiB')
        output = Path(sys.argv[1])
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(archive)
        print(f'Embedded resources: {len(entries)} files, {len(archive)} bytes, SHA-256 {sha256(archive).hexdigest()}')


if __name__ == '__main__':
    main()
