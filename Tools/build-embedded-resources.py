#!/usr/bin/env python3
"""Build an obfuscated bounded archive for the standalone dylib.

The key is public and shipped to all clients; this deters casual extraction,
but it does not protect the asset against a determined reverse engineer.
"""
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MAGIC = b'WPSRES1\0'
ENC_MAGIC = b'WPSENC2\0'
# Public, fixed client-side material: never put secrets or API keys here.
OBFUSCATION_KEY = sha256(b'SinglePet-zhour public artwork obfuscation v2').digest()
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
        # Deterministic IV makes builds reproducible; no secret is being
        # protected. Integrity is separately checked after decryption.
        iv = sha256(archive).digest()[:16]
        result = subprocess.run(['openssl', 'enc', '-aes-256-cbc', '-K', OBFUSCATION_KEY.hex(), '-iv', iv.hex()],
                                input=bytes(archive), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        sealed = ENC_MAGIC + iv + result.stdout
        if len(sealed) > MAX_ARCHIVE + 40:
            raise SystemExit('encrypted embedded resource archive exceeds its size limit')
        output = Path(sys.argv[1])
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(sealed)
        print(f'Embedded resources: {len(entries)} files, {len(sealed)} bytes, SHA-256 {sha256(sealed).hexdigest()}')


if __name__ == '__main__':
    main()
