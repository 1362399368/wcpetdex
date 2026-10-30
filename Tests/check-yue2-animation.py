#!/usr/bin/env python3
"""Inspect delivered Yue2 strips and geometry without rebuilding the assets."""
import hashlib
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageOps, ImageStat

ROOT=Path(__file__).resolve().parent.parent
ASSET=ROOT/'Resources/Yue2Pet'
REVIEW=ROOT/'Assets/Yue2Sources/Review'
metadata=json.loads((ASSET/'pet.json').read_text())
old=json.loads((ROOT/'Resources/DefaultPet/pet.json').read_text())
joints=json.loads((REVIEW/'gait-joints.json').read_text())
strips=[Image.open(ASSET/name).convert('RGBA') for name in metadata['rowAtlasPaths']]
checks={};measurements={}


def check(name,value):checks[name]=bool(value)
def cel(row,column):return strips[row].crop((192*column,0,192*(column+1),208))
def digest(image):return hashlib.sha256(image.tobytes()).hexdigest()
def composite(image):
    canvas=Image.new('RGBA',image.size,(0,0,0,255));canvas.alpha_composite(image)
    return canvas.convert('RGB')
def components(image):
    w,h=image.size;data=bytearray(image.getchannel('A').point(lambda a:255 if a>80 else 0).tobytes());areas=[]
    for origin,value in enumerate(data):
        if not value:continue
        data[origin]=0;q=deque([origin]);area=0
        while q:
            index=q.popleft();area+=1;x,y=index%w,index//w
            for yy in range(max(0,y-1),min(h,y+2)):
                for xx in range(max(0,x-1),min(w,x+2)):
                    k=yy*w+xx
                    if data[k]:data[k]=0;q.append(k)
        areas.append(area)
    return sorted(areas,reverse=True)


counts=[16 if row in (9,10) else 20 for row in range(29)]
check('v5Has572FramesAnd29ActionStrips',metadata.get('spriteVersionNumber')==5
      and metadata.get('columns')==20 and metadata.get('rows')==29
      and metadata.get('frameCounts')==counts and sum(counts)==572)
check('allStripsAre3840By208RGBA',all(s.size==(3840,208) and s.mode=='RGBA' for s in strips))
check('allPathsAreUniqueBasenames',len(strips)==29 and len(set(metadata['rowAtlasPaths']))==29
      and all(Path(n).name==n and n.endswith('.png') for n in metadata['rowAtlasPaths']))
check('independentNameAndIdentity',metadata.get('displayName')=='玥2' and metadata.get('id')!=old.get('id'))
check('sameActionAndOnlineMappings',metadata.get('semanticRows')==old.get('semanticRows') and metadata.get('onlinePhoneRow')==8)
check('doubledFramesAndRatePreserveAllActionDurations',metadata.get('frameRate')==30
      and all(math.isclose(n/30,o/old['frameRate']) for n,o in zip(counts,old['frameCounts'])))
empty=[];clipped=[];minimum=[192,208,192,208];row_unique=[]
for r,count in enumerate(counts):
    row_unique.append(len({digest(cel(r,c)) for c in range(count)}))
    for c in range(count):
        bounds=cel(r,c).getchannel('A').getbbox()
        if not bounds:empty.append([r,c]);continue
        margins=[bounds[0],bounds[1],192-bounds[2],208-bounds[3]]
        minimum=[min(a,b) for a,b in zip(minimum,margins)]
        if min(margins)<2:clipped.append([r,c,margins])
check('all572FramesVisibleAndNotClipped',not empty and not clipped)
check('eightUnusedTurnCellsAreTransparent',all(cel(r,c).getchannel('A').getbbox() is None for r in (9,10) for c in range(16,20)))
check('leftRunIsExactMirrorForAll20Frames',all(digest(cel(2,i))==digest(ImageOps.mirror(cel(1,i))) for i in range(20)))
check('all20RunFramesHaveDifferentLegPoses',len({digest(cel(1,i).crop((0,125,192,208))) for i in range(20)})==20)
check('gaitNotRepeatedOldFrames',row_unique[1]>old['frameCounts'][1])
check('allTwentyJointRecordsFinite',len(joints)==20 and all(math.isfinite(float(v)) for j in joints for leg in ('near','far') for key in ('hip','knee','ankle') for v in j[leg][key]))
lengths={}
for leg in ('near','far'):
    for key,a,b in [('thigh','hip','knee'),('shin','knee','ankle')]:
        lengths[leg+'_'+key]=[math.dist(j[leg][a],j[leg][b]) for j in joints]
check('allFourBoneLengthsAreConstant',all(min(values)>15 and max(values)-min(values)<1e-8 for values in lengths.values()))
check('legsExchangePhasesAfterTenFrames',all(math.isclose(joints[i]['far'][key],joints[(i+10)%20]['near'][key],abs_tol=1e-8) for i in range(20) for key in ('angle','shinAngle')))
max_jump=max(abs(joints[(i+1)%20][leg][key]-joints[i][leg][key]) for i in range(20) for leg in ('near','far') for key in ('angle','shinAngle'))
check('continuousJointStepsStayBelow19DegreesIncludingLoop',max_jump<19)
check('singleUniformScaleAndLessThanTwoPixelBob',len({j['scale'] for j in joints})==1
      and max(j['offset'][1] for j in joints)-min(j['offset'][1] for j in joints)<=1.5)
