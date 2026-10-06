-- Deterministic MAME 0.288 Exidy reference tap.
-- Run from a per-run output directory with -autoboot_script pointing here.
-- It records actual CPU bus taps and screen frames; it does not alter memory.
local m = manager.machine
local setname = m.system.name
local screen = m.screens[":screen"]
local cpu = m.devices[":maincpu"]
local prog = cpu and cpu.spaces["program"] or nil
local state = cpu and cpu.state or nil
local audio_cpu = m.devices[":soundbd:audiocpu"]
local audio_state = audio_cpu and audio_cpu.state or nil
local trace = io.open("bus.csv", "w")
local events = io.open("events.log", "w")
local counts = {}
local taps = {}
local frame = 0
local max_frame = (setname == "venture") and 900 or 3600
local snapshots = {}

local function fail(message)
	if events then
		events:write("ERROR " .. tostring(message) .. "\n")
		events:flush()
	end
	m:exit()
end

if not screen or not cpu or not prog or not trace or not events then
	fail("missing required screen, maincpu program space, or output file")
	return
end

local function pc_value()
	local e = state and state["PC"]
	return e and e.value or -1
end

local function reg_string(s, key, format)
	local ok, value = pcall(function() return s and s[key].value end)
	if not ok or value == nil then return "na" end
	return format and string.format(format, value) or tostring(value)
end

local function log_bus(kind, offset, data, mask)
	local f = screen:frame_number()
	local pc = pc_value()
	local t = m.time:as_double()
	trace:write(string.format("%s,%d,%.9f,%04X,%02X,%X,%04X\n",
		kind, f, t, offset, data, mask, pc & 0xffff))
	local key = string.format("%s_%04X", kind, offset)
	counts[key] = (counts[key] or 0) + 1
end

trace:write("kind,frame,time_s,address,data,mask,pc\n")
events:write(string.format("set=%s version=%s source=official-mame0288\n",
        setname, "0.288 (mame0288)"))
events:write(string.format("screen=%s refresh=%s frame_period=%s\n",
	screen.tag, tostring(screen.refresh), tostring(screen.frame_period)))
events:write("taps=maincpu writes 5000-5213; actual reads 5100/5101/5103 and venture PIA 5200-520f; no synthetic memory reads\n")

local function log_state_names(label, s)
	if not s then events:write("state=" .. label .. " unavailable\n"); return end
	local keys = {}
	for key in pairs(s) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local ok, value = pcall(function() return s[key].value end)
		if ok then events:write(string.format("state_name cpu=%s key=%s value=%s\n", label, key, tostring(value))) end
	end
end
log_state_names("maincpu", state)
log_state_names("audiocpu", audio_state)

-- Exidy video/audio control space and coordinate/selection writes. The
-- 0x5103 read tap is passive and only observes the game's real acknowledge.
local function normalize(offset)
	if offset >= 0x5000 and offset <= 0x50ff then
		if offset < 0x5040 then return 0x5000 end
		if offset < 0x5080 then return 0x5040 end
		if offset < 0x50c0 then return 0x5080 end
		return 0x50c0
	elseif offset >= 0x5100 and offset <= 0x51ff then
		return offset & (~0x00fc)
	end
	return offset
end

