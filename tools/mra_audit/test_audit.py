import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import audit


class AuditTests(unittest.TestCase):
    def test_selector_edges_and_address_truncation(self):
        self.assertEqual(audit.selector_at(0x0ffff), ("eprom_0/maincpu", 16, 0xffff))
        self.assertEqual(audit.selector_at(0x10000), ("eprom_6/audio", 14, 0))
        self.assertEqual(audit.selector_at(0x13fff), ("eprom_6/audio", 14, 0x3fff))
        self.assertEqual(audit.selector_at(0x14000), ("eprom_1/gfx", 11, 0))
        self.assertEqual(audit.selector_at(0x14800), ("eprom_2/decoder", 8, 0))
        self.assertEqual(audit.selector_at(0x14960), ("eprom_7/fallback", 14, 0x960))
        self.assertEqual(audit.selector_at(0x17fff), ("eprom_7/fallback", 14, 0x3fff))
        self.assertEqual(audit.selector_at(0x18000), ("eprom_7/fallback", 14, 0))

    def test_effective_bus_mask_detects_wrong_placement_but_allows_decoder_nibble_drop(self):
        self.assertTrue(audit.bytes_match_after_bus_mask(b"\xaf\x31", b"\x0f\x01", 4))
        self.assertFalse(audit.bytes_match_after_bus_mask(b"\xaf\x31", b"\x0f\x02", 4))
        self.assertFalse(audit.bytes_match_after_bus_mask(b"\xaa", b"\xab", 8))

    def test_mra_repeat_stream_and_zip_alias_resolution(self):
        scratch = Path(__file__).parents[2] / "simulation" / "mra_audit" / "synthetic"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as td:
            root = Path(td)
            payload = b"synthetic-rom-payload"
            with zipfile.ZipFile(root / "parent.zip", "w") as zf:
                zf.writestr("actual-name.bin", payload)
            mra = root / "fixture.mra"
            mra.write_text('''<misterromdescription><setname>fixture</setname>
              <rom index="0" zip="missing.zip|parent.zip"><part repeat="0x3"> 00 </part>
              <part crc="%08x" name="renamed.bin"/></rom></misterromdescription>'''
                           % (audit.zlib.crc32(payload) & 0xffffffff), encoding="utf-8")
            setname, parts = audit.read_mra(mra)
            self.assertEqual(setname, "fixture")
            self.assertEqual(parts[0], {"kind": "repeat", "length": 3, "value": 0})
            resolver = audit.ArchiveSet(root)
            data, archive, member = resolver.resolve(parts[1]["crc"], parts[1]["archives"])
            self.assertEqual((data, archive, member), (payload, "parent.zip", "actual-name.bin"))

    def test_manifest_hash_mismatch_is_reported(self):
        scratch = Path(__file__).parents[2] / "simulation" / "mra_audit" / "synthetic"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as td:
            root = Path(td)
            payload = b"verified bytes"
            with zipfile.ZipFile(root / "fixture.zip", "w") as zf:
                zf.writestr("member.bin", payload)
            manifest = {"sets": [{"set": "fixture", "roms": [{"name": "member.bin", "size": str(len(payload)),
                "crc": "%08x" % (audit.zlib.crc32(payload) & 0xffffffff), "sha1": "0" * 40}]}]}
            result = audit.check_manifest_archives(manifest, {"fixture"}, root)
            self.assertEqual(result[0]["status"], "mismatch")


if __name__ == "__main__":
    unittest.main()
