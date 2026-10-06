"""Synthetic contract model for Exidy extended ROM downloads and CPU reads.

This is not production RTL or an FPGA transport implementation. Transfer objects
represent the completed byte/address sequence delivered for one MRA <rom> node.
"""
from dataclasses import dataclass

INDEX_BASE = 0
INDEX_OPTIONS_PCB = 1
INDEX_OPTIONS_SHIFT = 2
INDEX_HISCORE_CONFIG = 3
INDEX_NVRAM = 4
INDEX_QUESTIONS = 5
INDEX_CVSD = 6
INDEX_DESCRIPTOR = 7
MARKER = 0x80
Q_BYTES = 24 * 0x2000
CVSD_BYTES = 0x4000

# FAX flags are provisional pending a hardware/profile decision; 0x30 is the
# existing Pepper II/Hard Hat hardware flag. Mouse Trap's current value is 0x10.
PROFILES = {
    1: ("fax", 0x30, (INDEX_BASE, INDEX_QUESTIONS)),
    2: ("fax2", 0x30, (INDEX_BASE, INDEX_QUESTIONS)),
    3: ("mtrap-cvsd", 0x10, (INDEX_BASE, INDEX_CVSD)),
}


class ProtocolError(ValueError):
    pass


@dataclass(frozen=True)
class Descriptor:
    profile_id: int
    required_mask: int
    lengths: dict[int, int]

    @classmethod
    def parse(cls, data: bytes) -> "Descriptor":
        if len(data) != 16 or data[:2] != b"EX" or data[2] != 1:
            raise ProtocolError("descriptor length/magic/version invalid")
        if data[14:16] != b"\0\0":
            raise ProtocolError("descriptor reserved bytes are nonzero")
        profile_id = data[3]
        if profile_id not in PROFILES:
            raise ProtocolError("unknown profile id")
        mask = data[4]
        expected_mask = sum(1 << slot for slot, index in enumerate((INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD))
                            if index in PROFILES[profile_id][2])
        if mask != expected_mask:
            raise ProtocolError("required stream mask does not match profile")
        lengths = {index: int.from_bytes(data[5 + slot * 3:8 + slot * 3], "little")
                   for slot, index in enumerate((INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD))}
        if any((lengths[i] != 0) != (i in PROFILES[profile_id][2]) for i in lengths):
            raise ProtocolError("length fields disagree with required stream mask")
        if lengths[INDEX_BASE] == 0:
            raise ProtocolError("base ROM length must be nonzero")
        if profile_id in (1, 2) and lengths[INDEX_QUESTIONS] != Q_BYTES:
            raise ProtocolError("FAX question stream must be exactly 192 KiB")
        if profile_id == 3 and lengths[INDEX_CVSD] != CVSD_BYTES:
            raise ProtocolError("Mouse Trap CVSD stream must be exactly 16 KiB")
        return cls(profile_id, mask, lengths)


def encode_descriptor(profile_id: int, base_bytes: int) -> bytes:
    """Synthetic-fixture helper. FAX PCB value remains provisional."""
    if profile_id not in PROFILES or base_bytes <= 0 or base_bytes >= 1 << 24:
        raise ProtocolError("invalid profile/base length")
    mask = sum(1 << slot for slot, i in enumerate((INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD))
               if i in PROFILES[profile_id][2])
    lengths = {INDEX_BASE: base_bytes, INDEX_QUESTIONS: 0, INDEX_CVSD: 0}
    if profile_id in (1, 2):
        lengths[INDEX_QUESTIONS] = Q_BYTES
    else:
        lengths[INDEX_CVSD] = CVSD_BYTES
    payload = bytearray(b"EX\x01") + bytes((profile_id, mask))
    for i in (INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD):
        payload.extend(lengths[i].to_bytes(3, "little"))
    payload.extend(b"\0\0")
    return bytes(payload)


