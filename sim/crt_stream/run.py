#!/usr/bin/env python3
"""Bounded independent image/ownership tests for the unbound CRT candidate."""
from pathlib import Path
import subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'simulation/crt_stream';out.mkdir(parents=True,exist_ok=True)
 src=[ROOT/'candidates/video/exidy_crt_stream.sv',ROOT/'sim/crt_stream/tb_crt_stream.sv']
 cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_crt_stream','--Mdir',str(out/'obj'),*map(str,src),'-o',str(out/'test')]
 r=subprocess.run(cmd,capture_output=True,text=True);(out/'build.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stderr[-1600:])
 results=[]
 for name,args in [('nominal',[]),('damage',['+DAMAGE']),('pause',['+PAUSE']),('reset',['+RESET']),('stop',['+STOP']),('fast_fault',['+DRIFT_PPM=10000','+FAULT_ONLY']),('slow_fault',['+DRIFT_PPM=-10000','+FAULT_ONLY'])]:
  r=subprocess.run([str(out/'test'),'+FRAMES=12',*args],capture_output=True,text=True);(out/(name+'.log')).write_text(r.stdout+r.stderr)
  if r.returncode or 'PASS:' not in r.stdout:raise RuntimeError(name+' failed: '+r.stdout[-1700:]+r.stderr[-500:])
  result=[l for l in r.stdout.splitlines() if 'PASS:' in l];print(name,*result);results.append({'case':name,'args':args,'result':result})
 (out/'results.json').write_text(json.dumps({'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in src},'runs':results,'scope':'Synthetic normalized RGB24 raster. Actual Exidy post-mixer capture, PLL and top-level integration/hardware remain separate gates.'},indent=2)+'\n')
if __name__=='__main__':main()
