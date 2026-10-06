#!/usr/bin/env python3
"""Raw-address reference metadata and actual graphics fixture; ROM output ignored."""
import csv,hashlib,json,zipfile,zlib
from collections import Counter
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'simulation/sprite_serialization'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def inspect(name):
    p=OUT/name; rows=list(csv.DictReader((p/'bus.csv').open(encoding='utf-8-sig')))
    writes=[r for r in rows if r['kind']=='W']
    aliases=[r for r in writes if 0x5000<=int(r['address'],16)<=0x50ff and int(r['address'],16) not in (0x5000,0x5040,0x5080,0x50c0)]
    image_states=[]; state={}; all_states={}
    for r in writes:
        address=int(r['address'],16); frame=int(r['frame']); data=int(r['data'],16)
        state[address]=data
        if address==0x50c0 and 2400<=frame<=2519:
            ctl=state.get(0x5101,0); imgs=state.get(0x5100,0)
            s={'frame':frame,'control':ctl,'image1':(imgs&15)+16*bool(ctl&32),'image2':(imgs>>4)+32+16*bool(ctl&64),'sprite1Enabled':not bool(ctl&128) or bool(ctl&16),'x1':232-state.get(0x5000,0),'y1':max(0,240-state.get(0x5040,0)),'x2':232-state.get(0x5080,0),'y2':240-data}
            image_states.append(s); all_states[frame]=s
    manifest=json.loads((p/'run-manifest.json').read_text(encoding='utf-8-sig'))
    if manifest['mameExitCode'] or manifest['verifyRomExitCode'] or not image_states: raise RuntimeError('invalid capture')
    return {'run':name,'manifest':manifest,'busSha256':sha(p/'bus.csv'),'rows':len(rows),'mirroredPositionWriteCount':len(aliases),'coordinateWrites':dict(Counter(r['address'] for r in writes if 0x5000<=int(r['address'],16)<=0x50ff)),'activeImagePairs':sorted(set((s['image1'],s['image2']) for s in image_states)),'states':image_states},all_states
def main():
    fire,fs=inspect('sixth_fire01'); right,rs=inspect('sixth_right01')
    archive=Path(r'\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)\venture.zip')
    with zipfile.ZipFile(archive) as z: gfx=z.read('vel_11d-2.11d')
    if len(gfx)!=2048 or zlib.crc32(gfx)!=0xea6fd981: raise RuntimeError('graphics ROM mismatch')
    generated=OUT/'generated'; generated.mkdir(exist_ok=True)
    (generated/'gfx.hex').write_text(''.join(f'{b:02x}\n' for b in gfx))
    atlas=Image.new('RGB',(8*96,8*104),(24,24,24)); d=ImageDraw.Draw(atlas)
    for code in range(64):
        x0=(code%8)*96; y0=(code//8)*104
        for y in range(16):
            for x in range(16):
                byte=gfx[code*32+y+(16 if x>=8 else 0)]
                if byte&(128>>(x%8)): d.rectangle((x0+x*5,y0+y*5,x0+x*5+4,y0+y*5+4),fill='white')
        d.text((x0,y0+82),str(code),fill='yellow')
    atlas.save(generated/'atlas.png')
    first=next((f for f in sorted(fs) if f in rs and fs[f]['x2']!=rs[f]['x2']),None)
    report={'schema':'exidy2-raw-sprite-reference/v1','fire':fire,'rightOnly':right,'firstObject2XDivergenceFrame':first,'graphics':{'member':'vel_11d-2.11d','crc32':'ea6fd981','sha256':hashlib.sha256(gfx).hexdigest(),'length':len(gfx),'layout':'16x16 1bpp; left/right bytes at code*32+y/+16; MSB first','atlas':'simulation/sprite_serialization/generated/atlas.png'},'projectileIdentityAccepted':False,'limits':['Raw addresses preserved; lack of mirror usage applies only to this set/input window.','Frame-end register state is not pixel-time state.','Graphics decode and serializer primitive test do not prove complete rendered-frame/clipping/collision parity.']}
    dest=ROOT/'docs/design/sprite-serialization/raw-reference.json'; dest.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'rawRows':[fire['rows'],right['rows']],'aliases':[fire['mirroredPositionWriteCount'],right['mirroredPositionWriteCount']],'activeImagePairs':fire['activeImagePairs'],'firstObject2XDivergenceFrame':first}))
if __name__=='__main__': main()
