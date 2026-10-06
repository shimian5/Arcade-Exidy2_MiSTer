import unittest

from contract import (
    CVSD_BYTES, CVSD_OFFSETS, CVSD_PART_BYTES, INDEX_FAX_QUESTIONS,
    INDEX_LEGACY, INDEX_MOUSETRAP_CVSD, Q_BANK_BYTES, fax_bank_select,
    mame_question_region_offset, question_address, question_bank_state,
    question_store_read_offset, transfer_memory, extended_session_ready,
    transfer_addresses_are_contiguous,
    starts_legacy_session,
)


class ExpansionContractTests(unittest.TestCase):
    def test_question_window_boundaries_and_distinct_banks(self):
        self.assertEqual(question_address(0, 0x2000), 0)
        self.assertEqual(question_address(0, 0x3fff), Q_BANK_BYTES - 1)
        self.assertEqual(question_address(1, 0x2000), Q_BANK_BYTES)
        self.assertEqual(question_address(23, 0x3fff), 24 * Q_BANK_BYTES - 1)
        self.assertNotEqual(question_address(0, 0x2000), question_address(1, 0x2000))
        with self.assertRaises(ValueError):
            question_address(0, 0x4000)
        slots = [question_store_read_offset("fax2", bank, 0x2000) for bank in range(24)]
        self.assertEqual(slots, [bank * Q_BANK_BYTES for bank in range(24)])
        self.assertEqual(len(set(slots)), 24)  # no bank-address collisions
        self.assertIsNone(question_store_read_offset("fax2", 24, 0x2000))

    def test_fax_control_aliases_and_holes_are_distinguished(self):
        self.assertEqual([fax_bank_select(x) for x in (0, 1, 22, 23, 24, 31, 0xff)], [0, 1, 22, 23, 24, 31, 31])
        self.assertEqual(question_bank_state("fax", 21), "populated")
        self.assertEqual(question_bank_state("fax", 22), "in-region-empty")
        self.assertEqual(question_bank_state("fax", 23), "in-region-empty")
        self.assertEqual(question_bank_state("fax", 24), "out-of-region-unpopulated")
        self.assertEqual(question_bank_state("fax2", 23), "populated")
        self.assertEqual(question_bank_state("fax2", 24), "out-of-region-unpopulated")
        self.assertEqual(question_store_read_offset("fax", 22, 0x2000), None)
        self.assertEqual(question_store_read_offset("fax", 24, 0x3fff), None)
        self.assertEqual(question_store_read_offset("fax2", 23, 0x2000), 23 * Q_BANK_BYTES)

    def test_mame_pointer_and_transfer_compatibility_boundaries(self):
        self.assertEqual(mame_question_region_offset(0, 0), 0x10000)
        self.assertEqual(mame_question_region_offset(23, 0x1fff), 0x3ffff)
        self.assertEqual(transfer_memory(INDEX_LEGACY, 0x14960), ("legacy-selector", 0x14960))
        self.assertEqual(transfer_memory(INDEX_FAX_QUESTIONS, 0), ("question-store", 0))
        self.assertEqual(transfer_memory(INDEX_FAX_QUESTIONS, 24 * Q_BANK_BYTES), None)
        self.assertEqual(transfer_memory(INDEX_MOUSETRAP_CVSD, 0), ("cvsd-store", 0))
        self.assertEqual(transfer_memory(INDEX_MOUSETRAP_CVSD, CVSD_BYTES - 1), ("cvsd-store", CVSD_BYTES - 1))
        self.assertEqual(transfer_memory(INDEX_MOUSETRAP_CVSD, CVSD_BYTES), None)

    def test_cvsd_chip_rotation_and_16k_capacity(self):
        ordered = [(0x0000, "mta_2a.2a"), (0x1000, "mta_3a.3a"), (0x2000, "mta_4a.4a"), (0x3000, "mta_1a.1a")]
        self.assertEqual(tuple(x[0] for x in ordered), CVSD_OFFSETS)
        self.assertEqual(len(ordered) * CVSD_PART_BYTES, CVSD_BYTES)
        self.assertEqual(ordered[-1][1], "mta_1a.1a")  # chip label order is not byte-address order

    def test_extended_session_requires_valid_base_and_complete_contiguous_streams(self):
        required = {0: 0x18000, INDEX_FAX_QUESTIONS: 24 * Q_BANK_BYTES}
        self.assertFalse(extended_session_ready(True, False, required, {0: 0x18000, INDEX_FAX_QUESTIONS: 24 * Q_BANK_BYTES}))
        self.assertFalse(extended_session_ready(True, True, required, {INDEX_FAX_QUESTIONS: 24 * Q_BANK_BYTES}))
        self.assertFalse(extended_session_ready(True, True, required, {0: 0x17fff, INDEX_FAX_QUESTIONS: 24 * Q_BANK_BYTES}))
        self.assertTrue(extended_session_ready(True, True, required, required.copy()))
        self.assertFalse(extended_session_ready(False, True, required, required.copy()))
        self.assertTrue(transfer_addresses_are_contiguous([0, 1, 2, 3], 4))
        for bad in ([0, 2, 3], [0, 1, 1, 3], [0, 1, 2, 4], [0, 1, 2, 3, 4]):
            self.assertFalse(transfer_addresses_are_contiguous(bad, 4))

    def test_extended_to_legacy_loader_order_clears_stale_readiness(self):
        # The local loader sends legacy index 0 before index 1. Completion of the
        # prior extended session must leave no armed marker to misclassify this base.
        actions = [starts_legacy_session(index, extended_marker_for_current_mra=False) for index in (0, 1)]
        self.assertEqual(actions, [True, True])
        self.assertFalse(starts_legacy_session(0, extended_marker_for_current_mra=True))


if __name__ == "__main__":
    unittest.main()
