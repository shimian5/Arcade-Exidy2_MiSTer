-- Zero-input Venture startup diagnostic. Writes only passive taps and snapshots.
local m = manager.machine
local screen = m.screens[":screen"]
local cpu = m.devices[":maincpu"]
local audio_cpu = m.devices[":soundbd:audiocpu"]
local prog = cpu and cpu.spaces["program"] or nil
local state = cpu and cpu.state or nil
local audio_state = audio_cpu and audio_cpu.state or nil
local bus = io.open("bus.csv", "w")
local events = io.open("events.log", "w")
local ram_csv = io.open("ram_writes_early.csv", "w")
local taps, counts, ram_counts, ram_unique = {}, {}, {}, {}
local frame = 0
local target = 3600
local input_flag = io.open("attract-input.flag", "r")
local probe_mode = "zero-input"
if input_flag then
	local v = input_flag:read("*a")
	if v == "coin-start-right-fire\n" then probe_mode = "right-and-fire"
	elseif v == "coin-start-right-only\n" then probe_mode = "right-only" end
	input_flag:close()
end
local active_probe = probe_mode ~= "zero-input"
local fire_probe = probe_mode == "right-and-fire"

local function fail(s)
	if events then events:write("ERROR " .. tostring(s) .. "\n"); events:flush() end
	m:exit()
end

if not screen or not cpu or not prog or not bus or not events then
	fail("missing screen, CPU, program space or output")
	return
end
if ram_csv then ram_csv:write("frame,time_s,address,data,pc\n") end

local function reg(s, key)
	local ok, value = pcall(function() return s and s[key].value end)
	if not ok or value == nil then return -1 end
	return value
end

local function log_bus(kind, address, data, mask)
	local pc = reg(state, "PC")
	bus:write(string.format("%s,%d,%.9f,%04X,%02X,%X,%04X\n",
		kind, screen:frame_number(), m.time:as_double(), address, data, mask, pc & 0xffff))
	local key = string.format("%s_%04X", kind, address)
	counts[key] = (counts[key] or 0) + 1
end

bus:write("kind,frame,time_s,address,data,mask,pc\n")
events:write(string.format("set=%s emulator=%s %s input_mode=%s\n", m.system.name, emu.app_name(), emu.app_version(), probe_mode))
events:write(string.format("screen=%s refresh=%s frame_period=%s target_frame=%d\n",
	screen.tag, tostring(screen.refresh), tostring(screen.frame_period), target))
events:write("probe=passive actual reads/writes only; no reads of side-effecting 5103 from script\n")
if active_probe then
	events:write("input_schedule=coin1 active 2100-2109; start1 active 2160-2189; right active 2400-2519\n")
	if fire_probe then events:write("button1 active 2400-2519\n") end
end
events:write(string.format("reset_vector_readonly=%02X%02X\n", prog:read_u8(0xfffd), prog:read_u8(0xfffc)))

for _, porttag in ipairs({ ":DSW", ":IN0", ":IN2" }) do
	local port = m.ioport.ports[porttag]
	if port then
		events:write(string.format("port_default tag=%s value=%02X active=%02X\n", porttag, port:read(), port.active))
		local names = {}
		for name in pairs(port.fields) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local f = port.fields[name]
			local live = port:read() & f.mask
			events:write(string.format("field_default port=%s name=%q mask=%02X def=%02X live=%02X impulse=%s\n",
				porttag, name, f.mask, f.defvalue, live, tostring(f.impulse)))
		end
	end
end

local write_tap = prog:install_write_tap(0x5000, 0x5213, "venture_startup_control_w",
	function(offset, data, mask)
		if (offset >= 0x5000 and offset <= 0x50ff)
			or (offset >= 0x5100 and offset <= 0x51ff)
			or (offset >= 0x5200 and offset <= 0x5213) then
			log_bus("W", offset & 0xffff, data, mask)
		end
	end)
