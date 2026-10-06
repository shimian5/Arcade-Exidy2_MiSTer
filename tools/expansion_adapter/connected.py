#!/usr/bin/env python3
"""Extract unchanged file decoder/GPIO ACK logic and exercise a connected loader."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def extract(out):
    hps=ROOT/'sys/hps_io.sv'; top=ROOT/'sys/sys_top.v'
    fio=hps.read_text().split('localparam FIO_FILE_TX      =',1)[1].split('\nendmodule',1)[0]
    fio='localparam FIO_FILE_TX      ='+fio
    wrapper='''`timescale 1ns/1ps
module source_fio(input clk_sys, input io_strobe, input fp_enable,
 input [15:0] io_din, output reg ioctl_download=0,
 output reg [15:0] ioctl_index=0, output reg ioctl_wr=0,
 output reg [26:0] ioctl_addr=0, output reg [7:0] ioctl_dout=0);
 localparam WIDE=0, DW=7;
 reg ioctl_rd=0, ioctl_upload=0;
 reg [31:0] ioctl_file_ext=0;
 wire [7:0] ioctl_din=0;
'''+fio+'\nendmodule\n'
    # Bodies retain original nonblocking assignments and conditions exactly.
    source=top.read_text()
    ack=re.search(r'always @\(posedge clk_sys\) begin\s*if\(~\(io_wait \| vs_wait\) \| io_strobe\).*?\nend',source,re.S).group(0)
    gpio=re.search(r'reg \[31:0\] gp_outr;\s*always @\(posedge clk_sys\) begin.*?\nend',source,re.S).group(0)
    wrapper+='''module source_ack(input clk_sys, input [31:0] gp_out, input io_wait,
 output reg io_ack=0, output io_strobe, output [15:0] io_din, output fp_enable);
 reg rack=0;
 wire vs_wait=0;
 wire io_clk=gp_outr[17];
 assign io_strobe=~rack & io_clk;
 assign io_din=gp_outr[15:0];
 assign fp_enable=gp_outr[18];
'''+ack+'\n'+gpio+'\nendmodule\n'
    result=out/'source_transport.sv'; result.write_text(wrapper)
    return result
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--run-dir',type=Path)
    p.add_argument('--report',type=Path)
    p.add_argument('--rom-images',type=Path,help='Verified ignored ROM fixture directory; select ROM-backed suite.')
    p.add_argument('--ram-loader',action='store_true',help='Use the separate registered-RAM candidate.')
    p.add_argument('--reset-sync',action='store_true',help='Increment 14: per-domain synchronized reset release (implies --ram-loader).')
    a=p.parse_args(); a.ram_loader=a.ram_loader or a.reset_sync
    increment=14 if a.reset_sync else 12 if a.ram_loader else 8
    a.run_dir=a.run_dir or ROOT/f'simulation/expansion_adapter/increment{increment:02d}'
    a.report=a.report or ROOT/f'docs/design/expansion-adapter/increment-{increment:02d}.json'
    out=a.run_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    generated=extract(out)
    rtl=ROOT/'sim/expansion_adapter/exidy_transport_adapter.sv'
    bridge=ROOT/'sim/expansion_adapter/exidy_expansion_bridge.sv'
    baseline_copy=ROOT/'sim/expansion_adapter/exidy_expansion_loader_baseline.sv'
    loader=ROOT/'sim/expansion_adapter'/('exidy_expansion_loader_ram.sv' if a.ram_loader else 'exidy_expansion_loader_baseline.sv')
    baseline=ROOT/'sim/expansion_loader/exidy_expansion_loader.sv'
    assert sha(baseline_copy)==sha(baseline), 'baseline copy changed'
    bench=ROOT/'sim/expansion_adapter/tb_connected.sv'
    extra=[]
    if a.reset_sync:
        # Derived copies: speech-domain reset port on the loader, rr bridge name in the bench.
        text=loader.read_text()
        for old,new in (('    input  logic        reset_n,\n','    input  logic        reset_n,\n    input  logic        cvsd_reset_n,\n'),
                        ('always_ff @(posedge cvsd_clk or negedge reset_n) begin\n        if (!reset_n) begin','always_ff @(posedge cvsd_clk or negedge cvsd_reset_n) begin\n        if (!cvsd_reset_n) begin')):
            assert text.count(old)==1, old; text=text.replace(old,new)
        loader=out/'exidy_expansion_loader_rr.sv'; loader.write_text(text)
        bridge=ROOT/'sim/expansion_adapter/exidy_expansion_bridge_rr.sv'
        text=bench.read_text(); assert text.count('exidy_expansion_bridge bridge')==1
        bench=out/'tb_connected_rr.sv'; bench.write_text(text.replace('exidy_expansion_bridge bridge','exidy_expansion_bridge_rr bridge'))
        extra=[str(ROOT/'sim/expansion_adapter/exidy_reset_sync.sv')]
    main_repo=ROOT.parent/'Main_MiSTer'
    host_sources=[main_repo/p for p in ('fpga_io.cpp','spi.h','spi.cpp','user_io.cpp')]
    # Ordinary ROM download uses spi_write -> spi_b/spi_w -> fpga_spi,
    # whose high-then-low ACK polling is represented by the bench host.
    assert 'return (uint8_t)fpga_spi(parm);' in host_sources[1].read_text()
    assert 'spi_write(addr, len, fio_size);' in host_sources[3].read_text()
    assert 'while (!(gpi & SSPI_ACK));' in host_sources[0].read_text()
    assert 'while (gpi & SSPI_ACK);' in host_sources[0].read_text()
    executable=out/'connected'
    r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_connected',
        '--Mdir',str(out/'obj'),str(generated),str(rtl),*extra,str(bridge),str(loader),str(bench),'-o',str(executable)],capture_output=True,text=True)
    (out/'build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError('connected build failed')
    cases=[]
    names=['source-hps-two-speech-sessions','source-hps-delayed-ack-consumer',
        'fax-full-question-image','fax2-full-question-image','descriptor-magic','descriptor-version',
        'descriptor-mask','descriptor-reserved','descriptor-profile','descriptor-question-length',
        'descriptor-marker-mismatch','base-before-descriptor','speech-before-base','speech-short',
        'speech-long','duplicate-base','unknown-trailing-stream','descriptor-before-marker',
        'empty-marker','descriptor-short','descriptor-long']
    selected=list(enumerate(names))+[(24,'malformed-full-speech-read-quarantine'),
        (25,'extended-to-legacy-reload'),(26,'legacy-recovery-after-loader-fault'),
        (27,'duplicate-speech-verdict-quarantine')]
    rom_metadata=None
    if a.rom_images:
        selected += [(21,'mtrap-rom-speech'),(22,'fax-rom-questions'),(23,'fax2-rom-questions')]
        rom_metadata=json.loads((ROOT/'docs/design/expansion-adapter/increment-07-roms.json').read_text())
    for case,name in selected:
        arguments=[str(executable),f'+CASE={case}']
        if 21<=case<=23:
            game=('mtrap','fax','fax2')[case-21]; image_path=a.rom_images.resolve()/(game+'.hex')
            payload=bytes(int(x,16) for x in image_path.read_text().split())
            expected=rom_metadata['images'][game]
            assert len(payload)==expected['bytes'] and hashlib.sha256(payload).hexdigest()==expected['sha256'], 'staged ROM changed'
            arguments.append('+ROM_IMAGE='+str(image_path))
        r=subprocess.run(arguments,capture_output=True,text=True,timeout=30)
        log=out/(name+'.log'); log.write_text(r.stdout+r.stderr)
        cases.append(dict(case=name,exitCode=r.returncode,expectationMet=r.returncode==0 and 'PASS' in r.stdout,log=str(log.relative_to(ROOT))))
    # A copy without the new verdict hold must fail at the precise end-edge
    # contract, independent of whether a remote clock samples that brief gap.
    mutant=out/'bridge_without_verdict.sv'
    anchor=' || speech_verdict_pending;'
    assert bridge.read_text().count(anchor)==1
    mutant.write_text(bridge.read_text().replace(anchor,';'))
    negative=out/'negative-verdict'
    r=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_connected',
        '--Mdir',str(out/'negative-obj'),str(generated),str(rtl),*extra,str(mutant),str(loader),str(bench),'-o',str(negative)],capture_output=True,text=True)
    (out/'negative-build.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError('verdict negative build failed')
    r=subprocess.run([str(negative),'+CASE=27'],capture_output=True,text=True,timeout=30)
    log=out/'negative-verdict.log'; log.write_text(r.stdout+r.stderr)
    cases.append(dict(case='negative-missing-verdict-hold',exitCode=r.returncode,expectedFailure=True,
        expectationMet=r.returncode!=0 and 'speech quarantine released before loader verdict' in r.stdout+r.stderr,
        log=str(log.relative_to(ROOT))))
    report=dict(schema='exidy2-expansion-connected-increment/v1',increment=increment,accepted=False,cases=cases,
        sha256={str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'sys/hps_io.sv',ROOT/'sys/sys_top.v',rtl,bridge,loader,bench,generated)},
        hostSources={str(p):sha(p) for p in host_sources},
        boundary='Original file-download always block and GPIO synchronizer/ACK bodies extracted unchanged; other hps_io commands and SoC MMIO execution excluded.',
        romImages=({name:{k:v for k,v in image.items() if k!='components'} for name,image in rom_metadata['images'].items()} if rom_metadata else None),
        remaining=['Missing descriptor/length/order permutations beyond the bounded matrix; adapter faults require shared reset; full game/audio execution.',
                   'Fast block MMIO path, other HPS commands, physical CDC/reset/memory/Quartus gates.'])
    a.report.parent.mkdir(parents=True,exist_ok=True); a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(cases))
    if not all(c['expectationMet'] for c in cases): raise RuntimeError('connected test failed')
if __name__=='__main__': main()
