#!/usr/bin/env python3
"""Bounded Exidy 336x280 to 336x262 rolling-row schedule model."""
from __future__ import annotations

from fractions import Fraction
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation" / "crt_schedule"
RASTER_JSON = ROOT / "docs" / "audits" / "raster" / "measurements.json"

SRC_TRANSPORT = 131       # common exact-rate schedule units per native clock
DST_TRANSPORT = 140       # common exact-rate schedule units per CRT clock
PIXELS_PER_LINE = 336
SRC_LINES = 280
DST_LINES = 262
ACTIVE_WIDTH = 256
ACTIVE_HEIGHT = 256
SRC_PIXEL = 8 * SRC_TRANSPORT
DST_PIXEL = 8 * DST_TRANSPORT
SRC_LINE = PIXELS_PER_LINE * SRC_PIXEL
DST_LINE = PIXELS_PER_LINE * DST_PIXEL
FRAME = SRC_LINES * SRC_LINE
DST_FRAME = DST_LINES * DST_LINE
SRC_FRAME_ORIGIN_TO_ACTIVE_ROW0 = 23 * SRC_PIXEL
SOURCE_PUBLICATION_UNCERTAINTY = 2 * SRC_TRANSPORT
READ_PIPELINE = 2 * DST_TRANSPORT
DELAY_MIN = 255 * SRC_PIXEL + 8 * DST_TRANSPORT
DELAY_MAX = 255 * SRC_PIXEL + 32 * DST_TRANSPORT
FRAMES_CHECKED = 3

assert FRAME == DST_FRAME


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_time(active_row: int, x: int, pipeline_offset_pixels: int = 0) -> int:
    frame, row = divmod(active_row, ACTIVE_HEIGHT)
    origin = SRC_FRAME_ORIGIN_TO_ACTIVE_ROW0 + pipeline_offset_pixels * SRC_PIXEL
    return frame * FRAME + origin + row * SRC_LINE + x * SRC_PIXEL


def output_time(frame: int, row: int, x: int, delay: int, pipeline_offset_pixels: int = 0) -> int:
    origin = SRC_FRAME_ORIGIN_TO_ACTIVE_ROW0 + pipeline_offset_pixels * SRC_PIXEL
    return frame * FRAME + origin + delay + row * DST_LINE + x * DST_PIXEL


def margins(lines: int, delay: int, pipeline_offset_pixels: int = 0) -> tuple[int, int]:
    publish = FRAME
    reuse = FRAME
    for frame in range(FRAMES_CHECKED):
        for row in range(ACTIVE_HEIGHT):
            absolute_row = frame * ACTIVE_HEIGHT + row
            first_read = output_time(frame, row, 0, delay, pipeline_offset_pixels)
            last_read = output_time(frame, row, ACTIVE_WIDTH - 1, delay, pipeline_offset_pixels) + READ_PIPELINE
            row_published = source_time(absolute_row, ACTIVE_WIDTH - 1, pipeline_offset_pixels) + SOURCE_PUBLICATION_UNCERTAINTY
            slot_reused = source_time(absolute_row + lines, 0, pipeline_offset_pixels) - SOURCE_PUBLICATION_UNCERTAINTY
            publish = min(publish, first_read - row_published)
            reuse = min(reuse, slot_reused - last_read)
    return publish, reuse


def check_every_pixel(lines: int, delay: int, pipeline_offset_pixels: int) -> int:
    checks = 0
    for frame in range(FRAMES_CHECKED):
        for row in range(ACTIVE_HEIGHT):
            absolute_row = frame * ACTIVE_HEIGHT + row
            for x in range(ACTIVE_WIDTH):
                read = output_time(frame, row, x, delay, pipeline_offset_pixels)
                written = source_time(absolute_row, x, pipeline_offset_pixels)
                overwritten = source_time(absolute_row + lines, x, pipeline_offset_pixels)
                assert read > written + SOURCE_PUBLICATION_UNCERTAINTY
                assert read + READ_PIPELINE < overwritten - SOURCE_PUBLICATION_UNCERTAINTY
                checks += 1
    return checks


