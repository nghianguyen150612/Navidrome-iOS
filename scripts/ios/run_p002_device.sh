#!/bin/sh
set -eu

usage() {
  echo "usage: run_p002_device.sh --bundle DIR [--results DIR]" >&2
  exit 2
}

BUNDLE=
RESULTS=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle)
      [ "$#" -ge 2 ] || usage
      BUNDLE=$2
      shift 2
      ;;
    --results)
      [ "$#" -ge 2 ] || usage
      RESULTS=$2
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done
[ -n "$BUNDLE" ] || usage

TMP_ROOT=/private/var/tmp
STAGE=
STAGE_MARKER=
STAGE_TOKEN="navidrome-p002-device-$$-$(date +%s)"
RESULTS_REQUESTED=$RESULTS
RESULTS=

canonical_dir() {
  (CDPATH= cd "$1" 2>/dev/null && pwd -P)
}

reject_music_path() {
  candidate=$1
  case "$candidate/" in
    /private/var/mnt/Music/*|/mnt/Music/*)
      echo "Refusing to read or write under the existing Music volume: $candidate" >&2
      return 1
      ;;
  esac
}

write_results_checksums() {
  if [ -n "$RESULTS" ] && [ -d "$RESULTS" ] && command -v shasum >/dev/null 2>&1; then
    (cd "$RESULTS" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; > SHA256SUMS) || true
  fi
}

cleanup() {
  exit_code=$?
  trap - EXIT HUP INT TERM
  if [ -n "$STAGE" ] && [ -n "$STAGE_MARKER" ] && [ -d "$STAGE" ] &&
     [ ! -L "$STAGE" ] && [ -f "$STAGE_MARKER" ] &&
     [ "$(cat "$STAGE_MARKER" 2>/dev/null || true)" = "$STAGE_TOKEN" ]; then
    case "$STAGE/" in
      "$TMP_ROOT"/navidrome-p002-device-*)
        rm -rf "$STAGE"
        if [ -n "$RESULTS" ]; then
          echo "Removed verified temporary staging directory." >> "$RESULTS/cleanup.txt" 2>/dev/null || true
        fi
        ;;
      *)
        if [ -n "$RESULTS" ]; then
          echo "Refused cleanup because the staging path did not match its verified prefix: $STAGE" \
            >> "$RESULTS/cleanup.txt" 2>/dev/null || true
        fi
        ;;
    esac
  elif [ -n "$RESULTS" ]; then
    echo "Refused cleanup because the staging ownership marker did not verify." \
      >> "$RESULTS/cleanup.txt" 2>/dev/null || true
  fi
  write_results_checksums
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run this script as root on the rootful Procursus device." >&2
  exit 78
fi
if [ ! -d "$BUNDLE" ]; then
  echo "BLOCKED: bundle directory is missing: $BUNDLE" >&2
  exit 78
fi
BUNDLE=$(canonical_dir "$BUNDLE") || {
  echo "BLOCKED: cannot resolve bundle directory." >&2
  exit 78
}
reject_music_path "$BUNDLE" || exit 78

if [ ! -d "$TMP_ROOT" ]; then
  echo "BLOCKED: temporary root must already exist: $TMP_ROOT" >&2
  exit 78
fi
TMP_ROOT=$(canonical_dir "$TMP_ROOT") || {
  echo "BLOCKED: cannot resolve temporary root." >&2
  exit 78
}
reject_music_path "$TMP_ROOT" || exit 78

if [ -z "$RESULTS_REQUESTED" ]; then
  RESULTS_REQUESTED="$TMP_ROOT/navidrome-p002-results-$(date -u +%Y%m%dT%H%M%SZ)"
fi
case "$RESULTS_REQUESTED" in
  /*) ;;
  *) RESULTS_REQUESTED="$PWD/$RESULTS_REQUESTED" ;;
esac
RESULTS_PARENT=${RESULTS_REQUESTED%/*}
RESULTS_NAME=${RESULTS_REQUESTED##*/}
if [ ! -d "$RESULTS_PARENT" ]; then
  echo "BLOCKED: results parent directory must already exist: $RESULTS_PARENT" >&2
  exit 78
