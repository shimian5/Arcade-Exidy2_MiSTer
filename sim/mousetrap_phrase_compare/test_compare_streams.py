import csv
import unittest
from pathlib import Path

from compare_streams import compare, load_native


class PhraseCompareTests(unittest.TestCase):
    def test_native_riots_pa_aliases_resolve_with_a2_timer_guard(self):
        capture = Path(__file__).resolve().parents[2] / "simulation" / "mousetrap_phrase_compare" / "test-native-aliases.csv"
        created_output_dir = not capture.parent.exists()
        capture.parent.mkdir(parents=True, exist_ok=True)
        try:
            with capture.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow(("kind", "bus", "frame", "time_s", "pc", "address", "data", "mask"))
                for i, offset in enumerate((0x01, 0x09, 0x11, 0x19)):
                    writer.writerow(("W", "audio", 1, f"{1.0 + i / 10:.1f}", "1111", f"{0x800 + offset:04X}", "1F", "FF"))
                for i, offset in enumerate((0x00, 0x08, 0x10, 0x18)):
                    writer.writerow(("W", "audio", 1, f"{2.0 + i / 10:.1f}", "2222", f"{0x800 + offset:04X}", "EF", "FF"))
                # A2 selects timer registers even when low A1:A0 resembles PA.
                for i, offset in enumerate((0x04, 0x14, 0x1C)):
                    writer.writerow(("W", "audio", 1, f"{3.0 + i / 10:.1f}", "3333", f"{0x800 + offset:04X}", "55", "FF"))
            _digits, callbacks = load_native(capture)
        finally:
            capture.unlink(missing_ok=True)
            if created_output_dir:
                capture.parent.rmdir()
        self.assertEqual([row["register"] for row in callbacks], ["DDRA"] * 4 + ["ORA"] * 4)
        self.assertEqual([row["resolved_pa"] for row in callbacks], [0xE0] * 4 + [0xEF] * 4)

    def test_comparison_consumes_entire_shorter_ordered_stream(self):
        native = [
            {"port": 0xEF, "bit": 0, "time_ps": 50_000_000, "frame": 1, "pc": "0001", "row": 2, "clock": 0},
            {"port": 0xDF, "bit": 1, "time_ps": 110_000_000, "frame": 1, "pc": "0002", "row": 3, "clock": 1},
            {"port": 0xEF, "bit": 0, "time_ps": 170_000_000, "frame": 1, "pc": "0003", "row": 4, "clock": 1},
        ]
        production = [
            {"port": 0xEF, "bit": 0, "time_ps": 88_000_000, "row": 2, "clock": 0},
            {"port": 0xDF, "bit": 1, "time_ps": 148_000_000, "row": 3, "clock": 1},
        ]
        result = compare(native, production)
        self.assertEqual(result["ordered_matching_prefix"], 2)
        self.assertEqual(result["native_uncompared_tail"], 1)
        self.assertFalse(result["complete_stream_equality"])
        self.assertEqual(result["cadence"]["aligned_prefix"]["exact_interval_matches"], 1)
        self.assertEqual(result["clock_phase"]["matching_levels"], 2)

    def test_negative_control_reports_first_ordered_mismatch(self):
        native = [{"port": 0xEF, "bit": 0, "time_ps": 1, "clock": 0}]
        production = [{"port": 0xEF, "bit": 1, "time_ps": 1, "clock": 0}]
        result = compare(native, production)
        self.assertEqual(result["ordered_matching_prefix"], 0)
        self.assertEqual(result["first_ordered_mismatch"]["index_one_based"], 1)
        self.assertFalse(result["complete_stream_equality"])


if __name__ == "__main__":
    unittest.main()