taps[#taps + 1] = write_tap
taps[#taps + 1] = prog:install_read_tap(0x5100, 0x51ff, "venture_startup_control_r",
	function(offset, data, mask)
		local a = offset & 0xffff
		if a == 0x5100 or a == 0x5101 or a == 0x5103 then log_bus("R", a, data, mask) end
	end)
taps[#taps + 1] = prog:install_read_tap(0x5200, 0x520f, "venture_startup_pia_r",
	function(offset, data, mask) log_bus("R", offset, data, mask) end)

local function ram_tap(lo, hi, name)
	taps[#taps + 1] = prog:install_write_tap(lo, hi, name, function(offset, data, mask)
		local a = offset & 0xffff
		local page = a >> 8
		ram_counts[page] = (ram_counts[page] or 0) + 1
		ram_unique[page] = ram_unique[page] or {}
		ram_unique[page][a] = true
		if frame <= 600 then
			if ram_csv then ram_csv:write(string.format("%d,%.9f,%04X,%02X,%04X\n", frame, m.time:as_double(), a, data, reg(state, "PC") & 0xffff)) end
		end
	end)
end
ram_tap(0x0000, 0x03ff, "venture_startup_zeropage_w")
ram_tap(0x4000, 0x43ff, "venture_startup_videoram_w")
ram_tap(0x4800, 0x4fff, "venture_startup_characterram_w")
_G.venture_startup_taps = taps

local function snap(f)
	local file = string.format("venture_startup_%06d.png", f)
	local err = screen:snapshot(file)
	events:write(string.format("snapshot frame=%d time_s=%.9f file=%s result=%s\n", f, m.time:as_double(), file, tostring(err)))
end

local function port_value(tag)
	local p = m.ioport.ports[tag]
	return p and p:read() or -1
end

local function field(tag, name)
	local port=m.ioport.ports[tag]
	return port and port.fields[name] or nil
end
local coin=field(":IN0", "Coin 1")
local start1=field(":IN0", "1 Player Start")
local right=field(":IN0", "P1 Right")
local button=field(":IN0", "P1 Button 1")
if active_probe and (not coin or not start1 or not right or not button) then fail("probe input field missing"); return end
local function inject(f, name, value)
	f:set_value(value)
	events:write(string.format("input frame=%d field=%s active=%s value=%d\n", frame, name, tostring(value ~= 0), value))
end

emu.register_frame_done(function()
	local ok, err = pcall(function()
		frame = screen:frame_number()
		if active_probe then
			if frame == 2100 then inject(coin, "Coin 1", 1) end
			if frame == 2110 then inject(coin, "Coin 1", 0) end
			if frame == 2160 then inject(start1, "1 Player Start", 1) end
			if frame == 2190 then inject(start1, "1 Player Start", 0) end
			if frame == 2400 then inject(right, "P1 Right", 1); if fire_probe then inject(button, "P1 Button 1", 1) end end
			if frame == 2520 then inject(right, "P1 Right", 0); if fire_probe then inject(button, "P1 Button 1", 0) end end
		end
		if frame % 60 == 0 then
			local p6, p7, p8, p9 = prog:read_u8(0x0006), prog:read_u8(0x0007), prog:read_u8(0x0008), prog:read_u8(0x0009)
			events:write(string.format("sample frame=%d time_s=%.9f pc=%04X p=%02X a=%02X x=%02X y=%02X sp=%02X ptr06_09=%02X%02X-%02X%02X DSW=%02X IN0=%02X IN2=%02X audio_pc=%04X\n",
				frame, m.time:as_double(), reg(state,"PC") & 0xffff, reg(state,"P") & 0xff,
				reg(state,"A") & 0xff, reg(state,"X") & 0xff, reg(state,"Y") & 0xff, reg(state,"SP") & 0xff,
				p7, p6, p9, p8, port_value(":DSW"), port_value(":IN0"), port_value(":IN2"), reg(audio_state,"PC") & 0xffff))
		end
		if frame == 600 or frame == 1200 or frame == 1800 or frame == 2100 or frame == 2110
			or frame == 2160 or frame == 2190 or frame == 2250 or frame == 2400 or frame == 2460 or frame == 2520
			or frame == 2700 or frame == 3000 or frame == 3600 then snap(frame) end
		if frame >= target then
			events:write(string.format("complete frame=%d time_s=%.9f pc=%04X\n", frame, m.time:as_double(), reg(state,"PC") & 0xffff))
			local pages={}; for page in pairs(ram_counts) do pages[#pages+1]=page end; table.sort(pages)
			for _,page in ipairs(pages) do
				local count=ram_counts[page]
				local n=0; for _ in pairs(ram_unique[page]) do n=n+1 end
				events:write(string.format("ram_writes page=%02X count=%d unique_addresses=%d\n",page,count,n))
			end
			local keys={}; for k in pairs(counts) do keys[#keys+1]=k end; table.sort(keys)
			for _,k in ipairs(keys) do events:write(string.format("count %s=%d\n",k,counts[k])) end
			bus:flush(); bus:close(); events:flush(); events:close(); if ram_csv then ram_csv:flush(); ram_csv:close() end; m:exit()
		end
	end)
	if not ok then fail("frame callback: " .. tostring(err)) end
end)
