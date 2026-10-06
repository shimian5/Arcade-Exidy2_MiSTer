#!/usr/bin/env python3
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser(); p.add_argument('--run-dir',type=Path,default=ROOT/'simulation/sprite_serialization/rtl'); a=p.parse_args()
    out=a.run_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    src=ROOT/'rtl/ttl_chips.v'; text=src.read_text()
    fragment=text[text.index('module oLS166 ('):text.index('endmodule',text.index('module oLS166 ('))+len('endmodule')]
    if 'negedge PE' not in fragment or 'shift_register[6:0], S' not in fragment: raise RuntimeError('source anchors changed')
    # Original attribution remains in the source; fragment retains exact text.
    copy=out/'oLS166.v'; copy.write_text(fragment+'\n')
    tb=ROOT/'sim/sprite_serialization/tb.sv'
    cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb','--Mdir',str(out/'obj'),str(copy),str(tb),'-o',str(out/'sprite')]
    r=subprocess.run(cmd,capture_output=True,text=True); (out/'build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise SystemExit(r.returncode)
    runs=[]
    for negative in (0,1):
        r=subprocess.run([str(out/'sprite'),f'+ROM={ROOT}/simulation/sprite_serialization/generated/gfx.hex',f'+NEGATIVE={negative}'],capture_output=True,text=True)
        (out/f'run{negative}.log').write_text(r.stdout+r.stderr); runs.append({'negative':bool(negative),'exitCode':r.returncode,'pass':('PASS checks=16384' in r.stdout) if not negative else r.returncode!=0 and 'DIVERGENCE' in r.stdout})
    if not all(r['pass'] for r in runs): raise RuntimeError(runs)
    report={'schema':'exidy2-sprite-serializer/v1','ttlSourceSha256':hashlib.sha256(src.read_bytes()).hexdigest(),'extractedFragmentSha256':hashlib.sha256(copy.read_bytes()).hexdigest(),'testbenchSha256':hashlib.sha256(tb.read_bytes()).hexdigest(),'runs':runs,'limits':['Exact source primitive plus explicit scheduling; actual control-PROM/ROM-latency gated-clock chain remains uninstantiated.','64 decoded images pass MSB-first bit ordering, not full game rendering or clipping.','TI synchronous load differs from existing source asynchronous PE edge; board-level remedy needs scheduling evidence.']}
    (ROOT/'docs/design/sprite-serialization/serializer-results.json').write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(runs))
if __name__=='__main__': main()