fi
RESULTS_PARENT=$(canonical_dir "$RESULTS_PARENT") || {
  echo "BLOCKED: cannot resolve results parent directory." >&2
  exit 78
}
if [ "$RESULTS_PARENT" != "$TMP_ROOT" ]; then
  echo "BLOCKED: results must be a direct child of $TMP_ROOT." >&2
  exit 78
fi
case "$RESULTS_NAME" in
  navidrome-p002-results-*) RESULTS_RUN_ID=${RESULTS_NAME#navidrome-p002-results-} ;;
  *)
    echo "BLOCKED: results directory must use the navidrome-p002-results-RUN_ID name." >&2
    exit 78
    ;;
esac
case "$RESULTS_RUN_ID" in
  ''|*[!0-9TZ]*)
    echo "BLOCKED: results RUN_ID must contain only digits, T, and Z." >&2
    exit 78
    ;;
esac
RESULTS_REQUESTED="$RESULTS_PARENT/$RESULTS_NAME"
reject_music_path "$RESULTS_REQUESTED" || exit 78
mkdir -m 700 "$RESULTS_REQUESTED" || {
  echo "BLOCKED: results directory already exists or cannot be created: $RESULTS_REQUESTED" >&2
  exit 78
}
RESULTS=$(canonical_dir "$RESULTS_REQUESTED") || {
  echo "BLOCKED: cannot resolve results directory." >&2
  exit 78
}
reject_music_path "$RESULTS" || exit 78

STAGE=$(mktemp -d "$TMP_ROOT/navidrome-p002-device-XXXXXXXX") || {
  echo "BLOCKED: cannot create temporary staging directory." >&2
  exit 78
}
STAGE=$(canonical_dir "$STAGE")
STAGE_MARKER="$STAGE/.p002-owner"
printf '%s\n' "$STAGE_TOKEN" > "$STAGE_MARKER"
chmod 700 "$STAGE"
mkdir -m 700 "$STAGE/tmp" "$RESULTS/runs"
printf '%s:%s\n' "$STAGE_TOKEN" "$RESULTS_NAME" > "$RESULTS/.p002-results-owner"

machine=$(sysctl -n hw.machine 2>/dev/null || true)
product_version=$(sw_vers -productVersion 2>/dev/null || true)
build_version=$(sysctl -n kern.osversion 2>/dev/null || true)
{
  printf 'hardware=%s\n' "$machine"
  printf 'product_version=%s\n' "$product_version"
  printf 'build_version=%s\n' "$build_version"
  printf 'architecture='; uname -m
  printf 'kernel='; uname -a
  printf 'uid='; id -u
  printf 'rootful_procursus_path='
  if [ -d /Library/LaunchDaemons ] && [ -d /usr/local/bin ]; then
    echo "present"
  else
    echo "not_verified"
  fi
  printf 'ldid='; command -v ldid 2>/dev/null || echo unavailable
  printf 'timeout='; command -v timeout 2>/dev/null || echo unavailable
  printf 'time='; if [ -x /usr/bin/time ]; then echo /usr/bin/time; else echo unavailable; fi
} > "$RESULTS/device-identity.txt"

if [ "$machine" != "iPad4,4" ] || [ "$product_version" != "12.5.7" ] ||
   [ "$build_version" != "16H81" ]; then
  echo "BLOCKED: expected iPad4,4 / iOS 12.5.7 build 16H81; observed $machine / $product_version / $build_version." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "BLOCKED: Procursus timeout is required to bound each probe process." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi
if ! command -v shasum >/dev/null 2>&1; then
  echo "BLOCKED: shasum is required to verify the received probe bundle." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi

if ! grep -qx 'signing=PASS' "$BUNDLE/SIGNING.txt" ||
   ! grep -qx 'method=ad-hoc-signature' "$BUNDLE/SIGNING.txt" ||
   ! grep -qx 'entitlements=none' "$BUNDLE/SIGNING.txt"; then
  echo "BLOCKED: bundle does not prove the expected ad-hoc signature with no entitlements." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi
