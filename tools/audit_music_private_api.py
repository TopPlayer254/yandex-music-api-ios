#!/usr/bin/env python3
"""Inventory static Mach-O imports; never rewrite ordinals or remove libraries.

PrivateFrameworks is conclusive about framework status. Imports from public
frameworks remain unclassified without a matching public SDK export/header set.
An import is a binding requirement, not proof that a function executes.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zlib

from macho_audit import iter_slices

DYLIB_LOADS = {0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20}
SPECIAL_ORDINALS = {0: 'self', -1: 'main-executable', -2: 'flat-lookup', -3: 'weak-lookup'}


def bounded(data: bytes, offset: int, count: int) -> bytes:
    if offset < 0 or count < 0 or offset + count > len(data):
        raise ValueError('Mach-O data outside file')
    return data[offset:offset+count]


def cstring(data: bytes, offset: int) -> str:
    if not 0 <= offset < len(data):
        raise ValueError('String offset outside table')
    end = data.find(b'\0', offset)
    if end < 0:
        raise ValueError('Unterminated Mach-O string')
    return data[offset:end].decode('utf-8', errors='replace')


def library_status(path: str) -> str:
    if '/PrivateFrameworks/' in path:
        return 'private-framework'
    if path == '/usr/lib/libMobileGestalt.dylib':
        return 'private-system-library'
    if path.startswith('@'):
        return 'embedded-or-relative'
    if path.startswith('special:'):
        return 'special-lookup'
    return 'requires-public-sdk-symbol-check'


def symbol_kind(name: str) -> str:
    if name.startswith(('_OBJC_CLASS_$_', '_OBJC_METACLASS_$_')):
        return 'objc-type'
    if name.startswith(('_$s', '_$S')):
        if name.endswith(('Mn', 'Ma', 'Mp', 'Mc', 'WP', 'WV', 'VN', 'CMn')):
            return 'swift-type-or-conformance'
        return 'swift-symbol'
    return 'function-or-data'


def chained_imports(blob: bytes, endian: str) -> list[dict]:
    version, _, imports, names, count, fmt, name_format = struct.unpack(endian+'7I', bounded(blob, 0, 28))
    if version != 0 or fmt not in (1, 2, 3) or name_format not in (0, 1):
        raise ValueError('Unsupported chained imports format')
    name_pool = bounded(blob, names, len(blob)-names)
    if name_format == 1:
        name_pool = zlib.decompress(name_pool)
    stride = {1:4, 2:8, 3:16}[fmt]
    bounded(blob, imports, count*stride)
    result = []
    for index in range(count):
        pos = imports + index*stride
        if fmt == 3:
            bits, = struct.unpack_from(endian+'Q', blob, pos)
            ordinal, weak, name = bits & 0xFFFF, bool((bits>>16)&1), bits>>32
            if ordinal > 0xFFF0:
                ordinal -= 0x10000
        else:
            bits, = struct.unpack_from(endian+'I', blob, pos)
            ordinal, weak, name = bits & 0xFF, bool((bits>>8)&1), bits>>9
            if ordinal > 0xF0:
                ordinal -= 0x100
        result.append({'ordinal':ordinal, 'symbol':cstring(name_pool, name), 'weak':weak, 'source':'chained-fixups'})
    return result


def parse_macho(data: bytes) -> list[dict]:
    result=[]
    for base, length in iter_slices(data) or ():
        image=bounded(data, base, length)
        endian='<' if image[:4] == b'\xcf\xfa\xed\xfe' else '>'
        _, cpu, subtype, _, count, command_bytes, _, _ = struct.unpack(endian+'8I', bounded(image,0,32))
        bounded(image,32,command_bytes)
        libraries=[]
        records=[]
        entitlements={}
        cursor=32
        for _ in range(count):
            command,size=struct.unpack(endian+'2I',bounded(image,cursor,8))
            if size < 8 or cursor+size > 32+command_bytes:
                raise ValueError('Invalid Mach-O load command')
            record=bounded(image,cursor,size)
            if command in DYLIB_LOADS:
                name_offset,=struct.unpack_from(endian+'I',record,8)
                name=cstring(record,name_offset)
                libraries.append({'ordinal':len(libraries)+1,'path':name,
                                  'weak_library':command == 0x80000018,'status':library_status(name)})
            if command in (2, 0x80000034):
                records.append((command,record))
            if command == 0x1D:
                off,span=struct.unpack_from(endian+'2I',record,8)
                sig=bounded(image,off,span)
                magic,_,items=struct.unpack('>3I',bounded(sig,0,12))
                if magic == 0xFADE0CC0:
                    for index in range(items):
                        _,loc=struct.unpack('>2I',bounded(sig,12+index*8,8))
                        blob_magic,blob_size=struct.unpack('>2I',bounded(sig,loc,8))
                        if blob_magic == 0xFADE7171:
                            entitlements=plistlib.loads(bounded(sig,loc+8,blob_size-8))
            cursor += size
        imports=[]
        for command,record in records:
            if command == 0x80000034:
                off,span=struct.unpack_from(endian+'2I',record,8)
                imports.extend(chained_imports(bounded(image,off,span),endian))
            else:
                off,count,string_off,string_size=struct.unpack_from(endian+'4I',record,8)
                strings=bounded(image,string_off,string_size)
                bounded(image,off,count*16)
                for index in range(count):
                    name,kind,_,desc,_=struct.unpack_from(endian+'IBBHQ',image,off+index*16)
                    if kind & 0xE0 or kind & 0xE or not (kind&1) or name==0:
                        continue
                    ordinal=desc>>8
                    if ordinal in (0xFE,0xFF):
                        ordinal -= 0x100
                    imports.append({'ordinal':ordinal,'symbol':cstring(strings,name),
                                    'weak':bool(desc&0x40),'source':'nlist'})
        unique={}
        for item in imports:
            ordinal=item['ordinal']
            if 1 <= ordinal <= len(libraries):
                library=libraries[ordinal-1]
            elif ordinal in SPECIAL_ORDINALS:
                library={'path':'special:'+SPECIAL_ORDINALS[ordinal],'status':'special-lookup','weak_library':False}
            else:
                raise ValueError(f'Unresolved dylib ordinal {ordinal}, {len(libraries)} libraries')
            key=(ordinal,item['symbol'])
            if key not in unique:
                unique[key]={**item,'library':library['path'],'status':library['status'],
                             'kind':symbol_kind(item['symbol']),'sources':[],
                             'weak_library':library['weak_library']}
            unique[key]['weak'] &= item['weak']
            unique[key]['sources'].append(item['source'])
        result.append({'cpu':cpu,'subtype':subtype,'libraries':libraries,
                       'imports':list(unique.values()),'entitlements':entitlements})
    return result


def jsonable(value):
    if isinstance(value,bytes): return {'hex':value.hex()}
    raise TypeError(type(value).__name__)


def inventory(app: Path) -> dict:
    app=app.resolve()
    binaries=[]
    for path in sorted(app.rglob('*')):
        if not path.is_file(): continue
        with path.open('rb') as stream: head=stream.read(4)
        if head not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'): continue
        data=path.read_bytes()
        binaries.append({'path':path.relative_to(app).as_posix(),
                         'sha256':hashlib.sha256(data).hexdigest(),'slices':parse_macho(data)})
    rows=[{**item,'binary':binary['path']} for binary in binaries for slice in binary['slices'] for item in slice['imports']]
    private=[item for item in rows if item['status'] in ('private-framework','private-system-library')]
    libraries=sorted({lib['path'] for b in binaries for s in b['slices'] for lib in s['libraries'] if lib['status'] in ('private-framework','private-system-library')})
    return {'schema_version':1,'bundle':app.name,'source_version':'iOS 26.5.1 (23F81)',
            'scope':'Static imports, not dynamic call-site coverage or a public-SDK allowlist.',
            'private_libraries':libraries,'private_symbol_count':len({(i['library'],i['symbol']) for i in private}),
            'private_bindings_per_binary':dict(collections.Counter(i['binary'] for i in private)),
            'binaries':binaries}


def write_reports(report:dict, destination:Path):
    destination.mkdir(parents=True,exist_ok=True)
    (destination/'private-api.json').write_text(json.dumps(report,ensure_ascii=False,indent=2,default=jsonable)+'\n',encoding='utf-8')
    fields=['binary','library','ordinal','symbol','kind','status','weak','weak_library','sources']
    rows=[{**i,'binary':b['path']} for b in report['binaries'] for s in b['slices'] for i in s['imports']]
    for name,filtered in [('all-imports.csv',rows),('private-imports.csv',[i for i in rows if i['status'] in ('private-framework','private-system-library')])]:
        with (destination/name).open('w',encoding='utf-8-sig',newline='') as stream:
            writer=csv.DictWriter(stream,fields,extrasaction='ignore')
            writer.writeheader()
            writer.writerows({**i,'sources':';'.join(sorted(set(i['sources'])))} for i in filtered)
    rights={b['path']:s['entitlements'] for b in report['binaries'] for s in b['slices'] if s['entitlements']}
    (destination/'entitlements.json').write_text(json.dumps(rights,ensure_ascii=False,indent=2,default=jsonable)+'\n',encoding='utf-8')
    unique={}
    for item in rows:
        if item['status'] not in ('private-framework','private-system-library'): continue
        key=(item['library'],item['symbol'])
        if key not in unique:
            unique[key]={'library':item['library'],'symbol':item['symbol'],'kind':item['kind'],'binaries':set()}
        unique[key]['binaries'].add(item['binary'])
    with (destination/'private-symbols.csv').open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.DictWriter(stream,['library','symbol','kind','binaries'])
        writer.writeheader()
        writer.writerows({**i,'binaries':';'.join(sorted(i['binaries']))} for _,i in sorted(unique.items()))
    lines=['# Приватные зависимости оригинального Music.app', '',
           'Источник: iOS 26.5.1, build 23F81. Бинарники не изменялись.', '',
           f"В {len(report['binaries'])} бинарниках найдено {len(report['private_libraries'])} уникальных приватных библиотек и {report['private_symbol_count']} уникальных импортов из них.", '',
           'Это статические требования связывания. Они не доказывают выполнение каждого вызова. Полная классификация SPI внутри публичных frameworks требует сравнения с публичным SDK; такие импорты отдельно помечены `requires-public-sdk-symbol-check`.', '',
           '## Количество импортов из приватных библиотек', '', '| Бинарник | Импорты |', '| --- | ---: |']
    lines += [f'| `{name}` | {count} |' for name,count in report['private_bindings_per_binary'].items()]
    lines += ['', '## Все приватные библиотеки', '']
    for library in report['private_libraries']:
        uses=[i for i in rows if i['library']==library]
        consumers={b['path'] for b in report['binaries'] for s in b['slices']
                   if any(lib['path']==library for lib in s['libraries'])}
        lines += [f'### {PurePosixPath(library).name}', '', f'`{library}`', '',
                  f"Уникальных импортов: {len({i['symbol'] for i in uses})}. Бинарников с LC_LOAD_DYLIB: {len(consumers)}.", '']
    lines += ['## Системные права и XPC', '', 'Полный список значений — в `entitlements.json`. Ключи с `.private` и `platform-application` выписаны ниже; остальные права сохранены для проверки provisioning profile, их нельзя автоматически считать публичными или приватными.', '']
    for binary,entitlements in rights.items():
        keys=[k for k in entitlements if '.private' in k or k=='platform-application']
        if keys:
            lines += [f'### {binary}', '']+[f'- `{key}`' for key in keys]+['']
        services=entitlements.get('com.apple.security.exception.mach-lookup.global-name',[])
        if services:
            lines += ['Запрашиваемые Mach/XPC-сервисы:', '']+[f'- `{service}`' for service in services]+['']
    lines += ['## Ограничения замены', '',
              'Удаление LC_LOAD_DYLIB изменяет нумерацию library ordinals и не переписывает nlist/chained fixups, код, Swift metadata или Objective-C superclasses. Подмена импортов пустыми функциями не реализует ABI классов, протоколов и структур.', '',
              'Данный отчёт не является модифицированным приложением. Замена Apple backend и проверка запуска не выполнены.', '',
              'Формат chained imports: https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h',
              'Provisioning и entitlements: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles', '']
    (destination/'PRIVATE-API.md').write_text('\n'.join(lines),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    report=inventory(args.app)
    write_reports(report,args.output)
    print(json.dumps({k:v for k,v in report.items() if k!='binaries'},ensure_ascii=False,indent=2))


if __name__=='__main__': main()
