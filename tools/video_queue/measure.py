#!/usr/bin/env python3
"""Independent accepted-input FIFO versus actual video output; simulation only."""
import argparse, importlib.util, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--run-dir',type=Path,default=ROOT/'simulation/video_queue')
    p.add_argument('--report',type=Path,default=ROOT/'docs/design/video-queue/results.json')
    a=p.parse_args(); out=a.run_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    spec=importlib.util.spec_from_file_location('compat',ROOT/'tools/video_compat/measure.py')
    base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    base.OUT=out
    meta=base.create_fixture(); mixer,compat=base.compatibility_mixer()
    files=[out/'source_video.sv',ROOT/'sys/arcade_video.v',mixer,*[ROOT/'sys'/f for f in ('gamma_corr.sv','scandoubler.v','hq2x.sv','video_freezer.sv')],ROOT/'sim/video_queue/tb.sv']
    cmd=['verilator','--binary','--timing','-Wno-fatal','-Wno-PROCASSWIRE','--top-module','tb','--Mdir',str(out/'obj'),*map(str,files),'-o',str(out/'queue')]
    r=subprocess.run(cmd,capture_output=True,text=True); (out/'build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise SystemExit(r.returncode)
    runs=[]
    for phase in range(8):
        r=subprocess.run([str(out/'queue'),f'+PHASE={phase}'],capture_output=True,text=True)
        (out/f'phase{phase}.log').write_text(r.stdout+r.stderr)
        m=re.search(r'RESULT ([^\n]+)',r.stdout)
        if r.returncode or not m: raise RuntimeError(r.stdout+r.stderr)
        runs.append({'phase':phase,'metrics':{k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',m[1])},'log':str((out/f'phase{phase}.log').relative_to(ROOT))})
    r=subprocess.run([str(out/'queue'),'+PHASE=0','+CORRUPT=1'],capture_output=True,text=True)
    (out/'negative.log').write_text(r.stdout+r.stderr)
    negative={'exitCode':r.returncode,'detected':r.returncode!=0 and 'FIFO_MISMATCH' in r.stdout}
    if not negative['detected']: raise RuntimeError('wrong FIFO expectation was not rejected')
    result={'schema':'exidy2-independent-video-queue/v1','fixture':meta,'compatibility':compat,'testbenchSha256':base.sha(files[-1]),'runs':runs,'negative':negative,'limits':['Simulation-only mixer scope normalization; original framework unchanged.','Stimulus derives solely from accepted input raster events, never output.','Synthetic coordinate pattern, gamma disabled, FX0; no full game/receiver/CRT acceptance.','Output sampled after VGA update at CLK_VIDEO edge with pre-edge CE_PIXEL; downstream consumer registration is a separate integration gate.']}
    a.report.parent.mkdir(parents=True,exist_ok=True); a.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'runs':runs,'negative':negative},indent=2))
if __name__=='__main__': main()