def first_drift_fault(lines: int, ppm: int, limit_frames: int = 100_000) -> dict:
    """Scale all time by (1e6+ppm), keeping source exact and CRT clock offset."""
    denominator = 1_000_000 + ppm  # ppm > 0 means CRT pixel clock is faster
    scale = 1_000_000
    origin = SRC_FRAME_ORIGIN_TO_ACTIVE_ROW0 * denominator
    src_frame = FRAME * denominator
    dst_line = DST_LINE * scale
    dst_pixel = DST_PIXEL * scale
    min_delay = 255 * SRC_PIXEL * denominator + 8 * DST_TRANSPORT * scale
    max_delay = 255 * SRC_PIXEL * denominator + 32 * DST_TRANSPORT * scale
    uncertainty = SOURCE_PUBLICATION_UNCERTAINTY * denominator
    read_pipe = READ_PIPELINE * scale
    for frame in range(limit_frames):
        src_origin = frame * src_frame + origin
        dst_origin = frame * FRAME * scale + origin
        for row in range(ACTIVE_HEIGHT):
            src_row = src_origin + row * SRC_LINE * denominator
            next_row_start = (frame * ACTIVE_HEIGHT + row + lines) // ACTIVE_HEIGHT * src_frame
            local_next_row = (frame * ACTIVE_HEIGHT + row + lines) % ACTIVE_HEIGHT
            overwrite = next_row_start + origin + local_next_row * SRC_LINE * denominator - uncertainty
            for delay in (min_delay, max_delay):
                first_read = dst_origin + delay + row * dst_line
                last_read = first_read + (ACTIVE_WIDTH - 1) * dst_pixel + read_pipe
                published = src_row + (ACTIVE_WIDTH - 1) * SRC_PIXEL * denominator + uncertainty
                if first_read <= published:
                    return {"status": "underflow", "frame": frame, "row": row, "delayEndpoint": "min", "marginScaled": first_read - published}
                if last_read >= overwrite:
                    return {"status": "row_reuse_before_last_read", "frame": frame, "row": row, "delayEndpoint": "max", "marginScaled": overwrite - last_read}
    return {"status": "no_failure_within_limit", "limitFrames": limit_frames}


def ppm_bounds() -> dict:
    # Test the finite row ownership window under a bounded free-running mismatch.
    # Positive output ppm consumes rows early; negative ppm consumes them late.
    return {str(ppm): first_drift_fault(32, ppm) for ppm in (10_000, -10_000, 1, -1)}


def row_read_decision(published: set[int], requested: int) -> str:
    """Arithmetic consumer contract: missing rows fault; never alias another row."""
    return "read" if requested in published else "underflow_fault_blank"


