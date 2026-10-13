-- Read only the Side Trak program-map ROM window at $4800-$4fff.
-- This is a debugger-side region probe, not an emulated CPU transaction.
local m = manager.machine
local cpu = m.devices[":maincpu"]
local prog = cpu and cpu.spaces["program"] or nil
local out = io.open("mame-char-window.bin", "wb")
if not prog or not out then
	if out then out:close() end
	m:exit()
	return
end
for address = 0x4800, 0x4fff do
	out:write(string.char(prog:read_u8(address)))
end
out:flush()
out:close()
m:exit()
