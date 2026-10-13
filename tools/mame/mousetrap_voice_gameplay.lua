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
local stateOnly=os.getenv("MTRAP_VOICE_STATE_TRACE")=="1"
local voiceState,voiceStateRows
local function stateValue(cpu,name)
 local ok,value=pcall(function()
  local entry=cpu.state[name]
  return entry and entry.value or nil
 end)
 if not ok then return "ERR" end
 if type(value)~="number" then return "NA" end
 return string.format("%04X",value & 0xffff)
end
local stateNames={"PC","AF","BC","DE","HL","SP","AF2","BC2","DE2","HL2","IX","IY","I","R","IM","IFF1","IFF2"}
local function stateRecord(kind,source,address,data,ddra,pa)
 if not stateOnly then return end
 local values={}
 for _,name in ipairs(stateNames) do values[#values+1]=stateValue(z80,name) end
 local invalid=false
 for _,value in ipairs(values) do if value=="ERR" or value=="NA" then invalid=true end end
 if invalid then events:write("ERROR state API unavailable for source="..source.."\n") end
 voiceStateRows=voiceStateRows+1
 voiceState:write(string.format("%d,%d,%.9f,%s,%s,%04X,%02X,%02X,%02X,%s\n",
  voiceStateRows,screen:frame_number(),m.time:as_double(),kind,source,
  address or 0xffff,data or 0,ddra or 0,pa or 0,table.concat(values,",")))
end
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
if stateOnly then
 local statePath=assert(os.getenv("MTRAP_VOICE_STATE_OUT"))
 voiceState=assert(io.open(statePath,"w")); voiceStateRows=0
 voiceState:write("row,frame,time_s,event,source,address,data,ddra,resolved_pa,PC,AF,BC,DE,HL,SP,AF2,BC2,DE2,HL2,IX,IY,I,R,IM,IFF1,IFF2\n")
 local probe=stateValue(z80,"BC")
 events:write("voice_state_api probe_BC="..probe.." fields="..table.concat(stateNames,"/").."; debugger state .value only; no CPU-space reads\n")
 if probe=="ERR" or probe=="NA" then
  events:write("ERROR speech CPU BC debugger state unavailable\n")
  voiceState:close(); out:close(); events:close(); m:exit(); return
 end
 local ora,ddra=0,0
 local previousReset=nil
 local releaseId=0
 local firstOutRemaining=0
 local bootOutRemaining=2
 local resetSeen=false
 local function paWrite(a,d)
  local offset=a & 0x1f
  local reg=offset & 0x07
  if reg==0 then ora=d & 0xff elseif reg==1 then ddra=d & 0xff else return end
  local resolved=(ora & ddra) | (ddra ~ 0xff)
  local reset=(resolved & 0x10)==0
  stateRecord("PA_CALLBACK",reg==0 and "ORA" or "DDRA",a,d,ddra,resolved)
  if reset then
   resetSeen=true; previousReset=true; firstOutRemaining=0
  elseif resetSeen and previousReset then
   releaseId=releaseId+1; firstOutRemaining=2; previousReset=false
   events:write(string.format("voice_release id=%d frame=%d time_s=%.9f PA=%02X source=state-only-native-callback\n",releaseId,screen:frame_number(),m.time:as_double(),resolved))
  else
   previousReset=false
  end
 end
 taps[#taps+1]=audiospace:install_write_tap(0x0800,0x0fff,"mtrap_state_pa",function(a,d,mask)
  if (a & 0x07)<=1 then paWrite(a,d) end
 end)
 taps[#taps+1]=iospace:install_write_tap(0,0xff,"mtrap_state_voice_out",function(a,d,mask)
  if (a & 0x10)==0 then
   if bootOutRemaining>0 then
    stateRecord("VOICE_OUT_BOOT",string.format("boot_%d",3-bootOutRemaining),a,d,nil,nil)
    bootOutRemaining=bootOutRemaining-1
   elseif firstOutRemaining>0 then
    local n=3-firstOutRemaining
    stateRecord("VOICE_OUT_AFTER_RELEASE",string.format("release_%d_out_%d",releaseId,n),a,d,nil,nil)
    firstOutRemaining=firstOutRemaining-1
   end
  end
 end)
 events:write("state_trace_mode=PA ORA/DDRA callbacks plus first two low-A4 voice writes at boot and after each reset release; no full bus taps\n")
else
 taps[#taps+1]=mainspace:install_read_tap(0x5101,0x5101,"mtrap_in0_base",function(a,d,mask) log("R",main,a,d,mask,"in0",true) end)
 taps[#taps+1]=mainspace:install_read_tap(0x5105,0x51fd,"mtrap_in0_mirror",function(a,d,mask) if (a & 3)==1 then log("R",main,a,d,mask,"in0",true) end end)
 taps[#taps+1]=mainspace:install_read_tap(0x5103,0x51ff,"mtrap_irq",function(a,d,mask) if (a & 3)==3 then log("R",main,a,d,mask,"irq",true) end end)
 taps[#taps+1]=mainspace:install_read_tap(0x5213,0x5213,"mtrap_in2",function(a,d,mask) log("R",main,a,d,mask,"in2",true) end)
 taps[#taps+1]=mainspace:install_write_tap(0x5200,0x52ff,"mtrap_main_sound",function(a,d,mask) log("W",main,a,d,mask,"main",true) end)
 taps[#taps+1]=audiospace:install_write_tap(0x0800,0x0fff,"mtrap_riot_write",function(a,d,mask) log("W",audio,a,d,mask,"audio",(a & 4)==0) end)
 taps[#taps+1]=iospace:install_read_tap(0,0xff,"mtrap_voice_read",function(a,d,mask) log("R",z80,a,d,mask,"z80io",(a & 0xc0)~=0xc0) end)
 taps[#taps+1]=iospace:install_write_tap(0,0xff,"mtrap_voice_write",function(a,d,mask) log("W",z80,a,d,mask,"z80io",(a & 0x30)~=0x30) end)
end
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
-- Normal profiles use coin/start. The separately labelled Free Play profile
-- changes only the IN2 DIP via user_value before scheduling genuine controls.
-- Movement and game actions are separated to give the game time to enter play.
local schedule,snapshots,state_frames
if profile=="freeplay" then
 local dipport=assert(m.ioport.ports[":IN2"])
 local dip=assert(dipport.fields["Free Play"])
 events:write(string.format("configuration Free Play before field_mask=%02X port=%02X user_value=%02X\n",dip.mask,dipport:read() & 0xff,dip.user_value))
 dip.user_value=0
 events:write(string.format("configuration Free Play after port=%02X user_value=%02X\n",dipport:read() & 0xff,dip.user_value))
end
if profile=="late" then
 schedule={
  {1800,"coin",1},{1825,"coin",0},{1860,"start",1},{1890,"start",0},
  {2000,"right",1},{2120,"right",0},{2150,"dog",1},{2180,"dog",0},
  {2220,"yellow",1},{2250,"yellow",0},{2300,"red",1},{2330,"red",0},
  {2380,"blue",1},{2410,"blue",0},{2500,"up",1},{2530,"up",0},
  {2600,"left",1},{2720,"left",0},{2800,"dog",1},{2830,"dog",0},
  {2900,"down",1},{2930,"down",0}
 }
 snapshots={[1600]="precoin.png",[1800]="coin.png",[1860]="start_pressed.png",[1890]="start_released.png",[1920]="after_start.png",[1950]="timeline_1950.png",[1980]="timeline_1980.png",[2010]="timeline_2010.png",[2040]="timeline_2040.png",[2070]="timeline_2070.png",[2100]="timeline_2100.png",[2130]="timeline_2130.png",[2160]="timeline_2160.png",[2190]="timeline_2190.png",[2220]="timeline_2220.png",[2250]="timeline_2250.png",[2280]="timeline_2280.png",[2310]="timeline_2310.png",[2340]="timeline_2340.png",[2370]="timeline_2370.png",[2400]="play.png"}
 state_frames={[1600]=true,[1800]=true,[1920]=true,[2100]=true,[2400]=true,[3000]=true,[3600]=true}
elseif profile=="active" then
 schedule={
  {1500,"coin",1},{1525,"coin",0},{1560,"start",1},{1590,"start",0},
  {1620,"right",1},{1740,"right",0},{1770,"dog",1},{1800,"dog",0},
  {1830,"yellow",1},{1860,"yellow",0},{1890,"red",1},{1920,"red",0},
  {1950,"blue",1},{1980,"blue",0},{2010,"up",1},{2040,"up",0}
 }
 snapshots={[1450]="precoin.png",[1550]="prestart.png",[1580]="start_held.png",[1600]="after_start.png",[1620]="first_action.png",[1700]="moving.png",[1800]="dog_action.png",[1880]="button_action.png",[2000]="after_actions.png"}
 state_frames={[1450]=true,[1500]=true,[1550]=true,[1580]=true,[1600]=true,[1620]=true,[1700]=true,[1800]=true,[2000]=true}
elseif profile=="sync" then
 schedule={
  {1500,"coin",1},{1500,"start",1},{1525,"coin",0},{1525,"start",0},
  {1530,"right",1},{1650,"right",0},{1530,"dog",1},{1560,"dog",0},
  {1580,"yellow",1},{1610,"yellow",0},{1640,"red",1},{1670,"red",0},
  {1700,"blue",1},{1730,"blue",0},{1760,"up",1},{1790,"up",0}
 }
 snapshots={[1450]="precoin.png",[1500]="coin_start.png",[1510]="both_held.png",[1520]="both_held_late.png",[1530]="actions_begin.png",[1560]="after_actions.png",[1600]="timeline_1600.png",[1650]="timeline_1650.png",[1700]="timeline_1700.png",[1800]="timeline_1800.png",[1900]="timeline_1900.png"}
 state_frames={[1450]=true,[1500]=true,[1510]=true,[1520]=true,[1530]=true,[1560]=true,[1600]=true,[1650]=true,[1700]=true,[1800]=true,[1900]=true}
elseif profile=="postdelay" then
 schedule={
  {2100,"coin",1},{2125,"coin",0},{2160,"start",1},{2190,"start",0},
  {2220,"right",1},{2340,"right",0},{2370,"dog",1},{2400,"dog",0},
  {2430,"yellow",1},{2460,"yellow",0},{2490,"red",1},{2520,"red",0},
  {2550,"blue",1},{2580,"blue",0},{2610,"up",1},{2640,"up",0}
 }
 snapshots={[2040]="after_startup_delay.png",[2100]="coin.png",[2160]="start_pressed.png",[2190]="start_released.png",[2220]="first_action.png",[2280]="movement.png",[2400]="dog_action.png",[2520]="button_action.png",[2640]="after_actions.png",[2700]="post_action.png"}
 state_frames={[2040]=true,[2100]=true,[2160]=true,[2190]=true,[2220]=true,[2280]=true,[2400]=true,[2520]=true,[2640]=true,[2700]=true}
elseif profile=="early" then
 schedule={
  {420,"coin",1},{445,"coin",0},{480,"start",1},{510,"start",0},
  {600,"right",1},{720,"right",0},{750,"dog",1},{780,"dog",0},
  {900,"yellow",1},{930,"yellow",0},{1050,"red",1},{1080,"red",0},
  {1200,"blue",1},{1230,"blue",0},{1350,"right",1},{1470,"right",0},
  {1500,"up",1},{1530,"up",0},{1560,"left",1},{1680,"left",0},
  {1700,"dog",1},{1730,"dog",0}
 }
 snapshots={[400]="startup.png",[500]="start_transition_1.png",[520]="start_transition_2.png",[560]="after_start.png",[600]="first_action.png",[660]="post_action.png",[720]="post_action_2.png",[900]="after_actions.png"}
 state_frames={[400]=true,[500]=true,[520]=true,[560]=true,[600]=true,[660]=true,[720]=true,[900]=true}
elseif profile=="freeplay" then
 schedule={
  {1560,"start",1},{1590,"start",0},
  {1620,"right",1},{1740,"right",0},{1770,"dog",1},{1800,"dog",0},
  {1830,"yellow",1},{1860,"yellow",0},{1890,"red",1},{1920,"red",0},
  {1950,"blue",1},{1980,"blue",0},{2010,"up",1},{2040,"up",0}
 }
 snapshots={[1450]="before_start.png",[1550]="prestart.png",[1580]="start_held.png",[1600]="after_start.png",[1620]="first_action.png",[1700]="moving.png",[1800]="dog_action.png",[1880]="button_action.png",[2000]="after_actions.png"}
 state_frames={[1450]=true,[1500]=true,[1550]=true,[1580]=true,[1600]=true,[1620]=true,[1700]=true,[1800]=true,[2000]=true}
else
 events:write("ERROR unsupported input profile "..profile.."\n"); out:close(); events:close(); m:exit(); return
end
local si=1
local checks={}
emu.register_frame_done(function()
 local ok,err=pcall(function()
  frames=screen:frame_number()
  if not stateOnly and snapshots[frames] then
   local path=snapdir.."/"..snapshots[frames]
   local err=screen:snapshot(path)
   events:write(string.format("snapshot frame=%d path=%s error=%s\n",frames,path,tostring(err)))
  end
  if not stateOnly and state_frames[frames] then
   local spreg=main.state.SP
   local sp=spreg and spreg.value or 0xff
   local retlo=mainspace:read_u8(0x0100+((sp+1)&0xff))
   local rethi=mainspace:read_u8(0x0100+((sp+2)&0xff))
   local ret=(rethi<<8)|retlo
   local function stackword(offset)
    local lo=mainspace:read_u8(0x0100+((sp+offset)&0xff))
    local hi=mainspace:read_u8(0x0100+((sp+offset+1)&0xff))
    return (hi<<8)|lo
   end
   events:write(string.format("main_state frame=%d pc=%04X sp=%02X returns=%04X/%04X/%04X ram1f=%02X IN0=%02X IN2=%02X audio_pc=%04X voice_pc=%04X\n",frames,pc(main)&0xffff,sp,ret,stackword(3),stackword(5),mainspace:read_u8(0x001f),m.ioport.ports[":IN0"]:read()&0xff,m.ioport.ports[":IN2"]:read()&0xff,pc(audio)&0xffff,pc(z80)&0xffff))
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
   if stateOnly then events:write("voice_state_rows="..voiceStateRows.."\n"); voiceState:flush(); voiceState:close() end
   out:flush(); out:close(); events:flush(); events:close(); m:exit()
  end
 end)
 if not ok then events:write("ERROR "..tostring(err).."\n"); if stateOnly and voiceState then voiceState:close() end; out:close(); events:close(); m:exit() end
end)
