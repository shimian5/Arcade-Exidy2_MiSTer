#!/usr/bin/env python3
"""Generate synthetic vectors and an oracle using pinned MAME's actual method."""
import hashlib
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation/mc3417"
SOURCE = ROOT / "simulation/reference_sources/hc55516.cpp"
PIN = "4eef48eb9589f8fd914692cd0251457495d6dc65a491326d542f20a5d8571ba4"


def main():
    source = SOURCE.read_bytes()
    if hashlib.sha256(source).hexdigest() != PIN:
        raise SystemExit("Reference hash mismatch; obtain the documented pinned source.")
    text = source.decode()
    begin = text.index("void mc3417_device::process_bit(")
    end = text.index("void mc3417_device::sound_stream_update", begin)
    method = text[begin:end]
    constants = "\n".join(re.findall(
        r"^#define (?:INTEGRATOR_LEAK_TC|FILTER_DECAY_TC|FILTER_CHARGE_TC|"
        r"FILTER_MIN|FILTER_MAX|SAMPLE_GAIN) .*$", text, re.M))
    coefficients = {}
    for name in ("charge", "decay", "leak"):
        coefficients[name] = re.search(
            r"m_" + name + r"\((pow\(exp\(-1\.0\),[^\n]+)\)", text).group(1)
    OUT.mkdir(parents=True, exist_ok=True)
    harness = "\n".join(text.splitlines()[:3]) + "\n"
    harness += (
        "#include <cmath>\n#include <cstdint>\n#include <fstream>\n"
        "#include <iomanip>\n#include <iostream>\n" + constants + "\n")
    harness += """class mc3417_device {
public:
    bool last=false;
    uint8_t m_shiftreg=0, m_shiftreg_mask=7;
    double m_charge=CHARGE_EXPR, m_decay=DECAY_EXPR, m_leak=LEAK_EXPR;
    double m_sylfilter=0, m_intfilter=0;
    float m_next_sample=0;
    bool is_active_clock_transition(bool state) { return state!=last && !state; }
    void process_bit(bool bit, bool state);
};
"""
    for name, value in coefficients.items():
        harness = harness.replace(name.upper() + "_EXPR", value)
    harness += method + """
int main(int argc,char **argv) {
    if(argc!=3) return 2;
    std::ifstream in(argv[1]); std::ofstream out(argv[2]);
    mc3417_device model;
    int cold,warm,clock,bit,rows=0;
    out<<std::setprecision(17);
    while(in>>cold>>warm>>clock>>bit) {
        if(cold) model=mc3417_device();
        else if(warm) model.last=false;
        else {
            if(bool(clock)!=model.last) model.process_bit(bit,clock);
            model.last=clock;
        }
        out<<cold<<' '<<warm<<' '<<clock<<' '<<bit<<' '
           <<int(model.m_shiftreg&7)<<' '<<model.m_sylfilter<<' '
           <<model.m_intfilter<<' '<<model.m_next_sample<<'\\n';
        ++rows;
    }
    std::cout<<"Generated "<<rows<<" pinned-method reference rows\\n";
    return !in.eof() || !out;
}
"""
    (OUT / "oracle.cpp").write_text(harness)
    rows = []

    def add(cold=0, warm=0, clock=0, bit=0):
        rows.append((cold, warm, clock, bit))

    def reset():
        add(cold=1)
        add()

    def bits(values):
        for bit in values:
            # Digit changes on held/high clock must not enter the decoder.
            add(clock=1, bit=1-bit)
            add(clock=1, bit=bit)
            add(clock=0, bit=bit)
            add(clock=0, bit=1-bit)

    for pattern in range(256):
        reset()
        bits([(pattern >> (7-i)) & 1 for i in range(8)])
    for value in (0, 1):
        reset()
        bits([value]*4096)
    reset()
    bits([i & 1 for i in range(4096)])
    reset()
    rng = random.Random(3417)
    bits([rng.randrange(2) for _ in range(8192)])
    for phase in (0, 1):
        reset()
        bits([0]*64)
        add(clock=phase, bit=1)
        add(warm=1, clock=phase, bit=1)
        add(clock=0, bit=1)
        bits([1]*64)
    for phase in (0, 1):
        add(clock=phase)
        for i in range(128):
            add(clock=phase, bit=i & 1)
    (OUT / "stimulus.txt").write_text(
        "".join(" ".join(map(str, row)) + "\n" for row in rows))
    print(f"Prepared {len(rows)} synthetic stimuli; pinned source SHA256={PIN}")


if __name__ == "__main__":
    main()
