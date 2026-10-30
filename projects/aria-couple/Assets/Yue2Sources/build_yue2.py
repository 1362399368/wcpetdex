#!/usr/bin/env python3
"""Assemble Yue's editable art layers into a continuous 30 fps v5 pet.

This is a native animation rig over the existing generated Yue art. It does
not redraw a face or stretch a character to manufacture in-between frames.
The legacy DefaultPet directory is never modified.
"""
import importlib.util
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART = HERE.parent / 'YueSources'
OUT = ROOT / 'Resources/Yue2Pet'
REVIEW = HERE / 'Review'
CELL = (192, 208)
COUNT = 20
RATE = 30
SS = 4
R = Image.Resampling

spec = importlib.util.spec_from_file_location('yue_art', ART / 'build_refined_pet.py')
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


def clean(image):
    image = image.convert('RGBA')
    image.putalpha(image.getchannel('A').point(lambda a: 0 if a < 20 else a))
    return image


def pose(image, dx=0, dy=0, angle=0, pivot=(96, 196)):
    """Sample a rigid pose at subpixel precision; the x/y scale is identical."""
    hi = image.resize((CELL[0]*SS, CELL[1]*SS), R.LANCZOS)
    if angle:
        hi = hi.rotate(angle, R.BICUBIC, center=(pivot[0]*SS,pivot[1]*SS))
    if dx or dy:
        hi = hi.transform(hi.size, Image.Transform.AFFINE,
                          (1,0,-dx*SS,0,1,-dy*SS), R.BICUBIC)
    return clean(hi.resize(CELL,R.LANCZOS))


def ease(t):
    t = min(1,max(0,t))
    return t*t*(3-2*t)


def curve(keys, t):
    """Smooth keyframe timing without blending two character pictures."""
    if t <= keys[0][0]: return keys[0][1]
    for (a,x),(b,y) in zip(keys,keys[1:]):
        if t <= b: return x+(y-x)*ease((t-a)/(b-a))
    return keys[-1][1]


def anchored_turn_key(image):
    """Hair width must not move the character's root during a turn."""
    subject=art.subject(image)
    scale=189/subject.height
    subject=subject.resize((round(subject.width*scale),189),R.LANCZOS)
    alpha=subject.getchannel('A').point(lambda a:255 if a>80 else 0)
    feet=alpha.crop((0,164,subject.width,189)).getbbox()
    anchor=(feet[0]+feet[2])/2 if feet else subject.width/2
    frame=Image.new('RGBA',CELL)
    frame.alpha_composite(subject,(round(96-anchor),13))
    return frame


def rigid_limb(part, start, end, target, angle):
    rest = math.degrees(math.atan2(end[0]-start[0],end[1]-start[1]))
    rotated = part.rotate(angle-rest,R.BICUBIC,center=(start[0]*SS,start[1]*SS))
    rotated = rotated.transform(rotated.size,Image.Transform.AFFINE,
        (1,0,-(target[0]-start[0])*SS,0,1,-(target[1]-start[1])*SS),R.BICUBIC)
    length = math.dist(start,end)
    endpoint=(target[0]+length*math.sin(math.radians(angle)),
              target[1]+length*math.cos(math.radians(angle)))
    return rotated,endpoint


