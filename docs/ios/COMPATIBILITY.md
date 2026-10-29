# Runtime and ABI compatibility

PASS means observed evidence for the stated check only. FAIL means an observed
mismatch. BLOCKED means a prerequisite is absent. NOT TESTED means no execution
evidence. Source risks are not device failures.

| Area | Finding | Status / gate |
| --- | --- | --- |
| Baseline | Upstream v0.64.2 equals pinned SHA; fork master equals upstream master at audit | PASS: git remote queries |
| Go requirement | go.mod says 1.27; Go go1.27.0 tag resolves to 8af21751f066eced273ca3ce49506b366847c623 | PASS: source/ref check only |
| Builder | Linux workspace /usr/bin/go responds `Go: Unknown option: version`; no usable Go version established | BLOCKED: application build/tests |
| Darwin/iOS | GOOS=ios GOARCH=arm64 CGO_ENABLED=1 is candidate; macOS darwin/arm64 is not an iOS binary | NOT TESTED: full compile/link |
| A7 runtime | Go 1.27 asm_arm64.s procyieldAsm reads CNTFRQ_EL0/CNTVCT_EL0; Beszel patches this to YIELD | PASS: source risk identified; NOT TESTED: Navidrome device execution |
| Minimum OS | iOS 12.5.7 device, proposed binary deployment floor 12.0 | NOT TESTED: runtime minimum, symbols, load commands; compiler flag alone insufficient |
| SDK/Xcode | Reference macos-14 runner selects installed iphoneos SDK; no Navidrome Xcode/SDK pairing qualified | BLOCKED: Apple builder/SDK unavailable here |
| CGo/libSystem | SQLite callbacks, pthread/TLS, signals, time, DNS, mmap, file locks/fsync need device tests | NOT TESTED |
| SQLite/FTS5 | Bundled amalgamation with sqlite_fts5 enables SQLITE_ENABLE_FTS5; never assume system SQLite supports it | PASS: source; NOT TESTED: WAL, migrations, locks, recovery, FTS queries |
| TagLib/C++ | Actual pinned replacement embeds taglib.wasm and uses wazero.NewRuntimeConfig | PASS: source; NOT TESTED: execution/metadata/artwork memory |
| wazero | v1.12.0 CompilerSupported GOOS switch excludes ios; NewRuntimeConfig safely falls back to interpreter on unsupported compiler platforms; device performance remains unmeasured | PASS: source risk; NOT TESTED: interpreter behavior and performance |
| Watcher | notify default darwin CGo file links CoreServices, macOS FSEvents API | FAIL: default dependency contract for iPhoneOS; NOT TESTED: kqueue adapter |
| WebP | unix/darwin dynamic backend uses purego callbacks; nodynamic candidate avoids native libwebp loading | NOT TESTED: build and WASM image behavior |
| FFmpeg | server/initial_setup.go warns when missing; raw stream path uses os.Open | PASS: source; NOT TESTED: Direct Play; transcoding deferred |
| UI/API | UI embeds build assets and existing OpenSubsonic routes are present | PASS: source; NOT TESTED: served assets/auth/playback; old Safari compatibility separate |
| dylibs/signing | No Mach-O produced, dylib closure or entitlements observed | BLOCKED: build; NOT TESTED: signing/device execution |
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