for phase in source_validation toolchain_qualification compilation_linking macho_inspection signing; do
  if ! grep -Eq "\"$phase\"[[:space:]]*:[[:space:]]*\"PASS\"" "$BUNDLE/qualification.json"; then
    echo "BLOCKED: qualification.json does not record $phase=PASS." \
      | tee "$RESULTS/preflight.txt" >&2
    exit 78
  fi
done
if ! grep -Eq '"physical_device_execution"[[:space:]]*:[[:space:]]*"BLOCKED"' "$BUNDLE/qualification.json"; then
  echo "BLOCKED: qualification.json must leave physical-device execution BLOCKED until this run completes." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi
if ! awk '
  NF != 2 { exit 1 }
  length($1) != 64 || $1 !~ /^[0-9a-f]+$/ { exit 1 }
  $2 == "native-c-probe" { native++ }
  $2 == "go-pure-probe" { pure++ }
  $2 == "go-cgo-probe" { cgo++ }
  $2 == "go-multip-probe" { multip++ }
  END { exit !(NR == 4 && native == 1 && pure == 1 && cgo == 1 && multip == 1) }
' "$BUNDLE/SHA256SUMS"; then
  echo "BLOCKED: SHA256SUMS must list exactly the four expected probe filenames." \
    | tee "$RESULTS/preflight.txt" >&2
  exit 78
fi
if ! (cd "$BUNDLE" && shasum -a 256 -c SHA256SUMS) > "$RESULTS/checksums.txt" 2>&1; then
  echo "FAIL: received probe checksum verification failed." | tee "$RESULTS/preflight.txt" >&2
  exit 1
fi
for name in native-c-probe go-pure-probe go-cgo-probe go-multip-probe; do
  if [ ! -f "$BUNDLE/$name" ] || [ ! -x "$BUNDLE/$name" ]; then
    echo "FAIL: probe is missing or not executable: $name" | tee "$RESULTS/preflight.txt" >&2
    exit 1
  fi
  cp -p "$BUNDLE/$name" "$STAGE/$name"
done
cp "$RESULTS/checksums.txt" "$STAGE/received-checksums.txt"

{
  echo "identity=PASS"
  echo "bundle_sha256=PASS"
  echo "signature_policy=PASS (host codesign verification; ad-hoc; no entitlements)"
  echo "execution=individual probes, each bounded to 30 seconds"
  echo "repetitions=5 per probe and GOMAXPROCS setting"
} > "$RESULTS/preflight.txt"
printf 'case\trepetition\tgomaxprocs\texit_status\n' > "$RESULTS/summary.tsv"
touch "$STAGE/start.marker"
ulimit -c 0 2>/dev/null || true
if command -v dmesg >/dev/null 2>&1; then
  if dmesg > "$STAGE/dmesg.before" 2> "$RESULTS/dmesg.before.err"; then
    echo "dmesg_before=CAPTURED" > "$RESULTS/kernel-log-status.txt"
  else
    status=$?
    echo "dmesg_before=UNAVAILABLE (exit=$status)" > "$RESULTS/kernel-log-status.txt"
  fi
else
  echo "dmesg_before=UNAVAILABLE (command missing)" > "$RESULTS/kernel-log-status.txt"
fi
if command -v vm_stat >/dev/null 2>&1; then
  vm_stat > "$RESULTS/vm-stat-before.txt" 2>&1 || true
fi

run_case() {
  case_name=$1
  binary=$2
  procs=$3
  repetition=1
  while [ "$repetition" -le 5 ]; do
    label="$case_name-$repetition"
    stdout_file="$RESULTS/runs/$label.stdout"
    stderr_file="$RESULTS/runs/$label.stderr"
    if [ -x /usr/bin/time ]; then
      if /usr/bin/time -l timeout 30 env IOS_PROBE_TMPDIR="$STAGE/tmp" GOMAXPROCS="$procs" \
        "$STAGE/$binary" > "$stdout_file" 2> "$stderr_file"; then
        status=0
      else
        status=$?
      fi
    else
      if timeout 30 env IOS_PROBE_TMPDIR="$STAGE/tmp" GOMAXPROCS="$procs" \
        "$STAGE/$binary" > "$stdout_file" 2> "$stderr_file"; then
        status=0
      else
        status=$?
        echo "runtime_and_memory=NOT_TESTED (/usr/bin/time unavailable)" >> "$stderr_file"
      fi
    fi
    printf '%s\t%d\t%s\t%d\n' "$case_name" "$repetition" "$procs" "$status" \
      >> "$RESULTS/summary.tsv"
    if [ "$status" -ne 0 ]; then
      echo "FAIL: $case_name repetition $repetition exited $status." >&2
      return 1
    fi
    repetition=$((repetition + 1))
  done
}

