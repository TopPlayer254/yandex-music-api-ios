#!/usr/bin/env python3
"""Create a cleaned, unsigned, sideload-ready IPA from the supplied package.

The script deliberately does not alter authentication or subscription enforcement.
It removes known third-party injected dylibs, neutralizes telemetry destinations,
replaces all legacy icon files, strips obsolete signatures, and validates the result.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import struct
import zipfile
from collections import Counter
from pathlib import Path, PurePosixPath

from PIL import Image

from macho_audit import DYLIB_COMMANDS, dylib_loads, is_macho


INJECTED_DYLIBS = {
    "flutersult.dylib",
    "iOSGods.dylib",
    "liberdade.dylib",
    "libpro.dylib",
    "libps.dylib",
    "libsubstrate.dylib",
    "lidersunframe.dylib",
    "popabobra.dylib",
    "putcher_concurent.dylib",
    "SatellaJailed.dylib",
}

TELEMETRY_REPLACEMENTS = {
    b"https://startup-mobile.ap.yandex-net.ru": b"https://0.invalid",
    b"https://startup.mobile.yandex.net": b"https://0.invalid",
    b"https://startup.mobile.webvisor.com": b"https://0.invalid",
    b"https://u.startup.mobile.webvisor.com": b"https://0.invalid",
    b"https://appmetrica.yandex.com": b"https://0.invalid",
    b"https://appmetrica.io": b"https://0.invalid",
    b"redirect.appmetrica.yandex.com": b"0.invalid",
    b"https://app.appsflyer.com": b"https://0.invalid",
    b"appsflyersdk.com": b"0.invalid",
    b"app.adjust.com": b"0.invalid",
    b"https://api.browser.yandex.ru/uma_proto": b"https://0.invalid",
    b"https://yandex.ru/clck/click": b"https://0.invalid",
    b"http://back.yandex.ru/": b"http://0.invalid/",
    b"http://log-test.strm.yandex.net/log": b"http://0.invalid",
    b"http://log-test.strm.yandex.net/testPayload": b"http://0.invalid",
    b"https://log.strm.yandex.ru/log": b"https://0.invalid",
    b"https://upload.stat.yandex-team.ru/": b"https://0.invalid",
}

SIGNING_ARTIFACT_FILES = {"embedded.mobileprovision", "SignedByEsign", ".Dump_GBLW.txt"}
SIGNING_ARTIFACT_DIRS = {"_CodeSignature", "SC_Info"}
SYSTEM_DYLIB = b"/usr/lib/libSystem.B.dylib"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_extract(archive: Path, destination: Path) -> None:
    root = destination.resolve()
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            pure = PurePosixPath(member.filename)
            if pure.is_absolute() or ".." in pure.parts:
                raise ValueError(f"Unsafe archive member: {member.filename}")
            target = destination.joinpath(*pure.parts)
            if root not in (target.resolve(), *target.resolve().parents):
                raise ValueError(f"Archive member escapes staging: {member.filename}")
        source.extractall(destination)


def replace_icons(app: Path, icon_path: Path) -> dict[str, dict[str, object]]:
    specs = {
        "icon.png": (512, 512),
        "icon@2x.png": (512, 512),
        "icon@3x.png": (512, 512),
        "AppIcon60x60@2x.png": (120, 120),
        "AppIcon76x76@2x~ipad.png": (152, 152),
    }
    with Image.open(icon_path) as opened:
        rgba = opened.convert("RGBA")
        background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        background.alpha_composite(rgba)
        source = background.convert("RGB")
        result: dict[str, dict[str, object]] = {}
        for name, size in specs.items():
            rendered = source.resize(size, Image.Resampling.LANCZOS)
            target = app / name
            rendered.save(target, format="PNG", optimize=True)
            result[name] = {"size": list(size), "sha256": sha256(target)}
    return result


def patch_injected_loads(path: Path, data: bytearray) -> list[dict[str, str]]:
    changes: list[dict[str, str]] = []
    for _, command_offset, command, name in list(dylib_loads(bytes(data))):
        basename = PurePosixPath(name).name
        if basename not in INJECTED_DYLIBS:
            continue
        endian = "<" if struct.unpack_from("<I", data, 0)[0] == 0xFEEDFACF else ">"
        name_offset = struct.unpack_from(endian + "I", data, command_offset + 8)[0]
        start = command_offset + name_offset
        old = name.encode("utf-8")
        if len(SYSTEM_DYLIB) > len(old):
            raise ValueError(f"Replacement does not fit in load command: {name}")
        data[start : start + len(old)] = SYSTEM_DYLIB + b"\0" * (len(old) - len(SYSTEM_DYLIB))
        changes.append({"file": str(path), "command": DYLIB_COMMANDS[command], "removed": name})
    return changes


def patch_telemetry(data: bytearray) -> Counter[str]:
    counts: Counter[str] = Counter()
    for old, new in TELEMETRY_REPLACEMENTS.items():
        if len(new) > len(old):
            raise ValueError(f"Telemetry replacement is too long: {old!r}")
        count = data.count(old)
        if not count:
            continue
        data[:] = data.replace(old, new + b"\0" * (len(old) - len(new)))
        counts[old.decode("ascii")] += count
    return counts


def patch_macho_files(app: Path) -> tuple[list[dict[str, str]], Counter[str], list[str]]:
    load_changes: list[dict[str, str]] = []
    telemetry_counts: Counter[str] = Counter()
    patched_files: list[str] = []
    for path in sorted(p for p in app.rglob("*") if p.is_file() and is_macho(p)):
        data = bytearray(path.read_bytes())
        changes = patch_injected_loads(path.relative_to(app), data)
        counts = patch_telemetry(data)
        if changes or counts:
            path.write_bytes(data)
            patched_files.append(str(path.relative_to(app)))
            load_changes.extend(changes)
            telemetry_counts.update(counts)
    return load_changes, telemetry_counts, patched_files


def clean_info_plist(app: Path) -> dict[str, object]:
    path = app / "Info.plist"
    info = plistlib.loads(path.read_bytes())
    original_types = info.get("CFBundleURLTypes", [])
    kept_types = [
        item
        for item in original_types
        if item.get("CFBundleURLName") != "yandexmusic-metrica-tracking"
        and "yandexmusic-metrica-tracking" not in item.get("CFBundleURLSchemes", [])
    ]
    info["CFBundleURLTypes"] = kept_types
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False))
    schemes = {scheme for item in kept_types for scheme in item.get("CFBundleURLSchemes", [])}
    return {
        "removed_url_type_count": len(original_types) - len(kept_types),
        "login_schemes_preserved": sorted(
            schemes.intersection({"yandexauth", "yandexauth2", "yandexauth3", "yandexauth4", "secondaryyandexloginsdk"})
        ),
    }


def remove_artifacts(app: Path) -> list[str]:
    removed: list[str] = []
    directories = sorted(
        (p for p in app.rglob("*") if p.is_dir() and p.name in SIGNING_ARTIFACT_DIRS),
        key=lambda value: len(value.parts),
        reverse=True,
    )
    for path in directories:
        removed.append(str(path.relative_to(app)) + "/")
        shutil.rmtree(path)
    for path in sorted(p for p in app.rglob("*") if p.is_file() and p.name in SIGNING_ARTIFACT_FILES):
        removed.append(str(path.relative_to(app)))
        path.unlink()
    for name in sorted(INJECTED_DYLIBS):
        path = app / name
        if path.exists():
            removed.append(str(path.relative_to(app)))
            path.unlink()
    return removed


def write_ipa(staging: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(staging.rglob("*")):
            relative = path.relative_to(staging).as_posix()
            if path.is_dir():
                info = zipfile.ZipInfo(relative.rstrip("/") + "/")
                info.create_system = 3
                info.compress_type = zipfile.ZIP_STORED
                info.external_attr = (stat.S_IFDIR | 0o755) << 16
                archive.writestr(info, b"")
                continue
            info = zipfile.ZipInfo(relative)
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = stat.S_IFREG | (0o755 if is_macho(path) else 0o644)
            info.external_attr = mode << 16
            with path.open("rb") as source, archive.open(info, "w", force_zip64=True) as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)


def validate(app: Path, output: Path) -> dict[str, object]:
    failures: list[str] = []
    remaining_injected_loads: list[str] = []
    remaining_telemetry: Counter[str] = Counter()
    for path in sorted(p for p in app.rglob("*") if p.is_file() and is_macho(p)):
        data = path.read_bytes()
        for _, _, _, name in dylib_loads(data):
            if PurePosixPath(name).name in INJECTED_DYLIBS:
                remaining_injected_loads.append(f"{path.relative_to(app)}: {name}")
        for old in TELEMETRY_REPLACEMENTS:
            count = data.count(old)
            if count:
                remaining_telemetry[old.decode("ascii")] += count
    remaining_injected_files = sorted(name for name in INJECTED_DYLIBS if (app / name).exists())
    signature_artifacts = sorted(
        str(p.relative_to(app))
        for p in app.rglob("*")
        if p.name in SIGNING_ARTIFACT_FILES | SIGNING_ARTIFACT_DIRS
    )
    font_count = sum(1 for _ in app.rglob("*.ttf"))
    info = plistlib.loads((app / "Info.plist").read_bytes())
    schemes = {
        scheme
        for item in info.get("CFBundleURLTypes", [])
        for scheme in item.get("CFBundleURLSchemes", [])
    }
    required_login_schemes = {"yandexauth", "secondaryyandexloginsdk"}
    if remaining_injected_loads:
        failures.append("Injected load commands remain")
    if remaining_injected_files:
        failures.append("Injected dylib files remain")
    if remaining_telemetry:
        failures.append("Telemetry destinations remain")
    if signature_artifacts:
        failures.append("Old signing artifacts remain")
    if not required_login_schemes.issubset(schemes):
        failures.append("Required login URL schemes are missing")
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        if "Payload/Maple.app/Info.plist" not in names:
            failures.append("IPA has no application Info.plist")
        bad_roots = sorted(name for name in names if not name.startswith("Payload/"))
        if bad_roots:
            failures.append("IPA contains entries outside Payload")
        tested = archive.testzip()
        if tested:
            failures.append(f"Corrupt ZIP entry: {tested}")
    return {
        "ok": not failures,
        "failures": failures,
        "remaining_injected_loads": remaining_injected_loads,
        "remaining_injected_files": remaining_injected_files,
        "remaining_telemetry": dict(remaining_telemetry),
        "old_signing_artifacts": signature_artifacts,
        "login_schemes_present": sorted(schemes.intersection(required_login_schemes)),
        "yandex_font_files_preserved_for_runtime_safety": font_count,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--icon", required=True, type=Path)
    parser.add_argument("--staging", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    for path in (args.input, args.icon):
        if not path.is_file():
            raise FileNotFoundError(path)
    if args.staging.exists():
        raise FileExistsError(f"Refusing to overwrite staging directory: {args.staging}")
    args.staging.mkdir(parents=True)
    safe_extract(args.input, args.staging)
    apps = list((args.staging / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise ValueError(f"Expected exactly one app bundle, found {len(apps)}")
    app = apps[0]

    icons = replace_icons(app, args.icon)
    load_changes, telemetry_counts, patched_files = patch_macho_files(app)
    plist_changes = clean_info_plist(app)
    removed_artifacts = remove_artifacts(app)
    write_ipa(args.staging, args.output)
    validation = validate(app, args.output)

    report = {
        "input": {"path": str(args.input.resolve()), "sha256": sha256(args.input)},
        "icon_source": {"path": str(args.icon.resolve()), "sha256": sha256(args.icon)},
        "output": {"path": str(args.output.resolve()), "sha256": sha256(args.output), "bytes": args.output.stat().st_size},
        "icons": icons,
        "injected_load_commands_neutralized": load_changes,
        "telemetry_strings_neutralized": dict(sorted(telemetry_counts.items())),
        "macho_files_patched": patched_files,
        "plist": plist_changes,
        "artifacts_removed": removed_artifacts,
        "validation": validation,
        "limitations": {
            "subscription_and_login": "Preserved; no access-control bypass was performed.",
            "fonts": "Bundled fonts were preserved because the precompiled registrar asserts that each TTF exists; source is required for a safe SF Pro migration.",
            "swiftui": "No source project was present, so compiled Maple components were not rewritten.",
            "signing": "The IPA is unsigned and must be signed by the user's sideloading tool or certificate.",
        },
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if validation["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
