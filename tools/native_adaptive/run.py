#!/usr/bin/env python3
"""Test post-mixer packet capture and adaptive Native transport at actual FX cadences."""
from __future__ import annotations
import hashlib, importlib.util, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'simulation'/'native_adaptive'

def sha(path:Path)->str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main()->None:
    spec=importlib.util.spec_from_file_location('video_capture',ROOT/'tools'/'video_capture'/'measure.py')
    base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
    arcade_video=(ROOT/'sys'/'arcade_video.v').read_text()
    mixer=(ROOT/'sys'/'video_mixer.sv').read_text()
    scandoubler=(ROOT/'sys'/'scandoubler.v').read_text()
    guards=[
      (arcade_video,r'wire\s+scandoubler\s*=\s*fx\s*\|\|\s*forced_scandoubler','scandoubler mode selection'),
      (arcade_video,r'\.hq2x\(fx\s*==\s*1\)','HQ2x FX selection'),
      (mixer,r'CE_PIXEL\s*<=\s*scandoubler\s*\?\s*ce_pix_sd\s*:','mixer CE_PIXEL routing'),
      (scandoubler,r'assign\s+ce_pix_out\s*=\s*hq2x\s*\?\s*ce_x4o\s*:\s*ce_x2o','scandoubler/HQ2x output CE selection'),
    ]
    for text,pattern,label in guards:
        if not re.search(pattern,text):raise RuntimeError('Production-source guard failed: '+label)
    OUT.mkdir(parents=True,exist_ok=True);base.OUT=OUT
    fixture=base.create_fixture()
    generated=OUT/'source_video.sv'
    source=generated.read_text()
    source=source.replace('input wire [7:0] mod_shift, input wire [2:0] source_rgb3,',
                          'input wire [7:0] mod_shift, input wire [2:0] source_rgb3, input wire [2:0] fx, input wire forced_scandoubler,')
    source=source.replace(".fx(3'b000), .forced_scandoubler(1'b0)",'.fx(fx), .forced_scandoubler(forced_scandoubler)')
    if 'input wire [2:0] fx' not in source or '.fx(fx), .forced_scandoubler(forced_scandoubler)' not in source:
        raise RuntimeError('Could not expose actual arcade_video FX inputs in extracted wrapper')
    generated.write_text(source)
    fixture['fixtureHashes']['generatedExtractedRtl']=sha(generated)
    fixture['videoConfiguration']['scandoubler']='Actual runtime FX0 native, FX2 ordinary scandoubler, forced_scandoubler FX0, and FX1 HQ2x cases; cadence changes while shared reset is held.'
    files=[generated,ROOT/'sys'/'arcade_video.v',ROOT/'sys'/'video_mixer.sv',
           ROOT/'sys'/'gamma_corr.sv',ROOT/'sys'/'scandoubler.v',ROOT/'sys'/'hq2x.sv',
           ROOT/'sys'/'video_freezer.sv',ROOT/'candidates'/'video'/'exidy_native_capture.sv',
           ROOT/'candidates'/'video'/'exidy_native_bridge_adaptive.sv',
           ROOT/'sim'/'video'/'tb_exidy_native_adaptive.sv']
    run=OUT/'run';run.mkdir(parents=True,exist_ok=True)
    cmd=['verilator','--binary','--timing','-Wno-fatal','-Wno-PROCASSWIRE','--top-module','tb_exidy_native_adaptive',
         '--Mdir',str(run/'obj'),*map(str,files),'-o',str(run/'native_adaptive')]
    build=subprocess.run(cmd,text=True,capture_output=True)
    (run/'build.log').write_text(build.stdout+build.stderr)
    if build.returncode:raise RuntimeError('Verilator compile failed; see '+str(run/'build.log'))
    phases=[0,333,1000,1666]
    phase_runs={}
    for phase in phases:
        args=[str(run/'native_adaptive'),f'+CLOCK_PHASE_PS={phase}']
        if phase==0:args.append('+FULL_FRAMES=1')
        sim=subprocess.run(args,text=True,capture_output=True)
        log=run/f'simulation-phase{phase}ps.log'
        log.write_text(sim.stdout+'\n--- stderr ---\n'+sim.stderr)
        if sim.returncode:raise RuntimeError('Simulation failed; see '+str(log)+'\n'+sim.stdout[-1200:])
        if f'RUN output phase_ps={phase}' not in sim.stdout or 'PASS native FX=0' not in sim.stdout or 'PASS native FX=2' not in sim.stdout or 'PASS native FX=1' not in sim.stdout or 'PASS negative control:' not in sim.stdout:
            raise RuntimeError(f'Expected mode/negative-control/phase PASS markers are missing for {phase} ps')
        phase_runs[str(phase)]={'log':f'simulation/native_adaptive/run/{log.name}','result':sim.stdout.strip()}
    digest_files=[ROOT/'rtl'/'Exidy2.v',ROOT/'Arcade-Exidy2.sv',ROOT/'sys'/'arcade_video.v',ROOT/'sys'/'video_mixer.sv',
      ROOT/'sys'/'scandoubler.v',ROOT/'sys'/'hq2x.sv',ROOT/'sys'/'gamma_corr.sv',ROOT/'sys'/'video_freezer.sv',
      ROOT/'tools'/'video_capture'/'measure.py',
      ROOT/'candidates'/'video'/'exidy_native_capture.sv',ROOT/'candidates'/'video'/'exidy_native_bridge_adaptive.sv',
      ROOT/'sim'/'video'/'tb_exidy_native_adaptive.sv',generated]
    audit={'purpose':'Actual arcade_video/video_mixer output cadence and transport qualification; not HQ2x image-math parity.',
      'fxCases':{'0':'native /8 clocks per CE_PIXEL','2':'ordinary scandoubler /4','forcedScandoubler':'FX0 with forced_scandoubler=1 /4','1':'HQ2x /2'},
      'captureContract':'One-cycle delayed CE_PIXEL samples settled post-mixer RGB/DE/HS/VS; independent testbench queue uses the same accepted CE history but stores expected packets outside the bridge.',
      'modeChangeContract':'FX cadence changes only while shared asynchronous reset is held; this resets both packet FIFO pointers and dividers.',
      'productionSourceGuards':['arcade_video selects scandoubler when FX or forced_scandoubler is set','HQ2x is FX1','video_mixer routes CE_PIXEL through the selected scandoubler CE','scandoubler routes ce_x2o except HQ2x ce_x4o'],
      'negativeControl':'FX0 source /8 with deliberately selected /4 output cadence outruns the queue and must assert the bridge underflow fault.',
      'phaseSweepPs':phases,
      'fullFrameRun':'Nominal 0 ps phase runs until source and destination have each transported at least two VS rising edges in native, ordinary SD, forced SD, and HQ2x; reset is asserted during DE before each cadence change.',
      'limitations':['Synthetic source raster/RGB only; no complete game renderer, OSD, gamma writes, CRT path or board PLL.','Transport qualification only; no parity claim for HQ2x image math.','Two full VS edges are checked for each FX/cadence case only at nominal phase; nonzero phase sweep runs remain bounded windows.','Coordinates are deliberately zero; frame pulse follows sampled VS rising edge.','No clock-ratio drift sweep; parent owns that test.'],
      'sha256':{str(p.relative_to(ROOT)):sha(p) for p in digest_files},
      'fixtureMetadata':fixture,'verilator':subprocess.run(['verilator','--version'],check=True,capture_output=True,text=True).stdout.strip(),
      'phaseRuns':phase_runs}
    (run/'source-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
    for result in phase_runs.values(): print(result['result'])
    print('Source audit and logs:',run)

if __name__=='__main__':main()
