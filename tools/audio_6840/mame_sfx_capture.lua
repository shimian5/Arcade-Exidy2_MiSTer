-- Passive capture of audio-CPU writes to the sound-effect ports (timestamped).
local m = manager.machine
local cpu = m.devices[":soundbd:audiocpu"] or m.devices[":audiocpu"]
local sp = cpu.spaces["program"]
local f = io.open(os.getenv("SFX_OUT"), "w")
f:write("time_s,addr,data\n")
local function w(offset, data, mask)
  f:write(string.format("%.9f,%04x,%02x\n", m.time:as_double(), offset, data & 0xff)); return data
end
_G.tap = sp:install_write_tap(0x1800, 0x3fff, "sfx_w", w)
local function field(tag, name) local p = m.ioport.ports[tag]; return p and p.fields[name] or nil end
local coin, start1, right, button = field(":IN0","Coin 1"), field(":IN0","1 Player Start"), field(":IN0","P1 Right"), field(":IN0","P1 Button 1")
local frames, limit = 0, tonumber(os.getenv("SFX_FRAMES") or "3600")
local screen = m.screens[":screen"]
local function set(fl, v) if fl then fl:set_value(v) end end
emu.register_frame_done(function()
  frames = screen:frame_number()
  if os.getenv("SFX_INPUT") then
    local d = tonumber(os.getenv("SFX_START") or "2100")
    if frames == d then set(coin,1) end
    if frames == d+10 then set(coin,0) end
    if frames == d+60 then set(start1,1) end
    if frames == d+90 then set(start1,0) end
    if frames == d+300 then set(right,1); set(button,1) end
    if frames == d+420 then set(right,0); set(button,0) end
  end
  if frames >= limit then f:close(); m:exit() end
end)
