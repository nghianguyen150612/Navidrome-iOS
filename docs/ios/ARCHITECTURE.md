# Navidrome-iOS P001 architecture

Status: design only; no Navidrome iPad runtime has been tested. Read
[manifest](P001_MANIFEST.md), [compatibility](COMPATIBILITY.md),
[build plan](BUILD_PLAN.md), [installer contract](INSTALLER_CONTRACT.md), and
[roadmap](ROADMAP.md). Evidence is pinned in [audit.json](audit.json).

## Baseline and isolation

Navidrome v0.64.2 is commit `101145742f4762164202cb4858c9126258bdc463`.
The remote tag is lightweight; resolving it proves repository identity, not a
cryptographic release signature. The fork's starting master was
`ec2e0a9ea9cd7c2f08f930fc0579b991e1fe0900`, equal to upstream master at audit.
Only master existed remotely. Create iOS at the stable tag; feature branches and
PRs target iOS. Keep master tracking upstream; never push platform patches there.
Reference branches/SHAs are recorded in audit.json; other reference feature
branches were listed but are not treated as the qualified implementation.

The product is a foreground Go native server with CGo SQLite, embedded frontend,
and the existing OpenSubsonic routes. There is no UIKit app, container or Linux
emulation. First streaming gate is authenticated Direct Play with range/seek.
No upstream Go, SQL, frontend, module or release behavior changes in P001.
Future changes use ios build constraints and narrow adapters, with non-iOS
regression checks. A dependency replacement needs a pinned, reviewed patch set.

## Source map and inventory

`go.mod` requires Go 1.27. audit.json records every direct/indirect module and
replacement; go.sum remains authoritative for module integrity. Important edges:

| Component | Actual source | Port implication |
| --- | --- | --- |
| Startup/config | cmd/root.go, conf/configuration.go | Starts DB, scan, HTTP, plugins, artwork, backups; configuration creates directories |
| SQLite | db/db.go, db/migrations, go-sqlite3 v1.14.52 | CGo; embedded SQL plus registered Go migrations; custom SEEDEDRAND and NATSORT |
| FTS | Makefile; search backend defaults to fts | Retain sqlite_fts5, migrations and queries |
| Metadata | adapters/gotaglib/gotaglib.go; deluan/go-taglib replacement | Embedded taglib.wasm on wazero, not native TagLib C++ linkage |
| WASM/plugins | plugins/manager*.go; extism/go-sdk v1.7.1, wazero v1.12.0 | Runtime code generation, memory, jailed filesystem and SSRF guards need review |
| Artwork | gen2brain/webp v0.6.4, purego v0.11.1 | Dynamic callbacks/dlopen versus nodynamic WASM path |
| Watchers | core/storage/local/watcher.go, watch_events_darwin.go; notify v0.9.3 | Darwin CGo backend imports CoreServices; kqueue candidate |
| HTTP/API | server/server.go, server/subsonic | Heartbeat /ping; preserve auth, rate limits and API capabilities |
| Streaming | core/stream/media_streamer.go, core/ffmpeg | raw opens source directly; transcoding invokes external tools |
| Service | cmd/svc.go, kardianos/service v1.3.0 | Existing upstream service commands retained; iOS manager owns canonical plist |
| UI | ui/embed.go, ui/package-lock.json, .nvmrc | go:embed all:build; Node v24 on builder, never on device |

## CLI and launchd

`navidrome` stays upstream's server/CLI. `navidrome-ios` is the future native-shell
management command, forwarding quoted arguments to the persisted manager; `nd`
is its symlink. Commands: install, setup, status, doctor, start, stop, restart,
logs, update, rollback, backup, restore, uninstall, version, help. No network
fetch for ordinary status/lifecycle commands. Read-only diagnostics work without
root; privileged mutations validate ownership and elevate explicitly.

LaunchDaemon com.navidrome.ios runs manager service-run as a verified existing
non-root account. service-run verifies mount/config and execs navidrome with
explicit --configfile (registered in cmd/root.go) and
sanitized environment; no background shell or competing PID supervisor.
ProgramArguments use distinct XML array entries. Set UserName, WorkingDirectory,
RunAtLoad, bounded restart throttling, stdout/stderr files and restrictive umask.
Validate supported iOS 12 launchctl syntax rather than assuming modern macOS
bootstrap/kickstart. Stop must suppress restart, wait for exit and DB closure;
restart requires successful stop then bounded /ping readiness and stable process
identity. /ping is liveness, not proof of DB integrity, auth or playable media.

Mount disappearance must stop scanning/writing and service operation; startup
preflight alone is insufficient. Prefer a small independently supervised mount
monitor or verified platform adapter, with explicit recovery/restart after the
same volume returns. Do not fake successful watcher or storage operations.

## Security boundaries

Root is needed to install trusted executables/plist, not to parse music or serve
HTTP. Root owns immutable manager, launcher, state and plist; service account
cannot replace privileged code. Service account reads music and writes only its
data/cache/logs; never recursively chown the external volume. Config contains
credentials and must be readable only by root and the chosen service identity.
Do not assume mobile is sufficiently isolated; verify account/group permissions.

Threats: hostile release payload/checksum paths, shell injection through state,
symlink races, malicious music/images/plugins, remote credential attacks,
first-admin takeover, proxy-header spoofing, disk exhaustion and DB corruption.
Controls: strict hash allowlists, never source state, private staging and locks,
no archive traversal, recheck destination ownership, least privilege, existing
upstream auth/rate limits/redaction/SSRF and plugin filesystem guards, bounded
caches/log rotation, stopped consistent DB snapshots. HTTPS plus SHA-256 does
not protect against a compromised publisher replacing bootstrap and checksums;
release provenance and signing require their own gate. Jailbreak/root compromise
is outside application isolation guarantees.

Loopback-only 127.0.0.1:4533 overrides upstream 0.0.0.0 through generated config,
not an upstream default change. Setup must explicitly select LAN or a verified
Tailscale address and warn about first-admin setup and transport protection.
No auth bypass, guessed tokens or trusted proxy shortcuts. Tailscale availability
on this device is NOT TESTED. Keep secrets out of manifests and diagnostics.

## Practical feasibility

Conditional and high risk for A7 with roughly 300 MB available. Direct Play
avoids a codec process but scan metadata WASM, artwork decompression, SQL caches,
plugins and Go/C heaps can still exhaust memory. A small controlled library and
one stream are initial goals, not a capacity guarantee. Measure RSS/peak physical
footprint plus C/WASM allocations, jetsam logs, scan rate, HTTP latency, thermal
and battery behavior. Go memory limits exclude C heaps and are not a hard cap.
Candidate GOMAXPROCS=1 and conservative scanner/artwork concurrency need measured
tradeoffs; they do not fix illegal instructions. Proposed qualification budget:
peak server footprint <=200 MiB and >=75 MiB measured device headroom during the
agreed scan + stream workload; revise explicitly if the OS measurement differs.
If probes, WASM or memory gates fail, pause the port and review the baseline or
adapter strategy; never lower Go's module directive merely to force compilation.
