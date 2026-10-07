-- Passive ordered audio-CPU RAM-window access log (read/write taps only).
local m = manager.machine
local cpu = m.devices[":soundbd:audiocpu"] or m.devices[":audiocpu"]
local sp = cpu.spaces["program"]
local f = io.open(os.getenv("AUD_OUT"), "w")
local function w(kind) return function(offset, data, mask) f:write(kind, ",", string.format("%x,%x", offset, data & 0xff), "\n"); return data end end
_G.t1 = sp:install_read_tap(0x0000, 0x07ff, "ar", w("R"))
_G.t2 = sp:install_write_tap(0x0000, 0x07ff, "aw", w("W"))
local frames, limit = 0, tonumber(os.getenv("AUD_FRAMES") or "600")
emu.register_frame_done(function() frames = frames + 1; if frames == limit then f:close(); m:exit() end end)
