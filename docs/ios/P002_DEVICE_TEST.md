# P002 physical-device test procedure

This procedure runs only four temporary diagnostic executables on
`iPad4,4 / iOS 12.5.7 / Amethyst rootful / Procursus`. It does not install
Navidrome, alter its music volume, create a daemon, or control any existing
SSH, Tailscale or Beszel service.

The device runner uses a dedicated directory under `/private/var/tmp`, verifies
device identity and artifact checksums, runs each executable separately, places
all probe file I/O inside its own staging directory, captures each stdout,
stderr and exit code, and cleans only that staging directory after validating
its random marker. Results remain in a separate temporary results directory
until the operator verifies and downloads them.

## Required CI bundle

Download `p002-ios-a7-go-runtime-probes.zip` and its `.sha256` sidecar from the
P002 workflow artifact. Verify the outer bundle on a Mac:

```sh
shasum -a 256 -c p002-ios-a7-go-runtime-probes.zip.sha256
mkdir -m 700 p002-bundle
unzip -q p002-ios-a7-go-runtime-probes.zip -d p002-bundle
cd p002-bundle
shasum -a 256 -c SHA256SUMS
cat SIGNING.txt
cat qualification.json
```

Proceed only when source validation, toolchain qualification,
compilation/linking, Mach-O inspection and signing all say `PASS`, the signature
policy says ad-hoc with no entitlements, and the only physical-device status is
`BLOCKED`. The four entries in `SHA256SUMS` must verify.

## Confirm the target without changing services

Use the existing rootful SSH path and credentials. Do not restart, reload,
install or reconfigure SSH, Tailscale, Beszel or any other daemon.

Record the device identity before transfer:

```sh
ssh root@DEVICE 'sysctl -n hw.machine; sw_vers -productVersion; sysctl -n kern.osversion; id -u'
```

Expected values are `iPad4,4`, `12.5.7`, `16H81` and UID `0`. Confirm
Amethyst rootful mode and Procursus from the device's existing operator tooling.
If any identity differs, stop; the runner also refuses a mismatched model or OS.

## Transfer and run

On the Mac, set `DEVICE` to the existing SSH host and `BUNDLE_DIR` to the
verified extracted bundle. Use a unique UTC run ID and paths outside
`/private/var/mnt/Music`:

```sh
DEVICE=root@DEVICE
BUNDLE_DIR="$PWD/p002-bundle"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_INPUT="/private/var/tmp/navidrome-p002-input-$RUN_ID"
REMOTE_RESULTS="/private/var/tmp/navidrome-p002-results-$RUN_ID"
ssh "$DEVICE" "mkdir -m 700 '$REMOTE_INPUT'"
scp -p -r "$BUNDLE_DIR"/. "$DEVICE:$REMOTE_INPUT/"
ssh "$DEVICE" "printf '%s\\n' '$RUN_ID' > '$REMOTE_INPUT/.p002-upload-owner' && chmod 600 '$REMOTE_INPUT/.p002-upload-owner'"
ssh "$DEVICE" "cd '$REMOTE_INPUT' && ./run_p002_device.sh --bundle '$REMOTE_INPUT' --results '$REMOTE_RESULTS'"
```

The runner checks the expected hardware/OS/build, root execution, bundle
signature policy and exact SHA-256 file list before it executes anything.
Results must be a new direct child of `/private/var/tmp` named
`navidrome-p002-results-$RUN_ID`; if omitted, the runner creates a UTC-named
directory there.
It executes these cases individually, five times each, with a 30-second process
limit:

| Probe | Runtime setting | Coverage |
| --- | --- | --- |
| Native C | `GOMAXPROCS=1` | startup, stdout, exit status, libc, monotonic time, temporary file I/O, pthread creation/join and mutex behavior |
| Pure Go | `GOMAXPROCS=1` | runtime startup, goroutines, channels, timers, GC, temporary filesystem I/O, SIGUSR1 delivery and clean shutdown |
| CGo callback | `GOMAXPROCS=1` | Go-to-C calls, C-to-Go callback from a native pthread, cgo.Handle, non-retained Go memory pointer, C errno and enabled checkptr build |
| Multi-P Go | `GOMAXPROCS=1` and `2` | runtime P count, goroutine contention, mutex/scheduler yield, bounded timer/synchronization and termination |

The runner records device identity, per-run output/error/exit status,
`/usr/bin/time -l` resource output when available, `vm_stat` when available,
filtered new dyld/AMFI/jetsam kernel messages, and matching crash reports when
accessible. Missing diagnostic facilities are recorded as unavailable; no
device logs are fabricated. Any nonzero exit or timeout marks the device run
FAIL and preserves the results directory for review.

The harness does not modify permanent Navidrome locations, the music mount,
launchd plists, installed binaries, accounts, config, databases or volume
ownership. Test file reads/writes use only the script's unique staging folder.

## Download and verify results, then clean the run

Copy the results directory to the Mac before removing device-side files:

```sh
LOCAL_RESULTS="$PWD/p002-device-results-$RUN_ID"
scp -p -r "$DEVICE:$REMOTE_RESULTS" "$LOCAL_RESULTS"
cd "$LOCAL_RESULTS"
shasum -a 256 -c SHA256SUMS
cat summary.tsv
```

Review every run's stdout, stderr and exit code. Preserve all logs needed for the
P002 decision. Only after the local copy verifies, remove the two unique input
and results directories with the bundled cleanup helper:

```sh
ssh "$DEVICE" "cd '$REMOTE_INPUT' && ./cleanup_p002_device.sh '$REMOTE_INPUT' '$REMOTE_RESULTS' '$RUN_ID'"
```

The helper verifies both paths are direct children of `/private/var/tmp`, their
names match the run ID, the upload marker matches, and the results marker has
the runner token and the same run ID. It refuses cleanup if any check fails. It never
targets `/private/var/mnt/Music`, `/usr/local/bin`,
`/Library/LaunchDaemons`, or Navidrome state.

## Report the outcome

Record `PASS`, `FAIL`, `BLOCKED` or `NOT TESTED` independently for toolchain,
compilation/linking, Mach-O, signing and device execution. Attach the verified
results checksums and relevant logs to `P002_MANIFEST.md`. A macOS CI pass is
not a physical-device pass. Do not apply a runtime patch unless a stock Go
runtime failure is reproduced and its instruction/subsystem is identified.