@dataclass
class Transfer:
    index: int
    data: bytes
    addresses: tuple[int, ...] | None = None

    def validated_addresses(self) -> tuple[int, ...]:
        addresses = self.addresses if self.addresses is not None else tuple(range(len(self.data)))
        if len(addresses) != len(self.data) or addresses != tuple(range(len(self.data))):
            raise ProtocolError(f"index {self.index} addresses must be contiguous from zero")
        return addresses


class DownloadModel:
    """Models resets/readiness and storage invalidation at complete MRA transfer boundaries."""
    def __init__(self):
        self.reset = False
        self.extended_armed = False
        self.extended_pending = False
        self.expansion_ready = False
        self.descriptor = None
        self.received = {}
        self.storage = {}
        self.base_memory = {}  # index-0 writes persist independently of session metadata
        self.invalid_reason = None
        self.download_active = False

    def begin_transfer(self, index: int):
        if self.download_active:
            raise ProtocolError("nested transfer")
        self.download_active = True
        self.reset = True
        if index == INDEX_OPTIONS_PCB:
            # New MRA generation starts here for expanded MRAs. Legacy MRAs may
            # start with index 0, handled below, per the real loader order.
            self._clear_extension()
        elif index == INDEX_BASE and not self.extended_armed:
            # A new legacy base must never be judged using stale extension state.
            self._clear_extension()
        self._index = index
        self._bytes = bytearray()
        self._addresses = []
        self._transfer_error = None
        self._ignore_due_to_fault = self.invalid_reason is not None and index not in (INDEX_OPTIONS_PCB, INDEX_BASE)

    def write(self, address: int, value: int):
        if not self.download_active:
            raise ProtocolError("write outside transfer")
        if not 0 <= value <= 255 or address != len(self._bytes):
            self._transfer_error = "duplicate/gapped/reordered address or non-byte value"
            return
        self._addresses.append(address)
        self._bytes.append(value)
        if self._index == INDEX_BASE:
            # The live legacy port writes as bytes arrive, even if the MRA is
            # interrupted before an extension descriptor/session is validated.
            self.base_memory[address] = value

    def end_transfer(self):
        if not self.download_active:
            raise ProtocolError("no active transfer")
        self.download_active = False
        index, data = self._index, bytes(self._bytes)
        self.reset = True
        if self._ignore_due_to_fault:
            return
        if self._transfer_error:
            self.invalid_reason = self._transfer_error
            self.extended_pending = self.extended_armed
            self.expansion_ready = False
            self._discard_expansion_payloads()
            return
        try:
            Transfer(index, data, tuple(self._addresses)).validated_addresses()
            if index == INDEX_OPTIONS_PCB:
                if len(data) != 1:
                    raise ProtocolError("index-1 marker must be exactly one byte")
                if data[0] & MARKER:
                    profile_flag = data[0] & 0x7f
                    self.extended_armed = True
                    self.extended_pending = True
                    self._marker_flag = profile_flag
                    self.invalid_reason = None
                else:
                    self._clear_extension()
                    self.reset = False
                    return
            elif index == INDEX_DESCRIPTOR:
                if not self.extended_armed or self.descriptor is not None:
                    raise ProtocolError("descriptor without fresh marker or duplicate descriptor")
                descriptor = Descriptor.parse(data)
                profile_name, expected_flag, _ = PROFILES[descriptor.profile_id]
                if self._marker_flag != expected_flag:
                    raise ProtocolError(f"PCB low bits do not match {profile_name} profile")
                self.descriptor = descriptor
                self.received = {}
                self.storage = {}
                self.invalid_reason = None
            elif index in (INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD):
                if self.extended_armed:
                    if self.invalid_reason is not None:
                        raise ProtocolError("faulted session requires fresh index-1 marker to recover")
                    if self.descriptor is None or index not in self.descriptor.lengths:
                        raise ProtocolError("ROM stream before descriptor or not declared")
                    required_order = [i for i in (INDEX_BASE, INDEX_QUESTIONS, INDEX_CVSD)
                                      if i in PROFILES[self.descriptor.profile_id][2]]
                    next_index = required_order[len(self.received)] if len(self.received) < len(required_order) else None
                    if index != next_index:
                        raise ProtocolError(f"index {index} out of stream order; expected {next_index}")
                    if index not in PROFILES[self.descriptor.profile_id][2]:
                        raise ProtocolError(f"index {index} not declared for this profile")
                    expected = self.descriptor.lengths[index]
                    if len(data) != expected:
                        raise ProtocolError(f"index {index} length {len(data)} != expected {expected}")
                    if index in self.received:
                        raise ProtocolError(f"duplicate index {index}")
                    self.received[index] = len(data)
                    self.storage[index] = data
                    if index == INDEX_BASE:
                        self.storage[index] = data
                    if set(self.received) == {i for i, n in self.descriptor.lengths.items() if n}:
                        self.expansion_ready = True
                        self.extended_pending = False
                        self.extended_armed = False  # active bytes remain ready until next session
                        self.reset = False
                else:
                    # Legacy index 0 is accepted without reinterpretation.
                    if index == INDEX_BASE:
                        self.storage[INDEX_BASE] = data
                        self.reset = False
                        return
                    raise ProtocolError(f"extension index {index} without a fresh session marker")
            elif index in (INDEX_OPTIONS_SHIFT, INDEX_HISCORE_CONFIG, INDEX_NVRAM):
                # These may follow expansion payloads and must not invalidate readiness.
                if self.invalid_reason is not None or self.extended_pending:
                    self.reset = True
                elif self.expansion_ready:
                    self.reset = False
                elif not self.extended_pending:
                    self.reset = False
                return
            else:
                raise ProtocolError(f"unsupported index {index}")
        except ProtocolError as exc:
            self.invalid_reason = str(exc)
            self.expansion_ready = False
            self._discard_expansion_payloads()
            self.extended_pending = self.extended_armed or index in (INDEX_OPTIONS_PCB, INDEX_DESCRIPTOR)
            self.reset = True

    def _clear_extension(self):
        self.extended_armed = False
        self.extended_pending = False
        self.expansion_ready = False
        self.descriptor = None
        self.received = {}
        self._discard_expansion_payloads()
        self.invalid_reason = None

    def _discard_expansion_payloads(self):
        self.storage = {INDEX_BASE: self.storage[INDEX_BASE]} if INDEX_BASE in self.storage else {}


