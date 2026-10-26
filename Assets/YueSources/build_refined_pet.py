#!/usr/bin/env python3
"""Bake Yue's fixed-proportion key cels and articulated two-leg gait to v4.

Art is generated with imagegen from Yue's supplied character. This assembler
uses rigid pieces and uniform scaling; no frame stretches heads or limbs.
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / 'Resources/DefaultPet'
CELL = (192, 208)
R = Image.Resampling


def clean(image):
    image = image.convert('RGBA')
    image.putalpha(image.getchannel('A').point(lambda a: 0 if a < 24 else a))
    return image


def subject(image):
    image = clean(image)
    box = image.getchannel('A').point(lambda a: 255 if a > 80 else 0).getbbox()
    if not box:
        raise ValueError('Empty generated cel')
    return image.crop((max(0, box[0]-1), max(0, box[1]-1), min(image.width, box[2]+1), min(image.height, box[3]+1)))


def place(image, scale=None, height=None, baseline=202, center=96):
    image = subject(image)
    scale = height/image.height if height is not None else scale
    image = image.resize((round(image.width*scale), round(image.height*scale)), R.LANCZOS)
    frame = Image.new('RGBA', CELL)
    frame.alpha_composite(image, (round(center-image.width/2), round(baseline-image.height)))
    return frame


def shifted(image, dx=0, dy=0):
    frame = Image.new('RGBA', CELL)
    frame.alpha_composite(image, (round(dx), round(dy)))
    return frame


def crop_key(sheet, col, row, split):
    return sheet.crop((col*sheet.width//3, 0 if row == 0 else split,
                       (col+1)*sheet.width//3, split if row == 0 else sheet.height))


def local_expression(base, candidate, amount=1):
    # Expressions may replace eyes/mouth inside the skull, never its outline.
    mask = Image.new('L', CELL)
    ImageDraw.Draw(mask).ellipse((66, 52, 128, 92), fill=round(255*amount))
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    return Image.composite(candidate, base, mask)


def standing_keys():
    sheet = Image.open(HERE/'standing-keys-cutout.png').convert('RGBA')
    raw = [place(crop_key(sheet, i%3, i//3, 523), height=189) for i in range(6)]
    neutral = raw[0]
    closed = local_expression(neutral, raw[1])
    # Every standing action shares exactly the same head shell, skirt, legs
    # and shoes. Only an arm/phone region and interior expression can change.
    wave = neutral.copy()
    wave.paste(raw[2].crop((117, 72, 163, 173)), (117, 72))
    anger = neutral.copy()
    anger.paste(raw[3].crop((53, 91, 143, 173)), (53, 91))
    phone = neutral.copy()
    phone.paste(raw[4].crop((53, 91, 143, 173)), (53, 91))
    # Both independently framed body keys retain their own lower chin at
    # y=91..93. Pasting that body under the fixed neutral head duplicates the
    # chin edge as a horizontal line. Reuse the fixed head's original neck
    # pixels at this seam while keeping each pose's exact existing matte.
    # The arms, clothing, face, hair silhouette and body pose stay intact.
    neck_box = (70, 91, 115, 94)
    for body in (anger, phone):
        neck = neutral.crop(neck_box)
        neck.putalpha(body.crop(neck_box).getchannel('A'))
        body.paste(neck, neck_box[:2])
    phone_closed = local_expression(phone, closed)
    return neutral, closed, wave, anger, phone, phone_closed


def cut_polygon(image, polygon):
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    out = image.copy()
    out.putalpha(ImageChops.multiply(out.getchannel('A'), mask))
    return out


def rigid_limb(part, start, end, target, angle):
    rest = math.degrees(math.atan2(end[0]-start[0], end[1]-start[1]))
    rotated = part.rotate(angle-rest, R.BICUBIC, center=start)
    result = Image.new('RGBA', part.size)
    result.alpha_composite(rotated, (round(target[0]-start[0]), round(target[1]-start[1])))
    length = math.dist(start, end)
    joint = (target[0]+length*math.sin(math.radians(angle)),
             target[1]+length*math.cos(math.radians(angle)))
    return result, joint


def walking_cycle():
    source = clean(Image.open(HERE/'walk-cycle-generated.png').crop((0, 0, 396, 402)))
    # Front/back legs are independent pieces from one consistent artwork cel.
    # Their source lengths remain invariant as they exchange support/swing.
    upper = cut_polygon(source, [(0,0),(396,0),(396,283),(250,283),(242,301),
                                  (213,313),(178,313),(146,306),(121,293),(0,283)])
    near_thigh = cut_polygon(source, [(202,289),(234,291),(253,338),(230,350),(211,322)])
    near_shin = cut_polygon(source, [(225,326),(251,326),(259,346),(307,352),
                                     (315,375),(297,397),(260,402),(237,395),(226,359)])
    far_thigh = cut_polygon(source, [(162,289),(203,301),(177,337),(150,349),(130,329)])
    far_shin = cut_polygon(source, [(129,319),(158,333),(154,347),(175,368),
                                    (158,393),(135,400),(106,385),(81,365),(80,343),(96,331)])
    angles = [26,21,8,-8,-21,-26,-21,-8,8,21]
    shin_angles = [18,10,0,-18,-35,-85,-100,-70,-30,8]
    cycles, joints = [], []
    for index in range(10):
        frame = Image.new('RGBA', source.size)
        record = {}
        for name, offset, hip, knee, ankle, thigh, shin in [
            ('far',5,(180,294),(150,324),(132,347),far_thigh,far_shin),
            ('near',0,(217,294),(236,334),(248,356),near_thigh,near_shin),
        ]:
            phase = (index+offset)%10
            leg, new_knee = rigid_limb(thigh, hip, knee, hip, angles[phase])
            lower, new_ankle = rigid_limb(shin, knee, ankle, new_knee, shin_angles[phase])
            frame.alpha_composite(leg)
            frame.alpha_composite(lower)
            record[name] = {'hip':hip, 'knee':new_knee, 'ankle':new_ankle,
                            'angle':angles[phase], 'shinAngle':shin_angles[phase]}
        frame.alpha_composite(upper)
        # One common isotropic scale. Move the cel to the shoe baseline; no
        # rescaling of the head, torso, thighs or shins across the ten phases.
        scale = .46
        scaled = frame.resize((round(frame.width*scale),round(frame.height*scale)),R.LANCZOS)
        cel = Image.new('RGBA',CELL)
        dx = round(96-198*scale)
        dy = 11 + [0,0,-1,-2,-1,0,0,-1,-2,-1][index]
        cel.alpha_composite(scaled,(dx,dy))
        record['offset'] = [dx,dy]
        record['scale'] = scale
        cycles.append(cel)
        joints.append(record)
    return cycles, joints


def mix(a, b, factor):
    # Short pose transitions; interior face/leg proportions remain those of
    # the two calibrated keys, with no geometric interpolation or stretching.
    return Image.blend(a,b,factor)


def build():
    neutral, closed, wave, anger, phone, phone_closed = standing_keys()
    half = local_expression(neutral,closed,.5)
    emotes = Image.open(HERE/'emote-keys-generated.png').convert('RGBA')
    em = [place(crop_key(emotes,i%3,i//3,455),scale=.375,
                baseline=180 if i==2 else 202) for i in range(6)]
    thought, hug, joy, high_wave, kiss, side = em
    # The side profile uses a natural standing height, keeping the same skull
    # height as the neutral key rather than fitting a sitting pose to it.
    side = place(crop_key(emotes,2,1,455),height=189)
    left_side = ImageOps.mirror(side)
    turns = Image.open(HERE/'turn-keys-generated.png').convert('RGBA')
    back,rear,quarter = [place(turns.crop((i*turns.width//3,0,(i+1)*turns.width//3,turns.height)),height=189) for i in range(3)]
    gait,joints = walking_cycle()
    small_bob = [0,0,-1,-1,0,0,1,1,0,0]
    rows = []
    idle = [neutral,neutral,neutral,half,closed,closed,half,neutral,neutral,neutral]
    rows.append([shifted(key,dy=small_bob[i]) for i,key in enumerate(idle)])
    rows.extend([gait,[ImageOps.mirror(f) for f in gait]])
    waving = [neutral,mix(neutral,wave,.5),wave,wave,wave,wave,wave,wave,mix(neutral,wave,.5),neutral]
    rows.append([shifted(f,dy=small_bob[i]) for i,f in enumerate(waving)])
    happy_wave = local_expression(wave,closed)
    rows.append([neutral,mix(neutral,happy_wave,.5)]+[shifted(happy_wave,dy=y) for y in [-1,-2,-2,-1,0,-1]]+[mix(neutral,happy_wave,.5),neutral])
    rows.append([shifted(thought,dy=small_bob[i]) for i in range(10)])
    rows.append([neutral.rotate(a,R.BICUBIC,center=(96,150)) for a in [0,-1,-2,-1,0,1,2,1,0,0]])
    rows.append(gait)
    phone_frames=[]
    for i in range(10):
        cel=phone_closed.copy() if i in (4,5) else phone.copy()
        phone_frames.append(cel)
    rows.append(phone_frames)
    rows.append([back,back,rear,rear,side,side,quarter,quarter]+[Image.new('RGBA',CELL) for _ in range(2)])
    rows.append([neutral,neutral,quarter,quarter,side,side,rear,back]+[Image.new('RGBA',CELL) for _ in range(2)])
    rows.append(rows[3])
    rows.append([neutral.rotate(a,R.BICUBIC,center=(96,145)) for a in [0,-1,-1,0,1,1,0,-1,0,0]])
    rows.append([shifted(closed,dy=small_bob[i]) for i in range(10)])
    rows.append(rows[3])
    rows.append([neutral,neutral,half,closed,closed,closed,closed,half,neutral,neutral])
    rows.append([shifted(kiss,dy=small_bob[i]) for i in range(10)])
    rows.append([shifted(joy,dy=y) for y in [0,-1,-2,-3,-3,-2,-1,0,1,0]])
    rows.append([neutral,mix(neutral,anger,.5)]+[anger]*8)
    rows.append([shifted(hug,dx=x) for x in [0,-1,0,1,0,-1,0,1,0,0]])
    rows.append([shifted(anger,dy=small_bob[i]) for i in range(10)])
    rows.append([anger,anger,anger,closed,closed,closed,half,neutral,neutral,neutral])
    rows.append(gait)
    rows.append([shifted(neutral,dy=y) for y in [-4,-3,-1,1,1,0,0,0,0,0]])
    rows.append(rows[6])
    rows.append([shifted(side,dy=small_bob[i]) for i in range(10)])
    rows.append([ImageOps.mirror(f) for f in rows[25]])
    qleft=ImageOps.mirror(quarter)
    rows.append([left_side,left_side,qleft,qleft,qleft,neutral,neutral,neutral,neutral,neutral])
    rows.append([neutral,neutral,neutral,qleft,qleft,qleft,left_side,left_side,left_side,left_side])
    assert len(rows)==29 and all(len(row)==10 for row in rows)
    sheet=Image.new('RGBA',(1920,6032))
    for row,frames in enumerate(rows):
        for column,frame in enumerate(frames):sheet.paste(clean(frame),(column*192,row*208))
    OUT.mkdir(parents=True,exist_ok=True)
    sheet.save(OUT/'spritesheet.png',optimize=True)
    # Private bundled paging keeps the legacy v4 atlas/import contract intact
    # while the injected renderer retains only one 1920x208 action strip.
    row_paths = []
    for row in range(29):
        name = f'row-{row:02d}.png'
        sheet.crop((0, row*208, 1920, (row+1)*208)).save(OUT/name, optimize=True)
        row_paths.append(name)
    metadata=json.loads((HERE/'original-pet.json').read_text())
    metadata['wpBundledRowAtlasPaths'] = row_paths
    metadata['onlinePhoneRow']=8
    metadata['assetRevision']='1.1.0'
    metadata['description']='玥：双腿关节交替行走，固定头身与腿长；自然眨眼、在线玩手机。'
    metadata['passiveAnimations']={
        'idle':{'intervalSeconds':5.2,'restFrames':[0,1,2,1,0,1], 'blinkFrames':[2,3,4,5,6,7]},
        'onlinePhone':{'intervalSeconds':5.6,'restFrames':[0,1,2,3,2,1,0,1,2,3,2,1], 'blinkFrames':[2,3,4,5,6,7,8,9]},
    }
    (OUT/'pet.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    review=HERE/'Review';review.mkdir(exist_ok=True)
    (review/'gait-joints.json').write_text(json.dumps(joints,indent=2)+'\n')
    contact=Image.new('RGB',(10*192+40,29*226),(226,232,241))
    draw=ImageDraw.Draw(contact)
    for row,frames in enumerate(rows):
        draw.text((3,row*226+4),str(row),fill='black')
        for col,frame in enumerate(frames):contact.paste(frame,(40+192*col,row*226+18),frame)
    contact.save(review/'refined-all-rows.jpg',quality=92)
    for label,indices in [('walking',[1,2]),('expressions',[0,8,15,20]),('actions',[3,5,16,17]),('edge',[25,26,27,28])]:
        frames=[]
        for phase in range(10):
            preview=Image.new('RGB',(len(indices)*240,280),(227,233,242))
            d=ImageDraw.Draw(preview)
            for pos,row in enumerate(indices):
                cel=rows[row][phase].resize((192,208),R.LANCZOS)
                preview.paste(cel,(pos*240+24,40),cel)
                d.text((pos*240+24,12),f'row {row}  frame {phase}',fill=(30,35,40))
            frames.append(preview)
        palette=frames[0].quantize(colors=255)
        frames=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
        frames[0].save(review/f'{label}.gif',save_all=True,append_images=frames[1:],loop=0,duration=1000//15,disposal=2,optimize=False)
    print(f'Wrote {OUT}, 29 rows / 286 valid cels')


if __name__=='__main__':
    build()
