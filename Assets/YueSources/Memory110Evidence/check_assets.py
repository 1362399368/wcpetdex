#!/usr/bin/env python3
"""Verify paging and narrow phone/arms-crossed neck repairs against v1.0.7."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def changes(a,b):
    diff=ImageChops.difference(a,b)
    mask=diff.getchannel('R')
    for channel in diff.split()[1:]:mask=ImageChops.lighter(mask,channel)
    return mask.getbbox()

def run():
    before=Image.open(HERE/'before/spritesheet.png').convert('RGBA')
    after=Image.open(ROOT/'Resources/DefaultPet/spritesheet.png').convert('RGBA')
    old=json.loads((HERE/'before/pet.json').read_text())
    meta=json.loads((ROOT/'Resources/DefaultPet/pet.json').read_text())
    assert before.size==after.size==(1920,6032)
    for key in ['id','columns','rows','frameWidth','frameHeight','frameCounts','frameRate','semanticRows','onlinePhoneRow','passiveAnimations']:
        assert old[key]==meta[key],key
    assert sum(meta['frameCounts'])==286
    assert before.getchannel('A').tobytes()==after.getchannel('A').tobytes()
    # Only the 3px splice under the fixed head may change. Row 20 has the
    # original +/-1px rigid bob, and row 18 starts with one neutral cel.
    bob=[0,0,-1,-1,0,0,1,1,0,0]
    expected={(8,i):(70,91,115,94) for i in range(10)}
    expected.update({(18,i):(70,91,115,94) for i in range(1,10)})
    expected.update({(20,i):(70,91+bob[i],115,94+bob[i]) for i in range(10)})
    expected.update({(21,i):(70,91,115,94) for i in range(3)})
    changed=[]
    for row,count in enumerate(meta['frameCounts']):
        for frame in range(count):
            box=(frame*192,row*208,(frame+1)*192,(row+1)*208)
            delta=changes(before.crop(box),after.crop(box))
            if delta:
                assert (row,frame) in expected and delta==expected[row,frame],(row,frame,delta)
                changed.append({'row':row,'frame':frame,'localBox':delta})
    assert len(changed)==len(expected)==32
    assert len(meta['wpBundledRowAtlasPaths'])==29
    for row,name in enumerate(meta['wpBundledRowAtlasPaths']):
        strip=Image.open(ROOT/'Resources/DefaultPet'/name).convert('RGBA')
        assert strip.size==(1920,208)
        assert strip.tobytes()==after.crop((0,row*208,1920,(row+1)*208)).tobytes()
    report={'baseVersion':'1.0.7','newVersion':'1.1.0','frames':286,'rows':29,
        'alphaUnchanged':True,'timingAndSemanticsUnchanged':True,
        'allStripsExactlyMatchFullAtlas':True,'neckRepair':changed,
        'baselineSHA256':hashlib.sha256((HERE/'before/spritesheet.png').read_bytes()).hexdigest(),
        'updatedSHA256':hashlib.sha256((ROOT/'Resources/DefaultPet/spritesheet.png').read_bytes()).hexdigest()}
    (HERE/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('PASS: 286 frames retain alpha, grid, timing and semantics; only the 3px neck splice in 32 phone/arms-crossed cels changes.')
    print('PASS: 29 action strips exactly match the corresponding full-atlas pixels.')
if __name__=='__main__':run()
