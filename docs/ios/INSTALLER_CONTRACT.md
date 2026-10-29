# Installer, filesystem and lifecycle contract

This is a future implementation contract, not an installer delivered by P001.
No live plist or install.sh is shipped here.

## Canonical paths and ownership

| Role | Absolute path | Contract |
| --- | --- | --- |
| Server | /usr/local/bin/navidrome | root-owned executable 0755; qualified signed artifact |
| CLI | /usr/local/bin/navidrome-ios | root-owned 0755 quoted wrapper to manager |
| Alias | /usr/local/bin/nd | symlink to /usr/local/bin/navidrome-ios; refuse occupied unknown path |
| Manager | /var/lib/navidrome-ios/manager.sh | root-owned 0755, exact verified local engine |
| State | /var/lib/navidrome-ios/install-state | root-owned 0600, data only, never sourced |
| Config | /var/lib/navidrome-ios/config/navidrome.toml | root-owned, service group readable 0640; directory 0750 |
| Backups | /var/lib/navidrome-ios/backup/ | root-owned 0700; space preflight required |
| LaunchDaemon | /Library/LaunchDaemons/com.navidrome.ios.plist | root:wheel 0644; no secret values |
| Logs | /var/log/navidrome-ios/ | service writable 0700, files 0600, bounded rotation |
| Existing volume | /private/var/mnt/Music | externally owned APFS; never format or recursively chown |
| Existing alias | /mnt/Music | existing symlink; validate resolves to canonical volume, never replace |
| Library | /private/var/mnt/Music/library | externally owned; read/traverse access only required |
| Data | /private/var/mnt/Music/data | service writable; database/migrations/backups under explicit policy |
| Cache | /private/var/mnt/Music/cache | service writable; no root-filesystem fallback |

Manager/config parents are root-controlled and not service writable. Data/cache
may be provisioned only after verified mount identity and explicit adoption;
existing owners/modes/content are preserved, access failures reported. Never
mkdir the mount path as evidence it is mounted. Record a volume identity, inspect
mount table/statfs APFS and mount boundary, resolve aliases, reject unexpected
symlink components. A directory existing at that name is insufficient. Check
mount identity before every start, update, restore and write-producing operation,
and monitor while running. Refuse root-volume st_dev fallback, even if writable.
Do not clean library/data/cache on uninstall. No recursive ownership operations.

The generated TOML uses the real configuration keys Address=127.0.0.1,
Port=4533, MusicFolder, DataFolder, CacheFolder with paths above. Prefer
EnforceNonRootUser=true after verifying its behavior; keep upstream security
validation. Preserve user edits and unknown supported keys; parse/validate with
the application, not sed replacements. Do not overwrite config during update.
Loopback setup must finish first admin creation before explicit network exposure.
Scan/write starts only after mount/access gates. No silently changed bind address
through inherited ND_* environment; lifecycle supplies a controlled environment.

## Actual reference patterns

Reference versions and full file hashes are in audit.json. Source links below
are pinned; these are inspection results, not rerun reference device tests.

