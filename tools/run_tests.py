#!/usr/bin/env python3
"""Run the self-contained tests added during the cloud work and report one PASS/FAIL/SKIP line each.
Test output and logs go to simulation/test-logs (ignored); nothing is printed or written elsewhere.
Needs Verilator (5.052 recommended; 5.020 mis-handles $finish in tasks), optionally GHDL.

  python3 tools/run_tests.py                 # fast tests
  python3 tools/run_tests.py --traces DIR    # also replay audio-RAM traces (seq_<game>.csv from tools/reference_cases/audio_ram_seq.lua)
  python3 tools/run_tests.py --slow          # also the GHDL 6840 pitch replay (needs --stim/--toggles inputs, see docs)
Exit status is 0 only if no test FAILs."""
import argparse, shutil, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
LOG = ROOT / 'simulation/test-logs'
results = []

def sh(cmd, name, timeout=900):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
    (LOG / (name + '.log')).write_text(r.stdout + r.stderr)
    return r

def verilate(name, top, files, defines=()):
    mdir = LOG / (name + '-obj')
    r = sh(['verilator', '--binary', '--timing', '-Wno-fatal', *defines, '--top-module', top, '--Mdir', str(mdir), *[str(ROOT / f) for f in files], '-o', 'sim'], name + '-build')
    return (mdir / 'sim') if r.returncode == 0 else None

def run_bin(exe, name, args=()):
    r = sh([str(exe), *args], name)
    return r.stdout

def record(name, status, note=''):
    results.append((name, status))
    print(f"{status:5} {name}" + (f"  ({note})" if note else ''))

def expect(name, text, ok_marker, fail_ok=False):
    passed = ok_marker in text and 'FAIL' not in text
    record(name, 'PASS' if (passed != fail_ok) else 'FAIL')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--traces', type=Path); ap.add_argument('--slow', action='store_true')
    a = ap.parse_args()
    LOG.mkdir(parents=True, exist_ok=True)
    if not shutil.which('verilator'): print('SKIP everything: verilator not found'); return 0
    ver = subprocess.run(['verilator', '--version'], capture_output=True, text=True).stdout.strip()
    if ' 5.05' not in ver and ' 5.1' not in ver: print(f'note: {ver}; 5.052 recommended')
    # audio mono mix (+ baseline-style mutant must fail)
    exe = verilate('audio_mix', 'tb_audio_mix', ['rtl/audio_mix.v', 'sim/audio_mix/tb_audio_mix.sv'])
    if exe: expect('audio mono mix', run_bin(exe, 'audio_mix'), 'PASS audio mix')
    else: record('audio mono mix', 'FAIL', 'build')
    # Audio-domain pause level synchronizer must protect both ready and mute.
    exe = verilate('pause_sync', 'tb_pause_sync', ['rtl/pause_sync.v', 'rtl/audio_mix.v', 'sim/pause_sync/tb_pause_sync.sv'])
    if exe: expect('audio pause synchronizer and mute/ready alignment', run_bin(exe, 'pause_sync'), 'PASS pause sync')
    else: record('audio pause synchronizer and mute/ready alignment', 'FAIL', 'build')
    mut = LOG / 'audio_mix_mutant.v'
    src = (ROOT / 'rtl/audio_mix.v').read_text()
    needle = "assign mono = mute ? 16'sd0 : sum;"
    if needle in src:
        mut.write_text(src.replace(needle, "assign mono = mute ? 16'sd0 : (src_a >>> 1);"))
        mdir = LOG / 'audio_mix_mut-obj'
        r = sh(['verilator', '--binary', '--timing', '-Wno-fatal', '--top-module', 'tb_audio_mix', '--Mdir', str(mdir), str(mut), str(ROOT / 'sim/audio_mix/tb_audio_mix.sv'), '-o', 'sim'], 'audio_mix_mut-build')
        if r.returncode == 0: expect('audio mono mix: mutant must fail', run_bin(mdir / 'sim', 'audio_mix_mut'), 'PASS audio mix', fail_ok=True)
    # interrupt cause profiles vs MAME formula
    exe = verilate('int_cause', 'tb_int_cause', ['rtl/int_cause.v', 'sim/int_cause/tb_int_cause.sv'])
    if exe: expect('interrupt cause profiles', run_bin(exe, 'int_cause'), 'PASS int cause')
    else: record('interrupt cause profiles', 'FAIL', 'build')
    # audio-domain reset synchronizer
    exe = verilate('reset_sync', 'tb_reset_sync', ['rtl/reset_sync.v', 'sim/reset_sync/tb_reset_sync.sv'])
    if exe: expect('audio reset synchronizer', run_bin(exe, 'reset_sync'), 'PASS reset sync')
    else: record('audio reset synchronizer', 'FAIL', 'build')
    # per-domain reset release (module, bridge, negative controls)
    r = sh([sys.executable, 'tools/expansion_adapter/reset_release.py', '--run-dir', str(LOG / 'reset_release'), '--report', str(LOG / 'reset_release.json')], 'reset_release')
    record('reset release (module, bridge, 2 negative controls)', 'PASS' if r.returncode == 0 else 'FAIL')
    # connected expansion suite
    if (ROOT.parent / 'Main_MiSTer/fpga_io.cpp').exists():
        roms = ROOT / 'simulation/expansion_adapter/rom-images'
        cmd = [sys.executable, 'tools/expansion_adapter/connected.py', '--reset-sync', '--run-dir', str(ROOT / 'simulation/expansion_adapter/test-run'), '--report', str(LOG / 'connected.json')]
        if roms.exists(): cmd += ['--rom-images', str(roms)]
        r = sh(cmd, 'connected', 1800)
        record('connected expansion suite' + (' incl. ROM cases' if roms.exists() else ' (no ROM images: 26 cases)'), 'PASS' if r.returncode == 0 else 'FAIL')
    else: record('connected expansion suite', 'SKIP', 'needs ../Main_MiSTer clone')
    # audio RAM mirror replay against MAME traces (+ flat map must fail on mtrap)
    if a.traces and a.traces.exists():
        exe = verilate('audio_ram', 'tb_audio_ram', ['rtl/audio_ram_map.v', 'sim/audio_ram/tb_audio_ram.sv'])
        flat = verilate('audio_ram_flat', 'tb_audio_ram', ['rtl/audio_ram_map.v', 'sim/audio_ram/tb_audio_ram.sv'], ['-DFLAT'])
        for g in ('venture', 'pepper2', 'mtrap'):
            t = a.traces / f'seq_{g}.csv'
            if not t.exists(): record(f'audio RAM mirror replay {g}', 'SKIP', 'trace missing'); continue
            if exe: expect(f'audio RAM mirror replay {g}', run_bin(exe, f'audio_ram_{g}', [f'+TRACE={t}']), 'PASS audio ram map')
            if flat and g == 'mtrap': expect('audio RAM flat map must fail on mtrap', run_bin(flat, 'audio_ram_flat_mtrap', [f'+TRACE={t}']), 'PASS audio ram map', fail_ok=True)
    else: record('audio RAM mirror replay', 'SKIP', 'pass --traces DIR with seq_<game>.csv')
    if a.slow: record('6840 pitch replay (GHDL)', 'SKIP', 'run manually per docs/audits/source/a3-a4-audio-effects.md (minutes per run)')
    bad = [n for n, s in results if s == 'FAIL']
    print(f"{len(results)} results: {sum(s=='PASS' for _, s in results)} PASS, {len(bad)} FAIL, {sum(s=='SKIP' for _, s in results)} SKIP")
    return 1 if bad else 0

if __name__ == '__main__': sys.exit(main())
