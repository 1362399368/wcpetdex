#!/usr/bin/env python3
"""Verify bundled Lulu rows preserve every pixel of the verified Petdex sprite."""
from pathlib import Path
from tempfile import TemporaryDirectory
from PIL import Image
import importlib.util
import io
import json
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
script = root / 'Tools' / 'prepare-single-lulu.py'
spec = importlib.util.spec_from_file_location('prepare_single_lulu', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = Image.open(io.BytesIO(module.read_sprite())).convert('RGBA')
with TemporaryDirectory() as tmp:
    subprocess.run([sys.executable, str(script), tmp], check=True)
    metadata = json.loads((Path(tmp) / 'pet.json').read_text())
    assert metadata['id'] == 'lulu-capybara'
    assert metadata['frameCounts'] == [6, 8, 8, 4, 5, 8, 6, 6, 6]
    assert len(metadata['rowAtlasPaths']) == 9
    for row, path in enumerate(metadata['rowAtlasPaths']):
        expected = source.crop((0, row * 208, 1536, (row + 1) * 208))
        with Image.open(Path(tmp) / path) as page:
            assert page.size == (1536, 208)
            assert page.convert('RGBA').tobytes() == expected.tobytes(), f'row {row} differs from source'
print('single Lulu: metadata and all 9 pixel-identical row atlases passed')
