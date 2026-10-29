#!/usr/bin/env python3
"""Host-side tests and negative controls for P002 evidence validation."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/ios"))

from validate_p002 import (  # noqa: E402
    ValidationError,
    parse_checksum_manifest,
    validate_macho_records,
    validate_pin,
)
from inspect_p002_macho import (  # noqa: E402
    InspectionError,
    parse_load_commands,
    validate_header,
)


PROBES = (
    "native-c-probe",
    "go-pure-probe",
    "go-cgo-probe",
    "go-multip-probe",
)


class ToolchainPinTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pin = json.loads((ROOT / "docs/ios/p002-toolchain.json").read_text())

    def test_go_probe_build_enables_external_cgo_linking(self) -> None:
        validate_pin(self.pin)

    def test_negative_control_rejects_cgo_disabled_for_ios(self) -> None:
        pin = json.loads(json.dumps(self.pin))
        pin["target"]["go_probe_cgo_enabled"] = False
        with self.assertRaises(ValidationError):
            validate_pin(pin)


def good_records() -> list[dict[str, object]]:
    return [
        {
            "file": name,
            "file_output": f"{name}: Mach-O 64-bit executable arm64",
            "header": "Mach header ARM64 EXECUTE PIE",
            "platforms": ["IOS"],
            "minimum_versions": ["12.0"],
            "dynamic_libraries": ["/usr/lib/libSystem.B.dylib"],
        }
        for name in PROBES
    ]


class ChecksumTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = "\n".join(f"{'a' * 64}  {name}" for name in PROBES) + "\n"

    def test_valid_manifest(self) -> None:
        parsed = parse_checksum_manifest(self.manifest)
        self.assertEqual(set(parsed), set(PROBES))

    def test_negative_control_rejects_bad_digest(self) -> None:
        bad = self.manifest.replace("a" * 64, "z" * 64, 1)
        with self.assertRaises(ValidationError):
            parse_checksum_manifest(bad)

    def test_negative_control_rejects_path_traversal(self) -> None:
        bad = self.manifest.replace("native-c-probe", "../native-c-probe")
        with self.assertRaises(ValidationError):
            parse_checksum_manifest(bad)

    def test_negative_control_rejects_duplicates_and_missing_artifacts(self) -> None:
        lines = self.manifest.splitlines()
        lines[-1] = lines[0]
        with self.assertRaises(ValidationError):
            parse_checksum_manifest("\n".join(lines))


class MachOTests(unittest.TestCase):
    def test_valid_ios_arm64_pie_records(self) -> None:
        validate_macho_records(good_records())

    def test_negative_control_rejects_macos_platform(self) -> None:
        records = good_records()
        records[0]["platforms"] = ["MACOS"]
        with self.assertRaises(ValidationError):
            validate_macho_records(records)

    def test_negative_control_rejects_newer_minimum_os(self) -> None:
        records = good_records()
        records[1]["minimum_versions"] = ["13.0"]
        with self.assertRaises(ValidationError):
            validate_macho_records(records)

    def test_negative_control_rejects_macos_framework(self) -> None:
        records = good_records()
        records[2]["dynamic_libraries"] = [
            "/System/Library/Frameworks/CoreServices.framework/CoreServices"
        ]
        with self.assertRaises(ValidationError):
            validate_macho_records(records)


class LoadCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.load_commands = """\
Load command 1
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform IOS
    minos 12.0
      sdk 18.0
   ntools 1
     tool LD
  version 1115.7
Load command 2
      cmd LC_LOAD_DYLIB
  cmdsize 56
     name /usr/lib/libSystem.B.dylib (offset 24)
"""
        self.file_output = "native-c-probe: Mach-O 64-bit executable arm64"
        self.header_output = "Mach header ARM64 ALL EXECUTE PIE"
        self.dependency_output = "native-c-probe:\n\t/usr/lib/libSystem.B.dylib"

    def test_parses_ios_platform_minimum_and_dylibs(self) -> None:
        parsed = parse_load_commands(self.load_commands)
        self.assertEqual(parsed["platforms"], ["IOS"])
        self.assertEqual(parsed["minimum_versions"], ["12.0"])
        self.assertEqual(parsed["dynamic_libraries"], ["/usr/lib/libSystem.B.dylib (offset 24)"])
        validate_header(
            self.file_output,
            self.header_output,
            self.load_commands,
            self.dependency_output,
            "/Applications/Xcode.app/SDKs/iPhoneOS.sdk",
        )

    def test_negative_control_rejects_macos_platform(self) -> None:
        load_commands = self.load_commands.replace("platform IOS", "platform MACOS")
        with self.assertRaises(InspectionError):
            validate_header(
                self.file_output, self.header_output, load_commands,
                self.dependency_output, "/Applications/Xcode.app/SDKs/iPhoneOS.sdk",
            )

    def test_negative_control_rejects_host_sdk_path(self) -> None:
        sdk_path = "/Applications/Xcode.app/SDKs/iPhoneOS.sdk"
        with self.assertRaises(InspectionError):
            validate_header(
                self.file_output, self.header_output, self.load_commands,
                f"{self.dependency_output}\n{sdk_path}/System/Library/Frameworks/UIKit.framework/UIKit",
                sdk_path,
            )

    def test_negative_control_rejects_weak_macos_framework_dependency(self) -> None:
        load_commands = self.load_commands.replace(
            "cmd LC_LOAD_DYLIB", "cmd LC_LOAD_WEAK_DYLIB"
        ).replace(
            "/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/CoreServices.framework/CoreServices"
        )
        with self.assertRaises(InspectionError):
            validate_header(
                self.file_output, self.header_output, load_commands,
                self.dependency_output, "/Applications/Xcode.app/SDKs/iPhoneOS.sdk",
            )

if __name__ == "__main__":
    unittest.main(verbosity=2)
