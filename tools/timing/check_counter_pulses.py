#!/usr/bin/env python3
"""Guard and model registered divider pulse equations from the current RTL.

This deliberately small source checker is not an HDL simulator. It requires
unique, expected initializer/increment/comparison expressions in the RTL,
derives each comparator and counter width from those matches, and then models
the nonblocking old-counter sampling for 128 parent ticks. Expected recurrence
and TimeQuest edge triplets are independently specified below.
"""

from dataclasses import dataclass
from pathlib import Path
import re


@dataclass(frozen=True)
class Pulse:
    name: str
    source_file: str
    counter: str
    counter_width: int
    slice_width: int
    expected_compare: int
    period: int
    first_tick: int
    expected_edges: tuple[int, int, int]


PULSES = (
    Pulse("BCLK", "rtl/Exidy2.v", "cencnt", 7, 3, 0, 8, 0, (1, 3, 17)),
    Pulse("PH_1", "rtl/Exidy2.v", "cencnt", 7, 6, 31, 64, 31, (63, 65, 191)),
    Pulse("PH_6", "rtl/Exidy2.v", "cencnt", 7, 6, 0, 64, 0, (1, 3, 129)),
    Pulse("auPH0", "rtl/audio_board.v", "cencnt_au", 4, 4, 0, 16, 0, (1, 3, 33)),
    Pulse("auPH0B", "rtl/audio_board.v", "cencnt_au", 4, 4, 1, 16, 1, (3, 5, 35)),
)


def unique(pattern: str, source: str, description: str) -> re.Match[str]:
    matches = list(re.finditer(pattern, source, re.MULTILINE))
    assert len(matches) == 1, f"expected exactly one {description}, found {len(matches)}"
    return matches[0]


def derive_source_equation(pulse: Pulse) -> tuple[int, int, int]:
    root = Path(__file__).resolve().parents[2]
    source = (root / pulse.source_file).read_text(encoding="utf-8")
    escaped_counter = re.escape(pulse.counter)
    init = unique(
        rf"reg\s+\[(\d+):0\]\s+{escaped_counter}\s*=\s*\d+'d(\d+)\s*;",
        source,
        f"{pulse.counter} initialized counter declaration",
    )
    counter_width = int(init.group(1)) + 1
    initial_value = int(init.group(2))
    assert initial_value == 0, f"{pulse.counter} initializer changed to {initial_value}"
    assert counter_width == pulse.counter_width, f"{pulse.counter}: declaration width changed to {counter_width}"
    unique(
        rf"{escaped_counter}\s*<=\s*{escaped_counter}\s*\+\s*\d+'d1\s*;",
        source,
        f"{pulse.counter} increment assignment",
    )
    target = unique(
        rf"\b{re.escape(pulse.name)}\s*<=\s*{escaped_counter}\s*\[(\d+):0\]\s*==\s*(\d+)'d(\d+)\s*;",
        source,
        f"{pulse.name} registered comparator",
    )
    slice_width = int(target.group(1)) + 1
    literal_width = int(target.group(2))
    compare = int(target.group(3))
    assert slice_width == pulse.slice_width, f"{pulse.name}: source slice width changed to {slice_width}"
    assert literal_width == slice_width, f"{pulse.name}: comparison literal width is {literal_width}"
    assert compare == pulse.expected_compare, f"{pulse.name}: source comparison changed to {compare}"
    assert counter_width >= slice_width, f"{pulse.name}: comparator exceeds counter width"
    return counter_width, slice_width, compare


def waveform(pulse: Pulse, counter_width: int, slice_width: int, compare: int, ticks: int = 128) -> list[int]:
    counter = 0
    mask = (1 << counter_width) - 1
    compare_mask = (1 << slice_width) - 1
    samples = []
    for _ in range(ticks):
        # Nonblocking RTL assignments compare the pre-edge counter value.
        samples.append(int((counter & compare_mask) == compare))
        counter = (counter + 1) & mask
    return samples


def edge_list(rises: list[int], period: int) -> tuple[int, int, int]:
    # TimeQuest edge 1 is the first source rising edge. Each parent tick adds
    # two edge numbers; a one-tick-high registered pulse falls one tick later.
    rise = 2 * rises[0] + 1
    fall = rise + 2
    next_rise = rise + 2 * period
    return rise, fall, next_rise


def check(pulse: Pulse) -> None:
    counter_width, slice_width, compare = derive_source_equation(pulse)
    samples = waveform(pulse, counter_width, slice_width, compare)
    rises = [i for i, value in enumerate(samples) if value and (i == 0 or not samples[i - 1])]
    highs = [i for i, value in enumerate(samples) if value]
    expected_rises = list(range(pulse.first_tick, len(samples), pulse.period))
    assert rises == expected_rises, f"{pulse.name}: rises {rises}, expected {expected_rises}"
    assert highs == [tick for rise in expected_rises for tick in (rise,)], (
        f"{pulse.name}: pulse width is not exactly one parent tick: {highs}"
    )
    actual_edges = edge_list(rises, pulse.period)
    assert actual_edges == pulse.expected_edges, (
        f"{pulse.name}: edge list {actual_edges}, expected {pulse.expected_edges}"
    )
    print(f"PASS {pulse.name}: source={pulse.source_file}:{pulse.counter}[{slice_width - 1}:0]=={compare}; rises={rises[:3]} edges={actual_edges}; width=1 parent tick")


def main() -> None:
    for pulse in PULSES:
        check(pulse)
    print("PASS all five source-equation pulse checks (128 parent ticks each)")


if __name__ == "__main__":
    main()
