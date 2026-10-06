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
    p.add_argument('--report',type=Path,default=ROOT/'docs/design/expansion-adapter/increment-15.json')
    a=p.parse_args(); out=a.run_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    pos=build_run(out,'safe',[]); neg=build_run(out,'unsafe',['-DUNSAFE'])
    # Bridge-level: derived loader with the speech-domain reset port.
    text=(SRC/'exidy_expansion_loader_ram.sv').read_text()
    for old,new in (('    input  logic        reset_n,\n','    input  logic        reset_n,\n    input  logic        cvsd_reset_n,\n'),
                    ('always_ff @(posedge cvsd_clk or negedge reset_n) begin\n        if (!reset_n) begin','always_ff @(posedge cvsd_clk or negedge cvsd_reset_n) begin\n        if (!cvsd_reset_n) begin')):
        assert text.count(old)==1, old; text=text.replace(old,new)
    (out/'exidy_expansion_loader_rr.sv').write_text(text)
    exe=out/'bridge-obj'/'bridge'
    r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_bridge_reset','--Mdir',str(out/'bridge-obj'),
        str(SRC/'exidy_reset_sync.sv'),str(SRC/'exidy_transport_adapter.sv'),str(SRC/'exidy_expansion_bridge_rr.sv'),
        str(out/'exidy_expansion_loader_rr.sv'),str(SRC/'tb_bridge_reset.sv'),'-o','bridge'],capture_output=True,text=True)
    (out/'bridge-build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError('bridge build failed')
    br=subprocess.run([str(exe)],capture_output=True,text=True,timeout=60).stdout
    (out/'bridge.log').write_text(br)
    # Negative control: speech-domain reset bypasses its synchronizer.
    bt=(SRC/'exidy_expansion_bridge_rr.sv').read_text()
    anchor='.reset_n(reset_n),.reset_n_sync(reset_n_cvsd));'
    assert bt.count(anchor)==1
    (out/'bridge_unsafe.sv').write_text(bt.replace(anchor,'.reset_n(reset_n),.reset_n_sync());').replace('wire reset_n_main, reset_n_cvsd;','wire reset_n_main; wire reset_n_cvsd = reset_n;'))
    r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_bridge_reset','--Mdir',str(out/'bridge-neg-obj'),
        str(SRC/'exidy_reset_sync.sv'),str(SRC/'exidy_transport_adapter.sv'),str(out/'bridge_unsafe.sv'),
        str(out/'exidy_expansion_loader_rr.sv'),str(SRC/'tb_bridge_reset.sv'),'-o','bridge'],capture_output=True,text=True)
    (out/'bridge-neg-build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError('bridge negative build failed')
    bn=subprocess.run([str(out/'bridge-neg-obj'/'bridge')],capture_output=True,text=True,timeout=60).stdout
    ver=subprocess.run(['verilator','--version'],capture_output=True,text=True).stdout.strip()
    cases=[dict(case='async-assert-sync-release-adversaries',expectationMet='PASS reset-release adversaries' in pos and 'FAIL' not in pos),
           dict(case='negative-unsynchronized-release',expectedFailure=True,
                expectationMet='FAIL' in neg and 'PASS' not in neg,failures=neg.count('FAIL'))]
    cases.append(dict(case='bridge-stopped-speech-clock-release',expectationMet='PASS bridge reset adversaries' in br and 'FAIL' not in br))
    cases.append(dict(case='negative-bridge-unsynchronized-speech-reset',expectedFailure=True,
                      expectationMet='FAIL' in bn and 'PASS' not in bn,failures=bn.count('FAIL')))
    rep=dict(schema='exidy2-reset-release-increment/v1',increment=15,accepted=False,verilator=ver,cases=cases,
        sha256={str(q.relative_to(ROOT)):sha(q) for q in (SRC/'exidy_reset_sync.sv',SRC/'tb_reset_release.sv',SRC/'tb_bridge_reset.sv',SRC/'exidy_expansion_bridge_rr.sv')},
        remaining=[
                   'Actual clocks/PLL lock-derived reset, CPU/audio wiring, QSF synchronizer assignments, whole-core fit.'])
    a.report.write_text(json.dumps(rep,indent=2)+'\n'); print(json.dumps(cases))
    if not all(c['expectationMet'] for c in cases): raise SystemExit(1)
if __name__=='__main__': main()
