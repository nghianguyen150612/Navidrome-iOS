# P002 runtime qualification on the iPad

This procedure runs four temporary diagnostic executables on
`iPad4,4 / iOS 12.5.7 / Amethyst rootful / Procursus`. It does not install
Navidrome, alter its music volume, create a daemon, or control any existing
SSH, Tailscale or Beszel service.

The device runner uses a dedicated directory under `/private/var/tmp`, verifies
device identity and the received probe checksums, runs each executable
separately, places probe file I/O in its own staging directory, captures each
stdout, stderr and exit code, and removes only that staging directory after
validating its random marker. Results remain in a separate temporary directory
until the operator verifies and downloads them.

## Download and verify the CI bundle on Linux or Arch Linux

Install or confirm the host tools `gh`, `sha256sum`, `unzip`, `ssh` and `scp`.
On Arch Linux these are provided by `github-cli`, `coreutils`, `unzip` and
`openssh`. Use the completed, successful Apple qualification run recorded in
`P002_MANIFEST.md`, and confirm its head SHA is the P002 commit being qualified:

```sh
RUN_ID="REPLACE_WITH_SUCCESSFUL_P002_CI_RUN_ID_FROM_MANIFEST"
gh run view "$RUN_ID" --repo nghianguyen150612/Navidrome-iOS \
  --json status,conclusion,headSha,jobs
mkdir -m 700 "p002-ci-artifact-$RUN_ID"
gh run download "$RUN_ID" --repo nghianguyen150612/Navidrome-iOS \
  --name navidrome-ios-p002-a7-go-runtime-probes \
  --dir "p002-ci-artifact-$RUN_ID"
cd "p002-ci-artifact-$RUN_ID"
sha256sum -c p002-ios-a7-go-runtime-probes.zip.sha256
unzip -t p002-ios-a7-go-runtime-probes.zip
mkdir -m 700 p002-bundle
unzip -q p002-ios-a7-go-runtime-probes.zip -d p002-bundle
(cd p002-bundle && sha256sum -c SHA256SUMS)
cat p002-bundle/SIGNING.txt
cat p002-bundle/qualification.json
cat p002-bundle/statuses.txt
```

Stop if either checksum command fails, the archive test fails, or the run is not
completed successfully on the expected head. Proceed only when source
validation, toolchain qualification, compilation/linking, Mach-O inspection and
signing say `PASS`, ad-hoc signing has no entitlements, and the physical-device
status is `BLOCKED`. All four probe hashes must verify. Do not skip either
checksum check.

## Confirm the existing rootful Procursus SSH target

Use the existing rootful SSH path and credentials. Do not restart, reload,
install or reconfigure SSH, Tailscale, Beszel or any other daemon. Set `DEVICE`
to the existing SSH destination, then run this preflight before transferring
anything:

```sh
DEVICE=root@DEVICE
ssh "$DEVICE" '
set -eu
for tool in shasum timeout; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "BLOCKED: required Procursus command is missing: $tool" >&2
    exit 78
  fi
  printf "%s=" "$tool"
  command -v "$tool"
done
printf "uid="; id -u
printf "hardware="; sysctl -n hw.machine
printf "product_version="; sw_vers -productVersion
printf "build_version="; sysctl -n kern.osversion
'
```

The expected values are `iPad4,4`, `12.5.7`, `16H81` and UID `0`. Confirm
Amethyst rootful mode and Procursus using the existing device operator tooling.
The runner independently requires root, `shasum` and `timeout`; `shasum`
verifies the received bundle and creates the results manifest, while `timeout`
bounds every probe process. Both commands must be present before starting.
Their availability on the physical device has not been verified until this
preflight runs. If either command is missing, stop and report `BLOCKED`; do not
skip checksum verification or process timeouts.

## Transfer and run

On the Linux/Arch host, set `BUNDLE_DIR` to the verified `p002-bundle` path.
Use a unique UTC run ID and paths outside `/private/var/mnt/Music`:

