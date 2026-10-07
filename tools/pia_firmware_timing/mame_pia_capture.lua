-- Passive MAME 0.288 bus capture for Exidy main/audio PIA firmware traffic.
-- Run from a private per-game working directory; this script never changes
-- emulated memory or forces a PIA signal.
local m = manager.machine
local setname = m.system.name
local screen = m.screens[":screen"]
local maincpu = m.devices[":maincpu"]
local audiocpu = m.devices[":soundbd:audiocpu"]
local mainprog = maincpu and maincpu.spaces["program"]
local audioprog = audiocpu and audiocpu.spaces["program"]
local trace = io.open("pia-bus.csv", "w")
local events = io.open("pia-events.log", "w")
local taps = {}
local counts = {}
local cr = { main = { 0, 0 }, audio = { 0, 0 } }
local frame = 0
local max_frame = 7200

local function finish(message)
	if events then events:write(message .. "\n"); events:flush() end
	if trace then trace:flush(); trace:close(); trace = nil end
	if events then events:close(); events = nil end
	m:exit()
end

if not trace or not events or not screen or not mainprog or not audioprog then
	finish(string.format("ERROR required device/space missing screen=%s main=%s audio=%s",
		tostring(screen ~= nil), tostring(mainprog ~= nil), tostring(audioprog ~= nil)))
	return
end

local function pc(cpu)
	local ok, val = pcall(function() return cpu.state["PC"].value end)
	if ok and val then return val & 0xffff end
	return -1
end

trace:write("cpu,op,frame,time_s,address,reg,kind,data,mask,pc,crA,crB\n")
events:write(string.format("set=%s mame=%s main_clock=master_clock/PH_1 audio=audio_clk/auPH0\n",
	setname, tostring(m.version)))
events:write("scope=passive memory taps; main PIA $5200-$520f; audio PIA $1000-$1003 (mirrored $07fc); no forced bus values\n")

local function record(cpu_name, op, cpu, offset, data, mask)
	local reg = offset & 3
	local n = cpu_name == "main" and "maincpu" or "audiocpu"
	local kind = "other"
	if reg == 1 then
		kind = "CRA"
		if op == "W" then cr[cpu_name][1] = data & 0x3f end
	elseif reg == 3 then
		kind = "CRB"
		if op == "W" then cr[cpu_name][2] = data & 0x3f end
	elseif reg == 0 then
		kind = ((cr[cpu_name][1] & 4) ~= 0) and "PA_DATA" or "DDRA"
	else
		kind = ((cr[cpu_name][2] & 4) ~= 0) and "PB_DATA" or "DDRB"
	end
	local addr = offset
	trace:write(string.format("%s,%s,%d,%.9f,%04X,%d,%s,%02X,%X,%04X,%02X,%02X\n",
		cpu_name, op, screen:frame_number(), m.time:as_double(), addr, reg, kind,
		data & 0xff, mask, pc(cpu), cr[cpu_name][1], cr[cpu_name][2]))
	local key = cpu_name .. "_" .. op .. "_" .. kind
	counts[key] = (counts[key] or 0) + 1
	if op == "W" and (kind == "CRA" or kind == "CRB") then
		events:write(string.format("control cpu=%s op=%s frame=%d time_s=%.9f reg=%s data=%02X ca2_cb2_mode=%d irq_bits=%X pc=%04X\n",
			cpu_name, op, screen:frame_number(), m.time:as_double(), kind, data & 0xff,
			((data >> 3) & 7), data & 3, pc(cpu)))
	end
end

local function install(space, lo, hi, name, cpu)
	taps[#taps + 1] = space:install_write_tap(lo, hi, "pia_fw_" .. name .. "_w", function(offset, data, mask)
		record(name, "W", cpu, offset, data, mask)
	end)
	taps[#taps + 1] = space:install_read_tap(lo, hi, "pia_fw_" .. name .. "_r", function(offset, data, mask)
		record(name, "R", cpu, offset, data, mask)
	end)
end

install(mainprog, 0x5200, 0x520f, "main", maincpu)
install(audioprog, 0x1000, 0x17ff, "audio", audiocpu)
_G.exidy_pia_firmware_taps = taps

local function field(port_tag, name)
	local port = m.ioport.ports[port_tag]
	return port and port.fields[name] or nil
end
local coin = field(":IN0", "Coin 1")
local start = field(":IN0", "1 Player Start")
events:write(string.format("inputs coin=%s start=%s\n", tostring(coin ~= nil), tostring(start ~= nil)))
local function pulse(f, name, value)
	if f then f:set_value(value) end
	events:write(string.format("input frame=%d time_s=%.9f name=%s value=%d\n", frame,
		m.time:as_double(), name, value))
end

emu.register_frame_done(function()
	local ok, err = pcall(function()
		frame = screen:frame_number()
		-- Venture reaches title/start readiness near 30 s in MAME. Delaying
		-- these common probe inputs avoids consuming them during reset/boot.
		if frame == 1920 then pulse(coin, "Coin 1", 1) end
		if frame == 1950 then pulse(coin, "Coin 1", 0) end
		if frame == 2040 then pulse(start, "1 Player Start", 1) end
		if frame == 2070 then pulse(start, "1 Player Start", 0) end
		if frame >= max_frame then
			for key, value in pairs(counts) do events:write(string.format("count %s=%d\n", key, value)) end
			finish(string.format("complete frame=%d time_s=%.9f", frame, m.time:as_double()))
		end
	end)
	if not ok then finish("ERROR frame callback: " .. tostring(err)) end
end)
