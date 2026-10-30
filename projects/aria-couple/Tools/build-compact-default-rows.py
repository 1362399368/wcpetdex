#!/usr/bin/env python3
"""Deduplicate byte-identical RGBA cels; retain logical timing and source files."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
pet = root / 'Resources/DefaultPet'
meta = json.loads((pet / 'pet.json').read_text())
paths, maps, rows = [], [], []
for index, source_name in enumerate(meta['wpBundledRowAtlasPaths']):
    source = Image.open(pet / source_name).convert('RGBA')
    cels, seen, mapping = [], {}, []
    for frame in range(meta['columns']):
        cel = source.crop((frame * 192, 0, (frame + 1) * 192, 208))
        data = cel.tobytes()
        key = hashlib.sha256(data).hexdigest()
        if key not in seen:
            seen[key] = len(cels)
            cels.append(cel)
        # Hashing only indexes candidates; compare bytes before reusing a cel.
        assert cels[seen[key]].tobytes() == data
        mapping.append(seen[key])
    compact = Image.new('RGBA', (192 * len(cels), 208))
    for position, cel in enumerate(cels):
        compact.paste(cel, (position * 192, 0))
    name = f'compact-row-{index:02}.png'
    compact.save(pet / name, optimize=True)
    decoded = Image.open(pet / name).convert('RGBA')
    for frame, position in enumerate(mapping):
        assert decoded.crop((position * 192, 0, (position + 1) * 192, 208)).tobytes() == source.crop((frame * 192, 0, (frame + 1) * 192, 208)).tobytes()
    paths.append(name)
    maps.append(mapping)
    rows.append({'row': index, 'uniqueFrames': len(cels), 'logicalFrames': meta['frameCounts'][index], 'legacyDecodedBytes': 1920 * 208 * 4, 'compactDecodedBytes': compact.width * 208 * 4})
meta['wpBundledCompactRowAtlasPaths'] = paths
meta['wpBundledCompactFrameMaps'] = maps
(pet / 'pet.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n')
report = {'pixelIdentity': True, 'rows': rows, 'originalFilesUnmodified': True}
(root / 'Tests/compact-rows-v111-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'pixelIdentity': True, 'idleUniqueFrames': rows[0]['uniqueFrames'], 'onlineUniqueFrames': rows[8]['uniqueFrames'], 'angerUniqueFrames': rows[20]['uniqueFrames'], 'newAssetBytes': sum((pet / name).stat().st_size for name in paths)}))
