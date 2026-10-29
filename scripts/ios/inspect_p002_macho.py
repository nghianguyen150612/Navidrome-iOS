#!/usr/bin/env python3
"""Inspect P002 probe Mach-O headers, load commands, dependencies and imports."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

EXPECTED = (
    "native-c-probe",
    "go-pure-probe",
    "go-cgo-probe",
    "go-multip-probe",
)
MACOS_ONLY_DEPENDENCIES = (
    "CoreServices.framework",
    "AppKit.framework",
    "Cocoa.framework",
    "ApplicationServices.framework",
    "DiskArbitration.framework",
    "QuickLookUI.framework",
    "Carbon.framework",
)
DYLIB_LOAD_COMMANDS = (
    "LC_LOAD_DYLIB",
    "LC_LOAD_WEAK_DYLIB",
    "LC_REEXPORT_DYLIB",
    "LC_LAZY_LOAD_DYLIB",
    "LC_LOAD_UPWARD_DYLIB",
)


class InspectionError(Exception):
    pass


def version_tuple(value: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in value.split("."))
    except ValueError as exc:
        raise InspectionError(f"invalid OS version: {value}") from exc


def parse_load_commands(text: str) -> dict[str, object]:
    commands: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("cmd "):
            current = {"cmd": stripped[4:]}
            commands.append(current)
            continue
        if current is None:
            continue
        parts = stripped.split(None, 1)
        if len(parts) == 2:
            current[parts[0]] = parts[1]

    platforms: list[str] = []
    minimum_versions: list[str] = []
    dynamic_libraries: list[str] = []
    for command in commands:
        kind = command["cmd"]
        if kind == "LC_BUILD_VERSION":
            platform = command.get("platform", "")
            platforms.append("IOS" if platform in ("IOS", "2") else platform.upper())
            if "minos" in command:
                minimum_versions.append(command["minos"])
        elif kind == "LC_VERSION_MIN_IPHONEOS":
            platforms.append("IOS")
            if "version" in command:
                minimum_versions.append(command["version"])
        elif kind == "LC_VERSION_MIN_MACOSX":
            platforms.append("MACOS")
            if "version" in command:
                minimum_versions.append(command["version"])
        elif kind in DYLIB_LOAD_COMMANDS:
            if "name" in command:
                dynamic_libraries.append(command["name"])

    return {
        "commands": commands,
        "platforms": platforms,
        "minimum_versions": minimum_versions,
        "dynamic_libraries": dynamic_libraries,
    }


def validate_header(file_output: str, header_output: str, load_output: str,
                    dependency_output: str, sdk_path: str) -> dict[str, object]:
    if "Mach-O 64-bit" not in file_output or "arm64" not in file_output:
        raise InspectionError("file(1) did not identify a 64-bit ARM64 Mach-O")
    if "ARM64" not in header_output or "EXECUTE" not in header_output:
        raise InspectionError("Mach-O header is not an ARM64 executable")
    if not re.search(r"\bPIE\b", header_output):
        raise InspectionError("Mach-O header does not carry the PIE flag")

    parsed = parse_load_commands(load_output)
    platforms = parsed["platforms"]
    minimum_versions = parsed["minimum_versions"]
    if not platforms:
        raise InspectionError("no iOS or macOS platform load command was found")
    if any(platform != "IOS" for platform in platforms):
        raise InspectionError(f"unexpected Mach-O platform load command: {platforms}")
    if not minimum_versions:
        raise InspectionError("no minimum OS version was found")
    if any(version_tuple(version) != (12, 0) for version in minimum_versions):
        raise InspectionError(f"minimum OS must be exactly iOS 12.0: {minimum_versions}")

    if sdk_path and (sdk_path in dependency_output or sdk_path in load_output):
        raise InspectionError("a load command contains the build-host SDK path")
    for library in parsed["dynamic_libraries"]:
        if any(name in library for name in MACOS_ONLY_DEPENDENCIES):
            raise InspectionError(f"macOS-only dynamic dependency: {library}")
    return parsed


def run(command: list[str]) -> str:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise InspectionError(f"required inspection tool is missing: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        raise InspectionError(f"{' '.join(command)} failed: {stderr}") from exc
    return result.stdout


def inspect(binary: Path, out: Path, sdk_path: str) -> dict[str, object]:
    if not binary.is_file() or binary.stat().st_size == 0:
        raise InspectionError(f"missing or empty probe executable: {binary}")
    name = binary.name
    file_output = run(["file", str(binary)])
    header_output = run(["otool", "-hv", str(binary)])
    load_output = run(["otool", "-l", str(binary)])
    dependency_output = run(["otool", "-L", str(binary)])
    imports_output = run(["nm", "-u", str(binary)])

    (out / f"{name}.file.txt").write_text(file_output)
    (out / f"{name}.header.txt").write_text(header_output)
    (out / f"{name}.load-commands.txt").write_text(load_output)
    (out / f"{name}.dylibs.txt").write_text(dependency_output)
    (out / f"{name}.imports.txt").write_text(imports_output)
    parsed = validate_header(file_output, header_output, load_output, dependency_output, sdk_path)
    return {
        "file": str(binary),
        "size_bytes": binary.stat().st_size,
        "file_output": file_output.strip(),
        "header": header_output.strip(),
        "platforms": parsed["platforms"],
        "minimum_versions": parsed["minimum_versions"],
        "dynamic_libraries": parsed["dynamic_libraries"],
        "imports_file": f"{name}.imports.txt",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sdk-path", required=True)
    parser.add_argument("binaries", nargs="+", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    names = tuple(path.name for path in args.binaries)
    if names != EXPECTED:
        print(f"FAIL: probe order/names must be exactly {EXPECTED}, got {names}", file=sys.stderr)
        return 1

    records = []
    try:
        for binary in args.binaries:
            record = inspect(binary, args.output, args.sdk_path)
            records.append(record)
            print(f"PASS: {binary.name}: iOS ARM64 executable, PIE, minos 12.0")
        (args.output / "macho-inspection.json").write_text(
            json.dumps(records, indent=2, sort_keys=True) + "\n"
        )
        with (args.output / "macho-summary.txt").open("w") as stream:
            for record in records:
                stream.write(f"{record['file']}\n")
                stream.write(f"  file: {record['file_output']}\n")
                stream.write(f"  platform: {','.join(record['platforms'])}\n")
                stream.write(f"  minimum_os: {','.join(record['minimum_versions'])}\n")
                stream.write("  dynamic libraries:\n")
                for library in record["dynamic_libraries"]:
                    stream.write(f"    {library}\n")
                stream.write(f"  imported symbols: {record['imports_file']}\n")
        return 0
    except InspectionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
