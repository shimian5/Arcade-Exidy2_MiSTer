-- Mouse Trap genuine-play capture. Digital input setters receive the complete
-- field mask when asserted and zero when released (including multi-bit masks).
-- This script never pokes CPUs,
-- memory, RIOT ports, or speech commands; it records native bus traffic.
local m=manager.machine
local main=assert(m.devices[":maincpu"])
local mainspace=assert(main.spaces["program"])
local audio=assert(m.devices[":soundbd:audiocpu"])
local audiospace=assert(audio.spaces["program"])
local z80=assert(m.devices[":soundbd:cvsdcpu"])
local iospace=assert(z80.spaces["io"])
local screen=assert(m.screens[":screen"])
local limit=tonumber(os.getenv("MTRAP_VOICE_FRAMES") or "1800")
local snapdir=assert(os.getenv("MTRAP_VOICE_SNAPSHOT_DIR"))
local profile=os.getenv("MTRAP_VOICE_INPUT_PROFILE") or "late"
local out=assert(io.open(assert(os.getenv("MTRAP_VOICE_OUT")),"w"))
local events=assert(io.open(assert(os.getenv("MTRAP_VOICE_EVENTS")),"w"))
local taps,counts={},{}
local frames=0
local function pc(cpu) local r=cpu.state.PC; return r and (r.value & 0xffff) or 0xffff end
local function log(kind,cpu,a,d,mask,bus,keep)
 local k=kind..":"..bus; counts[k]=(counts[k] or 0)+1
 if not keep then return end
 out:write(string.format("%s,%s,%d,%.9f,%04X,%04X,%02X,%X\n",kind,bus,screen:frame_number(),m.time:as_double(),pc(cpu),a & 0xffff,d & 0xff,mask or 0xff))
 counts[k..":saved"]=(counts[k..":saved"] or 0)+1
