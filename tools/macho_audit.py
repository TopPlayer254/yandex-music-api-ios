#!/usr/bin/env python3
"""Small, dependency-free Mach-O auditor for IPA repackaging work."""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

DYLIB_COMMANDS = {
    0x0C: "LC_LOAD_DYLIB",
    0x0D: "LC_ID_DYLIB",
    0x18 | 0x80000000: "LC_LOAD_WEAK_DYLIB",
    0x1F | 0x80000000: "LC_REEXPORT_DYLIB",
    0x23 | 0x80000000: "LC_LOAD_UPWARD_DYLIB",
    0x20: "LC_LAZY_LOAD_DYLIB",
}


def iter_slices(data: bytes):
    if len(data) < 4:
        return
    magic_be = struct.unpack_from(">I", data, 0)[0]
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        is_64 = magic_be == FAT_MAGIC_64
        count = struct.unpack_from(">I", data, 4)[0]
        stride = 32 if is_64 else 20
        for index in range(count):
            pos = 8 + index * stride
            if pos + stride > len(data):
                return
            if is_64:
                _, _, offset, size, _, _ = struct.unpack_from(">iiQQII", data, pos)
            else:
                _, _, offset, size, _ = struct.unpack_from(">iiIII", data, pos)
            yield offset, size
        return
    magic_le = struct.unpack_from("<I", data, 0)[0]
    if magic_le in (MH_MAGIC_64, MH_CIGAM_64):
        yield 0, len(data)


def dylib_loads(data: bytes):
    for slice_offset, slice_size in iter_slices(data) or ():
        if slice_offset + 32 > len(data):
            continue
        magic = struct.unpack_from("<I", data, slice_offset)[0]
        endian = "<" if magic == MH_MAGIC_64 else ">"
        ncmds = struct.unpack_from(endian + "I", data, slice_offset + 16)[0]
        cursor = slice_offset + 32
        slice_end = min(len(data), slice_offset + slice_size)
        for _ in range(ncmds):
            if cursor + 8 > slice_end:
                break
            cmd, cmdsize = struct.unpack_from(endian + "II", data, cursor)
            if cmdsize < 8 or cursor + cmdsize > slice_end:
                break
            if cmd in DYLIB_COMMANDS and cmdsize >= 24:
                name_offset = struct.unpack_from(endian + "I", data, cursor + 8)[0]
                name_start = cursor + name_offset
                name_end = data.find(b"\0", name_start, cursor + cmdsize)
                if name_start < cursor + cmdsize and name_end >= 0:
                    yield slice_offset, cursor, cmd, data[name_start:name_end].decode("utf-8", "replace")
            cursor += cmdsize


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            head = handle.read(4)
    except OSError:
        return False
    if len(head) != 4:
        return False
    return struct.unpack(">I", head)[0] in {FAT_MAGIC, FAT_MAGIC_64, MH_MAGIC_64, MH_CIGAM_64}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--domains", action="store_true")
    args = parser.parse_args()

    domain_re = re.compile(rb"(?i)(?:https?://)?(?:[a-z0-9-]+\.)+(?:com|net|org|ru|io|app)(?:/[a-z0-9_./?=&%:+@~-]*)?")
    for path in sorted(p for p in args.root.rglob("*") if p.is_file()):
        if not is_macho(path):
            continue
        data = path.read_bytes()
        print(f"[{path.relative_to(args.root)}]")
        for _, _, cmd, name in dylib_loads(data):
            print(f"  {DYLIB_COMMANDS[cmd]} {name}")
        if args.domains:
            domains = sorted({m.group().decode("ascii", "replace") for m in domain_re.finditer(data)})
            for domain in domains:
                if any(key in domain.lower() for key in ("metric", "analytic", "appsfly", "yandex", "adjust", "telemetr")):
                    print(f"  DOMAIN {domain}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
