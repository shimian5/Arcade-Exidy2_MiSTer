#!/usr/bin/env python3
"""Window converted 6840 writes without silently losing timer state before the first load."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Event:
    cycle: int
    kind: int
    register: int
    data: int

    def line(self, cycle: int | None = None) -> str:
        return f"{self.cycle if cycle is None else cycle} {self.kind} {self.register} {self.data}"


def read_events(path: Path) -> list[Event]:
    events: list[Event] = []
    previous = -1
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) != 4:
            raise ValueError(f"{path}:{lineno}: expected four columns")
        event = Event(*(int(value) for value in fields))
        if event.cycle < previous:
            raise ValueError(f"{path}:{lineno}: cycles are not monotonic")
        if event.kind not in (0, 1) or not (0 <= event.register <= 7) or not (0 <= event.data <= 255):
            raise ValueError(f"{path}:{lineno}: event field is out of range")
        previous = event.cycle
        events.append(event)
    return events


def timer_state(events: list[Event]) -> tuple[tuple[int, int, int], int, tuple[int, int, int]]:
    """Mirror compare_pitch.py's 6840 control/MSB/period register write decoding."""
    control = [1, 0, 0]
    msb = 0
    periods = [0, 0, 0]
    for event in events:
        if event.kind != 0:
            continue
        r, d = event.register, event.data
        if r == 0:
            if control[1] & 1:
                control[0] = d
            else:
                control[2] = d
        elif r == 1:
            control[1] = d
        elif r in (2, 4, 6):
            msb = d
        else:
            periods[(r - 3) // 2] = (msb << 8) | d
    return tuple(control), msb, tuple(periods)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="full converted stimulus")
    parser.add_argument("--output", type=Path, required=True, help="windowed stimulus output")
    parser.add_argument("--start-cycle", type=int, required=True, help="original stimulus cycle at window start")
    parser.add_argument("--span-cycles", type=int, required=True, help="retained cycle span")
    args = parser.parse_args()
    if args.start_cycle < 0 or args.span_cycles <= 0:
        parser.error("start-cycle must be nonnegative and span-cycles must be positive")

    events = read_events(args.input)
    prior = [event for event in events if event.cycle < args.start_cycle]
    selected = [
        event for event in events
        if args.start_cycle <= event.cycle <= args.start_cycle + args.span_cycles
    ]
    if not selected or selected[0].cycle != args.start_cycle:
        raise SystemExit("window must begin on an original stimulus event")
    first_load = next(
        (event for event in selected if event.kind == 0 and event.register in (3, 5, 7)),
        None,
    )
    if first_load is None:
        raise SystemExit("window contains no 6840 timer period load")

    prior_period_writes = [event for event in prior if event.kind == 0 and event.register >= 2]
    if prior_period_writes:
        raise SystemExit(
            f"refusing window: {len(prior_period_writes)} prior 6840 period/MSB writes "
            "would be omitted before its first load"
        )

    full_before_load = [event for event in events if event.cycle < first_load.cycle]
    window_before_load = [event for event in selected if event.cycle < first_load.cycle]
    historical_state = timer_state(full_before_load)
    reset_window_state = timer_state(window_before_load)
    if historical_state != reset_window_state:
        raise SystemExit(
            "refusing window: reset-start timer control/MSB/period state "
            f"{reset_window_state} differs from full-history state {historical_state} "
            f"at first timer period load cycle {first_load.cycle}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "\n".join(event.line(event.cycle - args.start_cycle) for event in selected) + "\n",
        encoding="utf-8",
    )
    print(f"source_events={len(events)} prior_events={len(prior)} prior_period_writes={len(prior_period_writes)}")
    print(f"first_load_original_cycle={first_load.cycle} first_load_register={first_load.register}")
    print(f"reset_window_timer_state_matches_history={historical_state}")
    print(f"window_events={len(selected)} start={args.start_cycle} span={args.span_cycles} last_relative_cycle={selected[-1].cycle - args.start_cycle}")
    print(f"output={args.output}")


if __name__ == "__main__":
    main()
