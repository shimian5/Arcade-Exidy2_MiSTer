#!/usr/bin/env python3
"""Reproducible isolated adapter and remote read-drain regressions."""
import argparse, hashlib, json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p = argparse.ArgumentParser()
    p.add_argument('--run-dir', type=Path, default=ROOT/'simulation/expansion_adapter/increment04')
    p.add_argument('--report', type=Path, default=ROOT/'docs/design/expansion-adapter/increment-04.json')
    a = p.parse_args(); out = a.run_dir.resolve(); out.mkdir(parents=True, exist_ok=True)
    hps = ROOT/'sys/hps_io.sv'; top = ROOT/'sys/sys_top.v'
    for anchor in ('ioctl_wr <= wr;', 'wr <= 0;', "addr <= addr + (WIDE ? 2'd2 : 2'd1);", 'assign HPS_BUS[37]   = ioctl_wait;'):
        if anchor not in hps.read_text(): raise RuntimeError('HPS anchor changed: '+anchor)
    rtl = ROOT/'sim/expansion_adapter/exidy_transport_adapter.sv'
    tb = ROOT/'sim/expansion_adapter/tb_review.sv'
    remote_tb = ROOT/'sim/expansion_adapter/tb_quarantine.sv'
    cases = []
    def build(name, source, bench, extra=()):
        executable = out/name
        r = subprocess.run(['verilator', '--binary', '--timing', '-Wno-fatal', '--top-module', bench.stem,
                            '--Mdir', str(out/(name+'-obj')), str(source), str(bench), '-o', str(executable), *extra], capture_output=True, text=True)
        (out/(name+'-build.log')).write_text(r.stdout+r.stderr)
        if r.returncode: raise RuntimeError('build failed: '+name)
        return executable
    def run(executable, case, name, token=None):
        r = subprocess.run([str(executable), f'+CASE={case}'], capture_output=True, text=True, timeout=30)
        log = out/(name+'.log'); log.write_text(r.stdout+r.stderr)
        passed = (r.returncode != 0 and token in r.stdout+r.stderr) if token else r.returncode == 0 and 'PASS' in r.stdout
        cases.append(dict(case=name, exitCode=r.returncode, expectedFailure=bool(token), expectationMet=passed, log=str(log.relative_to(ROOT))))
    executable = build('review', rtl, tb)
    for case, name in enumerate(('begin-index', 'skid-arrival', 'stale-ack', 'upper-index-rejection', 'blocked-skid-overflow')):
        run(executable, case, name)
    executable = build('quarantine', rtl, remote_tb)
    run(executable, 0, 'remote-stale-high')
    run(executable, 1, 'remote-outstanding-drain')
    run(executable, 2, 'abort-restart-pending-generation')
    run(executable, 3, 'shared-reset-stopped-clock')
    run(executable, 4, 'upper-address-fault-session')
    for latency in (1, 4):
        executable = build(f'latency{latency}', rtl, remote_tb, (f'-GREAD_LATENCY={latency}',))
        run(executable, 1, f'read-drain-latency{latency}')
    # Restore the old level-only authorization in an ignored copy. The same
    # stopped-clock test must detect the unsafe overwrite, not merely time out.
    mutant = out/'level_ack_mutant.sv'
    source = rtl.read_text()
    anchor = 'wire handshake_ready = ack_sync && (generation_sync == quarantine_generation);'
    assert source.count(anchor) == 1
    mutant.write_text(source.replace(anchor, 'wire handshake_ready = ack_sync;'))
    executable = build('negative', mutant, remote_tb)
    run(executable, 0, 'negative-level-only-ack', 'overwrite before remote drain')
    report = dict(schema='exidy2-expansion-adapter-increment/v1', increment=4, accepted=False, cases=cases,
                  sha256={str(p.relative_to(ROOT)):sha(p) for p in (hps, top, rtl, tb, remote_tb)},
                  resolved=['Fresh generation acknowledgement gates speech writes; start asserts wait immediately.',
                            'Unacknowledged generations are reused rather than toggled back after an aborted transfer.',
                            'Remote revocation blocks reads and drains the configured read pipe before echoing the generation.',
                            'Two complete 16KiB streams preserve exact data/address order under slow and stopped remote clocks.',
                            'Shared reset clears pending bytes with the remote clock stopped; abort/restart cannot cancel revocation.',
                            'Faulted sessions discard pending bytes, suppress later writes/restarts, and retain quarantine until reset.',
                            'Upper address rejection and read-drain latencies 1, 2 and 4 pass.'],
                  remaining=['Independent remote reset ownership/CDC timing remains a physical integration gate.',
                             'Actual HPS SPI/ACK model and connected baseline loader; upper address, descriptor/order/length/FAX2 matrix.',
                             'Physical CDC constraints/shared reset ownership, memory fit/timing and full-flow Quartus build.',
                             'FAX extra PROM routing and banks24..31 parity.'])
    a.report.parent.mkdir(parents=True, exist_ok=True); a.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(cases))
    if not all(x['expectationMet'] for x in cases): raise RuntimeError('regression failed; inspect logs')
if __name__ == '__main__': main()
