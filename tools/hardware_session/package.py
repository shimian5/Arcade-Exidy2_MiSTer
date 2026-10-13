#!/usr/bin/env python3
"""Package the accepted development RBF with isolated test MRAs; never copy ROMs."""
from pathlib import Path
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'simulation/hardware-session/20261013'
OUT.mkdir(parents=True,exist_ok=True)
rbf=ROOT/'simulation/full-core/fax-gfx-seed2-20261013/Arcade-Exidy2.rbf'
expected='f58fee7b7d2d70aae767d2e5bd0dec8e23ada4d649422ab9404cedf9d7c6a559'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if sha(rbf)!=expected:raise SystemExit('Accepted RBF hash differs')
shutil.copy2(rbf,OUT/'Arcade-Exidy2_Test_20261013.rbf')
paths=[ROOT/'candidates/mra'/n for n in ('Mouse Trap (speech expansion candidate).mra','FAX (question expansion candidate).mra','FAX 2 (question expansion candidate).mra','Teeter Torture (integration candidate).mra','Venture Revision 5 (int-profile test).mra','Pepper II (int-profile test).mra','Hard Hat (int-profile test).mra')]
paths += [ROOT/'releases'/n for n in ('TARG.mra','Spectar.mra','Mouse Trap.mra')]
manifest={'production_source_commit':'2b9eb2b','rbf_sha256':expected,'files':[],'limits':'Development hardware test only. CRT/Side Trak candidates remain unbound; complete games/audio/hardware and legacy clock coverage are not accepted.'}
for p in paths:
 raw=p.read_bytes().decode('utf-8');edited,n=re.subn(r'(<rbf>).*?(</rbf>)',r'\1Exidy2_Test\2',raw,count=1,flags=re.S);assert n==1
 dest=OUT/(p.stem+' [test].mra');dest.write_bytes(edited.encode('utf-8'));x=ET.parse(dest)
 # Only the core reference may change: preserve each ROM stream description.
 original=ET.parse(p).getroot();packaged=x.getroot()
 assert [ET.tostring(r) for r in original.findall('rom')]==[ET.tostring(r) for r in packaged.findall('rom')]
 manifest['files'].append({'source':str(p.relative_to(ROOT)),'source_sha256':sha(p),'test_mra':dest.name,'test_sha256':sha(dest)})
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'README.md').write_text('''# Exidy2 development hardware session

Source: 2b9eb2b. All 59 reported timing checks pass; targeted speech/reset inspection passes. This is a development test, not full-game/release acceptance.

Copy Arcade-Exidy2_Test_20261013.rbf into the MiSTer _Arcade/cores folder and the test MRAs into a separate _Arcade test folder. They reference Exidy2_Test, keeping the existing core reference intact. Supply your own matching ROM archives through your normal MRA workflow. No ROMs are in this package. Record the actual file hashes and MiSTer version.

Start with HDMI and the Mouse Trap speech checklist in docs/reference_cases/mousetrap-speech-hardware.md. Also compare the packaged legacy Mouse Trap MRA. Then check Teeter spinner/D-pad modes, FAX/FAX2 four-answer inputs and question progression, and the three interrupt-profile candidates. Repeat pause, warm reset and ROM reload across titles. Report exactly what happens; these are acceptance tests, not assumed passes.

The new CRT transport and Side Trak helpers remain outside production. Native 280-line output is still present, so Direct Video/S-Video/JVC observations cannot close the CRT issue. FAX has two missing NO_DUMP banks; out-of-range question banks use documented zero quarantine. Startup-check Skip/Run is a diagnostic setting with unresolved physical strap meaning.

Existing releases remain unchanged. Keep captures/ROMs/results outside tracked source. manifest.json records all source and packaged hashes; only each MRA core-reference tag differs.
''')
archive=shutil.make_archive(str(OUT.parent/'Exidy2-hardware-test-20261013'),'zip',OUT)
print(archive);print('MRAs',len(paths),'RBF',expected)