def walking_cycle():
    source = art.clean(Image.open(ART/'walk-cycle-generated.png').crop((0,0,396,402)))
    polygons = [
        [(0,0),(396,0),(396,283),(250,283),(242,301),(213,313),(178,313),(146,306),(121,293),(0,283)],
        [(202,289),(234,291),(253,338),(230,350),(211,322)],
        [(225,326),(251,326),(259,346),(307,352),(315,375),(297,397),(260,402),(237,395),(226,359)],
        [(162,289),(203,301),(177,337),(150,349),(130,329)],
        [(129,319),(158,333),(154,347),(175,368),(158,393),(135,400),(106,385),(81,365),(80,343),(96,331)],
    ]
    upper,near_thigh,near_shin,far_thigh,far_shin = [
        art.cut_polygon(source,p).resize((source.width*SS,source.height*SS),R.LANCZOS)
        for p in polygons]
    frames,records=[],[]
    for i in range(COUNT):
        t=i/COUNT
        frame=Image.new('RGBA',upper.size)
        record={'phase':t,'scale':.46,'supersampling':SS}
        for name,offset,hip,knee,ankle,thigh,shin in [
            ('far',.5,(180,294),(150,324),(132,347),far_thigh,far_shin),
            ('near',0,(217,294),(236,334),(248,356),near_thigh,near_shin),
        ]:
            phase=2*math.pi*(t+offset)
            thigh_angle=26*math.cos(phase)
            # Continuous cosine, rather than the old 50-degree key jump.
            # The sine term separates planted and recovery phases: without
            # this phase lag, a cosine-only gait repeats its first half in
            # reverse and does not produce twenty distinct leg positions.
            shin_angle=-36+54*math.cos(phase)+25*math.sin(phase)
            leg,new_knee=rigid_limb(thigh,hip,knee,hip,thigh_angle)
            lower,new_ankle=rigid_limb(shin,knee,ankle,new_knee,shin_angle)
            frame.alpha_composite(leg);frame.alpha_composite(lower)
            record[name]={'hip':hip,'knee':new_knee,'ankle':new_ankle,
                          'angle':thigh_angle,'shinAngle':shin_angle}
        frame.alpha_composite(upper)
        scale=.46
        scaled=frame.resize((round(source.width*scale*SS),round(source.height*scale*SS)),R.LANCZOS)
        dx=96-198*scale
        dy=11-.65*(1-math.cos(4*math.pi*t))
        cel=Image.new('RGBA',(CELL[0]*SS,CELL[1]*SS))
        # Fractional target placement is sampled at 4x resolution.
        cel.alpha_composite(scaled,(round(dx*SS),round(dy*SS)))
        frames.append(clean(cel.resize(CELL,R.LANCZOS)))
        record['offset']=[round(dx*SS)/SS,round(dy*SS)/SS]
        records.append(record)
    return frames,records


def interior_blink(neutral,closed,i):
    # Four fully closed frames at 30 fps = the old 2/15 second closure.
    amount=curve([(0,0),(.20,0),(.35,1),(.50,1),(.70,0),(1,0)],i/COUNT)
    return art.local_expression(neutral,closed,amount)


def rigid_cycle(image, amplitude=.5, tilt=0, dx=0, count=COUNT, pivot=(96,196)):
    return [pose(image,dx=dx*math.sin(2*math.pi*i/count),
                 dy=-amplitude*(1-math.cos(2*math.pi*i/count))/2,
                 angle=tilt*math.sin(2*math.pi*i/count),pivot=pivot) for i in range(count)]


def wave_cycle(neutral,wave,happy=None):
    # The painted arm stays intact; gently pivot the gesture, never dissolve
    # the face or interpolate a long arm into a short one.
    key=happy or wave
    return [pose(key,dy=-.55*math.sin(math.pi*i/COUNT),
                 angle=.85*math.sin(2*math.pi*i/COUNT),pivot=(96,170))
            for i in range(COUNT)]


def pose_sequence(keys,count=COUNT,reverse=False):
    """Turn with actual angle keys and small continuous anticipation."""
    if reverse: keys=list(reversed(keys))
    frames=[]
    for i in range(count):
        t=i/(count-1)
        pos=min(len(keys)-1,int(t*len(keys)))
        key=keys[pos]
        # Preserve skull/limb proportions within each genuine view.
        frames.append(pose(key,dy=-.5*math.sin(math.pi*t),angle=.3*math.sin(2*math.pi*t)))
    return frames


