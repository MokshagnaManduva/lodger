#!/usr/bin/env python3
"""Sequential, visible release-binary soaks; never certifies whole-system energy.

Use --seconds 3600 for the documented hour-long CPU test. Shorter intervals are
diagnostics. No fixture is substituted: the original manifest and assets load.
"""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def command(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    return {'returncode': p.returncode, 'stdout': p.stdout.strip(), 'stderr': p.stderr.strip()}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(samples, seconds):
    summary = {}
    for state in sorted({s['state'] for s in samples}):
        rows = [s for s in samples if s['state'] == state]
        values = [s['metrics']['cpu_seconds_per_hour'] for s in rows]
        quiet = all(s['quiet_scheduling'] for s in rows)
        battery = all('Battery Power' in s[boundary]['stdout']
                      for s in rows for boundary in ['power_before', 'power_after'])
        untouched = all(s['metrics']['input_idle_seconds_end'] >= s['metrics']['elapsed_seconds']
                        for s in rows)
        visible = all(s['metrics']['visible_start'] and s['metrics']['visible_end'] for s in rows)
        summary[state] = dict(samples=len(rows), cpu_seconds_per_hour=values,
                              median=statistics.median(values), minimum=min(values), maximum=max(values),
                              quiet_scheduling=quiet, battery_at_boundaries=battery,
                              no_input_during_samples=untouched, visible_at_boundaries=visible,
                              max_peak_rss_mib=max(s['metrics']['peak_rss_bytes'] for s in rows)/2**20,
                              median_under_target=statistics.median(values) < 7,
                              hour_long_samples=seconds >= 3600)
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--pack', type=Path, default=ROOT/'Packs/Norn')
    ap.add_argument('--binary', type=Path, default=ROOT/'Engine/.build/release/lodger')
    ap.add_argument('--states', nargs='+', default=['idle', 'reading', 'asleep'])
    ap.add_argument('--seconds', type=int, default=3600)
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--warmup', type=int, default=15)
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    if a.seconds <= 0 or a.runs <= 0 or a.warmup < 0:
        ap.error('seconds/runs must be positive; warmup nonnegative')
    a.pack = a.pack.resolve(); a.binary = a.binary.resolve()
    manifest = json.loads((a.pack/'pack.json').read_text())
    for state in a.states:
        if state not in manifest['states'] or not manifest['states'][state].get('quiescent'):
            ap.error(f'{state} is not a declared quiescent state')
    a.out.mkdir(parents=True, exist_ok=False)
    assets = sorted({t['file'] for t in manifest['textures'].values()} | set(manifest.get('hitMasks', {}).values()))
    report = dict(schema=1, pack=manifest['identity'], binary=str(a.binary),
                  binary_sha256=digest(a.binary), manifest_sha256=digest(a.pack/'pack.json'),
                  asset_sha256={p: digest(a.pack/p) for p in assets},
                  os=command('sw_vers'), started_at=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                  seconds=a.seconds, warmup_seconds=a.warmup, runs=a.runs,
                  scope='visible CLI Pet host; full original pack; normal pointer/system subscriptions; default scale; excludes menu/settings host',
                  full_energy_certification=False,
                  unmeasured=['kernel wakeups', 'WindowServer A/B delta', 'package power A/B delta', 'Activity Monitor Energy Impact'],
                  samples=[], summary={})

    def save():
        report['summary'] = summarize(report['samples'], a.seconds)
        (a.out/'results.json').write_text(json.dumps(report, indent=2)+'\n')

    save()
    try:
        for run in range(1, a.runs+1):
            for state in a.states:
                label = f'{state}-{run}'
                print(f'START {label}: {a.warmup}s warmup + {a.seconds}s measurement', flush=True)
                before = command('pmset', '-g', 'batt')
                args = [str(a.binary), '--pack', str(a.pack), '--state', state,
                        '--warmup', str(a.warmup), '--soak', str(a.seconds)]
                # A temporary display-idle assertion, scoped to this child only.
                # No power setting is changed. Samples are sequential, never concurrent.
                with (a.out/f'{label}.log').open('w') as log:
                    child = subprocess.Popen(['/usr/bin/caffeinate', '-d', '-i', *args],
                                             stdout=log, stderr=subprocess.STDOUT)
                    try:
                        result = child.wait(timeout=a.seconds+a.warmup+90)
                    except BaseException:
                        child.terminate(); child.wait(timeout=10)
                        raise
                if result:
                    raise RuntimeError(f'{label} exited {result}; see its log')
                lines = (a.out/f'{label}.log').read_text().splitlines()
                m = json.loads(next(line.removeprefix('ENERGY_JSON ') for line in lines if line.startswith('ENERGY_JSON ')))
                zero = ['transitions', 'state_deadlines_scheduled', 'live_state_timers',
                        'display_link_starts', 'display_link_ticks', 'routing_refreshes',
                        'user_idle_deadlines', 'pointer_idle_deadlines']
                off = ['display_link_running', 'routing_timer', 'routing_display_link',
                       'user_idle_armed', 'pointer_idle_armed']
                quiet = (m['start_state'] == m['end_state'] == state
                         and all(m[k] == 0 for k in zero) and not any(m[k] for k in off))
                report['samples'].append(dict(state=state, run=run, metrics=m, quiet_scheduling=quiet,
                                               power_before=before, power_after=command('pmset', '-g', 'batt')))
                save()
                print(f'END {label}: {m["cpu_seconds_per_hour"]:.3f} CPU s/hour; quiet={quiet}; peak RSS {m["peak_rss_bytes"]/2**20:.1f} MiB', flush=True)
    except BaseException as e:
        report['error'] = str(e); save(); raise
    report['completed_at'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
    report['inputs_unchanged'] = (digest(a.binary) == report['binary_sha256']
                                  and digest(a.pack/'pack.json') == report['manifest_sha256']
                                  and all(digest(a.pack/p) == h for p, h in report['asset_sha256'].items()))
    save()
    print(json.dumps(report['summary'], indent=2), flush=True)


if __name__ == '__main__':
    main()
