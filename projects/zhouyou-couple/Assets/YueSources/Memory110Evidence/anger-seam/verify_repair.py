#!/usr/bin/env python3
"""Check exact delivered repair bytes plus old import compatibility fixtures."""
import hashlib
import io
import json
import zipfile
from pathlib import Path
from PIL import Image, ImageChops

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]

def sha(data):return hashlib.sha256(data).hexdigest()

def main():
    before=json.loads((HERE/'before-hashes.json').read_text())
    after=json.loads((HERE/'corrected-hashes.json').read_text())
    for name,expected in after.items():
        assert sha((ROOT/'Resources'/name).read_bytes())==expected,name
    changed_rows={8:set(range(20)),18:set(range(20)),20:set(range(20)),21:set(range(7))}
    for row in set(range(29))-changed_rows.keys():
        name=f'Yue2Pet/row-{row:02d}.png'
        assert before[name]==after[name],name
    expected_diffs=json.loads((HERE/'yue2-diff.json').read_text())
    actual=[]
    with zipfile.ZipFile(HERE/'known-old-assets.zip') as archive:
        assert sha(archive.read('v4/spritesheet.png'))=='6c80ca328a8ac4b5c5015e4cee47958d3d8764a887b341ffabfd133f8ff2a475'
        assert json.loads(archive.read('v5/pet.json'))==json.loads((ROOT/'Resources/Yue2Pet/pet.json').read_text())
        for row,frames in changed_rows.items():
            filename=f'row-{row:02d}.png';raw=archive.read('v5/'+filename)
            assert sha(raw)==before['Yue2Pet/'+filename]
            old=Image.open(io.BytesIO(raw)).convert('RGBA')
            new=Image.open(ROOT/'Resources/Yue2Pet'/filename).convert('RGBA')
            correction=Image.open(ROOT/'Resources/PetCorrections'/('yue2-'+filename)).convert('RGBA')
            assert old.size==new.size==(3840,208)
            assert correction.tobytes()==new.tobytes()
            assert old.getchannel('A').tobytes()==new.getchannel('A').tobytes()
            for frame in range(20):
                box=(frame*192,0,(frame+1)*192,208)
                a,b=old.crop(box),new.crop(box)
                channels=ImageChops.difference(a,b).split();mask=channels[0]
                for channel in channels[1:]:mask=ImageChops.lighter(mask,channel)
                bbox=mask.getbbox()
                if frame not in frames:assert bbox is None,(row,frame)
                else:
                    assert bbox and bbox[0]>=61 and bbox[1]>=82 and bbox[2]<=119 and bbox[3]<=103,(row,frame,bbox)
                    actual.append({'row':row,'frame':frame,'bbox':list(bbox),
                        'changedPixels':sum(value>0 for value in mask.getdata()),'alphaEqual':True})
    assert actual==expected_diffs
    assert len(actual)==67
    print('PASS: 572 Yue2 cels retain alpha/grid/timing; 67 localized neck repairs; all other 25 action strips byte-identical.')
    print('PASS: corrected rows match four read-only compatibility resources, and exact old-byte fixtures remain intact.')

if __name__=='__main__':main()