def pll_candidates(source_mhz: Fraction) -> dict:
    target = source_mhz * Fraction(131, 140)
    scale = 1 << 32
    def candidate(m: int, target_mhz: Fraction) -> dict:
        ideal_k = (target_mhz * 32 / 50 - m) * scale
        k = (2 * ideal_k.numerator + ideal_k.denominator) // (2 * ideal_k.denominator)
        actual = Fraction(50 * (m * scale + k), 32 * scale)
        return {"M": m, "N": 1, "C": 32, "K_Q32": k, "targetMHz": float(target_mhz), "candidateMHz": float(actual), "errorHz": float((actual - target_mhz) * 1_000_000)}
    fallback_native = candidate(28, source_mhz)
    fallback_crt = candidate(27, target)
    source_frame_hz = source_mhz * 1_000_000 / (8 * PIXELS_PER_LINE * SRC_LINES)
    fallback_crt_frame_hz = Fraction(50_000_000 * (fallback_crt["M"] * scale + fallback_crt["K_Q32"]), 32 * scale) / (8 * PIXELS_PER_LINE * DST_LINES)

    pll_source = (ROOT / "rtl" / "pll" / "pll_0002.v").read_text(encoding="utf-8")
    out1_match = re.search(r'output_clock_frequency1\("([0-9.]+) MHz"\)', pll_source)
    assert out1_match, "could not find generated PLL output 1 frequency"
    source_out1 = Fraction(out1_match.group(1))
    # Separate, output-only integer PLL referenced to the existing source PLL's
    # unused quarter-rate output. These divider ratios give the exact 131/140
    # transport relation if the existing source outputs are truly in 4:1 ratio.
    native_rate = source_out1 * Fraction(128, 32)
    crt_rate = source_out1 * Fraction(131, 35)
    native_vco = source_out1 * 128
    crt_vco = source_out1 * 131
    declared_ratio = source_mhz / source_out1
    assert Fraction(131, 35) / Fraction(128, 32) == Fraction(131, 140)
    assert Fraction(128, 32) == 4
    exact_ref_candidate = {
        "reference": "existing pll_0002 outclk_1 (declared 11.288265 MHz), conditional GCLK reference to separate output PLL",
        "sourceOutput0DeclaredMHz": float(source_mhz),
        "sourceOutput1DeclaredMHz": float(source_out1),
        "declaredSourceOut0ToOut1Ratio": f"{declared_ratio.numerator}/{declared_ratio.denominator}",
        "nominalQuarterRateDifferenceHz": float((source_mhz - 4 * source_out1) * 1_000_000),
        "native": {"M": 128, "N": 1, "C": 32, "rateMHzFromDeclaredOut1": float(native_rate), "nominalVcoMHz": float(native_vco)},
        "crt": {"M": 131, "N": 1, "C": 35, "rateMHzFromDeclaredOut1": float(crt_rate), "nominalVcoMHz": float(crt_vco), "ratioToNative": "131/140"},
        "crtRefreshHzFromDeclaredOut1": float(crt_rate * 1_000_000 / (8 * PIXELS_PER_LINE * DST_LINES)),
        "sourceRefreshHzFromDeclaredOut0": float(source_frame_hz),
        "crtRefreshErrorHzAgainstDeclaredOut0": float(crt_rate * 1_000_000 / (8 * PIXELS_PER_LINE * DST_LINES) - source_frame_hz),
        "exactDividerRatioAssertions": {"nativeOutPerReference": "128/32 = 4", "crtOutPerReference": "131/35", "crtToNative": "(131/35)/(128/32) = 131/140", "passed": True},
        "vcoRangeCheck": {"nominalRangeMHzForTargetI7": [600, 1600], "bothNominalCandidatesInRange": 600 <= native_vco <= 1600 and 600 <= crt_vco <= 1600, "note": "Datasheet range is a device operating limit, not a proof that this generated cascaded/reference design fits."},
        "status": "preferred conditional candidate; exact 131/140 relationship only if actual original PLL out0/out1 ratio is exactly 4 and downstream reference routing/reconfiguration is supported and fitted",
    }
    return {"pixelFrequencyRatioCRTtoNative": "262/280 = 131/140", "targetCRTTransportMHzFromOut0": float(target), "targetNativePixelMHz": float(source_mhz / 8), "targetCRTPixelMHz": float(target * Fraction(1, 8)), "targetHorizontalHz": float(target * 1_000_000 / (8 * PIXELS_PER_LINE)), "preferredSameSourceReferenceCandidate": exact_ref_candidate, "fallbackIndependent50MHzQ32": {"referenceMHz": 50.0, "nativeOutputCandidate": fallback_native, "crtOutputCandidate": fallback_crt, "candidateRefreshHz": float(fallback_crt_frame_hz), "sourceDeclaredRefreshHz": float(source_frame_hz), "refreshErrorHzFromRoundedMetadata": float(fallback_crt_frame_hz - source_frame_hz), "status": "fallback only; based on rounded metadata and cannot guarantee long-term alignment to the original source"}, "requiredVerification": "Measure/fitter-confirm the existing out0:out1 ratio; verify the chosen Cyclone V PLL can use outclk_1 as its GCLK reference with legal placement, VCO, bandwidth, routing, and dynamic reconfiguration. No Quartus fit or silicon measurement is claimed."}


