"""Check Mach-O ordinal decoding with independent in-memory fixtures."""
import struct
import unittest

from audit_music_private_api import chained_imports, library_status, parse_macho


class PrivateAPIAuditTests(unittest.TestCase):
    def test_all_chained_import_formats_and_special_ordinals(self):
        # 140 is a positive ordinal, despite the high bit being set.
        for fmt,stride in ((1,4),(2,8),(3,16)):
            with self.subTest(format=fmt):
                packed=[]
                for ordinal,weak,name in ((140,False,0),(-2,True,6)):
                    if fmt==3:
                        packed.append(struct.pack('<QQ',(ordinal&0xffff)|(int(weak)<<16)|(name<<32),0))
                    else:
                        value=(ordinal&0xff)|(int(weak)<<8)|(name<<9)
                        packed.append(struct.pack('<I',value)+(b'\0'*4 if fmt==2 else b''))
                blob=struct.pack('<7I',0,0,28,28+2*stride,2,fmt,0)+b''.join(packed)+b'first\0second\0'
                imports=chained_imports(blob,'<')
                self.assertEqual([(x['ordinal'],x['symbol'],x['weak']) for x in imports],[(140,'first',False),(-2,'second',True)])

    def test_corrupt_chained_table_is_rejected(self):
        blob=struct.pack('<7I',0,0,28,28,100,1,0)+b'x\0'
        with self.assertRaises(ValueError): chained_imports(blob,'<')

    def test_framework_id_does_not_shift_library_ordinals(self):
        def dylib(command,name):
            size=(24+len(name)+1+7)&~7
            return struct.pack('<6I',command,size,24,0,0,0)+name.encode()+b'\0'*(size-24-len(name))
        own=dylib(0xd,'@rpath/Own.framework/Own')
        public=dylib(0xc,'/System/Library/Frameworks/Foundation.framework/Foundation')
        private=dylib(0xc,'/System/Library/PrivateFrameworks/Example.framework/Example')
        symbols=b'\0_OBJC_CLASS_$_PrivateType\0'
        payload=32+len(own+public+private)+24
        symtab=struct.pack('<6I',2,24,payload,1,payload+16,len(symbols))
        commands=own+public+private+symtab
        header=struct.pack('<8I',0xfeedfacf,0x100000c,2,6,4,len(commands),0,0)
        nlist=struct.pack('<IBBHQ',1,1,0,2<<8,0)
        slices=parse_macho(header+commands+nlist+symbols)
        self.assertEqual(len(slices[0]['libraries']),2)
        item=slices[0]['imports'][0]
        self.assertEqual(item['library'],'/System/Library/PrivateFrameworks/Example.framework/Example')
        self.assertEqual(item['kind'],'objc-type')
        self.assertFalse(item['weak'])

    def test_public_framework_is_not_automatically_public_api(self):
        self.assertEqual(library_status('/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer'),'requires-public-sdk-symbol-check')
        self.assertEqual(library_status('/System/Library/PrivateFrameworks/MusicUI.framework/MusicUI'),'private-framework')

    def test_truncated_macho_is_rejected(self):
        with self.assertRaises(ValueError): parse_macho(b'\xcf\xfa\xed\xfe'+b'\0'*8)


if __name__=='__main__': unittest.main()
