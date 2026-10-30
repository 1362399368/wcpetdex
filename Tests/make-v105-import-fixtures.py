#!/usr/bin/env python3
"""Generate tiny protocol fixtures, not desktop-pet production artwork."""
import copy
import io
import json
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
out = root / 'build/v105-import-fixtures'
out.mkdir(parents=True, exist_ok=True)
semantics = json.loads((root / 'Resources/DefaultPet/pet.json').read_text())['semanticRows']
metadata = {
    'id': 'v5-import-fixture', 'displayName': 'Yue2 fixture', 'author': 'Test',
    'spriteVersionNumber': 5, 'frameWidth': 192, 'frameHeight': 208,
    'columns': 20, 'rows': 29, 'frameRate': 30,
    'frameCounts': [16 if r in (9, 10) else 20 for r in range(29)],
    'rowAtlasPaths': [f'row-{r:02}.png' for r in range(29)],
    'spritesheetPath': 'row-00.png', 'semanticRows': semantics, 'onlinePhoneRow': 8,
    'assetRevision': 'fixture-1',
    'passiveAnimations': {'idle': {'intervalSeconds': 5.2, 'restFrames': [0, 1], 'blinkFrames': [8, 9, 10, 11]}},
}


def strip(count, mode='RGBA', width=3840, skip=None):
    background = (0, 0, 0, 0) if mode == 'RGBA' else (240, 240, 240)
    image = Image.new(mode, (width, 208), background)
    draw = ImageDraw.Draw(image)
    for cell in range(min(count, width // 192)):
        if cell == skip:
            continue
        color = (80 + cell, 120, 190, 255) if mode == 'RGBA' else (80 + cell, 120, 190)
        draw.rectangle((cell * 192 + 40, 24, cell * 192 + 150, 196), fill=color)
    output = io.BytesIO()
    image.save(output, format='PNG')
    return output.getvalue()


full, short = strip(20), strip(16)
base = {name: short if row in (9, 10) else full for row, name in enumerate(metadata['rowAtlasPaths'])}
manifest = {}


def fixture(name, valid=False, change=None, images=None, nested=False):
    meta = copy.deepcopy(metadata)
    if change:
        change(meta)
    files = dict(base)
    if images:
        for path, data in images.items():
            if data is None:
                files.pop(path, None)
            else:
                files[path] = data
    prefix = 'package/' if nested else ''
    with zipfile.ZipFile(out / (name + '.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(prefix + 'pet.json', json.dumps(meta).encode())
        for path, data in files.items():
            archive.writestr(prefix + path, data)
    manifest[name + '.zip'] = valid


fixture('valid-v5', True)
fixture('valid-v5-nested', True, nested=True)
fixture('missing-row', images={'row-28.png': None})
fixture('duplicate-row-name', change=lambda m: m['rowAtlasPaths'].__setitem__(1, m['rowAtlasPaths'][0]))
fixture('unsafe-row-name', change=lambda m: m['rowAtlasPaths'].__setitem__(1, '../row-01.png'))
fixture('wrong-preview-alias', change=lambda m: m.__setitem__('spritesheetPath', 'row-01.png'))
fixture('wrong-row-count', change=lambda m: m.__setitem__('rows', 28))
fixture('wrong-column-count', change=lambda m: m.__setitem__('columns', 10))
fixture('boolean-column-count', change=lambda m: m.__setitem__('columns', True))
fixture('fractional-frame-count', change=lambda m: m['frameCounts'].__setitem__(1, 19.5))
fixture('zero-frame-count', change=lambda m: m['frameCounts'].__setitem__(1, 0))
fixture('count-does-not-match-image', change=lambda m: m['frameCounts'].__setitem__(1, 19))
fixture('empty-middle-frame', images={'row-00.png': strip(20, skip=10)})
fixture('wrong-row-dimensions', images={'row-00.png': strip(10, width=1920)})
fixture('row-without-alpha', images={'row-00.png': strip(20, mode='RGB')})
fixture('bad-image-data', images={'row-14.png': b'not a PNG'})
fixture('missing-semantic', change=lambda m: m['semanticRows'].pop('tap'))
fixture('unknown-semantic', change=lambda m: m['semanticRows'].__setitem__('unknownAction', 11))
fixture('out-of-range-semantic', change=lambda m: m['semanticRows'].__setitem__('tap', 29))
fixture('boolean-semantic', change=lambda m: m['semanticRows'].__setitem__('tap', True))
fixture('bad-frame-rate', change=lambda m: m.__setitem__('frameRate', 31))
fixture('fractional-frame-rate', change=lambda m: m.__setitem__('frameRate', 29.5))
fixture('out-of-range-online-row', change=lambda m: m.__setitem__('onlinePhoneRow', 29))
fixture('short-path-array', change=lambda m: m['rowAtlasPaths'].pop())
# The file-size gate must reject it before reading/decompressing its body.
with (out / 'archive-over-32MiB.zip').open('wb') as file:
    file.seek(32 * 1024 * 1024)
    file.write(b'X')
manifest['archive-over-32MiB.zip'] = False
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with zipfile.ZipFile(out / 'legacy-v4.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in ('pet.json', 'spritesheet.png'):
        archive.write(root / 'Resources/DefaultPet' / name, name)
print(f'Generated {len(manifest)} v5 fixtures in {out}')
