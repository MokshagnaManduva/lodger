#!/usr/bin/env python3
"""Author all Klien scenario frames from the approved native sprite, then package.

Generated pose studies guide the joints; native pixel layers keep identity stable.
No external generation is needed to rebuild. Runtime uses composited body/cane/emblem frames; all three layers remain editable.
The emblem is authored on the native pixel grid from the supplied sun reference.
"""
from pathlib import Path
import argparse
import copy
import html
import json
import math
import shutil
import tempfile
from PIL import Image, ImageDraw
from build import build
from packtool import Report, check_schema, check_references, check_idle_policy, check_anchors, check_reachability

REPO=Path(__file__).resolve().parents[2]
PACK=REPO/'Packs/klien'
OUT=PACK/'reference/all-scenarios-v1'
IDLE=PACK/'reference/idle-v2'
P=[]
for line in (PACK/'reference/palette.gpl').read_text().splitlines():
    f=line.split()
    if len(f)>=3 and all(s.isdigit() for s in f[:3]): P.append(tuple(map(int,f[:3]))+(255,))
REST=Image.open(IDLE/'art/rest.png').convert('RGBA')
CLOSED=Image.open(IDLE/'art/blink.png').convert('RGBA')
GOLD=[]
for line in (PACK/'reference/sun-emblem-palette.gpl').read_text().splitlines():
    fields=line.split()
    if len(fields)>=3 and all(x.isdigit() for x in fields[:3]):
        GOLD.append(tuple(map(int,fields[:3]))+(255,))
CLEAR=(0,0,0,0)
BG=(157,149,150)


def blank(): return Image.new('RGBA',(128,128))

def emblem_sprite(width=12):
    """12x14 native emblem: flared rays, tapered base and dark central sun seal.

    Reference: reference/sun-emblem.tiff. Width poses turn a rigid coin edge-on;
    height stays constant. The small gold ramp is separate from the body palette.
    """
    rows=("....0110....", "...013310...", "..01344310..", "013323323310",
          ".1342122431.", "013421124310", "134214412431", "013421124310",
          ".1342122431.", "..13322331..", "..01333310..", "...013310...",
          "....1331....", ".....11.....")
    sprite=Image.new('RGBA',(12,14))
    for y,row in enumerate(rows):
        for x,c in enumerate(row):
            if c!='.': sprite.putpixel((x,y),GOLD[int(c)])
    if width!=12:
        sprite=sprite.resize((width,14),Image.Resampling.NEAREST)
    return sprite


