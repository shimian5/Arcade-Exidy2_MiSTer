-- Bounded native Side Trak reference. All bus observation uses passive taps;
-- the script never reads the side-effecting $5103 latch itself.
local m = manager.machine
local screen = m.screens[":screen"]
local cpu = m.devices[":maincpu"]
local prog = cpu and cpu.spaces["program"] or nil
local state = cpu and cpu.state or nil
local bus = io.open("bus.csv", "w")
local events = io.open("events.log", "w")
local counts, taps, rom_counts = {}, {}, {}
local frame, target = 0, 3600

local function fail(message)
	if events then events:write("ERROR " .. tostring(message) .. "\n"); events:flush() end
	m:exit()
end

if not screen or not cpu or not prog or not bus or not events then
	fail("missing screen, maincpu program space, or output files")
	return
end

local function state_value(key)
	local ok, value = pcall(function() return state and state[key].value end)
	if not ok or value == nil then return -1 end
	return value
end

local function log(kind, address, data, mask)
	bus:write(string.format("%s,%d,%.9f,%04X,%02X,%X,%04X\n", kind,
		screen:frame_number(), m.time:as_double(), address, data, mask,
		state_value("PC") & 0xffff))
	local key = string.format("%s_%04X", kind, address)
	counts[key] = (counts[key] or 0) + 1
end

local function normalize(address)
	if address >= 0x5000 and address <= 0x503f then return 0x5000 end
	if address >= 0x5040 and address <= 0x507f then return 0x5040 end
	if address >= 0x5080 and address <= 0x50bf then return 0x5080 end
	if address >= 0x50c0 and address <= 0x50ff then return 0x50c0 end
	if address >= 0x5100 and address <= 0x51ff then return address & (~0x00fc) end
	return address
end

bus:write("kind,frame,time_s,address,data,mask,pc\n")
events:write(string.format("set=%s version=%s source=pinned-mame-0.288\n", m.system.name, emu.app_version()))
events:write(string.format("screen=%s refresh=%s frame_period=%s target_frame=%d\n", screen.tag, tostring(screen.refresh), tostring(screen.frame_period), target))
events:write("taps=passive actual CPU transactions; no scripted memory reads; $5103 observed only on real CPU reads\n")

local function log_fields(porttag)
	local port = m.ioport.ports[porttag]
	if not port then events:write("port_missing tag=" .. porttag .. "\n"); return end
	events:write(string.format("port_default tag=%s value=%02X active=%02X\n", porttag, port:read(), port.active))
	local names = {}
	for name in pairs(port.fields) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local f = port.fields[name]
		events:write(string.format("input_field port=%s name=%q mask=%02X default=%02X live=%02X impulse=%s\n",
			porttag, name, f.mask, f.defvalue, port:read() & f.mask, tostring(f.impulse)))
	end
end
for _, tag in ipairs({":DSW", ":IN0", ":IN2", ":INTSOURCE"}) do log_fields(tag) end

local function field(porttag, name)
	local port = m.ioport.ports[porttag]
	return port and port.fields[name] or nil
end
local coin = field(":IN0", "Coin 1")
local start1 = field(":IN0", "1 Player Start")
local right = field(":IN0", "P1 Right")
local left = field(":IN0", "P1 Left")
local up = field(":IN0", "P1 Up")
local down = field(":IN0", "P1 Down")
local fire = field(":IN0", "P1 Button 1")
if not coin or not start1 or not right or not left or not up or not down or not fire then
	fail(string.format("required Side Trak input field missing coin=%s start=%s right=%s left=%s up=%s down=%s fire=%s",
		tostring(coin ~= nil), tostring(start1 ~= nil), tostring(right ~= nil), tostring(left ~= nil),
		tostring(up ~= nil), tostring(down ~= nil), tostring(fire ~= nil)))
	return
end

local function pulse(f, label, value)
	f:set_value(value)
	events:write(string.format("input frame=%d field=%s active=%s raw=%d\n", frame, label, tostring(value ~= 0), value))
end