taps[#taps + 1] = prog:install_write_tap(0x5000, 0x5213, "exidy_ref_w", function(offset, data, mask)
	if offset == 0x5000 or offset == 0x5040 or offset == 0x5080 or offset == 0x50c0
		or (offset >= 0x5000 and offset <= 0x50ff)
		or (offset >= 0x5100 and offset <= 0x51ff)
		or (offset >= 0x5200 and offset <= 0x5213) then
		log_bus("W", normalize(offset), data, mask)
	end
end)
taps[#taps + 1] = prog:install_read_tap(0x5100, 0x51ff, "exidy_ref_input_r", function(offset, data, mask)
	local base = normalize(offset)
	if base == 0x5100 or base == 0x5101 or base == 0x5103 then log_bus("R", base, data, mask) end
end)
if setname == "venture" then
	local pia_tap = prog:install_read_tap(0x5200, 0x520f, "exidy_ref_pia_r", function(offset, data, mask)
		log_bus("R", offset, data, mask)
	end)
	taps[#taps + 1] = pia_tap
end
-- Keep pass-through subscriptions strongly reachable after the autoboot
-- script returns; otherwise Lua GC can detach the taps mid-run.
_G.exidy_reference_taps = taps

local function field(port_tag, name)
	local port = m.ioport.ports[port_tag]
	return port and port.fields[name] or nil
end

for _, port_tag in ipairs({ ":DSW", ":IN0", ":INTSOURCE", ":IN2" }) do
	local port = m.ioport.ports[port_tag]
	if port then
		local names = {}
		for name in pairs(port.fields) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local f = port.fields[name]
			events:write(string.format("input_field port=%s name=%q mask=%02X\n", port_tag, name, f.mask))
		end
	end
end

local coin = field(":IN0", "Coin 1")
local start1 = field(":IN0", "1 Player Start")
local right = field(":IN0", "P1 Right")
local button = field(":IN0", "P1 Button 1")

if setname == "venture" and (not coin or not start1 or not right or not button) then
	fail(string.format("Venture input field missing coin=%s start=%s right=%s button=%s",
		tostring(coin ~= nil), tostring(start1 ~= nil), tostring(right ~= nil), tostring(button ~= nil)))
	return
end

local function pulse(f, name, at, value)
	if f then f:set_value(value) end
	if events then
		events:write(string.format("input frame=%d time_s=%.9f field=%s value=%d\n",
			at, m.time:as_double(), name, value))
	end
end

local function take_snapshot(f)
	if snapshots[f] then return end
	snapshots[f] = true
	local name = string.format("%s_frame_%06d.png", setname, f)
	local err = screen:snapshot(name)
	events:write(string.format("snapshot frame=%d time_s=%.9f file=%s result=%s\n",
		f, m.time:as_double(), name, tostring(err)))
end

emu.register_frame_done(function()
	local ok, err = pcall(function()
		frame = screen:frame_number()
		if setname == "venture" and frame % 60 == 0 then
			events:write(string.format("state frame=%d time_s=%.9f main_pc=%04X main_p=%s audio_pc=%s\n",
				frame, m.time:as_double(), pc_value() & 0xffff,
				reg_string(state, "P"),
				reg_string(audio_state, "PC", "%04X")))
		end
		if setname == "venture" then
			-- Explicit probe sequence, selected to exercise horizontal movement
			-- and fire after a single coin/start. The forum reporter's precise
			-- hardware timing was not specified.
			if frame == 30 then pulse(coin, "Coin 1", frame, 1) end
			if frame == 60 then pulse(coin, "Coin 1", frame, 0) end
			if frame == 120 then pulse(start1, "1 Player Start", frame, 1) end
			if frame == 150 then pulse(start1, "1 Player Start", frame, 0) end
			if frame == 240 then pulse(right, "P1 Right", frame, 1); pulse(button, "P1 Button 1", frame, 1) end
			if frame == 420 then pulse(right, "P1 Right", frame, 0); pulse(button, "P1 Button 1", frame, 0) end
			if frame == 255 or frame == 270 or frame == 285 or frame == 300 or frame == 360
				or frame == 420 or frame == 600 or frame == 900 then
				take_snapshot(frame)
			end
		else
			-- Pure zero-input attract run; capture a coarse deterministic cadence.
			if frame == 120 or frame == 600 or frame == 1200 or frame == 1800
				or frame == 2400 or frame == 3000 or frame == 3600 then
				take_snapshot(frame)
			end
		end
		if frame >= max_frame then
			events:write(string.format("complete frame=%d time_s=%.9f pc=%04X\n",
				frame, m.time:as_double(), pc_value() & 0xffff))
			local keys = {}
			for key in pairs(counts) do keys[#keys + 1] = key end
		table.sort(keys)
			for _, key in ipairs(keys) do
				events:write(string.format("count %s=%d\n", key, counts[key]))
			end
			trace:flush()
			trace:close()
			events:flush()
			events:close()
			m:exit()
		end
	end)
	if not ok and events then
		events:write("ERROR frame callback: " .. tostring(err) .. "\n")
		events:flush()
		trace:flush()
		m:exit()
	end
end)
