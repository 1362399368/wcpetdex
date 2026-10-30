#!/usr/bin/env python3
"""Prepare the single-edition default pet from its official Petdex artwork.

Artwork copyright belongs to its contributor; downloading it during the build
keeps the source repository from redistributing it. Pixels are cropped only.
Requires Pillow with WebP support; the output is a build artifact, not source.
"""
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import json
import sys
from urllib.request import Request, urlopen

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit('Preparing the default pet requires Pillow: python3 -m pip install Pillow') from exc

URL = 'https://assets.petdex.dev/pets/lulu-capybara-9f9107636ecc/sprite.webp'
DIGEST = 'f4b279d042266ae978a857bc25eefae49bb9bb9865917d7d1d5d1d02c77432a8'
ROOT = Path(__file__).resolve().parent.parent
MAX_BYTES = 8 * 1024 * 1024


def read_sprite():
    cache = ROOT / 'build' / 'lulu-cache' / 'sprite.webp'
    candidates = [cache, ROOT / '.single-pet-preparation' / 'lulu' / 'spritesheet.webp']
    for candidate in candidates:
        if candidate.is_file() and candidate.stat().st_size <= MAX_BYTES:
            data = candidate.read_bytes()
            if sha256(data).hexdigest() == DIGEST:
                return data
    request = Request(URL, headers={'User-Agent': 'zhour-single-build/1.0'})
    with urlopen(request, timeout=30) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or sha256(data).hexdigest() != DIGEST:
        raise SystemExit('Petdex 噜噜资源校验失败，已取消构建。')
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_bytes(data)
    return data


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: prepare-single-lulu.py OUTPUT_DIRECTORY')
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    with Image.open(BytesIO(read_sprite())) as source:
        if source.size != (1536, 1872):
            raise SystemExit('Petdex 噜噜资源尺寸不符，已取消构建。')
        atlas = source.convert('RGBA')
        paths, counts = [], []
        for row in range(9):
            page = atlas.crop((0, row * 208, 1536, (row + 1) * 208))
            nonempty = [column for column in range(8) if page.crop((column * 192, 0, (column + 1) * 192, 208)).getchannel('A').getbbox()]
            if not nonempty or nonempty != list(range(nonempty[-1] + 1)):
                raise SystemExit(f'Petdex 噜噜第 {row} 行帧布局不符合预期。')
            filename = f'lulu-row-{row:02}.png'
            page.save(destination / filename, format='PNG', optimize=True)
            paths.append(filename)
            counts.append(len(nonempty))
    # A paged v1 atlas is the same format already used by imported Petdex pets.
    metadata = {
        'id': 'lulu-capybara', 'displayName': '噜噜',
        'description': 'Petdex 噜噜', 'author': 'gitcjp',
        'source': 'https://petdex.dev/pets/lulu-capybara-2',
        'spriteVersionNumber': 5, 'wpLocalPagedVersion': 1,
        'wpLegacySpriteVersion': 1, 'spritesheetPath': paths[0],
        'rowAtlasPaths': paths, 'columns': 8, 'rows': 9,
        'frameWidth': 192, 'frameHeight': 208, 'frameRate': 12,
        'frameCounts': counts,
        'semanticRows': {'idle': 0, 'drag': 1, 'land': 0,
                         'tap': 6, 'longPress': 6, 'shake': 8,
                         'peekLeft': 0, 'peekRight': 0, 'reveal': 0, 'retract': 0},
    }
    (destination / 'pet.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