def main() -> None:
    raster = json.loads(RASTER_JSON.read_text(encoding="utf-8"))
    source_mhz = Fraction(str(raster["pll"]["instantiatedGeneratedOutput0MHz"]))
    offsets = (0, 1, 7, 8, 23, 335)
    min_lines = next(n for n in range(1, 33) if all(min(margins(n, d, off)) > 0 for d in (DELAY_MIN, DELAY_MAX) for off in offsets))
    assert min_lines == 18
    chosen = 32
    endpoint_margins = {
        "minimumStartupDelay": margins(chosen, DELAY_MIN, 0),
        "maximumStartupDelay": margins(chosen, DELAY_MAX, 0),
    }
    assert all(v[0] > 0 and v[1] > 0 for v in endpoint_margins.values())
    assert margins(min_lines - 1, DELAY_MAX, 0)[1] <= 0
    assert margins(chosen, 0, 0)[0] < 0  # refuse to display before row 0 commits
    pixel_checks = sum(check_every_pixel(chosen, delay, off) for delay in (DELAY_MIN, DELAY_MAX) for off in offsets)
    assert pixel_checks == 6 * 2 * FRAMES_CHECKED * ACTIVE_HEIGHT * ACTIVE_WIDTH

    missing_row = 17
    published_rows = set(range(17)) | set(range(18, ACTIVE_HEIGHT))
    missing_row_action = row_read_decision(published_rows, missing_row)
    assert missing_row_action == "underflow_fault_blank"
    assert all(row_read_decision(published_rows, row) == "read" for row in published_rows)
    missing_row_case = {"missingRow": missing_row, "firstBlockedOutputCoordinate": {"frame": 0, "row": missing_row, "pixel": 0}, "modelAction": missing_row_action, "assertion": "missing row is blocked and does not substitute another row; all published row identities remain readable", "scope": "consumer decision arithmetic only; not RTL fault-containment verification"}
    # An intentionally undersized store is independently shown to permit reuse
    # before a line's last read at the conservative startup endpoint.
    undersized = min_lines - 1
    under_margin = margins(undersized, DELAY_MAX, 0)[1]
    assert under_margin <= 0
    ownership_cases = [
        {"case": "source-row-not-published", "expectedAction": "blank/fault at that row's first destination pixel"},
        {"case": "source-stops-mid-frame", "expectedAction": "synchronize fault, blank output, retire frame request; restart only from a complete fresh row 0"},
        {"case": "row-slot-reuse-deadline-missed", "expectedAction": "fault/blank before stale or overwritten RGB is displayed"},
        {"case": "PLL-unlocked-or-lost", "expectedAction": "hold output blank and transport reset until lock and two output-frame boundaries"},
        {"case": "mode-change-or-user-reset", "expectedAction": "blank, reset packet/row ownership locally, reconfigure output PLL; preserve fixed game/audio source clock"},
    ]

    drift_cases = ppm_bounds()
    assert all(v["status"] in ("underflow", "row_reuse_before_last_read") for v in drift_cases.values())
    result = {
        "schema": "exidy2-crt-schedule/v1",
        "status": "PASS: exact aligned-rate row-ownership arithmetic; integration and fit remain required",
        "inputs": {"rasterMeasurement": "docs/audits/raster/measurements.json", "rasterMeasurementSha256": sha(RASTER_JSON), "sourceFrameOriginToActiveRow0RawPixels": 23, "commonCapturePipelineOffsetPixelsTested": list(offsets), "pipelineOffsetContract": "A constant post-tap latency translates the source schedule and cancels from row-ownership margins; the actual RGB-valid row-0 origin must be measured in integration."},
        "timing": {"sourceTransportTimeUnitsPerClock": SRC_TRANSPORT, "crtTransportTimeUnitsPerClock": DST_TRANSPORT, "sourcePixelTimeUnits": SRC_PIXEL, "crtPixelTimeUnits": DST_PIXEL, "sourceLineTimeUnits": SRC_LINE, "crtLineTimeUnits": DST_LINE, "sourceFrameTimeUnits": FRAME, "crtFrameTimeUnits": DST_FRAME, "frameRateFromRasterPLLHz": float(source_mhz * 1_000_000 / (8 * PIXELS_PER_LINE * SRC_LINES)), "exactNominalFrameEquality": FRAME == DST_FRAME, "sourceActiveStartOffsetUnits": SRC_FRAME_ORIGIN_TO_ACTIVE_ROW0},
        "startupAndMargins": {"startupDelayTimeUnits": [DELAY_MIN, DELAY_MAX], "startupDelayUsAtConfiguredSourceClock": [float(Fraction(d, SRC_TRANSPORT) / (source_mhz * 1_000_000) * 1_000_000) for d in (DELAY_MIN, DELAY_MAX)], "sourcePublicationUncertaintyTimeUnits": SOURCE_PUBLICATION_UNCERTAINTY, "readPipelineTimeUnits": READ_PIPELINE, "minimumRowsUnderContract": min_lines, "chosenRows": chosen, "chosenRgb24StorageBits": chosen * ACTIVE_WIDTH * 24, "alternateRgb6StorageBits": chosen * ACTIVE_WIDTH * 6, "alternateRawThreeBitStorageBits": chosen * ACTIVE_WIDTH * 3, "marginsTimeUnits": {k: {"publication": v[0], "reuse": v[1]} for k,v in endpoint_margins.items()}, "marginsMicroseconds": {k: {"publication": float(Fraction(v[0], SRC_TRANSPORT) / (source_mhz*1_000_000)*1_000_000), "reuse": float(Fraction(v[1], SRC_TRANSPORT) / (source_mhz*1_000_000)*1_000_000)} for k,v in endpoint_margins.items()}, "pixelChecks": pixel_checks, "offsetTranslationChecks": len(offsets)},
        "finiteDriftFaultCases": drift_cases,
        "negativeCases": {"missingRow": missing_row_case, "undersizedStore": {"rows": undersized, "reuseMarginAtMaximumStartupDelayTimeUnits": under_margin, "expected": "fail; row can be overwritten before final read"}},
        "modeSwitchFaultCases": ownership_cases,
        "pllCandidateAnalysis": pll_candidates(source_mhz),
        "counters": {"sequenceWidthBitsCandidate": 16, "wrapTest": {"startSequence": 65530, "rowsAdvanced": 16, "expectedEndSequence": 10, "modularDistanceChecks": [1, 16, 31, 32], "contract": "serial-number distance is modulo 2^16 and capacity is <2^15; Gray-coded CDC still needs implementation and skew constraints"}},
        "scope": "Arithmetic model only. It does not instantiate RTL, model analog PLL lock/phase noise, prove a clock fit, validate the actual post-video-mixer RGB-valid row origin, or establish HDMI/analog/Direct Video/CRT hardware acceptance.",
    }
    # Explicit modulo/Gray wrap contract checks, separate from timing proof.
    def gray(x: int) -> int: return x ^ (x >> 1)
    def dist(a: int, b: int) -> int: return (a - b) & 0xFFFF
    sequence = 65530
    gray_transitions = []
    for _ in range(16):
        nxt = (sequence + 1) & 0xFFFF
        assert (gray(sequence) ^ gray(nxt)).bit_count() == 1
        sequence = nxt
        gray_transitions.append(sequence)
    assert sequence == 10
    result["counters"]["wrapTest"]["grayOneBitTransitions"] = len(gray_transitions)
    for d in (1,16,31,32):
        assert dist((10+d)&0xFFFF,10)==d

    OUT.mkdir(parents=True, exist_ok=True)
    output = OUT / "results.json"
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
