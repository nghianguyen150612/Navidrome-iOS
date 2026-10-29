# P001–P024 gated roadmap

Only P001 is implemented. Every row requires reproducible tests and its own
manifest (schema described in BUILD_PLAN.md). A failed prerequisite blocks
dependent work; optional transcoding does not block Direct Play release.
No milestone is passed by compilation alone.

| Milestone | Scope | Dependencies | Acceptance gate |
| --- | --- | --- | --- |
| P001 | Baseline audit and contracts | — | Source refs verified; docs/scaffold pass; no upstream edits |
| P002 | Go 1.27/A7 runtime feasibility | P001 | Pinned Apple/Go tools; stock C/Go/CGo/multi-P signed probes on device; crash logs and explicit go/no-go |
| P003 | Reproducible iOS build skeleton | P002 | Clean builds, tags and Mach-O/dylib/minimum-OS inspection; manifest |
| P004 | SQLite and FTS5 qualification | P003 | Real device callbacks, FTS, WAL/locks, integrity and migration fixtures |
| P005 | Watcher platform adapter | P003 | No CoreServices; real kqueue rename/unmount/event tests, descriptor budget |
| P006 | WASM metadata and artwork | P003,P004 | Pinned taglib/WebP/plugin engines; format fixtures, corrupt input and peak memory |
| P007 | Embedded web frontend | P003 | Locked npm build; assets served; auth and browser compatibility recorded |
| P008 | Filesystem and account preflight | P004,P005 | APFS identity/access tests; absent mount and symlink attacks fail closed |
| P009 | Configuration and network setup | P007,P008 | TOML preservation; loopback default; tty and first-admin gates |
| P010 | Native manual server lifecycle | P006,P009 | Non-root foreground start, graceful stop, clean DB reopen |
| P011 | OpenSubsonic Direct Play | P010 | Authenticated browse/stream, range/seek and byte checks without FFmpeg |
| P012 | launchd integration | P010,P011 | Start/stop/restart/reboot, crash throttling and mount-loss recovery on device |
| P013 | Pipe-safe bootstrap and persistent CLI | P009,P012 | Pinned engine, strict state, quoted argv, ownership and tty fixtures |
| P014 | Transactional installation | P013 | Journal/lock and interrupted per-filesystem replacement tests |
| P015 | Backup and isolated restore | P004,P014 | Consistent DB/config snapshot, hash/integrity checks and restore drill |
| P016 | Update and rollback | P015 | Migration-aware restore; prior loaded/running state and failure injection |
| P017 | Explicit LAN/Tailscale access | P011,P012 | User opt-in, binding/transport/auth tests; actual Tailscale availability recorded |
| P018 | Low-memory resource qualification | P006,P011,P012 | Agreed corpus/one stream under budget, jetsam/thermal/headroom logs |
| P019 | Optional FFmpeg transcoding study | P018 | Separate tool/dylib/codecs/signing and bounded transcode tests; no Direct Play regression |
| P020 | Security and permission review | P016,P017 | Malicious path/state/media/proxy/plugin cases; upstream guards retained |
| P021 | Long-run lifecycle and resilience | P018,P020 | 24-hour bounded workload, sleep/wake, reboot, mount loss, disk pressure recovery |
| P022 | Release reproducibility and supply chain | P016,P020 | Independent clean rebuild comparison, provenance/checksum/signature verification |
| P023 | Release candidate device acceptance | P021,P022 | Fresh install/update/rollback/uninstall matrix; no failed required gates |
| P024 | Release readiness and maintenance handoff | P023 | Operator recovery docs, known limits, manifest and explicit release decision |

P024 depends on P019 only if transcoding is promoted into the release. Otherwise
record it as deferred, with failures visible. Changes to baseline, Go patches,
SDK or native dependencies reopen affected runtime and release gates.

Exact next step: P002 must pin a Go 1.27 patch archive and Apple toolchain,
inspect their documented iOS minimum, build stock native C, pure Go, CGo callback
and multi-P/yield probes using GOOS=ios/arm64 and minimum 12.0, inspect Mach-O,
sign under a documented minimal policy and run on iPad4,4/iOS 12.5.7. Capture
exit codes, dyld/crash logs, signatures, source hashes and disassembly. If the
stock runtime fails, reproduce and test a narrowly reviewed A7 runtime patch;
do not start application porting until this gate has an explicit decision.
