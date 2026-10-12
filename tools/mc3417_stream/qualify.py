#!/usr/bin/env python3
"""Extract/check pinned MAME software-clock stream behavior (not board PCM).

Run under WSL with g++. Outputs and private firmware sample replays remain
under ignored simulation/. This defines a reference contract before FPGA
stream/filter integration; it deliberately exposes callback-block dependence.
"""
import argparse
import csv
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "simulation/reference_sources/hc55516.cpp"
PIN = "4eef48eb9589f8fd914692cd0251457495d6dc65a491326d542f20a5d8571ba4"
OUT = ROOT / "simulation/mc3417_stream"


def generate(mutant=""):
    raw = SOURCE.read_bytes()
    if hashlib.sha256(raw).hexdigest() != PIN:
        raise SystemExit("Pinned MAME source hash differs")
    source = raw.decode("utf-8")
    bit_start = source.index("void mc3417_device::process_bit(")
    stream_start = source.index("void mc3417_device::sound_stream_update", bit_start)
    bit_method = source[bit_start:stream_start]
    end = source.index("//#####################################", stream_start)
    stream_method = source[stream_start:end]
    if mutant == "hold":
        needle = "(m_next_sample - sample) / stream.samples()"
        if stream_method.count(needle) != 1:
            raise SystemExit("Hold mutant source guard failed")
        stream_method = stream_method.replace(needle, "0")
    elif mutant == "early-timeout":
        needle = "m_samples_generated > SAMPLE_RATE / 32"
        if stream_method.count(needle) != 1:
            raise SystemExit("Timeout mutant source guard failed")
        stream_method = stream_method.replace(needle, "m_samples_generated >= SAMPLE_RATE / 32")
    constants = "\n".join(re.findall(
        r"^#define (?:SAMPLE_RATE|INTEGRATOR_LEAK_TC|FILTER_DECAY_TC|FILTER_CHARGE_TC|FILTER_MIN|FILTER_MAX|SAMPLE_GAIN) .*$",
        source, re.M))
    coeff = {name: re.search(r"m_" + name + r"\((pow\(exp\(-1\.0\),[^\n]+)\)", source).group(1)
             for name in ("charge", "decay", "leak")}
    header = "\n".join(source.splitlines()[:3]) + "\n"
    header += "#include <cmath>\n#include <cstdint>\n#include <fstream>\n#include <iomanip>\n#include <iostream>\n#include <vector>\n" + constants + "\n"
    header += """
struct sound_stream {
    using sample_t=float;
    std::vector<float> values;
    explicit sound_stream(int n):values(n) {}
    int samples() {return int(values.size());}
    void put(int,int i,float sample) {values.at(i)=sample;}
};
class mc3417_device {
public:
    bool last=false, buffered=false;
    uint8_t m_shiftreg=0, m_shiftreg_mask=7;
    uint32_t m_samples_generated=0;
    double m_charge=CHARGE_EXPR, m_decay=DECAY_EXPR, m_leak=LEAK_EXPR;
    double m_sylfilter=0, m_intfilter=0;
    float m_curr_sample=0, m_next_sample=0;
    bool is_external_oscillator() {return false;}
    bool is_active_clock_transition(bool state) {return state!=last && !state;}
    bool is_clock_changed(bool state) {return state!=last;}
    bool current_clock_state() {return false;}
    bool m_buffered_bit=false, m_last_clock_state=false;
    void process_bit(bool bit,bool state);
    void sound_stream_update(sound_stream &stream);
};
"""
    for name, expr in coeff.items():
        header = header.replace(name.upper()+"_EXPR", expr)
    return header + bit_method + stream_method + """
int main(int argc,char **argv) {
    if(argc!=4) return 2;
    std::ifstream in(argv[1]);std::ofstream pcm(argv[2]),state(argv[3]);
    pcm<<std::setprecision(17);state<<std::setprecision(17);
    pcm<<"op,index,sample\\n";state<<"op,count,current,next,history\\n";
    mc3417_device device;
    char op;double value;int index=0;
    while(in>>op>>value) {
        if(op=='R') device=mc3417_device();
        else if(op=='N') device.m_next_sample=float(value);
        else if(op=='D') device.buffered=bool(value);
        else if(op=='Z') device.last=false;
        else if(op=='C') {
            bool clock=bool(value);
            if(device.is_clock_changed(clock)) {
                device.m_samples_generated=0;
                device.process_bit(device.buffered,clock);
            }
            device.last=clock;
        } else if(op=='U') {
            int n=int(value);if(n<1 || n>192000 || n!=value) return 3;
            sound_stream stream(n);device.sound_stream_update(stream);
            for(int i=0;i<n;i++) pcm<<index<<','<<i<<','<<stream.values[i]<<'\\n';
        } else return 4;
        state<<index<<','<<device.m_samples_generated<<','<<device.m_curr_sample<<','
             <<device.m_next_sample<<','<<int(device.m_shiftreg&7)<<'\\n';
        index++;
    }
    return !in.eof() || !pcm || !state;
}
"""


