#!/usr/bin/env python3
"""Qualify actual Exidy mixer/capture and equal-rate native transport against source-side RGB coordinates."""
import argparse, importlib.util, json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--mixer',type=Path,default=ROOT/'sys/video_mixer.sv');p.add_argument('--run-dir',type=Path,default=ROOT/'simulation/native_video_join');p.add_argument('--clock-phase-ps',type=int,default=333);p.add_argument('--expect-failure',action='store_true');a=p.parse_args()
 out=a.run_dir.resolve();out.mkdir(parents=True,exist_ok=True)
 spec=importlib.util.spec_from_file_location('capture',ROOT/'tools/video_capture/measure.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base);base.OUT=out;meta=base.create_fixture()
 files=[out/'source_video.sv',ROOT/'sys/arcade_video.v',a.mixer.resolve(),*[ROOT/'sys'/f for f in ('gamma_corr.sv','scandoubler.v','hq2x.sv','video_freezer.sv')],ROOT/'candidates/video/exidy_crt_capture.sv',ROOT/'candidates/video/exidy_native_bridge.sv',ROOT/'sim/native_video_join/tb.sv']
 cmd=['verilator','--binary','--timing','-Wno-fatal','-Wno-PROCASSWIRE','--top-module','tb','--Mdir',str(out/'obj'),*map(str,files),'-o',str(out/'queue')]
 r=subprocess.run(cmd,capture_output=True,text=True);(out/'build.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError('Compile failed: '+r.stderr[-1200:])
 runs=[]
 for phase in ([0] if a.expect_failure else range(8)):
  r=subprocess.run([str(out/'queue'),f'+PHASE={phase}',f'+CLOCK_PHASE_PS={a.clock_phase_ps}'],capture_output=True,text=True);(out/f'phase{phase}.log').write_text(r.stdout+r.stderr)
  if a.expect_failure:
   if r.returncode==0 or 'FIFO_MISMATCH' not in r.stdout:raise RuntimeError('Original-scope negative control did not expose RGB failure')
   print('PASS original-scope negative control rejected by independent RGB oracle');return
  m=re.search(r'RESULT ([^\n]+)',r.stdout)
  if r.returncode or not m:raise RuntimeError(r.stdout+r.stderr)
  rows={k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',m[1])};runs.append(rows);print('PASS',rows)
 r=subprocess.run([str(out/'queue'),'+PHASE=0','+CORRUPT=1',f'+CLOCK_PHASE_PS={a.clock_phase_ps}'],capture_output=True,text=True);(out/'negative.log').write_text(r.stdout+r.stderr)
 if r.returncode==0 or 'FIFO_MISMATCH' not in r.stdout:raise RuntimeError('Corrupt expected RGB was not rejected')
 (out/'results.json').write_text(json.dumps({'clockPhasePs':a.clock_phase_ps,'actualMixer':str(a.mixer),'mixerSha256':base.sha(a.mixer),'sourceSha256':{str(f.relative_to(ROOT)):base.sha(f) for f in files if f.is_relative_to(ROOT) and not f.is_relative_to(out)},'fixture':meta,'runs':runs,'negative':'wrong expected RGB rejected','limits':['Native source raster and synthetic RGB3 bitplanes only','Gamma path present but table disabled; FX0, freeze tied off at unconnected child input','No full game, runtime PLL/mode controller, OSD or physical display acceptance']},indent=2)+'\n')
 print('PASS wrong expected RGB negative control')
if __name__=='__main__':main()
