#!/usr/bin/env python3
"""Stage verified expansion bytes in ignored simulation storage; never modify ROM ZIPs."""
import argparse, hashlib, json, zipfile, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--rom-dir',type=Path,required=True)
    p.add_argument('--out-dir',type=Path,default=ROOT/'simulation/expansion_adapter/rom-images')
    p.add_argument('--report',type=Path,default=ROOT/'docs/design/expansion-adapter/increment-07-roms.json')
    a=p.parse_args(); out=a.out_dir.resolve()
    # ROM-derived artifacts are confined to the repository's ignored directory.
    out.relative_to((ROOT/'simulation').resolve()); out.mkdir(parents=True,exist_ok=True)
    manifest_path=ROOT/'docs/baseline/roms/availability-manifest.json'
    manifest=json.loads(manifest_path.read_text()); sets={s['set']:s for s in manifest['sets']}
    old=json.loads((ROOT/'docs/design/rom-expansion/verified-rom-regions.json').read_text())
    archives={}; images={}
    for name in ('mtrap','fax','fax2'):
        region='soundbd:cvsdcpu' if name=='mtrap' else 'maincpu'
        start=0 if name=='mtrap' else 0x10000
        size=16384 if name=='mtrap' else 196608
        image=bytearray(size); occupied=bytearray(size); components=[]
        rows=[r for r in sets[name]['roms'] if r['region']==region and start<=int(r['offset'],16)<start+size]
        for row in sorted(rows,key=lambda r:int(r['offset'],16)):
            found=None
            for ancestor in (name,sets[name].get('cloneof')):
                if not ancestor: continue
                archive=a.rom_dir/(ancestor+'.zip')
                if archive not in archives:
                    with zipfile.ZipFile(archive) as z:
                        archives[archive]={f'{i.CRC:08x}':(i.filename,z.read(i)) for i in z.infolist() if not i.is_dir()}
                if row['crc'].lower() in archives[archive]:
                    member,data=archives[archive][row['crc'].lower()]; found=(archive,member,data); break
            if found is None: raise RuntimeError('missing ROM: '+row['name'])
            archive,member,data=found
            actual=dict(size=len(data),crc=f'{zlib.crc32(data)&0xffffffff:08x}',sha1=hashlib.sha1(data).hexdigest())
            expected=dict(size=int(row['size']),crc=row['crc'].lower(),sha1=row['sha1'].lower())
            assert actual==expected, f'ROM mismatch: {row["name"]}'
            offset=int(row['offset'],16)-start
            assert offset+len(data)<=size and not any(occupied[offset:offset+len(data)]), 'overlap/out-of-region ROM'
            image[offset:offset+len(data)]=data; occupied[offset:offset+len(data)]=b'\1'*len(data)
            components.append(dict(name=row['name'],archive=archive.name,member=member,offset=offset,**actual))
        digest=hashlib.sha256(image).hexdigest()
        old_image=old['sets'][name]['regions']['cvsdImage' if name=='mtrap' else 'questionImage']
        assert digest==old_image['sha256'], 'image differs from prior independent region audit'
        empty=[i for i in range(size//8192) if not any(occupied[i*8192:(i+1)*8192])]
        assert empty==([22,23] if name=='fax' else []), 'unexpected unmapped image bytes'
        path=out/(name+'.hex'); path.write_text(''.join(f'{b:02x}\n' for b in image))
        images[name]=dict(bytes=size,sha256=digest,hexFile=str(path.relative_to(ROOT)),emptyBanks=empty,components=components)
    report=dict(schema='exidy2-expansion-rom-fixtures/v1',manifestSha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        romDirectory=str(a.rom_dir),images=images,archiveFilesModified=False,romBytesTracked=False)
    a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({name:{k:v for k,v in row.items() if k!='components'} for name,row in images.items()}))
if __name__=='__main__':main()
