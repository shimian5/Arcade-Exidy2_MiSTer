#!/usr/bin/env python3
"""Generate an isolated full-flow Quartus resource probe, never alter the core project."""
import argparse, hashlib, json, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser(); p.add_argument('--ram-loader',action='store_true')
    p.add_argument('--synchronizers',action='store_true')
    p.add_argument('--increment',type=int); a=p.parse_args()
    if a.synchronizers: a.ram_loader=True
    increment=a.increment or (11 if a.synchronizers else (10 if a.ram_loader else 9))
    OUT=ROOT/f'simulation/expansion_adapter/fit{increment:02d}'
    OUT.mkdir(parents=True,exist_ok=True)
    source_qsf=ROOT/'Arcade-Exidy2.qsf'
    device=re.search(r'-name DEVICE (\S+)',source_qsf.read_text()).group(1)
    sources=[ROOT/'sim/expansion_adapter'/name for name in
             ('exidy_transport_adapter.sv','exidy_expansion_bridge.sv',
              'exidy_expansion_loader_ram.sv' if a.ram_loader else 'exidy_expansion_loader_baseline.sv')]
    lines=['set_global_assignment -name FAMILY "Cyclone V"',
        'set_global_assignment -name DEVICE '+device,
        'set_global_assignment -name TOP_LEVEL_ENTITY exidy_expansion_bridge',
        'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
        'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2',
        'set_global_assignment -name OPTIMIZATION_MODE "BALANCED"',
        'set_global_assignment -name SDC_FILE probe.sdc',
        'set_location_assignment PIN_V11 -to clk',
        'set_location_assignment PIN_Y13 -to cvsd_clk',
        'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk',
        'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to cvsd_clk']
    port_text=sources[1].read_text().split('module exidy_expansion_bridge (',1)[1].split(');',1)[0]
    port_text=re.sub(r'//[^\n]*','',port_text)
    port_text=re.sub(r'\[[^\]]*\]|\b(input|output|logic|wire)\b','',port_text)
    ports=re.findall(r'\b[A-Za-z_]\w*\b',port_text)
    assert len(ports)==len(set(ports)) and 'clk' in ports and 'cvsd_clk' in ports
    # Explicit top-port patterns avoid a global virtual-pin wildcard swallowing
    # clock pins even when a later OFF assignment is present in Quartus 17.
    lines += ['set_instance_assignment -name VIRTUAL_PIN ON -to '+port+'*'
              for port in ports if port not in ('clk','cvsd_clk')]
    lines += ['set_global_assignment -name SYSTEMVERILOG_FILE "'+p.as_posix()+'"' for p in sources]
    if a.synchronizers:
        # Scope identification to the five actual two-register CDC chains.
        # Generic async_reg remains useful to other tools but Quartus17 ignores it.
        registers=('ack_meta','ack_sync','generation_meta','generation_sync',
                   'req_meta','req_sync','gen_meta','gen_sync',
                   'cvsd_ready_meta','cvsd_ready_sync')
        lines += ['set_instance_assignment -name SYNCHRONIZER_IDENTIFICATION "FORCED IF ASYNCHRONOUS" -to "*|'+name+'"'
                  for name in registers]
    (OUT/'expansion_probe.qsf').write_text('\n'.join(lines)+'\n')
    (OUT/'expansion_probe.qpf').write_text('QUARTUS_VERSION = "17.0"\nPROJECT_REVISION = "expansion_probe"\n')
    (OUT/'probe.sdc').write_text('''# Resource-only independent clocks; not a production CDC signoff.
create_clock -name main -period 20.000 [get_ports clk]
create_clock -name speech -period 100.000 [get_ports cvsd_clk]
set_clock_groups -asynchronous -group main -group speech
derive_clock_uncertainty
# Virtual data/control pins intentionally have no board I/O timing here.
''')
    report=dict(schema='exidy2-expansion-fit-probe/v1',increment=increment,device=device,
        project=str(OUT.relative_to(ROOT)),
        command='Unsandboxed PowerShell: quartus_sh --flow compile expansion_probe',
        sourceSha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[source_qsf]},
        limits=['Standalone bridge only; no CPU/board/framework/PLL or whole-core capacity proof.',
               'Virtual data/control pins; main 50MHz/speech 10MHz abstract targets.',
               'Asynchronous clock groups intentionally exclude crossing timing; no CDC/reset/board signoff.',
               'Resource/result summaries must be added only after a completed full-flow build.'])
    (ROOT/f'docs/design/expansion-adapter/increment-{increment:02d}-project.json').write_text(json.dumps(report,indent=2)+'\n')
    print(str(OUT))
if __name__=='__main__':main()
