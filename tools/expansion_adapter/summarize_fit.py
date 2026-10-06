#!/usr/bin/env python3
"""Record completed isolated full-flow fit evidence with explicit timing limits."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser(); p.add_argument('--increment',type=int,default=10); a=p.parse_args()
    out=ROOT/f'simulation/expansion_adapter/fit{a.increment:02d}'
    log=out/'full-flow.log'; text=log.read_text()
    assert 'Quartus Prime Full Compilation was successful.' in text, 'full flow did not complete successfully'
    fit=out/'output_files/expansion_probe.fit.summary'
    timing=out/'output_files/expansion_probe.sta.summary'
    resources={line.split(':',1)[0].strip():line.split(':',1)[1].strip() for line in fit.read_text().splitlines() if ':' in line}
    assert resources['Fitter Status'].startswith('Successful'), 'fit summary is stale or unsuccessful'
    timing_rows=[dict(type=kind.strip(),slackNs=float(slack)) for kind,slack in re.findall(r'Type\s*:\s*([^\n]+)\nSlack\s*:\s*([-\d.]+)',timing.read_text())]
    report=dict(schema='exidy2-expansion-fit-result/v1',increment=a.increment,accepted=False,fullFlowCompleted=True,exitCode=0,
        resources=resources,timing=timing_rows,worstConstrainedSlackNs=min(row['slackNs'] for row in timing_rows),
        warnings=[line for line in text.splitlines() if line.startswith('Warning (')],
        reports={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (log,fit,timing)},
        limits=['Standalone bridge only; virtual data/control I/O have no board timing constraints.',
            '50MHz/10MHz abstract clocks and asynchronous groups; no physical CDC/reset signoff.',
            'Fitted expansion resources do not establish whole-core capacity, PLL/legal integration or game support.'])
    (ROOT/f'docs/design/expansion-adapter/increment-{a.increment:02d}-fit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:resources[k] for k in ('Logic utilization (in ALMs)','Total registers','Total block memory bits','Total RAM Blocks')}))
if __name__=='__main__':main()
