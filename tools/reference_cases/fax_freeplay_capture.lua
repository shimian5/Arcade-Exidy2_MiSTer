-- Passive FAX/FAX 2 bank-select capture under pinned MAME 0.288.
-- Inputs are scripted through MAME's declared controls; the tap observes
-- actual CPU writes and never changes the program space or bank register.
local m = manager.machine
local setname = m.system.name
local cpu = m.devices[":maincpu"]
local space = cpu and cpu.spaces["program"]
local state = cpu and cpu.state
local screen = m.screens[":screen"]
local frames = 0
local limit = tonumber(os.getenv("FAX_CAPTURE_FRAMES") or "7200")
local out = io.open(assert(os.getenv("FAX_BANK_OUT")), "w")
local bus = io.open(assert(os.getenv("FAX_BUS_OUT")), "w")
local events = io.open(assert(os.getenv("FAX_EVENT_OUT")), "w")
local counts = {}
local read_counts = {}
local input_checks = {}
local taps = {}

local function finish_error(message)
	if events then events:write("ERROR " .. tostring(message) .. "\n"); events:flush(); events:close() end
	if out then out:flush(); out:close() end
	if bus then bus:flush(); bus:close() end
	m:exit()
end

if (setname ~= "fax" and setname ~= "fax2") or not space or not out or not bus or not events then
	finish_error("wrong set or missing CPU program space/output")
	return
end

local function field(tag, name)
	local port = m.ioport.ports[tag]
	return port and port.fields[name] or nil
end
local coin = field(":IN0", "Coin 1")
local dsw_port = m.ioport.ports[":DSW"]
local freeplay_dips = {
	field(":DSW", "Bonus Time"),
	field(":DSW", "Game/Bonus Times"),
	field(":DSW", "Coinage")
}
local start1 = field(":IN3", "1 Player Start")
local start2 = field(":IN3", "2 Players Start")
local answers = {
	field(":IN3", "P1 Button 1"), field(":IN3", "P1 Button 2"),
	field(":IN3", "P1 Button 3"), field(":IN3", "P1 Button 4"),
	field(":IN4", "P2 Button 1"), field(":IN4", "P2 Button 2"),
	field(":IN4", "P2 Button 3"), field(":IN4", "P2 Button 4")
}
if not coin or not start1 or not start2 then finish_error("coin/start fields missing"); return end
if not dsw_port then finish_error("DSW port missing"); return end
for i = 1, 3 do
	local f = freeplay_dips[i]
	if not f or f.settings[0] == nil then finish_error("Free Play DIP field or zero setting missing index=" .. i); return end
	f.user_value = 0
	if f.user_value ~= 0 then finish_error("DIP user_value did not take zero for " .. f.name); return end
	events:write(string.format("dip field=%s mask=%02X setting=%s user_value=%02X\n", f.name, f.mask, tostring(f.settings[0]), f.user_value))
end
events:write(string.format("dip verification=freeplay settings set through field.user_value; immediate raw DSW=%02X\n", dsw_port:read() & 0xff))
for i = 1, 8 do if answers[i] == nil then finish_error("answer field missing index=" .. i); return end end

out:write("frame,time_s,pc,data,masked_bank\n")
bus:write("kind,frame,time_s,pc,address,data,mask\n")
events:write(string.format("set=%s frames=%d tap=actual maincpu writes at 2000\n", setname, limit))
events:write("input_taps=DSW at 5100, IN0 at 5101, IRQ status at 5103, P2 answers at 1a00, P1 answers/starts at 1c00; delayed active-low controls\n")

local function pc_value()
	local reg = state and state["PC"]
	return reg and reg.value or -1
end

taps[1] = space:install_write_tap(0x2000, 0x2000, "fax_bank_select_observer", function(offset, data, mask)
	local bank = data & 0x1f
	local frame = m.screens[":screen"]:frame_number()
	out:write(string.format("%d,%.9f,%04X,%02X,%02X\n", frame, m.time:as_double(), pc_value() & 0xffff, data & 0xff, bank))
	bus:write(string.format("W,%d,%.9f,%04X,%04X,%02X,%X\n", frame, m.time:as_double(), pc_value() & 0xffff, offset, data & 0xff, mask))
	counts[bank] = (counts[bank] or 0) + 1
end)
taps[2] = space:install_read_tap(0x2000, 0x3fff, "fax_question_read_observer", function(offset, data, mask)
	local frame = m.screens[":screen"]:frame_number()
	bus:write(string.format("Q,%d,%.9f,%04X,%04X,%02X,%X\n", frame, m.time:as_double(), pc_value() & 0xffff, offset, data & 0xff, mask))
	read_counts.Q = (read_counts.Q or 0) + 1
end)
for _, address in ipairs({ 0x1a00, 0x1c00, 0x5100, 0x5101, 0x5103 }) do
	local a = address
	taps[#taps + 1] = space:install_read_tap(a, a, "fax_answer_input_observer_" .. string.format("%04x", a), function(offset, data, mask)
		local frame = m.screens[":screen"]:frame_number()
		bus:write(string.format("I,%d,%.9f,%04X,%04X,%02X,%X\n", frame, m.time:as_double(), pc_value() & 0xffff, offset, data & 0xff, mask))
		read_counts[a] = (read_counts[a] or 0) + 1
	end)