def question_store_offset(bank: int, cpu_address: int) -> int | None:
    if not 0x2000 <= cpu_address <= 0x3fff or not 0 <= bank <= 31:
        raise ValueError("invalid FAX CPU bank/window address")
    if bank >= 24:
        return None  # deterministic fill; actual MAME/hardware parity unresolved
    return bank * 0x2000 + (cpu_address & 0x1fff)


class CpuReadPipeline:
    """Two nonblocking master-clock stages: BRAM Q, then CPU_databus_in register."""
    def __init__(self, memory, fill=0):
        self.memory = memory
        self.fill = fill
        self.bram_q = fill
        self.cpu_databus_in = fill

    def tick(self, address: int) -> int:
        sampled_by_cpu = self.cpu_databus_in
        new_q = self.memory.get(address, self.fill)
        new_cpu_data = self.bram_q
        self.bram_q = new_q
        self.cpu_databus_in = new_cpu_data
        return sampled_by_cpu


def delayed_cpu_read(pipeline: CpuReadPipeline, address: int, clocks: int, enable_period: int = 64) -> int:
    """Change address at a CPU enable; sample at next enable after `enable_period` ticks."""
    if clocks < enable_period:
        raise ValueError("need at least one full CPU enable interval")
    result = pipeline.fill
    for _ in range(clocks):
        result = pipeline.tick(address)
    return result
