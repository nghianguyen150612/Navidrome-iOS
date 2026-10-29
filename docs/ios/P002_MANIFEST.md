# P002 runtime qualification manifest

Status: qualification harness prepared; physical iPad execution is BLOCKED until
the checksummed bundle is run on iPad4,4 / iOS 12.5.7. A successful source or
macOS build job is not a device-runtime result. Do not start P003 until the
device gate passes or an alternative is formally accepted.

## Source and delivery

- P001 PR #1 merged with a normal merge commit: `2a7a18dd42591f80bd8c75e977d931a72f094893`.
- P001 expected head: `0ab7746b65855d4bada4aa941c083ec7de0c7074`.
- P002 branch: `feat/p002-ios-a7-go-runtime-probes`, based on the merged `iOS` head.
- P002 changes are isolated to runtime probes, toolchain/inspection/device scripts,
  CI, and qualification documentation. No Navidrome application code, modules,
  migrations, frontend or permanent installer paths are changed.
- Reference files listed in P001 audit.json were fetched at their pinned commits;
  all seven recorded SHA-256 hashes matched.

## Pinned Go toolchain

Go 1.27.3 is pinned in `p002-toolchain.json`. The release source tag is
`go1.27.3`, resolving to source commit
`2aae1000ea1d4b28923b96db28acf4e3b99d6aff`. The official source archive digest
is `6e7749035cf360f06b2575d162ea79df9fda8ef671889e5c375f8e50777f26bb`; this
archive was downloaded and verified in the Linux workspace. CI downloads the
host-specific macOS archive and verifies it before extraction:

| Go archive | SHA-256 |
| --- | --- |
| `go1.27.3.darwin-amd64.tar.gz` | `b6f8e931e4ab497fcde6da8ae4499a58f9d258e55c8a80824a516eae5950a750` |
| `go1.27.3.darwin-arm64.tar.gz` | `dd3908cf20959d798c1e06ebe5b72213f0505ce01373b40ce3110975a6cd99c2` |

For host-only probe source validation, the Linux Go archive
`go1.27.3.linux-amd64.tar.gz` with SHA-256
`65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40` was also
downloaded and verified. It is not used to qualify the iOS binary.

The manifest pins hashes for the exact Go runtime, iOS Darwin runtime and linker
source files used by the build. The workflow checks those hashes against the
installed Go distribution. Go 1.27.3 supports `ios/arm64` PIE in
`internal/platform/supported.go`; Go's platform source requires external linking
for `ios/arm64`. The build uses explicit `-buildmode=pie` and records the
effective Go linker command from `go build -x`.

## A7 runtime inspection

The pinned `src/runtime/asm_arm64.s` hash is
`47f9313d4f956b4159dcf8b292bf340a12adb6b58ee9a94360fe948045e2c5db`. In
`runtime·procyieldAsm`, Go 1.27.3:

- returns for a zero delay;
- executes `ISB`;
- reads `CNTFRQ_EL0` to convert a nanosecond delay to counter ticks;
- reads `CNTVCT_EL0` and loops with `ISB` until the requested interval elapses.

The source review also records Go's iOS ARM64 signal-stack special case:
iOS does not use the alternate signal stack. The build stores the exact source
excerpt and disassembly of `runtime.procyieldAsm` from the stock Go binary.

No runtime patch is applied. The source reference establishes what Go emits; it
does not establish that the A7 traps, or that a scheduler defect occurs. No
runtime failure has been observed on the target device.

## Build and signature policy

The qualification job requires an actual Xcode iPhoneOS SDK from `xcrun`; it
blocks if that SDK is unavailable. The clang wrapper supplies ARM64, the SDK
sysroot, and `-miphoneos-version-min=12.0`. `MACOSX_DEPLOYMENT_TARGET` is rejected.
The Go probes use `GOOS=ios`, `GOARCH=arm64`, PIE, and the pinned toolchain.
Pure Go and multi-P are built with CGo disabled; only the callback probe uses
CGo. CGo pointer checks are enabled at level 2. The build disables per-user Go
environment settings, clears CGo flag overrides, records the selected SDKROOT,
and stores the exact build and linker invocations.

CI signs each executable with Apple's ad-hoc codesign and no entitlements. It
records unsigned and signed SHA-256 values, Mach-O type, ARM64 architecture,
iOS platform/minimum OS, load commands, dylib dependencies, imported symbols,
Go build metadata and code-signature metadata. This is a minimal build signature
policy for investigation; it does not claim Amethyst will accept these files.
Device launch results provide the required runtime evidence.

## Evidence status

| Gate | Status | Evidence / limit |
| --- | --- | --- |
| P001 review and merge | PASS | PR #1 targeted `iOS`, expected head was unchanged, both Actions checks succeeded, no review blockers existed; merged SHA above |
| Go release/source pin | PASS | `go1.27.3` source tag and commit verified; source archive SHA-256 downloaded and verified; official per-host archive hashes pinned |
| Beszel-iOS / Forgejo-iOS references | PASS | Pinned source file hashes match audit.json; patterns reviewed without copying runtime patches or signing assumptions |
| Host-side validation | PASS | P001 and P002 source validators; 12 host-side tests including malformed checksum, macOS platform, unsupported minimum OS, weak framework and host-SDK negative controls; Go vet, gofmt and syntax checks |
| Host-only source build and execution | PASS | Verified Go 1.27.3 Linux/amd64 built and ran native C, pure-Go, CGo callback, and multi-P (1 and 2) probes; this does not qualify iOS/ARM64 |
| Local Apple SDK/toolchain | BLOCKED | Workspace is Linux x86_64; `xcrun`, iPhoneOS SDK, Apple clang, `otool`, and `codesign` are unavailable |
| CI toolchain/archive verification | NOT TESTED | Record the `apple-toolchain-qualification` job result and artifact manifest after CI runs |
| Probe compilation/linking | NOT TESTED | Requires the macOS iPhoneOS SDK workflow |
| Mach-O inspection | NOT TESTED | Requires generated iOS ARM64 executables and Apple inspection tools |
| Ad-hoc signing | NOT TESTED | Requires Apple codesign on the generated Mach-O files |
| Physical iPad execution | BLOCKED | No iPad4,4 / iOS 12.5.7 device session is attached; no device logs or measurements are claimed |
| Go A7 runtime failure | NOT TESTED | Stock runtime must run on the physical device before any patch is considered |
| Runtime patch | NONE | Stock Go source and binaries only |
| P002 decision | BLOCKED — NO-GO for P003 | Physical-device qualification is a required prerequisite |

The macOS workflow records separate source-validation, toolchain,
compilation/linking, Mach-O inspection, signing and physical-device statuses.
CI records physical-device execution as BLOCKED even when all build stages pass.
Its downloadable zip and sidecar checksum are generated only after successful
build, inspection and signing.

## Remaining action

Run the workflow-generated bundle using `P002_DEVICE_TEST.md` on
`iPad4,4 / iOS 12.5.7 / Amethyst rootful`. Preserve stdout, stderr, exit codes,
timing/memory data and any relevant dyld, crash or jetsam reports. Update this
manifest with observed CI and device evidence before making a GO/NO-GO decision.
