#!/usr/bin/env python3
"""Replay per-domain reset-release adversaries plus an unsafe-release negative control."""
import argparse, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'sim/expansion_adapter'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def build_run(out,name,defines):
    exe=out/name
    r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_reset_release',
        '--Mdir',str(out/(name+'-obj')),*defines,str(SRC/'exidy_reset_sync.sv'),str(SRC/'tb_reset_release.sv'),'-o',name],
        capture_output=True,text=True)
    (out/(name+'-build.log')).write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError(name+' build failed')
    r=subprocess.run([str(out/(name+'-obj')/name)],capture_output=True,text=True,timeout=60)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    return r.stdout
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--run-dir',type=Path,default=ROOT/'simulation/expansion_adapter/reset_release')
    p.add_argument('--report',type=Path,default=ROOT/'docs/design/expansion-adapter/increment-13.json')
    a=p.parse_args(); out=a.run_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    pos=build_run(out,'safe',[]); neg=build_run(out,'unsafe',['-DUNSAFE'])
    ver=subprocess.run(['verilator','--version'],capture_output=True,text=True).stdout.strip()
    cases=[dict(case='async-assert-sync-release-adversaries',expectationMet='PASS reset-release adversaries' in pos and 'FAIL' not in pos),
           dict(case='negative-unsynchronized-release',expectedFailure=True,
                expectationMet='FAIL' in neg and 'PASS' not in neg,failures=neg.count('FAIL'))]
    rep=dict(schema='exidy2-reset-release-increment/v1',increment=13,accepted=False,verilator=ver,cases=cases,
        sha256={str(q.relative_to(ROOT)):sha(q) for q in (SRC/'exidy_reset_sync.sv',SRC/'tb_reset_release.sv')},
        remaining=['Module not yet instantiated in the bridge; bridge/loader/adapter rely on raw reset_n.',
                   'Actual clocks/PLL lock-derived reset, CPU/audio wiring, QSF synchronizer assignments, whole-core fit.'])
    a.report.write_text(json.dumps(rep,indent=2)+'\n'); print(json.dumps(cases))
    if not all(c['expectationMet'] for c in cases): raise SystemExit(1)
if __name__=='__main__': main()