end
out:write("kind,bus,frame,time_s,pc,address,data,mask\n")
events:write("mtrap genuine-play input experiment; profile="..profile.." complete field masks set asserted=active; no injected CPU/RIOT/speech commands\n")
events:write("taps IN0 mirror 5101 and 5105-51fd; IRQ mirror 5103-51ff; IN2 5213; sound PIA 5200-52ff; RIOT 0800-0fff; voice IO 00-ff\n")
taps[#taps+1]=mainspace:install_read_tap(0x5101,0x5101,"mtrap_in0_base",function(a,d,mask) log("R",main,a,d,mask,"in0",true) end)
taps[#taps+1]=mainspace:install_read_tap(0x5105,0x51fd,"mtrap_in0_mirror",function(a,d,mask) if (a & 3)==1 then log("R",main,a,d,mask,"in0",true) end end)
taps[#taps+1]=mainspace:install_read_tap(0x5103,0x51ff,"mtrap_irq",function(a,d,mask) if (a & 3)==3 then log("R",main,a,d,mask,"irq",true) end end)
taps[#taps+1]=mainspace:install_read_tap(0x5213,0x5213,"mtrap_in2",function(a,d,mask) log("R",main,a,d,mask,"in2",true) end)
taps[#taps+1]=mainspace:install_write_tap(0x5200,0x52ff,"mtrap_main_sound",function(a,d,mask) log("W",main,a,d,mask,"main",true) end)
taps[#taps+1]=audiospace:install_write_tap(0x0800,0x0fff,"mtrap_riot_write",function(a,d,mask) log("W",audio,a,d,mask,"audio",(a & 4)==0) end)
taps[#taps+1]=iospace:install_read_tap(0,0xff,"mtrap_voice_read",function(a,d,mask) log("R",z80,a,d,mask,"z80io",(a & 0xc0)~=0xc0) end)
taps[#taps+1]=iospace:install_write_tap(0,0xff,"mtrap_voice_write",function(a,d,mask) log("W",z80,a,d,mask,"z80io",(a & 0x30)~=0x30) end)
_G.mtrap_voice_gameplay_taps=taps
local function field(port,name) local p=m.ioport.ports[port]; return p and p.fields[name] end
local controls={
 {":IN0","Coin 1","coin"},{":IN0","1 Player Start","start"},
 {":IN0","P1 Right","right"},{":IN0","P1 Left","left"},
 {":IN0","Dog Button","dog"},{":IN0","P1 Up","up"},{":IN0","P1 Down","down"},
 {":IN2","Yellow Button","yellow"},{":IN2","Red Button","red"},{":IN2","Blue Button","blue"}
}
local resolved={}
for _,c in ipairs(controls) do
 c[4]=field(c[1],c[2]); if not c[4] then events:write("ERROR missing field "..c[1].."/"..c[2].."\n"); m:exit(); return end
 resolved[c[3]]=c[4]
end
local function press(frame,name,value)
 local f=resolved[name]
 local raw=value~=0 and f.mask or 0
 f:set_value(raw)
 local tag=(name=="yellow" or name=="red" or name=="blue") and ":IN2" or ":IN0"
 local port=assert(m.ioport.ports[tag])
 events:write(string.format("input frame=%d control=%s asserted=%s set_value=%02X mask=%02X port_%s=%02X\n",frame,name,tostring(value~=0),raw,f.mask,tag,port:read() & 0xff))
end
-- Free play is avoided so the trace includes a real coin and start sequence.
-- Movement and game actions are separated to give the game time to enter play.
local schedule,snapshots,state_frames
if profile=="late" then
 schedule={
  {1800,"coin",1},{1825,"coin",0},{1860,"start",1},{1890,"start",0},
  {2000,"right",1},{2120,"right",0},{2150,"dog",1},{2180,"dog",0},
  {2220,"yellow",1},{2250,"yellow",0},{2300,"red",1},{2330,"red",0},
  {2380,"blue",1},{2410,"blue",0},{2500,"up",1},{2530,"up",0},
  {2600,"left",1},{2720,"left",0},{2800,"dog",1},{2830,"dog",0},
  {2900,"down",1},{2930,"down",0}
 }
 snapshots={[1600]="precoin.png",[1920]="after_start.png",[2400]="play.png"}
 state_frames={[1600]=true,[1800]=true,[1920]=true,[2100]=true,[2400]=true,[3000]=true,[3600]=true}
elseif profile=="early" then
 schedule={
  {420,"coin",1},{445,"coin",0},{480,"start",1},{510,"start",0},
  {600,"right",1},{720,"right",0},{750,"dog",1},{780,"dog",0},
  {900,"yellow",1},{930,"yellow",0},{1050,"red",1},{1080,"red",0},
  {1200,"blue",1},{1230,"blue",0},{1350,"right",1},{1470,"right",0},
  {1500,"up",1},{1530,"up",0},{1560,"left",1},{1680,"left",0},
  {1700,"dog",1},{1730,"dog",0}
 }
 snapshots={[400]="startup.png",[560]="after_start.png",[900]="after_actions.png"}
 state_frames={[400]=true,[560]=true,[900]=true}
else
 events:write("ERROR unsupported input profile "..profile.."\n"); out:close(); events:close(); m:exit(); return
end
local si=1
local checks={}
emu.register_frame_done(function()
 local ok,err=pcall(function()
  frames=screen:frame_number()
  if snapshots[frames] then
   local path=snapdir.."/"..snapshots[frames]
   local err=screen:snapshot(path)
   events:write(string.format("snapshot frame=%d path=%s error=%s\n",frames,path,tostring(err)))
  end
  if state_frames[frames] then
   events:write(string.format("main_state frame=%d pc=%04X IN0=%02X IN2=%02X\n",frames,pc(main)&0xffff,m.ioport.ports[":IN0"]:read()&0xff,m.ioport.ports[":IN2"]:read()&0xff))
  end
  while si<=#schedule and frames>=schedule[si][1] do
   local e=schedule[si]; if frames==e[1] then
    press(frames,e[2],e[3])
    local tag=(e[2]=="yellow" or e[2]=="red" or e[2]=="blue") and ":IN2" or ":IN0"
    checks[#checks+1]={frame=frames+2,tag=tag,name=e[2],asserted=e[3]~=0}
   end; si=si+1
  end
  for i=#checks,1,-1 do
   local c=checks[i]
   if frames>=c.frame then events:write(string.format("input_confirm frame=%d control=%s asserted=%s port_%s=%02X\n",frames,c.name,tostring(c.asserted),c.tag,m.ioport.ports[c.tag]:read() & 0xff)); table.remove(checks,i) end
  end
  if frames>=limit then
   events:write("complete frame="..frames.."\n")
   for k,v in pairs(counts) do events:write(string.format("count %s=%d\n",k,v)) end
   out:flush(); out:close(); events:flush(); events:close(); m:exit()
  end
 end)
 if not ok then events:write("ERROR "..tostring(err).."\n"); out:close(); events:close(); m:exit() end
end)
