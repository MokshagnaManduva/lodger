#!/usr/bin/env python3
"""Prepare isolated art-review/idle fixtures and optionally measure three idle runs.

Fixtures change scheduling only; they use the actual runtime atlas/mask bytes.
Use the showcase to review every state without manufacturing mouse/physics events.
"""
from pathlib import Path
import argparse
import copy
import json
import re
import shutil
import statistics
import subprocess

REPO=Path(__file__).resolve().parents[2]
PACK=REPO/'Packs/klien'
OUT=REPO/'build/klien-verification'
BIN=REPO/'build/Lodger.app/Contents/MacOS/Lodger'


def fixture(name,manifest):
    root=OUT/name;root.mkdir(parents=True,exist_ok=True)
    for rel in [t['file'] for t in manifest['textures'].values()]+list(manifest['hitMasks'].values()):
        dst=root/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(PACK/rel,dst)
    (root/'pack.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return root


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--measure',action='store_true');ap.add_argument('--showcase',action='store_true');ap.add_argument('--behavior',action='store_true');a=ap.parse_args()
    manifest=json.loads((PACK/'pack.json').read_text());OUT.mkdir(parents=True,exist_ok=True)
    if a.behavior:
        engine=REPO/'Engine/Sources/LodgerEngine'
        binary=OUT/'test-director'
        subprocess.run(['swiftc','-O',*[str(engine/f'{n}.swift') for n in ('Pack','Guard','Director')],
            str(REPO/'Tools/packtool/test_klien_director.swift'),'-o',str(binary)],check=True)
        subprocess.run([str(binary),str(PACK/'pack.json')],check=True)
    # PackStore load/clip lookup for every active state; separate from visual review.
    for state in manifest['states']:
        p=subprocess.run([str(BIN),'--pack',str(PACK),'--state',state,'--headless'],capture_output=True,text=True,check=True)
        assert f'state    : {state}' in p.stdout
    print(f'{len(manifest["states"])} runtime state/clip lookups passed',flush=True)
    idle=copy.deepcopy(manifest)
    idle['states']={'idle':{'clip':'idle','quiescent':True,'interrupts':[{'on':'system.wake','state':'idle'}]}}
    idle['parts']=[p for p in idle['parts'] if p['bind']['mode']!='overlay']
    for part in idle['parts']:part.pop('hiddenIn',None)
    idle_path=fixture('idle',idle)
    showcase=copy.deepcopy(manifest);names=list(showcase['states']);total=0
    for i,name in enumerate(names):
        clip=showcase['states'][name]['clip'];ms=sum(f.get('ms',250) for f in showcase['clips'][clip]['frames'])
        hold=max(ms,1800);total+=hold
        showcase['clips'][clip]['loop']='forever'
        showcase['states'][name]={'clip':clip,'duration':{'minMs':hold,'maxMs':hold},'next':[{'state':names[(i+1)%len(names)],'weight':100}]}
    show_path=fixture('showcase',showcase)
    (OUT/'showcase-timing.json').write_text(json.dumps({'duration_ms':total,'states':names},indent=2)+'\n')
    if a.showcase:
        with (OUT/'showcase.log').open('w') as log:
            subprocess.run([str(BIN),'--pack',str(show_path),'--soak',str(total/1000+10)],stdout=log,stderr=subprocess.STDOUT,check=True)
        playback=(OUT/'showcase.log').read_text()
        for name in names:
            assert re.search(r'^  '+re.escape(name)+r'\s',playback,re.M), f'Showcase missed {name}'
        assert len(re.findall(r'^  idle\s',playback,re.M))>=2, 'Showcase did not finish a complete loop'
        assert 'starts=0 ticks=0 running=false' in playback
        print(f'Showcase completed all {len(names)} states and returned to idle; zero display-link ticks',flush=True)
    if a.measure:
        readings=[]
        for i in range(3):
            result=subprocess.run([str(BIN),'--pack',str(idle_path),'--soak','60'],capture_output=True,text=True,check=True)
            (OUT/f'idle-{i+1}.log').write_text(result.stdout+result.stderr)
            cpu=float(re.search(r'projected:\s+([\d.]+)',result.stdout)[1]);readings.append(cpu)
            assert 'scheduler wakes: 0' in result.stdout
            assert 'starts=0 ticks=0 running=false' in result.stdout
            print(f'Idle run {i+1}: {cpu:.2f} CPU seconds/hour; zero scheduler wakes and display-link ticks',flush=True)
        report={'target_cpu_seconds_per_idle_hour':7,'runs':readings,'median':statistics.median(readings),'passes_target':statistics.median(readings)<7,'scheduler_wakes':0,'display_link_ticks':0,'method':'Three sequential requested 60s process-CPU soaks; actual shipped art, state scheduling isolated to quiescent idle.'}
        (OUT/'energy.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)

if __name__=='__main__':main()
