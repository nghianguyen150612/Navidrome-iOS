# Reproducible build and linking plan

P001 supplies no executable or installable release. Build commands below are a
candidate design, not verified tool availability. Keep Go, module/sum and UI
lockfiles unchanged. Pin a Go 1.27 patch release by archive digest after P002;
record exact Xcode build, host OS, clang, iPhoneOS SDK version/hash, deployment
floor, module cache checksums and frontend tool versions. Runner labels alone
are not reproducible toolchain pins. Record runtime patches and hashes separately.

1. P002: compile native C, pure Go, CGo callbacks and multi-P contention probes
   with stock Go first. Capture architecture, symbols, dyld load commands and
   signatures; run on actual iPad4,4/iOS 12.5.7. Compare reference workaround only
   after reproducing a failure; qualify zero-cycle yield and signal behavior.
2. Build frontend on host with Node selected from .nvmrc (v24; pin exact patch)
   and `npm ci` using ui/package-lock.json, then `npm run build` in ui. Hash all
   embedded assets; require nonempty index and matching static resources.
3. Candidate Apple compiler wrapper: xcrun --sdk iphoneos --find clang and
   --show-sdk-path; pass -arch arm64, -isysroot and -mios-version-min=12.0.
   Select matching CXX only if a measured native dependency requires it.
   Deployment flags on every C object and final link; check SDK availability
   diagnostics, undefined/new symbols and executable load commands.
4. Candidate environment GOOS=ios GOARCH=arm64 CGO_ENABLED=1 with the wrapper CC;
   proposed tags netgo,sqlite_fts5,kqueue,nodynamic. kqueue/nodynamic are
   dependency-provided candidates requiring independent tests, not disabled
   security checks. Use trimpath and version ldflags from Makefile; external
   iOS link/PIE selection must follow the exact Go toolchain, never macOS defaults.
5. Keep go-sqlite3's bundled SQLite, not `libsqlite3` tag/system substitution.
   Check compile options, SELECT sqlite_version(), FTS5 create/insert/search,
   custom collation/function callbacks, migration fixtures, foreign keys, WAL,
   busy timeout, locks across processes, crash/reopen and integrity_check.
6. Audit full dependency graph with go list -deps -json, go version -m,
   compiler/linker logs, nm, file and otool -hv/-l/-L. Require arm64 iOS load
   commands, min OS <=12.5.7, no build-host paths/frameworks, no Linux loader or
   macOS dylibs. libSystem remains dynamic; no fully-static-Darwin assumption.
   Prefer bundled static native leaf libraries only when licenses and SDK ABI
   permit. TagLib is WASM; no speculative native TagLib/C++ package installation.
7. Verify WASM interpreter/compiled-engine selection in taglib, plugins and WebP;
   do not globally request JIT entitlements or silently remove sandbox guards.
   If a real interpreter adapter is required, keep platform-local and test
   metadata equivalence, corrupt inputs and memory/concurrency bounds.
8. Preserve server/initial_setup.go missing-FFmpeg warning. No FFmpeg/ffprobe
   download requirement for first Direct Play; transcode requests must fail
   honestly. Later inspect Procursus FFmpeg's dylibs, deployment target,
   signature, codecs/licenses and peak resource use independently. Jukebox/mpv
   is another optional dependency, not a Direct Play prerequisite.
9. Hash unsigned build and final signed payload separately. Qualify minimal
   device entitlements and ldid/codesign tool versions experimentally. Forgejo's
   no-container entitlement is evidence for Forgejo only. Never add broad trust
   bypasses or claim ad-hoc signing proves execution on Amethyst.
10. Package checksummed explicit filenames and provenance manifest. Repeat clean
    build, compare artifacts, explain any non-deterministic signing/build data.
    Never label reproducible based only on one successful run.

Each future manifest includes source/base/patch SHAs, exact toolchain/digests,
commands/tags/environment without secrets, artifacts before/after signing,
device identity, workload/input hashes, logs, exit codes and PASS/FAIL/BLOCKED/
NOT TESTED per gate. Compile/link, launch, feature and long-run tests stay
separate. This Linux P001 scaffold uses Python standard library only and does
not run the application or alter data. See P001_MANIFEST.md for exact checks.