areas=[components(cel(1,i)) for i in range(20)]
check('bodyAndLegsStayConnectedForAll20Frames',all(len([a for a in values if a>20])==1 and values[0]>3000 for values in areas))

# Remove only the recorded translation. Subpixel filtering can change edge
# samples, so compare mean raster error rather than demand false byte equality.
heads=[]
for i,j in enumerate(joints):
    dx=j['offset'][0]-joints[0]['offset'][0];dy=j['offset'][1]-joints[0]['offset'][1]
    aligned=cel(1,i).transform((192,208),Image.Transform.AFFINE,(1,0,dx,0,1,dy),Image.Resampling.BICUBIC)
    heads.append(composite(aligned).crop((16,4,156,115)))
head_errors=[sum(ImageStat.Stat(ImageChops.difference(heads[0],h)).mean)/3 for h in heads]
check('runHeadDoesNotShrinkOrWarp',max(head_errors)<2.5)

old_atlas=Image.open(ROOT/'Resources/DefaultPet/spritesheet.png').convert('RGBA')
old_frames=[old_atlas.crop((i*192,208,(i+1)*192,416)).crop((0,125,192,208)) for i in range(10)]
new_frames=[cel(1,i).crop((0,125,192,208)) for i in range(20)]
def mean_steps(frames):
    return sum(sum(ImageStat.Stat(ImageChops.difference(composite(f),composite(frames[(i+1)%len(frames)]))).mean)/3 for i,f in enumerate(frames))/len(frames)
old_step=mean_steps(old_frames);new_step=mean_steps(new_frames)
check('meanLegPixelStepReducedVersusOldTenFrames',new_step<old_step*.85)

passive=metadata.get('passiveAnimations',{})
check('idleAndPhoneKeepSlowBlinkSchedule',all(4<=passive.get(name,{}).get('intervalSeconds',0)<=8
      and not (set(passive[name]['restFrames'])&{7,8,9,10})
      and {7,8,9,10}<=set(passive[name]['blinkFrames'])
      and len(passive[name]['blinkFrames'])/30<.6 for name in ('idle','onlinePhone')))
phone_face_change=ImageStat.Stat(ImageChops.difference(composite(cel(8,0).crop((66,52,128,92))),composite(cel(8,8).crop((66,52,128,92))))).mean
check('phoneHasVisibleEyeBlink',sum(phone_face_change)>8)
check('edgePeekDirectionsAreExactMirrors',all(digest(cel(26,i))==digest(ImageOps.mirror(cel(25,i))) for i in range(20)))
turn_root_centers=[]
for row in (27,28):
    values=[]
    for i in range(20):
        bounds=cel(row,i).getchannel('A').point(lambda a:255 if a>80 else 0).crop((0,179,192,208)).getbbox()
        values.append((bounds[0]+bounds[2])/2 if bounds else -100)
    turn_root_centers.append(values)
check('turningShoeRootStaysAligned',all(max(v)-min(v)<=2 for v in turn_root_centers))
end_difference=ImageStat.Stat(ImageChops.difference(composite(cel(28,19)),composite(cel(26,0)))).mean
check('retractEndsOnSameProfileAsHeldPeek',max(end_difference)<.5)
total=sum((ASSET/n).stat().st_size for n in metadata['rowAtlasPaths'])+(ASSET/'pet.json').stat().st_size
check('compressedAssetsStayBelow32MiB',total<32*1024*1024)

measurements.update({'totalValidFrames':572,'oldValidFrames':sum(old['frameCounts']),
    'minimumTransparentMarginsLTRB':minimum,'clippedFrames':clipped,'uniqueFramesPerRow':row_unique,
    'boneLengths':lengths,'maximumJointStepDegrees':max_jump,'headMeanRasterErrors':head_errors,
    'oldMeanLegPixelStep':old_step,'newMeanLegPixelStep':new_step,'walkingComponentAreas':areas,
    'pngAndMetadataBytes':total,'oneStripDecodedPixelBytes':3840*208*4,
    'fullAtlasEquivalentPixelBytes':3840*6032*4,'turningShoeRootCenters':turn_root_centers})
report={'allPassed':all(checks.values()),'caseCount':len(checks),'passedCount':sum(checks.values()),
        'results':checks,'measurements':measurements,
        'inputs':{n:hashlib.sha256((ASSET/n).read_bytes()).hexdigest() for n in ['pet.json']+metadata['rowAtlasPaths']},
        'scope':'Delivered v5 animation strips and native geometry; not a phone or runtime importer test.'}
dest=ROOT/'Tests/yue2-animation-report.json';dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f"{dest.name}: {sum(checks.values())}/{len(checks)} passed")
for name,passed in checks.items():
    if not passed:print('FAIL:',name)
raise SystemExit(0 if report['allPassed'] else 1)