taps[#taps + 1] = prog:install_write_tap(0x5000, 0x5213, "sidetrak_control_audio_write", function(offset, data, mask)
	local a = normalize(offset)
	if (a >= 0x5000 and a <= 0x50c0) or (a >= 0x5100 and a <= 0x5103) or (a >= 0x5200 and a <= 0x5213) then
		log("W", a, data, mask)
	end
end)
taps[#taps + 1] = prog:install_read_tap(0x5100, 0x51ff, "sidetrak_input_status_read", function(offset, data, mask)
	local a = normalize(offset)
	if a == 0x5100 or a == 0x5101 or a == 0x5103 then log("R", a, data, mask) end
end)
taps[#taps + 1] = prog:install_read_tap(0x4800, 0x4fff, "sidetrak_character_window_read", function(offset, data, mask)
	local a = offset & 0xffff
	rom_counts[a] = (rom_counts[a] or 0) + 1
	if a < 0x4c00 then log("C", a, data, mask) end
end)
taps[#taps + 1] = prog:install_read_tap(0x0800, 0x3fff, "sidetrak_program_window_read", function(offset)
	local a = offset & 0xffff
	rom_counts[a] = (rom_counts[a] or 0) + 1
end)
_G.side_trak_reference_taps = taps

local function snapshot(f)
	local name = string.format("sidetrak_frame_%06d.png", f)
	local result = screen:snapshot(name)
	events:write(string.format("snapshot frame=%d time_s=%.9f file=%s result=%s\n", f, m.time:as_double(), name, tostring(result)))
end

local snap_frames = { [120]=true, [600]=true, [1200]=true, [1800]=true, [2400]=true, [3000]=true, [3600]=true }
emu.register_frame_done(function()
	local ok, err = pcall(function()
		frame = screen:frame_number()
		-- One credit/start and short independent control pulses; values nonzero are active.
		if frame == 60 then pulse(coin, "Coin 1", 1) end
		if frame == 70 then pulse(coin, "Coin 1", 0) end
		if frame == 120 then pulse(start1, "1 Player Start", 1) end
		if frame == 150 then pulse(start1, "1 Player Start", 0) end
		if frame == 240 then pulse(right, "P1 Right", 1) end
		if frame == 360 then pulse(right, "P1 Right", 0); pulse(fire, "P1 Button 1", 1) end
		if frame == 480 then pulse(fire, "P1 Button 1", 0); pulse(left, "P1 Left", 1) end
		if frame == 600 then pulse(left, "P1 Left", 0); pulse(up, "P1 Up", 1) end
		if frame == 720 then pulse(up, "P1 Up", 0); pulse(down, "P1 Down", 1) end
		if frame == 840 then pulse(down, "P1 Down", 0) end
		if frame == 60 or frame == 70 or frame == 120 or frame == 150 or frame == 240 or frame == 360
			or frame == 480 or frame == 600 or frame == 720 or frame == 840 then
			events:write(string.format("frame_state frame=%d time_s=%.9f pc=%04X IN0=%02X DSW=%02X\n", frame,
				m.time:as_double(), state_value("PC") & 0xffff,
				m.ioport.ports[":IN0"]:read(), m.ioport.ports[":DSW"]:read()))
		end
		if snap_frames[frame] then snapshot(frame) end
		if frame >= target then
			events:write(string.format("complete frame=%d time_s=%.9f pc=%04X\n", frame, m.time:as_double(), state_value("PC") & 0xffff))
		local keys = {}; for k in pairs(counts) do keys[#keys + 1] = k end; table.sort(keys)
		for _, k in ipairs(keys) do events:write(string.format("count %s=%d\n", k, counts[k])) end
		local addresses = {}; for a in pairs(rom_counts) do addresses[#addresses + 1] = a end; table.sort(addresses)
		local seen = 0; for _, a in ipairs(addresses) do if a >= 0x4800 and a <= 0x4bff then seen = seen + 1 end end
		events:write(string.format("character_rom_unique_addresses_read=%d\n", seen))
		bus:flush(); bus:close(); events:flush(); events:close(); m:exit()
		end
	end)
	if not ok then fail("frame callback: " .. tostring(err)) end
end)
