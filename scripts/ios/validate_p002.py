#!/usr/bin/env python3
"""Host-side P002 scope, source, pin and artifact validators."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_PROBES = (
    "native-c-probe",
    "go-pure-probe",
    "go-cgo-probe",
    "go-multip-probe",
)
EXACT_ALLOWED = {
    ".github/workflows/ios-p002-runtime-qualification.yml",
    "docs/ios/COMPATIBILITY.md",
    "docs/ios/P002_DEVICE_TEST.md",
    "docs/ios/P002_MANIFEST.md",
    "docs/ios/ROADMAP.md",
    "docs/ios/p002-toolchain.json",
    "scripts/ios/build_p002_probes.sh",
    "scripts/ios/cleanup_p002_device.sh",
    "scripts/ios/inspect_p002_macho.py",
    "scripts/ios/run_p002_device.sh",
    "scripts/ios/validate_p001.py",
    "scripts/ios/validate_p002.py",
    "tests/ios/test_validate_p002.py",
}


class ValidationError(Exception):
    pass


def parse_checksum_manifest(text: str,
                            expected_names: tuple[str, ...] = EXPECTED_PROBES) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for number, line in enumerate(text.splitlines(), start=1):
        parts = line.split()
        if len(parts) != 2:
            raise ValidationError(f"checksum line {number} must contain a hash and one filename")
        digest, filename = parts
        filename = filename.removeprefix("*")
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValidationError(f"checksum line {number} has an invalid SHA-256 digest")
        if filename not in expected_names:
            raise ValidationError(f"unexpected checksum filename: {filename}")
        if filename in hashes:
            raise ValidationError(f"duplicate checksum filename: {filename}")
        hashes[filename] = digest
    if tuple(sorted(hashes)) != tuple(sorted(expected_names)):
        raise ValidationError("checksum manifest does not contain every expected probe exactly once")
    return hashes


def validate_macho_records(records: list[dict[str, object]]) -> None:
    by_name = {Path(str(record.get("file", ""))).name: record for record in records}
    if tuple(sorted(by_name)) != tuple(sorted(EXPECTED_PROBES)) or len(records) != len(EXPECTED_PROBES):
        raise ValidationError("Mach-O evidence does not contain the four expected probes exactly once")
    for name in EXPECTED_PROBES:
        record = by_name[name]
        file_output = str(record.get("file_output", ""))
        header = str(record.get("header", ""))
        if "Mach-O 64-bit" not in file_output or "arm64" not in file_output:
            raise ValidationError(f"{name} is not recorded as a 64-bit ARM64 Mach-O")
        if "ARM64" not in header or "EXECUTE" not in header or not re.search(r"\bPIE\b", header):
            raise ValidationError(f"{name} is not recorded as an ARM64 PIE executable")
        platforms = record.get("platforms")
        if platforms != ["IOS"]:
            raise ValidationError(f"{name} has unexpected platform load commands: {platforms}")
        minimum_versions = record.get("minimum_versions")
        if minimum_versions != ["12.0"]:
            raise ValidationError(f"{name} must declare iOS minimum 12.0, got {minimum_versions}")
        libraries = record.get("dynamic_libraries")
        if not isinstance(libraries, list):
            raise ValidationError(f"{name} has no dynamic-library inventory")
        forbidden = (
            "CoreServices.framework",
            "AppKit.framework",
            "Cocoa.framework",
            "ApplicationServices.framework",
            "DiskArbitration.framework",
            "QuickLookUI.framework",
            "Carbon.framework",
        )
        for library in libraries:
            if any(value in str(library) for value in forbidden):
                raise ValidationError(f"{name} imports a macOS-only framework: {library}")


def validate_pin(pin: dict[str, object]) -> None:
    if pin.get("go_version") != "go1.27.3" or pin.get("go_tag") != "go1.27.3":
        raise ValidationError("Go toolchain must be pinned to Go 1.27.3")
    if pin.get("go_source_commit") != "2aae1000ea1d4b28923b96db28acf4e3b99d6aff":
        raise ValidationError("Go source tag commit does not match the verified Go 1.27.3 tag")
    for label, digest in (
        ("source archive", pin.get("go_source_archive_sha256")),
        *(
            (name, item.get("sha256"))
            for name, item in pin.get("go_archives", {}).items()
        ),
        *(
            (name, digest)
            for name, digest in pin.get("runtime_source_sha256", {}).items()
        ),
    ):
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValidationError(f"{label} must have a lowercase SHA-256 digest")
    target = pin.get("target")
    if not isinstance(target, dict) or (
        target.get("GOOS"), target.get("GOARCH"), target.get("minimum_ios"),
        target.get("buildmode"),
    ) != ("ios", "arm64", "12.0", "pie"):
        raise ValidationError("target pin must be ios/arm64, iOS 12.0, buildmode pie")
    if target.get("go_probe_cgo_enabled") is not True:
        raise ValidationError("all ios/arm64 Go probes must enable CGo for external linking")
    if target.get("probe_uses_cgo") != {
        "native-c": False,
        "pure-go": False,
        "cgo-callback": True,
        "multi-p": False,
    }:
        raise ValidationError("probe CGo source-use matrix does not match the probe sources")


def source_files() -> tuple[Path, ...]:
    return (
        ROOT / ".github/workflows/ios-p002-runtime-qualification.yml",
        ROOT / "docs/ios/P002_MANIFEST.md",
        ROOT / "docs/ios/P002_DEVICE_TEST.md",
        ROOT / "docs/ios/p002-toolchain.json",
        ROOT / "scripts/ios/build_p002_probes.sh",
        ROOT / "scripts/ios/cleanup_p002_device.sh",
        ROOT / "scripts/ios/inspect_p002_macho.py",
        ROOT / "scripts/ios/run_p002_device.sh",
        ROOT / "scripts/ios/validate_p001.py",
        ROOT / "scripts/ios/validate_p002.py",
        ROOT / "tests/ios/test_validate_p002.py",
        ROOT / "tools/ios-p002/native-c/main.c",
        ROOT / "tools/ios-p002/pure-go/main.go",
        ROOT / "tools/ios-p002/cgo-callback/callback.h",
        ROOT / "tools/ios-p002/cgo-callback/callback.c",
        ROOT / "tools/ios-p002/cgo-callback/main.go",
        ROOT / "tools/ios-p002/multi-p/main.go",
    )


def validate_sources(check_diff: bool = False) -> None:
    for path in source_files():
        if not path.is_file() or path.stat().st_size == 0:
            raise ValidationError(f"missing or empty P002 source file: {path.relative_to(ROOT)}")

    pin = json.loads((ROOT / "docs/ios/p002-toolchain.json").read_text())
    validate_pin(pin)

    banned = (
        "GODEBUG=asyncpreemptoff",
        "GODEBUG=checkptr=0",
        "-d=checkptr=0",
        "-gcflags=all=-d=checkptr=0",
    )
    for directory in (
        ROOT / "tools/ios-p002",
        ROOT / "scripts/ios/build_p002_probes.sh",
        ROOT / "scripts/ios/run_p002_device.sh",
        ROOT / "scripts/ios/cleanup_p002_device.sh",
        ROOT / ".github/workflows/ios-p002-runtime-qualification.yml",
    ):
        paths = (directory,) if directory.is_file() else directory.rglob("*")
        for path in paths:
            if path.is_file() and path.suffix in (".go", ".c", ".h", ".sh", ".py", ".yml"):
                content = path.read_text(errors="replace")
                for forbidden in banned:
                    if forbidden in content:
                        raise ValidationError(f"runtime-check bypass found in {path.relative_to(ROOT)}")

    if check_diff:
        try:
            base = subprocess.check_output(
                ["git", "-C", str(ROOT), "rev-parse", "--verify", "origin/iOS"],
                text=True,
            ).strip()
        except subprocess.CalledProcessError as exc:
            raise ValidationError("origin/iOS is unavailable; fetch the P002 base before scope validation") from exc
        changed = set(
            subprocess.check_output(
                ["git", "-C", str(ROOT), "diff", "--name-only", f"{base}...HEAD"],
                text=True,
            ).splitlines()
        )
        changed.update(
            subprocess.check_output(
                ["git", "-C", str(ROOT), "diff", "--name-only", "--cached", base],
                text=True,
            ).splitlines()
        )
        untracked = subprocess.check_output(
            ["git", "-C", str(ROOT), "ls-files", "--others", "--exclude-standard"],
            text=True,
        ).splitlines()
        changed.update(untracked)
        unexpected = []
        for path in sorted(changed):
            if path in EXACT_ALLOWED or path.startswith("tools/ios-p002/"):
                continue
            unexpected.append(path)
        if unexpected:
            raise ValidationError(f"out-of-scope changes: {unexpected}")
        subprocess.run(["git", "-C", str(ROOT), "diff", "--check", base], check=True)
        subprocess.run(["git", "-C", str(ROOT), "diff", "--cached", "--check", base], check=True)


def validate_bundle(bundle: Path) -> None:
    checksums = parse_checksum_manifest((bundle / "SHA256SUMS").read_text())
    for name, digest in checksums.items():
        path = bundle / name
        if not path.is_file():
            raise ValidationError(f"probe file is missing: {name}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != digest:
            raise ValidationError(f"probe checksum mismatch: {name}")
    signing = dict(
        line.split("=", 1)
        for line in (bundle / "SIGNING.txt").read_text().splitlines()
        if "=" in line
    )
    if signing.get("signing") != "PASS" or signing.get("method") != "ad-hoc-signature":
        raise ValidationError("bundle signature evidence is incomplete")
    if signing.get("entitlements") != "none":
        raise ValidationError("bundle must not contain entitlements")
    qualification = json.loads((bundle / "qualification.json").read_text())
    statuses = qualification.get("statuses", {})
    for phase in (
        "source_validation",
        "toolchain_qualification",
        "compilation_linking",
        "macho_inspection",
        "signing",
    ):
        if statuses.get(phase) != "PASS":
            raise ValidationError(f"bundle has no PASS evidence for {phase}")
    if statuses.get("physical_device_execution") != "BLOCKED":
        raise ValidationError("CI bundle must leave physical-device execution BLOCKED")

    inspection_file = bundle / "macho-inspection.json"
    if inspection_file.is_file():
        validate_macho_records(json.loads(inspection_file.read_text()))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-diff", action="store_true")
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    try:
        validate_sources(check_diff=args.check_diff)
        if args.bundle:
            validate_bundle(args.bundle)
        print("PASS: P002 sources, toolchain pins, scope and runtime-check policy")
        if args.bundle:
            print("PASS: probe bundle checksums, signature evidence, statuses and Mach-O evidence")
        return 0
    except (ValidationError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
