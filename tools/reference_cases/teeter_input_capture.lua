local m = manager.machine
local space = m.devices[":maincpu"].spaces["program"]
local dialport = m.ioport.ports[":DIAL"]
local in0 = m.ioport.ports[":IN0"]
local dial = dialport:field(0xff)
local out = assert(io.open(os.getenv("AUD_OUT"), "w"))
out:write("frame,dial_port,in0_port,tap_data\n")
local frame = 0
local tapped = -1
_G.teeter_read_tap = space:install_read_tap(0x5101, 0x5101, "teeter_in0", function(offset, data, mask)
  tapped = data & 0xff
  return data
end)
emu.register_frame_done(function()
  frame = frame + 1
  if frame == 20 then dial:set_value(1) end
  if frame == 30 then dial:set_value(0x80) end
  if frame == 40 then dial:set_value(0x00) end
  if frame == 50 then dial:set_value(0x7f) end
  if frame == 60 then dial:set_value(0xff) end
  if frame % 2 == 0 then
    local d = dialport:read() & 0xff
    local v = in0:read() & 0xff
    out:write(frame, ",", string.format("%02x,%02x,%02x", d, v, tapped), "\n")
  end
  if frame >= 100 then out:close(); m:exit() end
end)