def assembled(body,cane,*,palm=(38,78),center=None,width=12,dy=0,legs=None):
    center=center or (palm[0],palm[1]-7)
    emblem=blank(); emblem.alpha_composite(emblem_sprite(width),(center[0]-width//2,center[1]-7))
    combined=body.copy(); combined.alpha_composite(cane); combined.alpha_composite(emblem)
    anchors={'hand':{'x':81,'y':93+dy},'emblem':{'x':center[0],'y':center[1]}}
    return combined,body,cane,anchors,emblem,{'palm':list(palm),'emblemCenter':list(center),'emblemWidth':width,'legs':legs}


def poly(im,points,color,outline=None):
    # Cloth may pool on the floor, but cannot extend beneath the ground boundary.
    ImageDraw.Draw(im).polygon([(x,min(y,119)) for x,y in points],fill=P[color],outline=P[outline] if outline is not None else None)

def limb(im,points,color=3,width=7):
    d=ImageDraw.Draw(im)
    d.line(points,fill=P[1],width=width+2,joint='curve')
    d.line(points,fill=P[color],width=width,joint='curve')

def shoe(im,x,y,near=True,compact=False):
    if compact:
        poly(im,[(x-3,y-3),(x+2,y-3),(x+3,y),(x-5,y),(x-5,y-1)],2 if near else 1,1)
        ImageDraw.Draw(im).line([(x-3,y-2),(x+1,y-2)],fill=P[3],width=1)
        return
    poly(im,[(x-5,y-3),(x+3,y-3),(x+5,y-1),(x+5,y),(x-6,y),(x-6,y-1)],2 if near else 1,1)
    ImageDraw.Draw(im).line([(x-4,y-2),(x+2,y-2)],fill=P[3],width=1)

def hand(im,x,y):
    poly(im,[(x-3,y-2),(x+2,y-2),(x+3,y),(x+1,y+3),(x-2,y+2)],24,1)
    ImageDraw.Draw(im).line([(x-1,y+1),(x+1,y+1)],fill=P[20])

def close_face(im,half=False):
    out=im.copy()
    # The open and closed canonical have identical registration.
    box=(47,63,70,70)
    if half: box=(47,63,70,67)
    out.paste(CLOSED.crop(box),box[:2])
    return out

def rig(*,dy=0,left=((54,95),(54,107),(54,119)),right=((63,95),(69,107),(71,119)),
        cape=0,arm='rest',eyes='open',cane_tip=(81,119),air=False,face_dx=0,
        palm_offset=0,emblem_center=None,emblem_width=12,reach_palm=(38,78),compact_legs=False):
    body=blank(); cane=blank()
    # Compress only knee/foot x coordinates toward the hip center. The head,
    # torso and cane retain their approved proportions. Maximum stride: 20px.
    def narrow(points):
        return (points[0],)+tuple((round(59+(x-59)*0.70),y) for x,y in points[1:])
    if not compact_legs:
        left,right=narrow(left),narrow(right)
    def cloth(points,color,outline=None):
        # Crouching coat tails stop above the soles; otherwise a lower breathing
        # pose spreads the cape across the floor and masquerades as a wide leg.
        floor=115 if compact_legs else 119
        poly(body,[(x,min(y,floor)) for x,y in points],color,outline)
    # Authored lower cape replaces the original legs' background; legs draw over it.
    if air:
        cloth([(45,88+dy),(33,68+dy),(43,75+dy),(50,83+dy),(68,83+dy),
                   (94,69+dy),(89,90+dy),(81,105+dy),(54,105+dy)],2,1)
        cloth([(75,89+dy),(90,75+dy),(84,97+dy),(75,102+dy)],5)
    else:
        cloth([(45,88+dy),(66,91+dy),(91+cape,98+dy),(80+cape,108+dy),
                   (68,105+dy),(58,108+dy),(47,108+dy),(44,105+dy)],2,1)
        cloth([(72,95+dy),(85+cape,99+dy),(78+cape,106+dy),(73,102+dy)],5)
        cloth([(47,96+dy),(51,99+dy),(53,107+dy),(47,105+dy)],3)
    # Bent joints are authored in cell coordinates, including explicit foot contact.
    limb(body,list(left[:-1])+[(left[-1][0],left[-1][1]-3)],color=2,width=5 if compact_legs else 7); shoe(body,*left[-1],near=False,compact=compact_legs)
    limb(body,list(right[:-1])+[(right[-1][0],right[-1][1]-3)],color=3,width=5 if compact_legs else 7); shoe(body,*right[-1],compact=compact_legs)
    poly(body,[(50,92+dy),(65,92+dy),(68,99+dy),(59,102+dy),(50,99+dy)],3,1)
    top=REST.copy()
    if eyes in ('closed','half'): top=close_face(top,eyes=='half')
    d=ImageDraw.Draw(top); d.rectangle((0,95,127,127),fill=CLEAR)
    # Remove shaft from the source, keep the palm/pommel in the body.
    d.rectangle((80,94,81,94),fill=CLEAR)
    if arm!='rest':
        d.polygon([(34,73),(43,73),(47,78),(54,79),(54,85),(45,88),(35,82)],fill=CLEAR)
    if eyes=='surprise':
        d.rectangle((57,74,59,76),fill=P[8]); d.point((58,74),fill=P[24])
    if face_dx:
        # Small eye glance only, rather than distorting the head during a turn.
        for box in [(48,65,53,70),(62,65,67,70)]:
            eye=top.crop(box); d.rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=P[24]); top.paste(eye,(box[0]+face_dx,box[1]))
    body.alpha_composite(top,(0,dy))
    if arm!='rest':
        # Restore the sleeve cap removed with the old outstretched arm.
        # Overlap the torso and new upper arm so every pose has a solid shoulder.
        poly(body,[(50,78+dy),(55,80+dy),(55,85+dy),(51,88+dy),
                   (47,85+dy),(47,81+dy)],3,1)
        ImageDraw.Draw(body).line([(50,80+dy),(53,82+dy),(53,85+dy)],fill=P[5],width=1)
    if arm=='lap':
        limb(body,[(51,83+dy),(44,91+dy),(49,96+dy)],3,5); hand(body,49,96+dy)
    elif arm=='brim':
        limb(body,[(51,83+dy),(38,74+dy),(41,53+dy)],3,5); hand(body,41,52+dy)
    elif arm=='chest':
        limb(body,[(51,83+dy),(43,89+dy),(45,85+dy)],3,5); hand(body,45,85+dy)
    elif arm=='raised':
        limb(body,[(51,83+dy),(42,79+dy),(38,71+dy)],3,5); hand(body,38,70+dy)
    elif arm=='reach':
        px,py=reach_palm
        limb(body,[(51,83+dy),(42,max(76,py)+dy),(px,py+dy)],3,5)
        hand(body,px,py+dy)
    elif arm=='toss':
        limb(body,[(51,83+dy),(44,83+dy),(38,78+dy+palm_offset)],3,5)
        hand(body,38,78+dy+palm_offset)
    # Cane is authored as its own pixel layer; the right palm is kept above it.
    cd=ImageDraw.Draw(cane)
    cd.line([(81,94+dy),cane_tip],fill=P[1],width=3)
    cd.line([(81,95+dy),(cane_tip[0],cane_tip[1]-1)],fill=P[12],width=1)
    palms={'rest':(38,78),'lap':(49,96),'brim':(41,52),
           'chest':(45,85),'raised':(38,70),'toss':(38,78+palm_offset),'reach':reach_palm}
    palm=palms[arm]; palm=(palm[0],palm[1]+dy)
    return assembled(body,cane,palm=palm,center=emblem_center,width=emblem_width,dy=dy,legs=[left,right])


def original(name):
    im=Image.open(IDLE/f'art/{name}.png').convert('RGBA')
    cane=blank(); cane.paste(im.crop((80,94,82,120)),(80,94))
    body=im.copy(); ImageDraw.Draw(body).rectangle((80,94,81,119),fill=CLEAR)
    return assembled(body,cane)


def poses_and_clips():
    frames={k:original(k) for k in ('rest','inhale','peak','blink')}
    def add(name,**kwargs): frames[name]=rig(**kwargs); return name
    # Six contact/pass poses: feet really step, while the approved head stays fixed.
    specs=[(((54,95),(50,107),(45,119)),((63,95),(67,107),(73,119))),
           (((54,95),(57,104),(60,114)),((63,95),(66,108),(68,119))),
           (((54,95),(60,106),(67,119)),((63,95),(58,108),(51,119))),
           (((54,95),(60,106),(70,119)),((63,95),(57,106),(48,119))),
           (((54,95),(55,108),(55,119)),((63,95),(60,103),(55,114))),
           (((54,95),(50,107),(47,119)),((63,95),(62,107),(67,119)))]
    for i,(l,r) in enumerate(specs): add(f'walk{i}',left=l,right=r,cape=[-1,0,1,1,0,-1][i],cane_tip=(81+[0,-2,-1,1,2,1][i],119 if i%3==0 else 117))
    for i in range(3):
        add(f'turn{i}',left=((54,95),(57+i,106),(59+i,119)),right=((63,95),(61-i,106),(66-i,119)),face_dx=-1 if i<2 else 1,cape=i-1)
    for i,palm in enumerate(((39,72),(40,65),(41,58))):
        add(f'tip_reach{i}',arm='reach',reach_palm=palm)
    for i,dy in enumerate((0,1,3,1)):
        add(f'tip{i}',dy=dy,arm='brim',eyes='closed' if i==2 else 'open',left=((54,95+dy),(54,107),(54,119)),right=((63,95+dy),(69,107),(71,119)))
    for i,dy in enumerate((-1,-2,0)):
        add(f'startle{i}',dy=dy,arm='chest',eyes='surprise',cape=i-1,left=((54,95+dy),(50,108),(53,119)),right=((63,95+dy),(72,108),(73,119)))
    for i in range(4):
        add(f'held{i}',dy=-3,arm='raised',eyes='surprise' if i==0 else 'open',cape=i%3-1,compact_legs=True,
            left=((54,92),(54,101),(54+[0,-1,0,1][i],111)),
            right=((63,92),(64,102),(64+[0,1,0,-1][i],114)),cane_tip=(83,114))
    for i in range(3):
        add(f'fall{i}',dy=-5,arm='raised',air=True,eyes='surprise',
            left=((54,90),(49,99),(54+i,105)),right=((63,90),(68,98),(65-i,108)),cane_tip=(84+i,111))
    for i,dy in enumerate((6,3,1)):
        add(f'land{i}',dy=dy,arm='chest' if i==0 else ('reach' if i==1 else 'rest'),reach_palm=(41,82),eyes='closed' if i==0 else 'open',
            compact_legs=True,left=((54,95+dy),(54,109),(54,119)),
            right=((63,95+dy),(64+i,109),(65+2*i,119)))
    for name,dy,eyes in [('sit',12,'open'),('sit_breath',11,'open'),('sit_blink',12,'closed'),
                         ('drowse',12,'half'),('sleep',13,'closed'),('sleep_breath',12,'closed'),
                         ('perch',12,'open'),('perch_blink',12,'closed')]:
        add(name,dy=dy,arm='lap',eyes=eyes,compact_legs=True,
            left=((54,95+dy),(54,112),(54,119)),right=((63,95+dy),(64,112),(65,119)))
    for i,dy in enumerate((9,6,3)):
        add(f'lower{i}',dy=dy,arm='reach',reach_palm=(38+dy,78+round(dy*1.5)),compact_legs=True,
            left=((54,95+dy),(54,108+dy//3),(54,119)),
            right=((63,95+dy),(66-dy//3,108+dy//3),(71-2*(dy//3),119)))
    add('watch',arm='rest',face_dx=-1)
    add('watch_blink',arm='rest',eyes='closed')
    # Toss uses the canonical lower body so entry/exit cannot pop into rig legs.
    toss_specs=[(2,(38,73),12),(-2,(37,64),8),(-3,(35,57),3),
                (-2,(33,53),8),(0,(32,51),12),(0,(32,51),8),
                (0,(33,53),3),(0,(35,57),8),(0,(37,64),12),(1,(38,72),12)]
    for i,(offset,center,width) in enumerate(toss_specs):
        posed=rig(arm='toss',palm_offset=offset)
        body=posed[1].copy(); body.paste(frames['rest'][1].crop((0,95,128,128)),(0,95))
        frames[f'toss{i}']=assembled(body,frames['rest'][2],palm=(38,78+offset),center=center,width=width)
    C={
      'idle':('forever',[('rest',400),('blink',120),('rest',380),('inhale',250),('peak',300),('inhale',250),('rest',1300)]),
      'toss_emblem':('none',[('rest',100)]+[(f'toss{i}',100) for i in range(10)]+[('rest',100)]),
      'walk':('forever',[(f'walk{i}',120) for i in range(6)]),
      'turn':('none',[('rest',80)]+[(f'turn{i}',100) for i in range(3)]+[('rest',100)]),
      'watch':('forever',[('watch',1200),('watch_blink',120),('watch',1680)]),
      'tip_hat':('none',[('rest',100)]+[(f'tip_reach{i}',80) for i in range(3)]+[(f'tip{i}',ms) for i,ms in enumerate((140,160,300,160))]+[(f'tip_reach{i}',80) for i in (2,1,0)]+[('rest',160)]),
      'startle':('none',[('startle0',80),('startle1',120),('startle2',160),('rest',140)]),
      'grabbed':('forever',[(f'held{i}',180) for i in range(4)]),
      'falling':('forever',[(f'fall{i}',140) for i in (0,1,2,1)]),
      'land':('none',[('land0',90),('land1',100),('land2',120),('rest',180)]),
      'sit_down':('none',[('rest',100),('lower2',120),('lower1',120),('lower0',120),('sit',200)]),
      'stand_up':('none',[('sit',140),('lower0',120),('lower1',120),('lower2',120),('rest',160)]),
      'sit':('forever',[('sit',1100),('sit_blink',120),('sit',480),('sit_breath',600),('sit',700)]),
      'perch':('forever',[('perch',1600),('perch_blink',120),('perch',1280)]),
      'sleep_in':('none',[('sit',300),('drowse',500),('sleep',600)]),
      'sleep':('forever',[('sleep',1800),('sleep_breath',1800)]),
      'wake':('none',[('sleep',200),('drowse',200),('sit',300),('lower0',120),('lower1',120),('lower2',120),('rest',200)]),
      'blink':('none',[('rest',60),('blink',120),('rest',60)]),
      'eyes_shut':('forever',[('blink',1500)])}
    return frames,C


def write_assets(frames,clips):
    for d in ('frames','layers/body','layers/cane','layers/emblem','art','previews','sheets','anchors'): (OUT/d).mkdir(parents=True,exist_ok=True)
    keys=list(frames); index={k:i for i,k in enumerate(keys)}
    body_strip=Image.new('RGBA',(128*len(keys),128)); cane_strip=body_strip.copy()
    for i,k in enumerate(keys):
        comp,body,cane,anchors,emblem,pose=frames[k]
        comp.save(OUT/f'frames/{k}.png'); body.save(OUT/f'layers/body/{k}.png'); cane.save(OUT/f'layers/cane/{k}.png')
        emblem.save(OUT/f'layers/emblem/{k}.png')
        body_strip.paste(comp,(128*i,0)); cane_strip.paste(cane,(128*i,0))
    body_strip.save(OUT/'art/body.png'); cane_strip.save(OUT/'art/cane.png')
    emblem_sprite().save(OUT/'art/sun_emblem.png')
    anchors={'anchors':{a:{str(i):frames[k][3][a] for i,k in enumerate(keys)} for a in ('hand','emblem')}}
    (OUT/'anchors/body.json').write_text(json.dumps(anchors,indent=2)+'\n')
    (OUT/'frames.json').write_text(json.dumps({'order':keys,'poses':{k:frames[k][5] for k in keys},'clips':{k:{'loop':mode,'frames':[{'name':n,'ms':ms} for n,ms in seq]} for k,(mode,seq) in clips.items()}},indent=2)+'\n')
    return index


def manifest(clips,index):
    blueprint=json.loads((PACK/'reference/planned-pack.json').read_text())
    m=copy.deepcopy(blueprint)
    # Owner preference: half the former 2x display size, retaining native pixels.
    m['stage']['defaultScale']=1
    m['identity']['version']='0.4.0'
    m['identity']['description']='Klien: a golden sun-emblem toss, compact walking, hat tips, reactions, sitting and sleep/wake animations.'
    m['requires']=['windowEdges']; m.pop('sounds',None)
    m['textures']={'body':{'strip':'art/body.png','preload':True},'cane':{'strip':'art/cane.png'}}
    m['clips']={name:{'texture':'body','loop':mode,'frames':[{'cell':index[n],'ms':ms} for n,ms in seq]} for name,(mode,seq) in clips.items()}
    # Deliberate hand travel: toss launch and seated lowering span up to 9px.
    for name in ('toss_emblem','sit_down','stand_up','wake'):
        m['clips'][name]['anchorJumpLimit']=10
    for name,seq in [('cane_hold',[('rest',3000)]),('cane_walk',clips['walk'][1])]:
        m['clips'][name]={'texture':'cane','loop':'forever','frames':[{'cell':index[n],'ms':ms} for n,ms in seq]}
    m['parts']=[{'name':'body','bind':{'mode':'body'}}]
    states=m['states']; states['watching']['clip']='watch'; states['perched']['clip']='perch'
    # Watching is entered on approach, before a click can arrive. It must retain
    # click/fast reactions, and distant cursor motion must not startle the pet.
    nearby={'pointerDistance':{'op':'lte','px':60}}
    for edge in states['idle']['interrupts']:
        if isinstance(edge['on'],dict) and 'pointer.fast' in edge['on']:
            edge['when']=copy.deepcopy(nearby)
    states['watching']['interrupts'] += [
        {'on':'pointer.click','state':'tipping_hat'},
        {'on':{'pointer.fast':1400},'state':'startled','when':copy.deepcopy(nearby)}]
    # Enter seated poses through an actual lowering transition rather than popping.
    states['sitting_down']={'clip':'sit_down','duration':'clip','next':[{'state':'sitting','weight':100}]}
    states['sleep_preparing']={'clip':'sit_down','duration':'clip','next':[{'state':'sleeping','weight':100}]}
    for st in states.values():
        for edge in st.get('next',[])+st.get('interrupts',[]):
            if edge['state']=='sitting': edge['state']='sitting_down'
            if edge['state']=='sleeping': edge['state']='sleep_preparing'
    states['sitting_down']['next'][0]['state']='sitting'
    states['sleep_preparing']['next'][0]['state']='sleeping'
    states['standing_up']={'clip':'stand_up','duration':'clip','next':[{'state':'idle','weight':100}]}
    # Already seated states need only close the eyes.
    for name in ('sitting','perched'):
        for edge in states[name].get('next',[])+states[name].get('interrupts',[]):
            if edge['state']=='sleep_preparing': edge['state']='sleeping'
            if edge['state'] in ('idle','walking','tipping_hat'): edge['state']='standing_up'
    # The existing engine owns facing and chooses the mirrored walk direction.
    if not any(e['on']=='system.wake' for e in states['asleep']['interrupts']):
        states['asleep']['interrupts'].append({'on':'system.wake','state':'waking'})
    for edge in states['idle']['next']:
        if edge['state']=='idle': edge['weight']=25
    states['idle']['next'].append({'state':'toss_emblem','weight':15})
    states['toss_emblem']={'clip':'toss_emblem','motion':'none','surface':'floor',
        'duration':'clip','next':[{'state':'idle','weight':100}],
        'interrupts':copy.deepcopy(states['idle']['interrupts'])}
    return m


def previews(frames,clips):
    for name,(mode,seq) in clips.items():
        composite=[frames[n][0].copy() for n,ms in seq]
        animated=composite; durations=[ms for n,ms in seq]
        for scale in (1,2):
            gif=[]
            for im in animated:
                bg=Image.new('RGB',(128,128),BG); bg.paste(im,mask=im.getchannel('A')); gif.append(bg.resize((128*scale,128*scale),Image.Resampling.NEAREST))
            gif[0].save(OUT/f'previews/{name}-{scale}x.gif',save_all=True,append_images=gif[1:],duration=durations,loop=0,disposal=2,optimize=False)
        sheet=Image.new('RGB',(min(6,len(seq))*264,math.ceil(len(seq)/6)*285),BG); d=ImageDraw.Draw(sheet)
        for i,(im,(n,ms)) in enumerate(zip(composite,seq)):
            x=i%6*264+4; y=i//6*285; z=im.resize((256,256),Image.Resampling.NEAREST); sheet.paste(z,(x,y),z)
            d.text((x,y+261),f'{i}: {n} / {ms}ms',fill=(29,26,34))
        sheet.save(OUT/f'sheets/{name}.png')
    # Match the engine's whole-rig reflection, including the held emblem.
    for direction in ('left','right'):
        for scale in (1,2):
            source=Image.open(OUT/f'previews/walk-{scale}x.gif')
            images=[]; timings=[]
            for i in range(source.n_frames):
                source.seek(i); frame=source.convert('RGB')
                images.append(frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if direction=='right' else frame)
                timings.append(source.info['duration'])
            images[0].save(OUT/f'previews/walk_{direction}-{scale}x.gif',save_all=True,append_images=images[1:],duration=timings,loop=0,disposal=2,optimize=False)
        sheet=Image.new('RGB',(6*264,285),BG); draw=ImageDraw.Draw(sheet)
        for i,(n,ms) in enumerate(clips['walk'][1]):
            frame=frames[n][0].copy()
            if direction=='right': frame=frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            frame=frame.resize((256,256),Image.Resampling.NEAREST)
            sheet.paste(frame,(i*264+4,0),frame)
            draw.text((i*264+4,261),f'{direction} {i} / {ms}ms',fill=(29,26,34))
        sheet.save(OUT/f'sheets/walk_{direction}.png')
    states=json.loads((OUT/'pack.json').read_text())['states']
    # Gallery is a review artifact, not an engine or user-facing product API.
    cards=[]
    for name,st in states.items():
        clip=st['clip']; cards.append(f'<article><h2>{html.escape(name)}</h2><img src="previews/{clip}-2x.gif" width="256" height="256"><p>{html.escape(clip)} · {sum(ms for _,ms in clips[clip][1])}ms · {clips[clip][0]}</p><a href="sheets/{clip}.png">Frame sheet</a></article>')
    for direction in ('left','right'):
        cards.append(f'<article><h2>Walking {direction}</h2><img src="previews/walk_{direction}-2x.gif" width="256" height="256"><p>720ms · forever</p><a href="sheets/walk_{direction}.png">Frame sheet</a></article>')
    page='''<!doctype html><meta charset="utf-8"><title>Klien — animation scenarios</title><style>body{font:16px system-ui;background:#ece8e2;color:#242127;margin:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(272px,1fr));gap:18px}article{background:#fff;padding:16px;border-radius:12px}h2{font-size:18px}img{image-rendering:pixelated;background:#9d9596}a{color:#514275}button{padding:8px 14px}</style><h1>Klien — all scenarios</h1><p>Native 128px frames · approved identity · 26 body colors + 5 gold colors. Finite actions repeat here for review; the toss occurs occasionally in the app.</p><p><button onclick="document.querySelectorAll('img').forEach(i=>{i.width=i.width===256?128:256;i.height=i.width})">Toggle native / 2×</button></p><main>'''+''.join(cards)+'</main>'
    (OUT/'gallery.html').write_text(page)
    # One glanceable all-scenario poster.
    chosen=[('idle','rest'),('walking','walk0'),('turning','turn1'),('watching','watch'),('hat tip','tip2'),('startled','startle1'),('held','held1'),('falling','fall1'),('landing','land0'),('sitting','sit'),('perched','perch'),('drowsing','drowse'),('asleep','sleep'),('waking','lower1'),('sun emblem toss','toss4')]
    poster=Image.new('RGB',(4*272,4*286),(229,225,220)); d=ImageDraw.Draw(poster)
    for i,(name,n) in enumerate(chosen):
        im=frames[n][0].copy(); x=i%4*272+8;y=i//4*286+8
        bg=Image.new('RGB',(128,128),BG);bg.paste(im,mask=im.getchannel('A'));poster.paste(bg.resize((256,256),Image.Resampling.NEAREST),(x,y));d.text((x,y+260),name,fill=(29,26,34))
    poster.save(OUT/'all-scenarios.png')
    poster.resize((544,572),Image.Resampling.NEAREST).save(OUT/'native-overview.png')
    # Attachment clips are reusable art too, even when the runtime body bakes cane.
    extras={
      'cane_hold':([frames['rest'][2]],[3000]),
      'cane_walk':([frames[n][2] for n,_ in clips['walk'][1]],[ms for _,ms in clips['walk'][1]])}
    for name,(ims,timings) in extras.items():
        for scale in (1,2):
            rendered=[]
            for im in ims:
                bg=Image.new('RGB',(128,128),BG);bg.paste(im,mask=im.getchannel('A'))
                rendered.append(bg.resize((128*scale,128*scale),Image.Resampling.NEAREST))
            rendered[0].save(OUT/f'previews/{name}-{scale}x.gif',save_all=True,append_images=rendered[1:],duration=timings,loop=0,disposal=2,optimize=False)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--install',action='store_true');args=ap.parse_args()
    frames,clips=poses_and_clips();index=write_assets(frames,clips);m=manifest(clips,index)
    (OUT/'pack.json').write_text(json.dumps(m,indent=2)+'\n')
    frames['rest'][0].save(OUT/'preview.png')
    previews(frames,clips)
    with tempfile.TemporaryDirectory(prefix='klien-scenarios-') as tmp:
        rep=Report();built=build(OUT,Path(tmp),rep,clean=False)
        if check_schema(built,rep):
            check_references(built,Path(tmp),rep);check_idle_policy(built,rep);check_anchors(built,rep);check_reachability(built,rep)
        if rep.emit('Klien scenarios'): raise SystemExit(1)
        if args.install:
            # The cane remains editable in source, but its animation is already
            # composited into the runtime body. Do not decode an unused duplicate
            # full-size atlas in the pet process.
            built['textures'].pop('cane')
            built['hitMasks'].pop('cane')
            for clip in ('cane_hold','cane_walk'): built['clips'].pop(clip)
            (Path(tmp)/'pack.json').write_text(json.dumps(built,indent=2)+'\n')
            for name in built['textures']:
                for relative in (built['textures'][name]['file'],built['hitMasks'][name]):
                    (PACK/relative).parent.mkdir(exist_ok=True,parents=True)
                    shutil.copy2(Path(tmp)/relative,PACK/relative)
            for file in ('pack.json','preview.png'): shutil.copy2(Path(tmp)/file,PACK/file)
            for unused in ('atlas/cane.png','masks/cane.mask','atlas/dumpling.png','masks/dumpling.mask',
                           'atlas/dumpling_squash.png','masks/dumpling_squash.mask'):
                (PACK/unused).unlink(missing_ok=True)
    print(f'{len(frames)} authored body poses, {len(clips)} body clips, {len(m["states"])} scenarios: {OUT}')

if __name__=='__main__': main()
