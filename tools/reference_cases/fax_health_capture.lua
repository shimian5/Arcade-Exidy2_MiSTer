-- Add passive CPU progress/interrupt diagnostics to the existing Free Play run.
-- All output remains ignored; no ROM/program/bank state is modified.
local m = manager.machine
local cpu = assert(m.devices[":maincpu"])
local space = assert(cpu.spaces["program"])
local output = assert(io.open(assert(os.getenv("FAX_HEALTH_OUT")), "w"))
local base_script = assert(os.getenv("FAX_HEALTH_BASE_SCRIPT"))
local vector_reads = { [0xfffa] = 0, [0xfffb] = 0, [0xfffe] = 0, [0xffff] = 0 }
local taps = {}
-- Diagnostic experiment only: the startup branch tests IN3 bit 2 before
-- enabling IRQs. Default captures preserve MAME's declared idle input.
if os.getenv("FAX_HEALTH_FORCE_STARTUP_BIT2_LOW") == "1" then
    taps[#taps + 1] = space:install_read_tap(0x1c00, 0x1c00, "fax_health_diagnostic_bit2",
        function(offset, data, mask) return data & 0xfb end)
end
local function state(name)
    local reg = assert(cpu.state[name], "missing CPU state " .. name)
    return reg.value
end
for _, address in ipairs({0xfffa, 0xfffb, 0xfffe, 0xffff}) do
    local a = address
    taps[#taps + 1] = space:install_read_tap(a, a, "fax_health_vector_" .. a,
        function(offset, data, mask) vector_reads[a] = vector_reads[a] + 1 end)
end
_G.fax_health_taps = taps
output:write("frame,pc,p,sp,pointer07,bank0d,skip13,done06,group83,group84,nmi_lo_reads,nmi_hi_reads,irq_lo_reads,irq_hi_reads\n")
emu.register_frame_done(function()
    local frame = m.screens[":screen"]:frame_number()
    if frame % 60 == 0 then
        output:write(string.format("%d,%04X,%02X,%02X,%04X,%02X,%02X,%02X,%02X,%02X,%d,%d,%d,%d\n",
            frame, state("PC") & 0xffff, state("P") & 0xff, state("SP") & 0xff,
            space:read_u8(7) | (space:read_u8(8) << 8), space:read_u8(0x0d), space:read_u8(0x13),
            space:read_u8(6), space:read_u8(0x83), space:read_u8(0x84),
            vector_reads[0xfffa], vector_reads[0xfffb], vector_reads[0xfffe], vector_reads[0xffff]))
        output:flush()
    end
end)
dofile(base_script)
