#!/usr/bin/env python3
"""Synthetic guard for cross-CPU timestamp regressions in PIA event pairing."""

import unittest

from tools.pia_firmware_timing.analyze_capture import first_callback_order_read


class CallbackOrderTests(unittest.TestCase):
    def test_callback_rows_win_over_regressing_cpu_local_timestamps(self) -> None:
        read_before_write = {"row": 10, "time": 1.25, "data": 0x40}
        write = {"row": 11, "time": 1.00, "data": 0x00}
        read_after_write = {"row": 12, "time": 1.01, "data": 0x00}
        following_write_row = 13

        chosen = first_callback_order_read(
            [read_before_write, read_after_write], write["row"], following_write_row
        )

        self.assertIs(chosen, read_after_write)
        self.assertLess(read_before_write["row"], write["row"])
        self.assertGreater(read_before_write["time"], write["time"])


if __name__ == "__main__":
    unittest.main()