- [Beszel bootstrap](https://github.com/nghianguyen150612/Beszel-iOS/blob/0c3e4cd22ac24264834c401ad412e44aeda4e4f3/install.sh)
  downloads the engine to private staging and verifies an embedded SHA-256 before
  execution. Adopt download/verify/execute, HTTPS limits and /dev/tty prompting;
  never execute a fetched engine before verification. Mutable bootstrap remains
  the trust root and can be replaced by a compromised publisher.
- Beszel scripts/ios/install-beszel.sh `stage_manager_source`,
  `install_persistent_manager`, `command_wrapper_is_managed` persist the exact
  local engine with ownership/marker checks and quoted forwarding. Reuse this
  boundary; change names/paths and reject environment-based privileged redirects.
  Its state readers parse known keys without shell evaluation. Use strict
  duplicate rejection in the new schema rather than first-value acceptance.
- Beszel `validate_sums_file` expects exactly two agent/hub assets;
  `transact_hub_update`, `rollback_component`, `rollback_plist` stage binaries,
  back up plists, trap interruption, reload and health-check. Reuse transaction
  structure, not its two-service schema, keys, /api/health route or purge flows.
  Its CLI distinguishes status/doctor from mutation and verifies service state;
  preserve this approach for a single Navidrome service.
- Beszel .github/workflows/ios-build.yml builds Go iOS/CGo on macos-14,
  patches runtime via .github/scripts/patch-go-ios-arm64-runtime.py, builds UI
  with Bun, inspects Mach-O/minimum 12.0 and generates SHA256SUMS. Reuse provenance,
  inspections and artifact hashing; use Navidrome npm lockfile, separately pinned
  Apple tools and separately qualified Go 1.27 runtime. Its tag-release path
  does not prove this server runs on A7.
- [Forgejo bootstrap](https://github.com/nghianguyen150612/Forgejo-iOS/blob/dfb0b0664f1245f7436a306baf711540f712a03f/install.sh)
  also checksum-pins its engine. scripts/ios/install-forgejo.sh `choose_user`,
  `check_config`, `permissions`, `write_config` enforce a non-root account,
  rootful paths and private INI configuration. Adapt to TOML and separate
  manager-owned versus external APFS paths; do not copy its repository/data
  layout, mode loops or account default uncritically.
- Forgejo `service_run`, `service_start`, `service_stop`, `service_restart`,
  `capture_service_state`, `restore_saved_service_state` implement foreground
  exec, load/unload waits and HTTP health. Adopt preserving loaded/running/
  stopped state. Replace /api/healthz and PID assumptions; use Navidrome /ping
  plus authenticated API and DB validation in acceptance tests.
- Forgejo `download`, `qualify_artifact`, `sign_binary`, `snapshot`,
  `restore_snapshot`, `install_update` validate a single named checksum,
  frozen artifact/version, sign before non-root version execution, stage on the
  destination filesystem and roll back manager/binary/state/permissions/service.
  Its version restriction recognizes binary rollback cannot reverse migrations.
  Reuse that principle; never copy its frozen Forgejo hash, version, Go patch,
  entitlements or test fixtures as Navidrome qualification.
- Forgejo ios-cgo-probe.yml preserves C/Go/CGo and instruction probes, build
  statuses, disassembly and metadata. Reuse evidence structure; old Go 1.20/
  1.26 results are not Go 1.27 evidence. Both references have tests that mock
  launchctl/download/health; mock success never substitutes for device evidence.

## Transaction and recovery state machine

Future install/update: validate platform, account, paths, mount, free space and
config; acquire exclusive root-owned lock; download to private staging; validate
strict filenames/digests; inspect/sign; execute only non-root version/probe;
snapshot binary, manager, config, state, plist and service state; stop and wait;
make a consistent SQLite snapshot with sidecar policy; stage replacements on
EACH destination filesystem; journal phases; atomically rename per file; start
only if prior policy calls for it; check bounded readiness; commit state last.
Cross-filesystem changes are not globally atomic: durable journal and crash
recovery are required. Incomplete recovery reports failure and preserves evidence.

Install-state schema needs version, baseline/platform source SHA, release,
unsigned/signed hashes, engine/config hash, service UID, volume identity,
transaction/backup identity, migration/schema version and previous loaded/running
state. Reject unknown schema versions, duplicate keys and malformed values;
never store secrets or source/eval this file. Lock cleanup must verify ownership.
Persist trusted engine as part of the same recoverable transaction.

Rollback must restore a coherent DB + application/config set after migrations,
not simply the old executable. Backup only with a clean stopped DB or verified
SQLite backup API; do not copy live DB/WAL independently. Restore to isolated
staging and integrity-check before replacement; reject archive traversal and
symlinks. Preserve newer data after a failed update for explicit recovery.
Migration downgrades need an explicit data-loss decision; never automatic.
Checksummed backups and restore drills are mandatory before update promotion.

Input comes from /dev/tty when piped. Missing tty requires explicit unattended
flags or failure, never permissive defaults. Offline lifecycle stays offline.
Refuse unrecognized occupied CLI/plist paths. Uninstall removes only proven
managed artifacts; preserve config/backups and all external volume content by
default. No music purge command is planned.

Required future failure-injection cases: wrong/duplicate hash, unsafe filename,
missing mount or replaced alias, path occupied, insufficient space, interrupted
rename/phase, launch failure, DB migration failure, rollback failure, tty absent,
stopped-service update and reboot recovery. None is implemented or passed here.
