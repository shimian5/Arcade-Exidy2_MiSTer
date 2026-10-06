#!/usr/bin/env python3
"""Replay the baseline public-port/T65-deadline contract on the RAM candidate."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    out=ROOT/'simulation/expansion_adapter/public10'; out.mkdir(parents=True,exist_ok=True)
    rtl=ROOT/'sim/expansion_adapter/exidy_expansion_loader_ram.sv'
    bench=ROOT/'sim/expansion_loader/tb_exidy_expansion_loader.sv'
    cases=[]
    for name,negative in (('positive',False),('negative-late-read',True)):
        source=bench
        if negative:
            text=bench.read_text()
            anchor='if (sampled_cpu_data == qpattern(8192)) $fatal(1, "deadline-negative case unexpectedly captured new byte");'
            assert text.count(anchor)==1
            source=out/'wrong_deadline.sv'
            source.write_text(text.replace(anchor,'if (sampled_cpu_data != qpattern(8192)) $fatal(1, "injected late-read expectation rejected");'))
        executable=out/name
        r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2',
            '--top-module','tb_exidy_expansion_loader','--Mdir',str(out/(name+'-obj')),
            str(rtl),str(source),'-o',str(executable)],capture_output=True,text=True)
        (out/(name+'-build.log')).write_text(r.stdout+r.stderr)
        if r.returncode: raise RuntimeError('public-port build failed')
        r=subprocess.run([str(executable)],capture_output=True,text=True,timeout=30)
        log=out/(name+'.log'); log.write_text(r.stdout+r.stderr)
        passed=(r.returncode!=0 and 'injected late-read expectation rejected' in r.stdout+r.stderr) if negative else r.returncode==0 and 'PASS:' in r.stdout
        cases.append(dict(case=name,exitCode=r.returncode,expectedFailure=negative,expectationMet=passed,log=str(log.relative_to(ROOT))))
    report=dict(schema='exidy2-expansion-public-read/v1',increment=10,cases=cases,
        sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (rtl,bench)},
        limits=['Baseline public-port fixture including provisional bank24 zero fill; no MAME bank24 parity claim.',
                '64-master-clock registered T65 sampling fixture, not a full CPU/board implementation.'])
    (ROOT/'docs/design/expansion-adapter/increment-10-public.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(cases))
    if not all(c['expectationMet'] for c in cases): raise RuntimeError('public-port regression failed')
if __name__=='__main__':main()