failed=0
run_case native-c native-c-probe 1 || failed=1
run_case pure-go go-pure-probe 1 || failed=1
run_case cgo-callback go-cgo-probe 1 || failed=1
run_case multi-p-1 go-multip-probe 1 || failed=1
run_case multi-p-2 go-multip-probe 2 || failed=1

if command -v vm_stat >/dev/null 2>&1; then
  vm_stat > "$RESULTS/vm-stat-after.txt" 2>&1 || true
fi
if command -v dmesg >/dev/null 2>&1; then
  if dmesg > "$STAGE/dmesg.after" 2> "$RESULTS/dmesg.after.err"; then
    echo "dmesg_after=CAPTURED" >> "$RESULTS/kernel-log-status.txt"
  else
    status=$?
    echo "dmesg_after=UNAVAILABLE (exit=$status)" >> "$RESULTS/kernel-log-status.txt"
  fi
  if [ -f "$STAGE/dmesg.before" ] && [ -f "$STAGE/dmesg.after" ]; then
    diff -u "$STAGE/dmesg.before" "$STAGE/dmesg.after" 2>/dev/null | \
      grep '^+' | grep -Eiv '^\+\+\+' | \
      grep -Ei 'dyld|amfi|jetsam|native-c-probe|go-pure-probe|go-cgo-probe|go-multip-probe' \
      > "$RESULTS/kernel-runtime-events.txt" || true
  fi
else
  echo "dmesg=UNAVAILABLE" > "$RESULTS/kernel-runtime-events.txt"
fi

if command -v log >/dev/null 2>&1; then
  log show --last 5m --style compact \
    --predicate 'process == "native-c-probe" OR process == "go-pure-probe" OR process == "go-cgo-probe" OR process == "go-multip-probe" OR eventMessage CONTAINS[c] "jetsam"' \
    > "$RESULTS/unified-log.txt" 2>&1 || echo "unified log query unavailable" >> "$RESULTS/unified-log.txt"
else
  echo "unified_log=UNAVAILABLE" > "$RESULTS/unified-log.txt"
fi

crash_copy="$RESULTS/crash-reports"
mkdir -p "$crash_copy"
for crash_root in /var/mobile/Library/Logs/CrashReporter /private/var/mobile/Library/Logs/CrashReporter; do
  [ -d "$crash_root" ] || continue
  find "$crash_root" -type f -newer "$STAGE/start.marker" \
    \( -name '*native-c-probe*' -o -name '*go-pure-probe*' -o -name '*go-cgo-probe*' \
       -o -name '*go-multip-probe*' -o -name 'JetsamEvent*' \) -print |
  while IFS= read -r report; do
    if grep -Eil 'native-c-probe|go-pure-probe|go-cgo-probe|go-multip-probe' "$report" >/dev/null 2>&1; then
      cp "$report" "$crash_copy/"
    fi
  done
done
if [ -z "$(find "$crash_copy" -type f -print -quit)" ]; then
  echo "crash_or_jetsam_reports=NONE_FOUND_OR_UNAVAILABLE" > "$RESULTS/crash-report-status.txt"
else
  echo "crash_or_jetsam_reports=CAPTURED" > "$RESULTS/crash-report-status.txt"
fi

if [ "$failed" -ne 0 ]; then
  echo "device_execution=FAIL" > "$RESULTS/device-status.txt"
  echo "device_execution=FAIL"
  exit 1
fi
echo "device_execution=PASS" > "$RESULTS/device-status.txt"
echo "device_execution=PASS"
echo "All probe runs passed on iPad4,4 / iOS 12.5.7 build 16H81."
