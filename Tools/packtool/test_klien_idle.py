#!/usr/bin/env python3
"""Integration checks over the actual shipped idle assets, not their builder."""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / 'Packs/klien'
p = json.loads((ROOT / 'pack.json').read_text())
assert p['stage']['defaultScale'] == 1
assert p['stage']['cell'] == {'w':128,'h':128}
assert p['stage']['ground'] == {'x':64,'y':120}
assert p['initialState'] == 'idle'
state = next(s for s in p['states'].values() if s.get('quiescent'))
assert state['quiescent'] and not any(k in state for k in ('next','duration','motion'))
assert not p.get('sounds') and p['requires'] == ['windowEdges']
clip = p['clips']['idle']
assert clip['loop'] == 'forever' and sum(f['ms'] for f in clip['frames']) == 3000
assert sum(f['cell']==3 for f in clip['frames']) == 1
assert next(f['ms'] for f in clip['frames'] if f['cell']==3) == 120
assert [f['cell'] for f in clip['frames'] if f['cell'] in (1,2)] == [1,2,1]
assert p['parts']==[{'name':'body','bind':{'mode':'body'}}]
assert set(p['textures'])=={'body'}, 'Unused attachment atlas shipped'
palette=set()
for line in ((ROOT/'reference/palette.gpl').read_text()+'\n'+(ROOT/'reference/sun-emblem-palette.gpl').read_text()).splitlines():
    f=line.split()
    if len(f)>=3 and all(s.isdigit() for s in f[:3]): palette.add(tuple(map(int,f[:3])))
images={}
for name, tex in p['textures'].items():
    image=Image.open(ROOT/tex['file']).convert('RGBA')
    assert image.size==(128*tex['columns'],128*tex['rows'])
    cells=[]
    for y in range(tex['rows']):
        for x in range(tex['columns']):
            a=np.array(image.crop((128*x,128*y,128*(x+1),128*(y+1))))
            assert set(np.unique(a[:,:,3])) <= {0,255}
            assert {tuple(c) for c in a[:,:,:3][a[:,:,3]>0]} <= palette
            assert not (a[0,:,3].any() or a[-1,:,3].any() or a[:,0,3].any() or a[:,-1,3].any())
            cells.append(a)
    images[name]=cells
rest, inhale, peak, blink=images['body'][:4]
for a in images['body'][:4]:
    assert Image.fromarray(a).getbbox()==(32,24,93,120)
    assert np.array_equal(a[110:],rest[110:]), 'feet drift'
    assert np.array_equal(a[91:120,80:82],rest[91:120,80:82]), 'cane drift'
    assert np.array_equal(a[:,:,3],rest[:,:,3]) or a is peak
for a in (inhale,peak):
    assert np.array_equal(a[:78],rest[:78]), 'head drift during breathing'
    assert not np.array_equal(a[80:90],rest[80:90]), 'no breathing deformation'
assert not np.array_equal(inhale,peak)
assert np.array_equal(blink[71:],rest[71:]), 'blink changes costume or mouth'
assert np.array_equal(blink[:63],rest[:63]), 'blink changes hat/hair'
# The archived idle artwork is retained separately from the active emblem pack.
assert Image.open(ROOT/'reference/idle-v2/approved-dumpling.png').getbbox()==(14,52,31,74)
# Decode the published hit masks independently and compare every alpha pixel.
for name, relative in p['hitMasks'].items():
    blob=iter((ROOT/relative).read_bytes())
    assert bytes(next(blob) for _ in range(5))==b'LMSK\x01'
    def varint():
        value=shift=0
        while True:
            byte=next(blob); value |= (byte&127)<<shift
            if byte<128: return value
            shift+=7
    assert (varint(),varint())==(128,128)
    count=varint()
    assert count <= len(images[name])
    assert all(not a[:,:,3].any() for a in images[name][count:])
    for a in images[name][:count]:
        flat=[]; solid=False
        for _ in range(varint()):
            flat.extend([solid]*varint()); solid=not solid
        assert np.array_equal(np.array(flat).reshape(128,128),a[:,:,3]>0)
    assert next(blob,None) is None
print('Klien idle: timing, held emblem, palette, alpha, planted contacts, fixed head and hit masks PASS')