```sh
BUNDLE_DIR="$PWD/p002-bundle"
RUN_TOKEN="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_INPUT="/private/var/tmp/navidrome-p002-input-$RUN_TOKEN"
REMOTE_RESULTS="/private/var/tmp/navidrome-p002-results-$RUN_TOKEN"
ssh "$DEVICE" "mkdir -m 700 '$REMOTE_INPUT'"
scp -p -r "$BUNDLE_DIR"/. "$DEVICE:$REMOTE_INPUT/"
ssh "$DEVICE" "printf '%s\\n' '$RUN_TOKEN' > '$REMOTE_INPUT/.p002-upload-owner' && chmod 600 '$REMOTE_INPUT/.p002-upload-owner'"
ssh "$DEVICE" "cd '$REMOTE_INPUT' && ./run_p002_device.sh --bundle '$REMOTE_INPUT' --results '$REMOTE_RESULTS'"
```

The runner checks the expected hardware/OS/build, root execution, required
commands, bundle signature policy and exact SHA-256 file list before execution.
Results must be a new direct child of `/private/var/tmp` named
`navidrome-p002-results-$RUN_TOKEN`.

It executes each case five times with a 30-second process limit:

| Probe | Runtime setting | Coverage |
| --- | --- | --- |
| Native C | `GOMAXPROCS=1` | Startup, stdout, exit status, libc, monotonic time, temporary file I/O, pthread creation/join and mutex behavior |
| Pure Go | `GOMAXPROCS=1` | Runtime startup, goroutines, channels, timers, GC, temporary filesystem I/O, SIGUSR1 delivery and clean shutdown |
| CGo callback | `GOMAXPROCS=1` | Go-to-C calls, C-to-Go callback from a native pthread, cgo.Handle, non-retained Go memory pointer, C errno and enabled checkptr build |
| Multi-P Go | `GOMAXPROCS=1` and `2` | Runtime P count, goroutine contention, mutex/scheduler yield, bounded timer/synchronization and termination |

The runner records device identity, per-run stdout, stderr and exit status,
`/usr/bin/time -l` resource output when available, `vm_stat` when available,
filtered new dyld/AMFI/jetsam kernel messages, and matching crash reports when
accessible. Missing diagnostic facilities are recorded as unavailable. Any
nonzero exit or timeout marks execution `FAIL` and preserves the results
directory. Failure to create the results `SHA256SUMS` also makes the runner
exit nonzero and prevents a device `PASS` result.

## Download and verify results, then clean the run

Copy the results directory to the Linux/Arch host before removing device-side
files:

```sh
LOCAL_RESULTS="$PWD/p002-device-results-$RUN_TOKEN"
scp -p -r "$DEVICE:$REMOTE_RESULTS" "$LOCAL_RESULTS"
(cd "$LOCAL_RESULTS" && sha256sum -c SHA256SUMS)
cat "$LOCAL_RESULTS/summary.tsv"
cat "$LOCAL_RESULTS/device-status.txt"
cat "$LOCAL_RESULTS/checksum-status.txt"
```

Review every run's stdout, stderr and exit code. Preserve the complete verified
results directory and relevant logs for the P002 decision. Only after the
local copy passes `sha256sum -c`, remove the two unique input and results
directories with the bundled cleanup helper:

```sh
ssh "$DEVICE" "cd '$REMOTE_INPUT' && ./cleanup_p002_device.sh '$REMOTE_INPUT' '$REMOTE_RESULTS' '$RUN_TOKEN'"
```

The helper verifies both paths are direct children of `/private/var/tmp`, their
names match the run token, the upload marker matches, and the results marker
has the runner token and the same run token. It refuses cleanup if any check
fails. It never targets `/private/var/mnt/Music`, `/usr/local/bin`,
`/Library/LaunchDaemons`, or Navidrome state.

## Report the outcome

Record `PASS`, `FAIL`, `BLOCKED` or `NOT TESTED` independently for toolchain,
compilation/linking, Mach-O, signing and device execution. Attach the verified
results checksums and relevant logs to `P002_MANIFEST.md`. A macOS CI pass is
not a physical-device pass. Do not apply a runtime patch unless a stock Go
runtime failure is reproduced and its instruction or subsystem is identified.
