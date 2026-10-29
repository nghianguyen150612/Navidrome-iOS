#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
PIN_FILE="$ROOT/docs/ios/p002-toolchain.json"
OUTPUT_PATH=${1:-"$ROOT/build/ios/p002"}
if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$ROOT/$OUTPUT_PATH"
fi
mkdir -p "$OUTPUT_PATH"
OUT=$(cd "$OUTPUT_PATH" && pwd -P)
if [[ -n "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Output directory must be empty: $OUT" >&2
  exit 2
fi

mkdir -p "$OUT/bundle" "$OUT/logs" "$OUT/inspection" "$OUT/source"
BUNDLE="$OUT/bundle"
LOGS="$OUT/logs"
INSPECTION="$OUT/inspection"
SOURCE="$OUT/source"

source_validation=${P002_SOURCE_VALIDATION:-NOT_TESTED}
toolchain_status=NOT_TESTED
compile_status=NOT_TESTED
macho_status=NOT_TESTED
signing_status=NOT_TESTED
device_status=BLOCKED
device_reason="No physical iPad runner is connected to GitHub Actions; use P002_DEVICE_TEST.md."
overall_status=BLOCKED
go_version=
go_archive=
go_archive_sha256=
host_arch=
host_os=
sdk_version=
sdk_path=
clang_version=
linker_version=
codesign_path=
goroot=
go_bin=
clang_path=
cc_wrapper=
stage_dir=
stage_marker=
stage_parent=
stage_token="p002-build-$$-$(date +%s)"

write_manifest() {
  local result=$?
  trap - EXIT
  set +e
  if [[ -n "$OUT" && -d "$OUT" ]]; then
    P002_ROOT="$ROOT" P002_OUT="$OUT" P002_BUNDLE="$BUNDLE" \
    P002_SOURCE_STATUS="$source_validation" P002_TOOLCHAIN_STATUS="$toolchain_status" \
    P002_COMPILE_STATUS="$compile_status" P002_MACHO_STATUS="$macho_status" \
    P002_SIGNING_STATUS="$signing_status" P002_DEVICE_STATUS="$device_status" \
    P002_DEVICE_REASON="$device_reason" P002_OVERALL_STATUS="$overall_status" \
    P002_GO_VERSION="$go_version" P002_GO_ARCHIVE="$go_archive" \
    P002_GO_ARCHIVE_SHA256="$go_archive_sha256" P002_HOST_ARCH="$host_arch" \
    P002_HOST_OS="$host_os" P002_SDK_VERSION="$sdk_version" P002_SDK_PATH="$sdk_path" \
    P002_CLANG_VERSION="$clang_version" P002_LINKER_VERSION="$linker_version" \
    P002_CODESIGN_PATH="$codesign_path" \
    python3 - "$PIN_FILE" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

pin = json.loads(Path(sys.argv[1]).read_text())
root = Path(os.environ["P002_ROOT"])
out = Path(os.environ["P002_OUT"])
bundle = Path(os.environ["P002_BUNDLE"])
statuses = {
    "source_validation": os.environ["P002_SOURCE_STATUS"],
    "toolchain_qualification": os.environ["P002_TOOLCHAIN_STATUS"],
    "compilation_linking": os.environ["P002_COMPILE_STATUS"],
    "macho_inspection": os.environ["P002_MACHO_STATUS"],
    "signing": os.environ["P002_SIGNING_STATUS"],
    "physical_device_execution": os.environ["P002_DEVICE_STATUS"],
}
def git(*args):
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    except Exception:
        return ""

def hashes(directory):
    result = {}
    for name in ("native-c-probe", "go-pure-probe", "go-cgo-probe", "go-multip-probe"):
        path = directory / name
        if path.is_file():
            result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result

def hash_lines(path):
    result = {}
    if not path.is_file():
        return result
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            result[parts[1]] = parts[0]
    return result

checkout_commit = git("rev-parse", "HEAD")
source_commit = checkout_commit
base = git("merge-base", "HEAD", "origin/iOS")
event_path = os.environ.get("GITHUB_EVENT_PATH", "")
if event_path and Path(event_path).is_file():
    try:
        event = json.loads(Path(event_path).read_text())
        pull_request = event.get("pull_request", {})
        source_commit = pull_request.get("head", {}).get("sha", source_commit)
        base = pull_request.get("base", {}).get("sha", base)
    except (OSError, json.JSONDecodeError):
        pass
record = {
    "schema": "navidrome-ios-p002-qualification-v1",
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "repository": "nghianguyen150612/Navidrome-iOS",
    "source_commit": source_commit,
    "build_checkout_commit": checkout_commit,
    "base_commit": base,
    "target": pin["target"],
    "go_pin": {
        "version": pin["go_version"],
        "tag": pin["go_tag"],
        "source_commit": pin["go_source_commit"],
        "source_archive_sha256": pin["go_source_archive_sha256"],
        "host_archive": os.environ["P002_GO_ARCHIVE"],
        "host_archive_sha256": os.environ["P002_GO_ARCHIVE_SHA256"],
        "runtime_source_sha256": pin["runtime_source_sha256"],
    },
    "observed_toolchain": {
        "host_os": os.environ["P002_HOST_OS"],
        "host_arch": os.environ["P002_HOST_ARCH"],
        "go_version": os.environ["P002_GO_VERSION"],
        "iphoneos_sdk_version": os.environ["P002_SDK_VERSION"],
        "iphoneos_sdk_path": os.environ["P002_SDK_PATH"],
        "apple_clang": os.environ["P002_CLANG_VERSION"],
        "linker": os.environ["P002_LINKER_VERSION"],
        "codesign_tool_path": os.environ["P002_CODESIGN_PATH"],
    },
    "environment_policy": {
        "GOOS": "ios",
        "GOARCH": "arm64",
        "CGO_ENABLED": "1 for every Go probe because ios/arm64 requires external CGo linking",
        "probe_source_uses_cgo": "only the callback probe; pure-Go and multi-P import no CGo code",
        "IOS_MINIMUM_OS": "12.0",
        "CC": "xcrun iphoneos SDK clang wrapper with -arch arm64, -isysroot, and -miphoneos-version-min=12.0",
        "SDKROOT": "the xcrun-selected iphoneos SDK",
        "CGO_CPPFLAGS": "",
        "CGO_CFLAGS": "",
        "CGO_CXXFLAGS": "",
        "CGO_LDFLAGS": "",
        "GOFLAGS": "",
        "GOENV": "off",
        "GOTOOLCHAIN": "local",
        "cgo_checkptr": "enabled at level 2 for the CGo probe",
        "runtime_patch": "none; stock Go runtime",
        "signing_policy": "ad-hoc signature with no entitlements",
    },
    "statuses": statuses,
    "overall_status": os.environ["P002_OVERALL_STATUS"],
    "p002_decision": (
        "FAIL — NO-GO for P003"
        if any(value == "FAIL" for value in statuses.values())
        else "PASS"
        if all(value == "PASS" for value in statuses.values())
        else "BLOCKED — NO-GO for P003"
    ),
    "physical_device_reason": os.environ["P002_DEVICE_REASON"],
    "unsigned_probe_sha256": hash_lines(bundle / "UNSIGNED_SHA256SUMS"),
    "signed_probe_sha256": hashes(bundle),
}
(out / "qualification.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
if bundle.is_dir():
    (bundle / "qualification.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    device_doc = root / "docs/ios/P002_DEVICE_TEST.md"
    if device_doc.is_file():
        (bundle / "P002_DEVICE_TEST.md").write_bytes(device_doc.read_bytes())
PY
    for file in "$OUT/toolchain.txt" "$OUT/go-toolchain.txt" \
      "$OUT/go-source-sha256.txt" "$OUT/source/runtime-source-review.txt" \
      "$OUT/source/runtime-procyieldAsm-disassembly.txt" "$OUT/source/go-pure-build-info.txt" \
      "$OUT/source/go-cgo-build-info.txt" "$OUT/source/go-multi-p-build-info.txt" \
      "$OUT/inspection/macho-summary.txt"; do
      [[ -f "$file" ]] && cp "$file" "$BUNDLE/$(basename "$file")"
    done
    cp "$ROOT/scripts/ios/run_p002_device.sh" "$BUNDLE/run_p002_device.sh"
    cp "$ROOT/scripts/ios/cleanup_p002_device.sh" "$BUNDLE/cleanup_p002_device.sh"
    chmod 700 "$BUNDLE/run_p002_device.sh" "$BUNDLE/cleanup_p002_device.sh"
    if [[ -d "$INSPECTION" ]]; then
      for file in "$INSPECTION"/*; do
        [[ -f "$file" ]] && cp "$file" "$BUNDLE/$(basename "$file")"
      done
    fi
    for file in "$LOGS"/*-codesign.log; do
      [[ -f "$file" ]] && cp "$file" "$BUNDLE/$(basename "$file")"
    done
    cat > "$OUT/statuses.txt" <<EOF
source_validation=$source_validation
toolchain_qualification=$toolchain_status
compilation_linking=$compile_status
macho_inspection=$macho_status
signing=$signing_status
physical_device_execution=$device_status
overall=$overall_status
EOF
    cp "$OUT/statuses.txt" "$BUNDLE/statuses.txt"
    if [[ "$signing_status" == PASS ]]; then
      local zip_path="$OUT/p002-ios-a7-go-runtime-probes.zip"
      if ! (cd "$BUNDLE" && zip -q -r "$zip_path" .); then
        echo "FAIL: could not package the signed P002 probe bundle." >&2
        result=1
      elif ! (cd "$OUT" && shasum -a 256 "$(basename "$zip_path")" > "$(basename "$zip_path").sha256"); then
        echo "FAIL: could not checksum the P002 probe bundle." >&2
        result=1
      fi
    fi
  fi
  if [[ -n "$stage_dir" && -n "$stage_parent" && -d "$stage_dir" && -f "$stage_marker" ]] &&
     [[ "$(cat "$stage_marker" 2>/dev/null)" == "$stage_token" ]] &&
     [[ "$stage_dir" == "$stage_parent"/navidrome-p002-build-* ]]; then
    rm -rf -- "$stage_dir"
  fi
  exit "$result"
}
trap write_manifest EXIT

block_toolchain() {
  toolchain_status=BLOCKED
  compile_status=BLOCKED
  macho_status=BLOCKED
  signing_status=BLOCKED
  overall_status=BLOCKED
  echo "BLOCKED: $*" | tee "$LOGS/blocker.txt" >&2
  exit 78
}

fail_toolchain() {
  toolchain_status=FAIL
  overall_status=FAIL
  echo "FAIL: $*" | tee "$LOGS/toolchain-failure.txt" >&2
  exit 1
}

fail_compile() {
  compile_status=FAIL
  overall_status=FAIL
  echo "FAIL: $*" | tee "$LOGS/compile-failure.txt" >&2
  exit 1
}

fail_inspection() {
  macho_status=FAIL
  overall_status=FAIL
  echo "FAIL: $*" | tee "$LOGS/inspection-failure.txt" >&2
  exit 1
}

fail_signing() {
  signing_status=FAIL
  overall_status=FAIL
  echo "FAIL: $*" | tee "$LOGS/signing-failure.txt" >&2
  exit 1
}

pin_value() {
  python3 - "$PIN_FILE" "$1" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1]))
parts = sys.argv[2].split("|") if "|" in sys.argv[2] else sys.argv[2].split(".")
for part in parts:
    value = value[part]
print(value)
PY
}

host_arch=$(uname -m)
host_os=$(sw_vers -productVersion 2>/dev/null || uname -s)
case "$host_arch" in
  x86_64) archive_key=darwin-amd64 ;;
  arm64) archive_key=darwin-arm64 ;;
  *) block_toolchain "unsupported macOS host architecture: $host_arch" ;;
esac
go_archive=$(pin_value "go_archives.$archive_key.file")
go_archive_sha256=$(pin_value "go_archives.$archive_key.sha256")
go_version=$(pin_value go_version)

if [[ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ]]; then
  fail_toolchain "MACOSX_DEPLOYMENT_TARGET is set; refusing a host-targeted build"
fi
if ! command -v xcrun >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then
  block_toolchain "Xcode command-line tools and xcrun are unavailable"
fi
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)
if [[ -z "$sdk_path" || -z "$sdk_version" || ! -d "$sdk_path" ]]; then
  block_toolchain "the iPhoneOS SDK is unavailable; no substitute SDK will be used"
fi
case "$sdk_path" in
  *iPhoneOS*.sdk) ;;
  *) block_toolchain "xcrun returned a non-iPhoneOS SDK path: $sdk_path" ;;
esac
clang_path=$(xcrun --sdk iphoneos --find clang 2>/dev/null || true)
if [[ -z "$clang_path" || ! -x "$clang_path" ]]; then
  block_toolchain "the iPhoneOS SDK clang is unavailable"
fi

stage_parent=${RUNNER_TEMP:-/tmp}
mkdir -p "$stage_parent"
stage_parent=$(cd "$stage_parent" && pwd -P)
stage_dir=$(mktemp -d "$stage_parent/navidrome-p002-build-XXXXXXXX")
stage_marker="$stage_dir/.p002-owner"
printf '%s\n' "$stage_token" > "$stage_marker"

cc_wrapper="$stage_dir/ios-clangwrap.sh"
cat > "$cc_wrapper" <<'WRAP'
#!/bin/sh
exec "$P002_CLANG" -arch arm64 -isysroot "$P002_IOS_SDK" -miphoneos-version-min=12.0 "$@"
WRAP
chmod 700 "$cc_wrapper"

toolchain_status=PASS
P002_CLANG="$clang_path"
P002_IOS_SDK="$sdk_path"
export P002_CLANG P002_IOS_SDK

{
  printf 'Repository commit='; git -C "$ROOT" rev-parse HEAD
  printf 'Repository base='; git -C "$ROOT" merge-base HEAD origin/iOS 2>/dev/null || true
  printf 'Host OS='; sw_vers
  printf 'Host architecture='; uname -m
  printf 'Xcode path='; xcode-select -p
  xcodebuild -version
  printf 'iPhoneOS SDK path=%s\n' "$sdk_path"
  printf 'iPhoneOS SDK version=%s\n' "$sdk_version"
  if [[ -f "$sdk_path/SDKSettings.plist" ]]; then
    printf 'iPhoneOS SDKSettings.plist SHA256='
    shasum -a 256 "$sdk_path/SDKSettings.plist"
  fi
  printf 'Apple clang path=%s\n' "$clang_path"
  "$clang_path" --version | head -n 1
  printf 'Linker path='; xcrun --sdk iphoneos --find ld
  linker_path=$(xcrun --sdk iphoneos --find ld)
  "$linker_path" -v 2>&1 | head -n 3
  printf 'Go archive=%s\nGo archive SHA256=%s\n' "$go_archive" "$go_archive_sha256"
  printf 'Go source commit=%s\n' "$(pin_value go_source_commit)"
  printf 'Go source archive SHA256=%s\n' "$(pin_value go_source_archive_sha256)"
  printf 'Deployment target=12.0\n'
  printf 'Build mode=pie (explicitly supported by Go 1.27.3 ios/arm64)\n'
  printf 'Go build flags=-x -trimpath -buildvcs=false -mod=readonly -buildmode=pie -ldflags=-linkmode=external\n'
  printf 'CGo checkptr flags=-gcflags=all=-d=checkptr=2 (callback probe only)\n'
  printf 'Native C flags=-std=c11 -O2 -Wall -Wextra -Werror -pthread\n'
  printf 'Code-signing tool path='; xcrun --find codesign
  printf 'Code-signing tool help='; codesign -h 2>&1 | head -n 1 || true
  printf 'GOENV=off\nGOTOOLCHAIN=local\nGOFLAGS=\n'
  printf 'CGO_ENABLED=1 for all Go probes; only the callback source imports CGo\n'
  printf 'Go external link flag=-linkmode=external\n'
  printf 'SDKROOT=%s\n' "$sdk_path"
  printf 'CGO_CPPFLAGS=\nCGO_CFLAGS=\nCGO_CXXFLAGS=\nCGO_LDFLAGS=\n'
  printf 'GOOS=ios\nGOARCH=arm64\n'
  printf 'CC=%s\n' "$cc_wrapper"
  printf 'CC flags=-arch arm64 -isysroot %s -miphoneos-version-min=12.0\n' "$sdk_path"
  printf 'MACOSX_DEPLOYMENT_TARGET=unset\n'
} > "$OUT/toolchain.txt" 2>&1
clang_version=$("$clang_path" --version 2>/dev/null | head -n 1)
linker_path=$(xcrun --sdk iphoneos --find ld)
linker_version=$("$linker_path" -v 2>&1 | head -n 1)
codesign_path="$(xcrun --find codesign 2>/dev/null || printf 'codesign path unavailable')"

curl --fail --location --retry 3 --silent --show-error \
  "https://go.dev/dl/$go_archive" -o "$stage_dir/$go_archive" ||
  block_toolchain "could not download the pinned Go archive"
if ! printf '%s  %s\n' "$go_archive_sha256" "$stage_dir/$go_archive" | shasum -a 256 -c - > "$LOGS/go-archive-checksum.log" 2>&1; then
  fail_toolchain "pinned Go archive SHA-256 mismatch"
fi
tar -xzf "$stage_dir/$go_archive" -C "$stage_dir" ||
  fail_toolchain "could not extract the pinned Go archive"
goroot="$stage_dir/go"
go_bin="$goroot/bin/go"
expected_host_goarch=amd64
[[ "$host_arch" == arm64 ]] && expected_host_goarch=arm64
if [[ ! -x "$go_bin" ]] || [[ "$("$go_bin" version)" != "go version go1.27.3 darwin/$expected_host_goarch" ]]; then
  fail_toolchain "downloaded archive did not report the pinned Go version and host architecture"
fi
go_version=$("$go_bin" version)

{
  printf 'Verified Go version='; "$go_bin" version
  printf 'GOROOT=%s\n' "$goroot"
  printf 'Go env for pure-Go probe (CGo enabled for required external linking):\n'
  env GOENV=off GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$cc_wrapper" SDKROOT="$sdk_path" \
    CGO_CPPFLAGS= CGO_CFLAGS= CGO_CXXFLAGS= CGO_LDFLAGS= GOTOOLCHAIN=local GOFLAGS= \
    "$go_bin" env -json GOOS GOARCH CGO_ENABLED GOHOSTOS GOHOSTARCH GOVERSION GOROOT CC GOFLAGS GOTOOLCHAIN GOEXPERIMENT
  printf '\nGo env for CGo probe:\n'
  env GOENV=off GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$cc_wrapper" SDKROOT="$sdk_path" \
    CGO_CPPFLAGS= CGO_CFLAGS= CGO_CXXFLAGS= CGO_LDFLAGS= \
    GOTOOLCHAIN=local GOFLAGS= "$go_bin" env -json GOOS GOARCH CGO_ENABLED GOHOSTOS GOHOSTARCH GOVERSION GOROOT CC GOFLAGS GOTOOLCHAIN GOEXPERIMENT
  printf '\nGo build mode help:\n'
  "$go_bin" help buildmode
  printf '\nGo linker options (usage output):\n'
  "$go_bin" tool link -h 2>&1 || true
  printf '\nGo link configuration source:\n'
  sed -n '32,60p;143,159p' "$goroot/src/cmd/link/internal/ld/config.go"
  sed -n '175,198p;230,245p' "$goroot/src/internal/platform/supported.go"
} > "$OUT/go-toolchain.txt" 2>&1

runtime_sha_expected=$(pin_value "runtime_source_sha256|src/runtime/asm_arm64.s")
darwin_sha_expected=$(pin_value "runtime_source_sha256|src/runtime/os_darwin.go")
link_sha_expected=$(pin_value "runtime_source_sha256|src/cmd/link/internal/ld/config.go")
platform_sha_expected=$(pin_value "runtime_source_sha256|src/internal/platform/supported.go")
for item in \
  "src/runtime/asm_arm64.s:$runtime_sha_expected" \
  "src/runtime/os_darwin.go:$darwin_sha_expected" \
  "src/cmd/link/internal/ld/config.go:$link_sha_expected" \
  "src/internal/platform/supported.go:$platform_sha_expected"; do
  file=${item%%:*}
  expected=${item#*:}
  actual=$(shasum -a 256 "$goroot/$file" | awk '{print $1}')
  printf '%s  %s\n' "$actual" "$file" >> "$OUT/go-source-sha256.txt"
  [[ "$actual" == "$expected" ]] || fail_toolchain "Go source file hash mismatch: $file"
done
awk '
  /^TEXT runtime·procyieldAsm\(SB\)/ { copy=1 }
  copy { print }
  copy && /^TEXT / && !/procyieldAsm/ { exit }
' "$goroot/src/runtime/asm_arm64.s" > "$SOURCE/runtime-procyieldAsm-source.txt"
grep -q 'CNTFRQ_EL0' "$SOURCE/runtime-procyieldAsm-source.txt" ||
  fail_toolchain "pinned Go runtime source does not contain the expected counter routine"
grep -q 'CNTVCT_EL0' "$SOURCE/runtime-procyieldAsm-source.txt" ||
  fail_toolchain "pinned Go runtime source does not contain the expected virtual counter reads"
grep -n -A12 -B2 'iOS does not support alternate signal stack' "$goroot/src/runtime/os_darwin.go" \
  > "$SOURCE/ios-signal-source.txt"
{
  printf 'Go version='; "$go_bin" version
  printf 'Go source tag=%s\n' "$(pin_value go_tag)"
  printf 'Go source commit=%s\n' "$(pin_value go_source_commit)"
  cat "$OUT/go-source-sha256.txt"
  printf '\nStock runtime source, unmodified:\n'
  cat "$SOURCE/runtime-procyieldAsm-source.txt"
  printf '\niOS signal-stack source notes:\n'
  cat "$SOURCE/ios-signal-source.txt"
  printf '\nNo Go runtime files are modified by this workflow.\n'
} > "$SOURCE/runtime-source-review.txt"

if ! "$clang_path" -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=12.0 \
  -std=c11 -O2 -Wall -Wextra -Werror -pthread \
  "$ROOT/tools/ios-p002/native-c/main.c" -o "$BUNDLE/native-c-probe" \
  > "$LOGS/native-c-build.log" 2>&1; then
  fail_compile "native C probe compilation/linking failed"
fi

if ! env GOENV=off GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$cc_wrapper" SDKROOT="$sdk_path" \
  CGO_CPPFLAGS= CGO_CFLAGS= CGO_CXXFLAGS= CGO_LDFLAGS= GOTOOLCHAIN=local GOFLAGS= \
  "$go_bin" build -x -trimpath -buildvcs=false -mod=readonly -buildmode=pie \
  -ldflags=-linkmode=external -o "$BUNDLE/go-pure-probe" ./tools/ios-p002/pure-go \
  > "$LOGS/go-pure-build.log" 2>&1; then
  fail_compile "pure-Go iOS probe compilation/linking failed"
fi

if ! env GOENV=off GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$cc_wrapper" SDKROOT="$sdk_path" \
  CGO_CPPFLAGS= CGO_CFLAGS= CGO_CXXFLAGS= CGO_LDFLAGS= GOTOOLCHAIN=local GOFLAGS= \
  "$go_bin" build -x -trimpath -buildvcs=false -mod=readonly -buildmode=pie \
  -ldflags=-linkmode=external -gcflags=all=-d=checkptr=2 \
  -o "$BUNDLE/go-cgo-probe" ./tools/ios-p002/cgo-callback \
  > "$LOGS/go-cgo-build.log" 2>&1; then
  fail_compile "CGo callback iOS probe compilation/linking failed"
fi

if ! env GOENV=off GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$cc_wrapper" SDKROOT="$sdk_path" \
  CGO_CPPFLAGS= CGO_CFLAGS= CGO_CXXFLAGS= CGO_LDFLAGS= GOTOOLCHAIN=local GOFLAGS= \
  "$go_bin" build -x -trimpath -buildvcs=false -mod=readonly -buildmode=pie \
  -ldflags=-linkmode=external -o "$BUNDLE/go-multip-probe" ./tools/ios-p002/multi-p \
  > "$LOGS/go-multi-p-build.log" 2>&1; then
  fail_compile "multi-P iOS probe compilation/linking failed"
fi
compile_status=PASS

if ! "$go_bin" tool objdump -s 'runtime\.procyieldAsm' "$BUNDLE/go-multip-probe" \
  > "$SOURCE/runtime-procyieldAsm-disassembly.txt" 2>&1; then
  fail_inspection "Go tool objdump could not inspect runtime.procyieldAsm"
fi
if ! grep -q 'procyieldAsm' "$SOURCE/runtime-procyieldAsm-disassembly.txt"; then
  fail_inspection "runtime.procyieldAsm disassembly was empty"
fi
"$go_bin" version -m "$BUNDLE/go-pure-probe" > "$SOURCE/go-pure-build-info.txt" 2>&1
"$go_bin" version -m "$BUNDLE/go-cgo-probe" > "$SOURCE/go-cgo-build-info.txt" 2>&1
"$go_bin" version -m "$BUNDLE/go-multip-probe" > "$SOURCE/go-multi-p-build-info.txt" 2>&1
(cd "$BUNDLE" && shasum -a 256 native-c-probe go-pure-probe go-cgo-probe go-multip-probe > UNSIGNED_SHA256SUMS)

if ! python3 "$ROOT/scripts/ios/inspect_p002_macho.py" \
  --output "$INSPECTION" --sdk-path "$sdk_path" \
  "$BUNDLE/native-c-probe" "$BUNDLE/go-pure-probe" \
  "$BUNDLE/go-cgo-probe" "$BUNDLE/go-multip-probe" \
  > "$LOGS/macho-inspection.log" 2>&1; then
  cat "$LOGS/macho-inspection.log" >&2
  fail_inspection "one or more probe artifacts failed Mach-O inspection"
fi
macho_status=PASS

for binary in "$BUNDLE/native-c-probe" "$BUNDLE/go-pure-probe" \
  "$BUNDLE/go-cgo-probe" "$BUNDLE/go-multip-probe"; do
  name=$(basename "$binary")
  if ! codesign --force --sign - --timestamp=none "$binary" \
    > "$LOGS/$name-codesign.log" 2>&1; then
    fail_signing "ad-hoc signing failed for $name"
  fi
  if ! codesign --verify --strict --verbose=2 "$binary" \
    >> "$LOGS/$name-codesign.log" 2>&1; then
    fail_signing "signature verification failed for $name"
  fi
  if ! codesign -d --entitlements :- "$binary" \
    > "$INSPECTION/$name-entitlements.xml" \
    2> "$INSPECTION/$name-signature-metadata.txt"; then
    fail_signing "could not inspect signature or entitlements for $name"
  fi
  if [[ -s "$INSPECTION/$name-entitlements.xml" ]]; then
    fail_signing "unexpected entitlements found in $name"
  fi
  codesign -d --verbose=4 "$binary" >> "$INSPECTION/$name-signature-metadata.txt" 2>&1 ||
    fail_signing "could not capture signature metadata for $name"
done
signing_status=PASS
overall_status=BLOCKED
cat > "$BUNDLE/SIGNING.txt" <<EOF
signing=PASS
method=ad-hoc-signature
entitlements=none
verification=codesign --verify --strict --verbose=2
EOF
(cd "$BUNDLE" && shasum -a 256 native-c-probe go-pure-probe go-cgo-probe go-multip-probe > SHA256SUMS)
echo "P002 artifacts were built with stock Go $go_version; no runtime patch was applied." \
  > "$BUNDLE/README.txt"
