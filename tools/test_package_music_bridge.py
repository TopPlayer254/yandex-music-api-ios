"""Regression checks for preserving executable code and import ordinals."""
import struct
import unittest

from macho_audit import dylib_loads
from package_music_bridge import patch_macho, BRIDGE_LOAD, CORE_ANALYTICS


def fixture(padding=True,analytics=False):
    def load(name):
        encoded=name.encode()+b'\0'
        size=(24+len(encoded)+7)&~7
        return struct.pack('<6I',0xc,size,24,0,0,0)+encoded+b'\0'*(size-24-len(encoded))
    libraries=load(CORE_ANALYTICS if analytics else '/usr/lib/libSystem.B.dylib')+load('/usr/lib/libobjc.A.dylib')
    extent=32+152+len(libraries)+16
    offset=512 if padding else extent
    segment=struct.pack('<II16sQQQQIIII',0x19,152,b'__TEXT',0,1024,0,1024,5,5,1,0)
    section=struct.pack('<16s16sQQIIIIIIII',b'__text',b'__TEXT',offset,16,offset,2,0,0,0x80000400,0,0,0)
    signature=struct.pack('<4I',0x1d,16,768,64)
    commands=segment+section+libraries+signature
    result=bytearray(1024)
    result[:32]=struct.pack('<8I',0xfeedfacf,0x100000c,2,2,4,len(commands),0,0)
    result[32:32+len(commands)]=commands
    result[offset:offset+16]=bytes(range(16))
    result[768:832]=b's'*64
    return bytes(result),offset


class PackageMusicBridgeTests(unittest.TestCase):
    def test_injection_keeps_code_and_original_library_ordinals(self):
        original,offset=fixture()
        patched=patch_macho(original,BRIDGE_LOAD)
        self.assertEqual(original[offset:offset+16],patched[offset:offset+16])
        self.assertEqual([i[3] for i in dylib_loads(patched)],
                         [i[3] for i in dylib_loads(original)]+[BRIDGE_LOAD])
        self.assertEqual(patched[768:832],b'\0'*64)
        self.assertEqual(len(original),len(patched))

    def test_no_room_is_an_error_instead_of_overwriting_instructions(self):
        original,_=fixture(padding=False)
        with self.assertRaisesRegex(ValueError,'padding'):
            patch_macho(original,BRIDGE_LOAD)

    def test_signature_removal_keeps_all_dependency_names(self):
        original,_=fixture()
        patched=patch_macho(original)
        self.assertEqual(list(dylib_loads(original)),list(dylib_loads(patched)))
        cursor=32
        for _ in range(struct.unpack_from('<I',patched,16)[0]):
            command,size=struct.unpack_from('<II',patched,cursor)
            self.assertNotEqual(command,0x1d)
            cursor+=size

    def test_other_macho_formats_are_rejected(self):
        with self.assertRaises(ValueError): patch_macho(b'\xca\xfe\xba\xbe'+b'\0'*80)

    def test_analytics_imports_point_to_noop_exports_without_ordinal_shift(self):
        original,offset=fixture(analytics=True)
        patched=patch_macho(original,BRIDGE_LOAD)
        self.assertEqual([i[3] for i in dylib_loads(patched)],[BRIDGE_LOAD,'/usr/lib/libobjc.A.dylib',BRIDGE_LOAD])
        self.assertEqual(original[offset:offset+16],patched[offset:offset+16])


if __name__=='__main__': unittest.main()
