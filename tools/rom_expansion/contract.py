"""Pure address/selection model for the proposed Exidy ROM expansion contract."""

Q_BANK_BYTES = 0x2000
Q_FIRST_MAINCPU_OFFSET = 0x10000
Q_BANK_COUNT = 32
Q_POPULATED_FAX = set(range(22))
Q_POPULATED_FAX2 = set(range(24))
Q_IN_REGION_EMPTY_FAX = {22, 23}
Q_OUT_OF_REGION = set(range(24, 32))
CVSD_BYTES = 0x4000
CVSD_PART_BYTES = 0x1000
CVSD_OFFSETS = (0x0000, 0x1000, 0x2000, 0x3000)
INDEX_LEGACY = 0
INDEX_FAX_QUESTIONS = 5
INDEX_MOUSETRAP_CVSD = 6
INDEX_EXPANSION_DESCRIPTOR = 7
FAX_PROFILE_ID = 1
FAX2_PROFILE_ID = 2
MOUSETRAP_PROFILE_ID = 3


def fax_bank_select(value: int) -> int:
    """MAME control write semantics: only D[4:0] select the bank."""
    if not 0 <= value <= 0xff:
        raise ValueError("bank select must be a byte")
    return value & 0x1f


def question_address(bank: int, cpu_address: int) -> int:
    """Return packed address; caller must use question_store_read_offset to guard missing banks."""
    if not 0 <= bank < Q_BANK_COUNT:
        raise ValueError("question bank must be 0..31")
    if not 0x2000 <= cpu_address <= 0x3fff:
        raise ValueError("CPU address must be inside the bank window")
    return bank * Q_BANK_BYTES + (cpu_address - 0x2000)


def question_store_read_offset(setname: str, bank: int, cpu_address: int) -> int | None:
    """Return a physical offset only for a populated bank; None means deterministic fill."""
    if not 0 <= bank < Q_BANK_COUNT:
        raise ValueError("question bank must be 0..31")
    if not 0x2000 <= cpu_address <= 0x3fff:
        raise ValueError("CPU address must be inside the bank window")
    if question_bank_state(setname, bank) != "populated":
        return None
    return question_address(bank, cpu_address)


def mame_question_region_offset(bank: int, window_offset: int) -> int:
    """MAME bank source pointer: maincpu base + 0x10000 + bank*0x2000."""
    if not 0 <= bank < Q_BANK_COUNT or not 0 <= window_offset < Q_BANK_BYTES:
        raise ValueError("invalid bank/window offset")
    return Q_FIRST_MAINCPU_OFFSET + bank * Q_BANK_BYTES + window_offset


def question_bank_state(setname: str, bank: int) -> str:
    if not 0 <= bank < Q_BANK_COUNT:
        raise ValueError("question bank must be 0..31")
    if setname == "fax":
        if bank in Q_POPULATED_FAX:
            return "populated"
        if bank in Q_IN_REGION_EMPTY_FAX:
            return "in-region-empty"
        return "out-of-region-unpopulated"
    if setname == "fax2":
        return "populated" if bank in Q_POPULATED_FAX2 else "out-of-region-unpopulated"
    raise ValueError("setname must be fax or fax2")


def transfer_memory(index: int, address: int) -> tuple[str, int] | None:
    """Decode download streams without changing the old index-0 address map."""
    if address < 0:
        raise ValueError("address must be nonnegative")
    if index == INDEX_LEGACY:
        return ("legacy-selector", address)
    if index == INDEX_FAX_QUESTIONS:
        if address >= 24 * Q_BANK_BYTES:
            return None
        return ("question-store", address)
    if index == INDEX_MOUSETRAP_CVSD:
        if address >= CVSD_BYTES:
            return None
        return ("cvsd-store", address)
    return None


def extended_session_ready(extended_flag: bool, descriptor_valid: bool,
                           required_lengths: dict[int, int], received_lengths: dict[int, int]) -> bool:
    """Ready only when a valid descriptor's every required index arrived at exact length."""
    if not extended_flag or not descriptor_valid or 0 not in required_lengths:
        return False
    return all(received_lengths.get(index) == length for index, length in required_lengths.items())


def transfer_addresses_are_contiguous(addresses: list[int], expected_length: int) -> bool:
    """Reject short, extra, duplicated, reordered, or gapped stream byte addresses."""
    return expected_length >= 0 and addresses == list(range(expected_length))


def starts_legacy_session(index: int, extended_marker_for_current_mra: bool) -> bool:
    """Legacy MRA base/config transfers invalidate stale extension state."""
    return index in (0, 1) and not extended_marker_for_current_mra