def run(exe, name, operations):
    name = exe.name + "-" + name
    stimulus, pcm, state = (OUT / f"{name}-{suffix}" for suffix in ("ops.txt", "pcm.csv", "state.csv"))
    stimulus.write_text("".join(f"{op} {value}\n" for op, value in operations), encoding="utf-8")
    subprocess.run([str(exe), str(stimulus), str(pcm), str(state)], check=True)
    with pcm.open(encoding="utf-8") as f:
        samples = list(csv.DictReader(f))
    with state.open(encoding="utf-8") as f:
        states = list(csv.DictReader(f))
    return samples, states


def tests(exe):
    checks = 0
    def check(value, label):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(label)
    # Half-open ramps: first sample is previous endpoint, final endpoint only
    # becomes the next block's initial sample. Negative ramps exercise sign.
    for n in (1, 2, 13, 4096):
        pcm, _ = run(exe, f"ramp-{n}", [("R",0),("N",.5),("U",n),("C",1),("N",-.25),("U",n)])
        values = [float(r["sample"]) for r in pcm]
        expected = [i*.5/n for i in range(n)] + [.5-i*.75/n for i in range(n)]
        check(len(values)==len(expected) and max(abs(a-b) for a,b in zip(values, expected)) < 1e-4,
              f"half-open ramp N={n}")
    pcm, states = run(exe,"timeout",[("R",0),("N",.5),("U",1),("U",5999),("U",4),("U",2)])
    check(float(states[3]["next"]) == .5 and int(states[3]["count"]) == 6000, "exact timeout threshold stays active")
    check([float(r["sample"]) for r in pcm if int(r["op"])==4] == [.5,.375,.25,.125], "timeout ramps whole crossing block")
    check(all(float(r["sample"])==0 for r in pcm if int(r["op"])==5), "post-timeout silence")
    _, states = run(exe,"clock-reset",[("R",0),("N",.25),("U",100),("C",0),("Z",0),("C",1),("U",10),("D",1),("C",0)])
    check(int(states[3]["count"])==100, "repeated clock does not clear count")
    check(int(states[4]["count"])==100 and float(states[4]["current"])==.25, "warm clock reset retains stream state")
    check(int(states[5]["count"])==0 and float(states[5]["next"])==.25, "rising edge resets count without decoding")
    check(int(states[8]["count"])==0 and int(states[8]["history"])==1, "falling edge decodes and clears count")
    a, _ = run(exe,"single-block",[("R",0),("N",.5),("U",8)])
    b, _ = run(exe,"split-block",[("R",0),("N",.5),("U",4),("U",4)])
    check([r["sample"] for r in a] != [r["sample"] for r in b], "MAME rendering depends on callback segmentation")
    return checks


def firmware_replay(exe, path):
    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    # Chosen fixed event blocks; no native MAME scheduler/sound-stream claim.
    ops=[("R",0)]
    last_tick=0
    for row in rows:
        tick=int(row["time_ps"])*192000//10**12
        if tick > last_tick:
            ops.append(("U",tick-last_tick))
        ops.extend((("C",1),("C",0),("N",int(row["sample_q24"])/(1<<24))))
        last_tick=tick
    ops.extend((("U",6000),("U",13),("U",13)))
    pcm, states=run(exe,"firmware-events",ops)
    if not pcm or not any(float(r["sample"]) != 0 for r in pcm):
        raise AssertionError("Firmware stream replay is empty/silent")
    if float(states[-1]["next"]) != 0 or any(float(r["sample"])!=0 for r in pcm if int(r["op"])==len(ops)-1):
        raise AssertionError("Firmware stopped-clock tail did not settle to silence")
    return dict(event_rows=len(rows), pcm_samples=len(pcm), peak=max(abs(float(r["sample"])) for r in pcm),
                scope="192 kHz event-block diagnostic; not native MAME scheduling/board filtering/PCM equality")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware-samples",type=Path)
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    report={"source_sha256":PIN,"sample_rate":192000,"timeout_samples":6000}
    for mutant in ("", "hold", "early-timeout"):
        name=mutant or "reference"
        source=OUT/f"{name}.cpp";exe=OUT/name
        source.write_text(generate(mutant),encoding="utf-8")
        subprocess.run(["g++","-std=c++17","-O2",str(source),"-o",str(exe)],check=True)
        try:
            count=tests(exe)
        except AssertionError as error:
            if not mutant:
                raise
            expected_failure={"hold":"half-open ramp N=2",
                              "early-timeout":"exact timeout threshold stays active"}[mutant]
            if str(error) != expected_failure:
                raise AssertionError(f"Unexpected mutant failure: {mutant}: {error}") from error
            report[name]="rejected: "+str(error)
        else:
            if mutant:
                raise AssertionError(f"Mutant survived: {mutant}")
            report["directed_checks"]=count
    if args.firmware_samples:
        report["firmware_replay"]=firmware_replay(OUT/"reference",args.firmware_samples)
    (OUT/"report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,indent=2))


if __name__=="__main__":
    main()