end
_G.fax_bank_capture_taps = taps

local function drive(f, label, value)
	-- MAME 0.288 ioport_field::set_value stores value != 0 as the asserted
	-- digital state. The port read applies IP_ACTIVE_LOW polarity afterward.
	f:set_value(value)
	local ptag = (label == "Coin 1") and ":IN0" or ((label == "1 Player Start" or label == "2 Players Start" or label:match("^P1 ")) and ":IN3" or ":IN4")
	local port = m.ioport.ports[ptag]
	local mask = f.mask
	local raw = port and (port:read() & 0xff) or 0
	events:write(string.format("input frame=%d time_s=%.6f field=%s asserted=%d mask=%02X immediate_port_%s=%02X\n", frames, m.time:as_double(), label, value, mask or 0, ptag, raw))
	input_checks[#input_checks + 1] = { frame = frames + 1, field = label, tag = ptag, mask = mask, expected = value }
end

local input_schedule = {
	-- Hold each phase long enough to span sparse polling. Keep answer controls
	-- released until after the start request; title code waits for release.
	{ 3700, coin, "Coin 1", 1 }, { 3900, coin, "Coin 1", 0 },
	{ 4000, start1, "1 Player Start", 1 }, { 4500, start1, "1 Player Start", 0 },
	{ 4700, answers[1], "P1 Button 1", 1 }, { 4900, answers[1], "P1 Button 1", 0 },
	{ 5000, answers[2], "P1 Button 2", 1 }, { 5200, answers[2], "P1 Button 2", 0 },
	{ 5300, answers[3], "P1 Button 3", 1 }, { 5500, answers[3], "P1 Button 3", 0 },
	{ 5600, answers[4], "P1 Button 4", 1 }, { 5800, answers[4], "P1 Button 4", 0 },
	{ 5900, coin, "Coin 1", 1 }, { 6100, coin, "Coin 1", 0 },
	{ 6200, start1, "1 Player Start", 1 }, { 6700, start1, "1 Player Start", 0 },
	{ 6800, answers[1], "P1 Button 1", 1 }, { 7000, answers[1], "P1 Button 1", 0 }
}
local scheduled_index = 1

emu.register_frame_done(function()
	local ok, err = pcall(function()
		frames = m.screens[":screen"]:frame_number()
		if frames == 1 then events:write(string.format("dip frame1 raw_DSW=%02X\n", dsw_port:read() & 0xff)) end
		for i = #input_checks, 1, -1 do
			local check = input_checks[i]
			if frames >= check.frame then
				local port = m.ioport.ports[check.tag]
				local raw = port and (port:read() & 0xff) or 0
				local observed = (raw & check.mask) == 0
				events:write(string.format("input_check frame=%d field=%s expected=%d observed=%d mask=%02X port=%02X\n", frames, check.field, check.expected, observed and 1 or 0, check.mask, raw))
				table.remove(input_checks, i)
				if observed ~= (check.expected == 1) then finish_error("active-low input assertion failed at frame=" .. frames .. " field=" .. check.field); return end
			end
		end
		while scheduled_index <= #input_schedule and frames >= input_schedule[scheduled_index][1] do
			local event = input_schedule[scheduled_index]
			if frames == event[1] then drive(event[2], event[3], event[4]) end
			scheduled_index = scheduled_index + 1
		end
		if frames == 1 or frames == 3000 or frames == 3600 or frames == 4200 or frames == 4800 or frames == 5400 or frames == 6000 or frames == 6600 or frames == limit then
			local file = string.format("snapshot_%04d.png", frames)
			local result = screen:snapshot(file)
			events:write(string.format("snapshot frame=%d file=%s result=%s\n", frames, file, tostring(result)))
		end
		if frames >= limit then
			events:write("complete frame=" .. frames .. "\n")
			for bank = 0, 31 do if counts[bank] then events:write(string.format("count bank=%02X writes=%d\n", bank, counts[bank])) end end
			for key, count in pairs(read_counts) do events:write(string.format("reads %s=%d\n", tostring(key), count)) end
			out:flush(); out:close(); bus:flush(); bus:close(); events:flush(); events:close(); m:exit()
		end
	end)
	if not ok then finish_error("frame callback: " .. tostring(err)) end
end)
