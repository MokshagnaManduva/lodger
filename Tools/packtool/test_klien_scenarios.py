#!/usr/bin/env python3
"""Acceptance checks for all scenario art and the runnable state graph."""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]/'Packs/klien'
SRC=ROOT/'reference/all-scenarios-v1'
p=json.loads((ROOT/'pack.json').read_text())
blueprint=json.loads((ROOT/'reference/planned-pack.json').read_text())
source=json.loads((SRC/'pack.json').read_text())
meta=json.loads((SRC/'frames.json').read_text())
assert set(blueprint['states']) <= set(p['states']), 'Missing scenario'
assert set(blueprint['clips'])-{'dumpling_idle','dumpling_squash'} <= set(source['clips']), 'Missing original art clip'
assert {'sitting_down','sleep_preparing','standing_up'} <= set(p['states'])
assert 'cane' not in p['textures'], 'Redundant composited cane atlas loaded at runtime'
assert all(s['clip'] in p['clips'] for s in p['states'].values())
assert p['states']['asleep']['quiescent']
assert not any(k in p['states']['asleep'] for k in ('next','duration','motion'))
assert p['states']['held']['motion']['type']=='drag'
assert p['states']['falling']['motion']['type']=='fall'
assert p['states']['walking']['motion']['type']=='walk'
assert p['states']['perched']['surface']=='windowTop'
assert p['requires']==['windowEdges'] and not p.get('sounds')
frames={name:np.array(Image.open(SRC/f'frames/{name}.png').convert('RGBA')) for name in meta['order']}
rest=frames['rest']
# Head identity stays fixed across every walk pose; feet actually change.
walk=[frames[f'walk{i}'] for i in range(6)]
assert all(np.array_equal(a[:74],rest[:74]) for a in walk)
assert len({a[100:].tobytes() for a in walk})==6
assert all(a[119,:,3].any() for a in walk)
# Airborne feet tuck up; landing compresses while preserving ground contact.
assert all(not frames[f'fall{i}'][115:,:,3].any() for i in range(3))
assert all(frames[f'land{i}'][119,:,3].any() for i in range(3))
assert all(not a[120:,:,3].any() for a in frames.values())
# Blink changes only the face, including in the separate watching pose.
for open_name,closed_name in [('sit','sit_blink'),('watch','watch_blink'),('perch','perch_blink')]:
    a,b=frames[open_name],frames[closed_name]
    assert np.array_equal(a[90:],b[90:]), f'{open_name} blink moves lower body'
for x0,x1 in ((41,53),(63,75)):
    assert np.array_equal(frames['sit'][119,x0:x1],frames['sleep'][119,x0:x1]), 'seated shoe contact drifts'
for name,a in frames.items():
    assert a.shape==(128,128,4)
    assert not (a[0,:,3].any() or a[-1,:,3].any() or a[:,0,3].any() or a[:,-1,3].any()),name
    body=Image.open(SRC/f'layers/body/{name}.png').convert('RGBA')
    body.alpha_composite(Image.open(SRC/f'layers/cane/{name}.png').convert('RGBA'))
    body.alpha_composite(Image.open(SRC/f'layers/emblem/{name}.png').convert('RGBA'))
    assert np.array_equal(np.array(body),a), f'Layer reassembly mismatch: {name}'
for name,c in meta['clips'].items():
    assert (SRC/f'sheets/{name}.png').exists()
    for scale in (1,2):
        gif=Image.open(SRC/f'previews/{name}-{scale}x.gif')
        assert gif.size==(128*scale,128*scale) and gif.info['loop']==0
        duration=0
        for i in range(gif.n_frames): gif.seek(i);duration+=gif.info['duration']
        assert duration==sum(f['ms'] for f in c['frames']),name
# No sitting-to-standing pop on normal timeout/click routes.
for edge in p['states']['sitting'].get('next',[])+p['states']['sitting'].get('interrupts',[]):
    assert edge['state'] not in ('idle','walking','tipping_hat')
print(f'Klien scenarios: {len(frames)} poses, {len(meta["clips"])} body clips, {len(p["states"])} states; coverage, contacts, identity, layer reassembly and GIF timings PASS')

# Toss is finite and occasional, and every interrupt resolves to a held-emblem pose.
toss=p['states']['toss_emblem']
assert toss['duration']=='clip' and toss['motion']=='none'
assert toss['next']==[{'state':'idle','weight':100}]
assert toss['interrupts']==p['states']['idle']['interrupts']
weights={e['state']:e['weight'] for e in p['states']['idle']['next']}
assert weights=={'idle':25,'walking':35,'tipping_hat':10,'sitting_down':15,'toss_emblem':15}
seq=meta['clips']['toss_emblem']['frames']
assert sum(f['ms'] for f in seq)==1200 and seq[0]['name']==seq[-1]['name']=='rest'
centers=[meta['poses'][f['name']]['emblemCenter'] for f in seq]
assert min(y for x,y in centers)==centers[0][1]-20
assert {meta['poses'][f['name']]['emblemWidth'] for f in seq}=={3,8,12}
for f in seq:
    assert np.array_equal(frames[f['name']][95:],rest[95:]), 'Toss changes planted legs/cane'
for name,pose in meta['poses'].items():
    if not name.startswith('toss'):
        x,y=pose['palm']; assert pose['emblemCenter']==[x,y-7], f'{name}: detached emblem'
    if pose['legs']:
        a,b=pose['legs']
        assert abs(a[-1][0]-b[-1][0])<=20, f'{name}: excessive stance width'
for edge in toss['interrupts']:
    first=p['clips'][p['states'][edge['state']]['clip']]['frames'][0]['cell']
    assert not meta['order'][first].startswith('toss')
# Both direction exports exactly mirror the complete rendered frames, timings included.
for scale in (1,2):
    left=Image.open(SRC/f'previews/walk_left-{scale}x.gif')
    right=Image.open(SRC/f'previews/walk_right-{scale}x.gif')
    assert left.n_frames==right.n_frames
    for i in range(left.n_frames):
        left.seek(i);right.seek(i)
        assert left.info['duration']==right.info['duration']
        assert np.array_equal(np.array(left.convert('RGB'))[:,::-1],np.array(right.convert('RGB')))
print('Sun emblem: toss arc, catch, interruption destinations, compact legs and mirrored walking PASS')

# A lowered body must not push its knees outside its supporting feet. Both soles
# stay identical during seated breathing/sleep; coat pixels cannot fake a foot.
seated=('sit','sit_breath','sit_blink','drowse','sleep','sleep_breath','perch','perch_blink')
for name in seated+('lower0','lower1','lower2','land0','land1','land2'):
    left,right=meta['poses'][name]['legs']
    assert left[-1][0] <= left[1][0] <= right[-1][0], name
    assert left[-1][0] <= right[1][0] <= right[-1][0], name
for name in seated:
    assert np.array_equal(frames[name][119,:75],frames['sit'][119,:75]), name
    assert not frames[name][119,:49,3].any(), f'{name}: coat/leg splays left'
    assert not frames[name][119,69:75,3].any(), f'{name}: leg splays right'
spreads=[abs(meta['poses'][n]['legs'][1][-1][0]-meta['poses'][n]['legs'][0][-1][0])
         for n in ('lower2','lower1','lower0','sit')]
assert spreads==sorted(spreads,reverse=True), 'Feet spread outward during lowering'
print('Crouch: knees within support, inward lowering and stable seated soles PASS')