def build():
    neutral,closed,wave,anger,phone,phone_closed=art.standing_keys()
    # The legacy front artwork's shoes are 2.5px off its bitmap center. Give
    # all front keys one common root, matching new turns and their mirrors.
    foot_bounds=neutral.getchannel('A').point(lambda a:255 if a>80 else 0).crop((0,179,192,208)).getbbox()
    root_dx=96-(foot_bounds[0]+foot_bounds[2])/2
    neutral,closed,wave,anger,phone,phone_closed=[pose(k,dx=root_dx)
        for k in (neutral,closed,wave,anger,phone,phone_closed)]
    emotes=Image.open(ART/'emote-keys-generated.png').convert('RGBA')
    em=[art.place(art.crop_key(emotes,i%3,i//3,455),scale=.375,
                  baseline=180 if i==2 else 202) for i in range(6)]
    thought,hug,joy,high_wave,kiss,side=em
    side=art.place(art.crop_key(emotes,2,1,455),height=189)
    turns=Image.open(ART/'turn-keys-generated.png').convert('RGBA')
    back,rear,quarter=[art.place(turns.crop((i*turns.width//3,0,(i+1)*turns.width//3,turns.height)),height=189) for i in range(3)]
    # Optional matching front-to-left angle keys supplied by imagegen. Both
    # edge directions then share these exact keys through renderer mirroring.
    turn_keys=[neutral,ImageOps.mirror(quarter),ImageOps.mirror(side)]
    extra=HERE/'turn-keys-smooth.png'
    if extra.exists():
        # Parent can provide a calibrated manifest when accepting extra keys.
        manifest=HERE/'turn-keys-smooth.json'
        sheet=Image.open(extra).convert('RGBA')
        if manifest.exists():
            boxes=json.loads(manifest.read_text())['boxes']
        else:
            boxes=[(i%5*sheet.width//5,i//5*sheet.height//2,
                    (i%5+1)*sheet.width//5,(i//5+1)*sheet.height//2) for i in range(10)]
        turn_keys=[anchored_turn_key(sheet.crop(tuple(box))) for box in boxes]
        turn_keys[0]=neutral
        side=ImageOps.mirror(turn_keys[-1])
    gait,joints=walking_cycle()
    rows=[]
    rows.append([pose(interior_blink(neutral,closed,i),dy=-.45*math.sin(math.pi*i/COUNT)**2) for i in range(COUNT)])
    rows.extend([gait,[ImageOps.mirror(f) for f in gait]])
    rows.append(wave_cycle(neutral,wave))
    rows.append(wave_cycle(neutral,wave,art.local_expression(wave,closed)))
    rows.append(rigid_cycle(thought,.45,.25,pivot=(96,177)))
    rows.append(rigid_cycle(neutral,.2,1.4,pivot=(96,150)))
    rows.append(gait)
    rows.append([pose(interior_blink(phone,phone_closed,i),dy=-.25*math.sin(math.pi*i/COUNT)**2) for i in range(COUNT)])
    rows.append(pose_sequence([back,rear,side,quarter],count=16))
    rows.append(pose_sequence([neutral,quarter,side,rear,back],count=16))
    rows.append(wave_cycle(neutral,wave))
    rows.append([pose(neutral,angle=1.1*math.sin(2*math.pi*i/COUNT),pivot=(96,145)) for i in range(COUNT)])
    rows.append(rigid_cycle(closed,.65,.25,pivot=(96,158)))
    rows.append(wave_cycle(neutral,wave))
    rows.append([pose(interior_blink(neutral,closed,i),dy=-.5*math.sin(math.pi*i/COUNT)**2) for i in range(COUNT)])
    rows.append(rigid_cycle(kiss,.6,.45,pivot=(96,162)))
    rows.append([pose(joy,dy=-2*math.sin(math.pi*i/(COUNT-1))**2,
                      angle=.5*math.sin(2*math.pi*i/COUNT),pivot=(96,170)) for i in range(COUNT)])
    rows.append([pose(anger,dy=-.5*math.sin(math.pi*i/COUNT)**2,
                      angle=.5*math.sin(2*math.pi*i/COUNT)) for i in range(COUNT)])
    rows.append(rigid_cycle(hug,.35,.35,dx=.5,pivot=(96,176)))
    rows.append(rigid_cycle(anger,.45,.15))
    rows.append([pose(anger if i<7 else interior_blink(neutral,closed,i),
                      dy=-.45*math.sin(math.pi*i/COUNT)**2) for i in range(COUNT)])
    rows.append(gait)
    rows.append([pose(neutral,dy=curve([(0,-4),(.28,1.2),(.5,-.5),(.76,.15),(1,0)],i/(COUNT-1))) for i in range(COUNT)])
    rows.append(rigid_cycle(neutral,.15,1.8,pivot=(96,150)))
    rows.append(rigid_cycle(side,.45,.12))
    rows.append([ImageOps.mirror(f) for f in rows[25]])
    reveal_keys=list(reversed(turn_keys))
    rows.append(pose_sequence(reveal_keys))
    rows.append(pose_sequence(reveal_keys,reverse=True))
    assert len(rows)==29
    counts=[len(row) for row in rows]
    assert counts==[16 if r in (9,10) else 20 for r in range(29)]
    OUT.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    filenames=[]
    for r,frames in enumerate(rows):
        filename=f'row-{r:02d}.png';filenames.append(filename)
        strip=Image.new('RGBA',(CELL[0]*COUNT,CELL[1]))
        for c,frame in enumerate(frames):strip.paste(clean(frame),(CELL[0]*c,0))
        strip.save(OUT/filename,optimize=True)
    metadata=json.loads((ROOT/'Resources/DefaultPet/pet.json').read_text())
    # This private paging alias applies only to the legacy bundled v4 atlas.
    # The v5 package uses its own validated rowAtlasPaths manifest below.
    metadata.pop('wpBundledRowAtlasPaths',None)
    metadata.update({'id':'yue2-zhour-20261022','displayName':'玥2',
        'description':'玥2：连续双腿骨架、20帧动作、30fps，固定头身比例与慢眨眼。',
        'spriteVersionNumber':5,'spritesheetPath':filenames[0],
        'rowAtlasPaths':filenames,'frameWidth':192,'frameHeight':208,
        'columns':20,'rows':29,'frameCounts':counts,'frameRate':RATE,
        'assetRevision':'2.0.0','minimumPluginVersion':'1.0.5'})
    metadata['passiveAnimations']={
        'idle':{'intervalSeconds':5.2,'restFrames':[0,1,2,3,4,3,2,1],
                'blinkFrames':list(range(4,17))},
        'onlinePhone':{'intervalSeconds':5.6,'restFrames':[0,1,2,3,4,3,2,1],
                       'blinkFrames':list(range(4,17))}}
    (OUT/'pet.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    (REVIEW/'gait-joints.json').write_text(json.dumps(joints,indent=2)+'\n')
    contact=Image.new('RGB',(20*144+36,29*174),(229,235,243));d=ImageDraw.Draw(contact)
    for r,frames in enumerate(rows):
        d.text((3,r*174+4),str(r),fill=(30,35,40))
        for c,f in enumerate(frames):
            f=f.resize((144,156),R.LANCZOS);contact.paste(f,(36+c*144,r*174+18),f)
    contact.save(REVIEW/'all-rows.jpg',quality=93)
    for label,indices in [('walking',[1,2]),('expressions',[0,8,13,20]),
                          ('interactions',[11,16,17,19]),('edge',[25,26,27,28])]:
        preview=[]
        for i in range(COUNT):
            canvas=Image.new('RGB',(240*len(indices),260),(230,236,244));d=ImageDraw.Draw(canvas)
            for col,r in enumerate(indices):
                cel=rows[r][i%len(rows[r])]
                canvas.paste(cel,(col*240+24,30),cel)
                d.text((col*240+24,8),f'row {r}',fill=(35,40,48))
            preview.append(canvas)
        # Shared palette plus a 30/40ms schedule approximates 30 fps in GIF.
        palette=Image.new('RGB',(preview[0].width,preview[0].height*5))
        for k,i in enumerate((0,4,8,12,16)):palette.paste(preview[i],(0,k*preview[0].height))
        palette=palette.quantize(colors=255)
        converted=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in preview]
        converted[0].save(REVIEW/f'{label}.gif',save_all=True,append_images=converted[1:],
            duration=[30,30,40]*6+[30,40],loop=0,disposal=2,optimize=False)
    print(f'Yue2: {sum(counts)} valid frames / {len(rows)} action strips / {RATE} fps')
    return rows,joints


if __name__=='__main__':
    build()
