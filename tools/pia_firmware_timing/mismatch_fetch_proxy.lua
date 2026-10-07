-- Focused passive PIA save-item sampling plus the next audio 6502
-- program-space read after each PB=00 transaction near the Venture mismatch.
-- No PIA registers are read and no emulated memory/signals are changed.
local m = manager.machine
local screen = m.screens[":screen"]
local main = m.devices[":pia"]
local audio = m.devices[":soundbd:pia"]
local maincpu = m.devices[":maincpu"]
local audiocpu = m.devices[":soundbd:audiocpu"]
local out = io.open("pia-fetch-proxy.csv", "w")
local meta = io.open("pia-fetch-proxy.meta", "w")
local taps = {}
local frame = 0
local max_frame = 4500
local next_id = 1
local pending_fetch_id = nil
local awaiting_main_id = nil

local function item(dev, name)
	local ok, value = pcall(function()
		return emu.item(dev.items["0/" .. name]):read(0)
	end)
	if ok then return value end
	return -1
end

local function pc(cpu)
	local ok, value = pcall(function() return cpu.state["PC"].value end)
	if ok then return value & 0xffff end
	return -1
end

local function log(event, cpu, addr, data, mask, seq)
	local t = m.time:as_double()
	if t < 50.9 or t > 72.0 then return end
	out:write(string.format(
        "%s,%d,%.9f,%d,%s,%04X,%02X,%02X,%04X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X\n",
        event, seq or 0, t, screen:frame_number(), cpu, addr, data & 0xff,
		mask & 0xff,
		pc(cpu == "main" and maincpu or audiocpu),
		item(main, "m_in_a"), item(main, "m_ddr_a"), item(main, "m_ctl_a"),
		item(main, "m_in_ca1"), item(main, "m_irq_a1"),
		item(audio, "m_out_b"), item(audio, "m_ddr_b"), item(audio, "m_ctl_b"),
		item(audio, "m_out_cb2"), item(audio, "m_in_a"), item(audio, "m_irq_b1")))
end

out:write("event,seq,time_s,frame,cpu,address,bus_data,bus_mask,pc,main_in_a,main_ddra,main_cra,main_ca1,main_irq_a1,audio_out_b,audio_ddrb,audio_crb,audio_out_cb2,audio_in_a,audio_irq_b1\n")
if meta then
	local debugger = m.debugger
	local execution_state = "unavailable"
	if debugger then
		local ok, value = pcall(function() return debugger.execution_state end)
		if ok then execution_state = tostring(value) end
	end
    meta:write(string.format("mame=%s\ndebugger_available=%s\ndebugger_execution_state=%s\nside_effects_disabled_api=not_exposed_by_mame_lua\naudio_cpu_tag=:soundbd:audiocpu\naudio_cpu_type=m6502_device\ninstruction_fetch_space=program (AS_OPCODES not configured; MAME default sync access aliases AS_PROGRAM)\nproxy_read_range=0x5C30-0x5C40\npending_rule=next read tap in narrow program range after full-mask audio PB-data write 00 at 0x1002\n",
		tostring(m.version), tostring(debugger ~= nil), execution_state))
	meta:flush(); meta:close()
end
if not main or not audio or not screen then
    out:write("ERROR,missing PIA or screen device\n"); out:flush(); out:close(); m:exit(); return
end

local function install(space, low, high, label, cpu)
	taps[#taps + 1] = space:install_write_tap(low, high, "pia_state_" .. label .. "_w", function(offset, data, mask)
		if cpu == "audio" and ((offset & 3) == 2 or (offset & 3) == 3) then
			local reg = offset & 3
			local data_select = (item(audio, "m_ctl_b") & 4) ~= 0
			if reg == 2 then
                local now = m.time:as_double()
                if data_select and (data & 0xff) == 0 and (mask & 0xff) == 0xff and now >= 50.9 and now <= 72.0 then
                    local id = next_id
                    next_id = next_id + 1
                    log("audio_pb_zero_write_tap", cpu, offset, data, mask, id)
                    pending_fetch_id = id
                elseif data_select then
                    log("audio_pb_data_write_tap", cpu, offset, data, mask)
                else
                    log("audio_ddrb_write_tap", cpu, offset, data, mask)
                end
			else
				log("audio_crb_write_tap", cpu, offset, data, mask)
			end
		elseif cpu == "main" and ((offset & 3) == 0 or (offset & 3) == 1) then
			local reg = offset & 3
			log(reg == 0 and ((item(main, "m_ctl_a") & 4) ~= 0 and "main_pa_data_write_tap" or "main_ddra_write_tap") or "main_cra_write_tap", cpu, offset, data, mask)
		end
	end)
	taps[#taps + 1] = space:install_read_tap(low, high, "pia_state_" .. label .. "_r", function(offset, data, mask)
        if cpu == "main" and awaiting_main_id and (offset & 3) == 1 and (data & 0x80) ~= 0 then
            log("main_cra_irq_read_after_write", cpu, offset, data, mask, awaiting_main_id)
        elseif cpu == "main" and awaiting_main_id and (offset & 3) == 0 and (item(main, "m_ctl_a") & 4) ~= 0 then
            log("main_pa_data_read_after_write", cpu, offset, data, mask, awaiting_main_id)
            awaiting_main_id = nil
		end
	end)
end

install(maincpu.spaces["program"], 0x5200, 0x520f, "main", "main")
install(audiocpu.spaces["program"], 0x1000, 0x17ff, "audio", "audio")
if not audiocpu.spaces["program"] then
	out:write("ERROR,audio CPU program space unavailable\n"); out:flush(); out:close(); m:exit(); return
end
taps[#taps + 1] = audiocpu.spaces["program"]:install_read_tap(0x5c30, 0x5c40, "pia_next_instruction_fetch", function(offset, data, mask)
	if pending_fetch_id then
		log("audio_next_program_read_after_write", "audio", offset, data, mask, pending_fetch_id)
		awaiting_main_id = pending_fetch_id
		pending_fetch_id = nil
	end
end)
_G.exidy_pia_state_taps = taps

local function field(tag, name)
	local port = m.ioport.ports[tag]
	return port and port.fields[name] or nil
end
local coin = field(":IN0", "Coin 1")
local start = field(":IN0", "1 Player Start")
local function pulse(f, value)
	if f then f:set_value(value) end
end

emu.register_frame_done(function()
	local ok, err = pcall(function()
		frame = screen:frame_number()
		if frame == 1920 then pulse(coin, 1) end
		if frame == 1950 then pulse(coin, 0) end
		if frame == 2040 then pulse(start, 1) end
		if frame == 2070 then pulse(start, 0) end
		if frame >= max_frame then
			out:flush(); out:close(); out = nil; m:exit()
		end
	end)
	if not ok then
		if out then out:write("ERROR," .. tostring(err) .. "\n"); out:flush(); out:close(); out = nil end
		m:exit()
	end
end)
