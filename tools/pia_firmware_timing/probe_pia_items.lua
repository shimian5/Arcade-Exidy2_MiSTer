-- Enumerate saved PIA state items without reading PIA registers or changing state.
local m = manager.machine
local f = io.open("pia-items.log", "w")
if not f then m:exit(); return end
for _, tag in ipairs({ ":pia", ":soundbd:pia" }) do
	local dev = m.devices[tag]
	f:write(string.format("device=%s present=%s\n", tag, tostring(dev ~= nil)))
	if dev then
		for key, _ in pairs(dev.items) do f:write("  " .. tostring(key) .. "\n") end
	end
end
f:flush()
f:close()
m:exit()
