#!/usr/bin/env python3
"""Package the original Music UI with the experimental Kreshka framework."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import tempfile
import zipfile

from macho_audit import is_macho, dylib_loads, DYLIB_COMMANDS

BUNDLE_ID='dev.hikeri.kreshka.music'
ORIGINAL_SHA256='1111db60f9e19436b30f732dde0f9d0cbaf0b1127bee1d3ca3bee33ba3dedd2a'
BRIDGE_LOAD='@executable_path/Frameworks/KreshkaBridge.framework/KreshkaBridge'
CORE_ANALYTICS='/System/Library/PrivateFrameworks/CoreAnalytics.framework/CoreAnalytics'


def patch_macho(data:bytes, inject:str|None=None) -> bytes:
    if data[:4]!=b'\xcf\xfa\xed\xfe':
        raise ValueError('Only thin little-endian 64-bit Mach-O is supported')
    image=bytearray(data)
    count,size=struct.unpack_from('<II',image,16)
    if 32+size>len(image): raise ValueError('Invalid load-command extent')
    cursor=32
    commands=[]
    first_section=len(image)
    for _ in range(count):
        command,span=struct.unpack_from('<II',image,cursor)
        if span<8 or cursor+span>32+size: raise ValueError('Invalid load command')
        record=bytes(image[cursor:cursor+span])
        if command in DYLIB_COMMANDS and command != 0xD:
            name_offset=struct.unpack_from('<I',record,8)[0]
            name=record[name_offset:].split(b'\0',1)[0].decode()
            if name==CORE_ANALYTICS:
                replacement=BRIDGE_LOAD.encode()+b'\0'
                if len(replacement)>span-name_offset: raise ValueError('Analytics replacement does not fit')
                record=record[:name_offset]+replacement+b'\0'*(span-name_offset-len(replacement))
        if command==0x19:
            sections=struct.unpack_from('<I',record,64)[0]
            if 72+80*sections>span: raise ValueError('Invalid segment sections')
            for index in range(sections):
                offset=struct.unpack_from('<I',record,72+80*index+48)[0]
                if offset: first_section=min(first_section,offset)
        if command==0x1D:
            offset,length=struct.unpack_from('<II',record,8)
            if offset+length>len(image): raise ValueError('Invalid signature span')
            image[offset:offset+length]=b'\0'*length
        else: commands.append(record)
        cursor += span
    if inject:
        name=inject.encode()+b'\0'
        span=(24+len(name)+7)&~7
        commands.append(struct.pack('<6I',0xC,span,24,0,0x10000,0x10000)+name+b'\0'*(span-24-len(name)))
    payload=b''.join(commands)
    if 32+len(payload)>first_section:
        raise ValueError('Insufficient header padding; sections must not be overwritten')
    image[32:32+max(size,len(payload))]=payload+b'\0'*max(0,size-len(payload))
    struct.pack_into('<II',image,16,len(commands),len(payload))
    return bytes(image)


def package(original:Path, framework:Path, output:Path, simulator=False):
    original=original.resolve(); framework=framework.resolve(); output=output.resolve()
    source_executable=plistlib.loads((original/'Info.plist').read_bytes())['CFBundleExecutable']
    source_hash=hashlib.sha256((original/source_executable).read_bytes()).hexdigest()
    if not simulator and source_hash!=ORIGINAL_SHA256:
        raise ValueError('Unexpected original Music binary; refusing version-specific patch')
    if not (framework/'KreshkaBridge').is_file(): raise ValueError('Compiled KreshkaBridge framework is missing')
    with tempfile.TemporaryDirectory(prefix='kreshka-package-') as temporary:
        app=Path(temporary)/'Payload/Music.app'
        shutil.copytree(original,app)
        for path in [app/'PlugIns',app/'Extensions',app/'Metadata.appintents']:
            if path.is_dir(): shutil.rmtree(path)
        for path in list(app.rglob('XPCServices')):
            if path.is_dir(): shutil.rmtree(path)
        destination=app/'Frameworks/KreshkaBridge.framework'
        if destination.exists(): raise ValueError('Original already includes the bridge')
        destination.parent.mkdir(exist_ok=True)
        shutil.copytree(framework,destination)
        info=plistlib.loads((app/'Info.plist').read_bytes())
        info['CFBundleIdentifier']=BUNDLE_ID
        info['CFBundleDisplayName']='Крешка'
        info['UIFileSharingEnabled']=True
        info['LSSupportsOpeningDocumentsInPlace']=True
        info['NSAppleMusicUsageDescription']='Доступ к музыкальному интерфейсу приложения.'
        info['KreshkaBridgeVersion']='0.1.0-experimental'
        info['CFBundleURLTypes']=[{'CFBundleURLName':BUNDLE_ID+'.oauth','CFBundleURLSchemes':['maplemusic','kreshkamusic']}]
        info['YandexClientID']=__import__('os').environ.get('YANDEX_CLIENT_ID','')
        info['YandexRedirectURI']='maplemusic://oauth'
        info['MusicBackendBaseURL']=__import__('os').environ.get('MUSIC_BACKEND_BASE_URL','')
        info['UIBackgroundModes']=['audio']
        for key in ['SBMachServices','BGTaskSchedulerPermittedIdentifiers','LSCounterpartIdentifiers',
                    'NSUserActivityTypes','INIntentsSupported','UTExportedTypeDeclarations',
                    'UNUserNotificationCenter','NSRegulatoryPrivacyDisclosure']:
            info.pop(key,None)
        (app/'Info.plist').write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_BINARY))
        stripped=[]
        original_loads=[name for _,_,_,name in dylib_loads((app/source_executable).read_bytes())]
        for path in sorted(app.rglob('*')):
            if not path.is_file(): continue
            if path.name=='embedded.mobileprovision': path.unlink(); continue
            if is_macho(path):
                path.write_bytes(patch_macho(path.read_bytes(),BRIDGE_LOAD if path==app/source_executable else None))
                path.chmod(0o755)
                stripped.append(path.relative_to(app).as_posix())
        for path in sorted(app.rglob('_CodeSignature'),key=lambda p:len(p.parts),reverse=True):
            if path.is_dir(): shutil.rmtree(path)
        loads=[name for _,_,_,name in dylib_loads((app/source_executable).read_bytes())]
        expected=[BRIDGE_LOAD if name==CORE_ANALYTICS else name for name in original_loads]+[BRIDGE_LOAD]
        if loads!=expected: raise ValueError('Original library ordinals changed')
        output.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
            for path in sorted(app.rglob('*')):
                if not path.is_file(): continue
                member=zipfile.ZipInfo(path.relative_to(Path(temporary)).as_posix())
                member.create_system=3
                member.external_attr=(stat.S_IFREG | (0o755 if is_macho(path) else 0o644))<<16
                member.compress_type=zipfile.ZIP_DEFLATED
                archive.writestr(member,path.read_bytes())
        with zipfile.ZipFile(output) as archive:
            if archive.testzip(): raise ValueError('IPA ZIP integrity check failed')
        report={'bundle_id':BUNDLE_ID,'original_sha256':source_hash,'original_ui_retained':True,
                'bridge':'KreshkaBridge 0.1.0-experimental','apple_backend_fully_replaced':False,
                'direct_coreanalytics_imports_disabled':['AnalyticsSendEvent','AnalyticsSendEventLazy'],
                'runtime_device_verified':False,'simulator_package':simulator,
                'unsigned_macho_files':stripped,'ipa_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
                'limitations':['Private method adapters are conditional on runtime ABI.',
                               'Unsupported Apple HTTP endpoints return explicit errors.',
                               'No claim of complete MPC/Swift MusicKit route coverage.']}
        output.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(report,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original',type=Path,required=True)
    parser.add_argument('--framework',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--simulator',action='store_true')
    args=parser.parse_args()
    package(args.original,args.framework,args.output,args.simulator)
