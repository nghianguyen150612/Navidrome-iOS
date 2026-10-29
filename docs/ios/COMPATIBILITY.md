# Runtime and ABI compatibility

PASS means observed evidence for the stated check only. FAIL means an observed
mismatch. BLOCKED means a prerequisite is absent. NOT TESTED means no execution
evidence. Source risks are not device failures.

| Area | Finding | Status / gate |
| --- | --- | --- |
| Baseline | Upstream v0.64.2 equals pinned SHA; fork master equals upstream master at audit | PASS: git remote queries |
| Go requirement | go.mod says 1.27; P002 pins Go 1.27.3 tag at 2aae1000ea1d4b28923b96db28acf4e3b99d6aff and verifies the source archive SHA-256 | PASS: source pin and macOS archive checksum verified in workflow run 40871355426 |
| Builder | Linux workspace /usr/bin/go responds `Go: Unknown option: version`; Go 1.27.3 source archive was downloaded and digest-verified | BLOCKED: no local Apple SDK or application build |
| Darwin/iOS | P002 configures GOOS=ios GOARCH=arm64, PIE and external CGo linking with iPhoneOS SDK clang; only the callback source imports CGo | First macOS run exposed a CGO_ENABLED=0 build configuration error; corrected rerun pending; no A7 runtime failure is claimed |
| A7 runtime | Go 1.27.3 procyieldAsm executes ISB, reads CNTFRQ_EL0/CNTVCT_EL0 and loops until a timer interval elapses | PASS: pinned source inspection; NOT TESTED: stock runtime on iPad4,4 |
| Minimum OS | P002 requests iOS 12.0 for native C and Go external links and checks Mach-O load commands | NOT TESTED: SDK build/load commands and runtime minimum |
| SDK/Xcode | P002 CI used macOS 15.7.9 arm64, Xcode 16.4, iPhoneOS SDK 18.5, Apple clang 17.0.0 and linker ld-1167.5 | PASS: pinned archive/toolchain verified; local workspace has no Apple SDK |
| CGo/libSystem | SQLite callbacks, pthread/TLS, signals, time, DNS, mmap, file locks/fsync need device tests | NOT TESTED |
| SQLite/FTS5 | Bundled amalgamation with sqlite_fts5 enables SQLITE_ENABLE_FTS5; never assume system SQLite supports it | PASS: source; NOT TESTED: WAL, migrations, locks, recovery, FTS queries |
| TagLib/C++ | Actual pinned replacement embeds taglib.wasm and uses wazero.NewRuntimeConfig | PASS: source; NOT TESTED: execution/metadata/artwork memory |
| wazero | v1.12.0 CompilerSupported GOOS switch excludes ios; NewRuntimeConfig safely falls back to interpreter on unsupported compiler platforms; device performance remains unmeasured | PASS: source risk; NOT TESTED: interpreter behavior and performance |
| Watcher | notify default darwin CGo file links CoreServices, macOS FSEvents API | FAIL: default dependency contract for iPhoneOS; NOT TESTED: kqueue adapter |
| WebP | unix/darwin dynamic backend uses purego callbacks; nodynamic candidate avoids native libwebp loading | NOT TESTED: build and WASM image behavior |
| FFmpeg | server/initial_setup.go warns when missing; raw stream path uses os.Open | PASS: source; NOT TESTED: Direct Play; transcoding deferred |
| UI/API | UI embeds build assets and existing OpenSubsonic routes are present | PASS: source; NOT TESTED: served assets/auth/playback; old Safari compatibility separate |
| dylibs/signing | P002 inspection records each probe's load commands, dylibs, imports, code signature and entitlements | NOT TESTED: first build stopped before Mach-O inspection or signing |
| Filesystem | Mount identity, APFS permissions, WAL and free space not observed on device | NOT TESTED |
| Network/launchd | Non-root socket binding, DNS/TLS, start/stop/reboot/sleep not exercised | NOT TESTED |
| Memory | No workload executed on iPad4,4 | NOT TESTED: no footprint claims |

Go's ios target also satisfies darwin build constraints: audit both GOOS-specific
files and explicit tags. kqueue is a real candidate backend, not a no-op watcher;
its descriptor use and rename/unmount semantics need tests. Reference runtime
patches are precedents only: do not transplant by substring without exact source
hashes, zero-cycle semantics, disassembly and stock/patched device comparison.
Do not infer iOS 12 support from Go 1.27 availability or an older Go probe.
A downgrade would require a separately reviewed API/dependency and security audit.

No verified Navidrome device blocker is claimed: none was run on an iPad.
The verified source blocker is the default CoreServices watcher dependency.
Other high-priority unresolved gates are Go 1.27/A7, SDK minimum, WASM execution,
service-account access to APFS and aggregate memory.

P002 supplies stock C, pure-Go, CGo callback and multi-P probes plus a bounded
device runner. Its current decision remains BLOCKED until the iPhoneOS build is
inspected and the checksummed probes run on iPad4,4 / iOS 12.5.7. No runtime
failure or signing acceptance is claimed from source review or CI compilation.
