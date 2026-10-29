#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: cleanup_p002_device.sh INPUT_DIR RESULTS_DIR RUN_ID" >&2
  exit 2
fi

INPUT=$1
RESULTS=$2
RUN_ID=$3
ROOT=/private/var/tmp

if [ "$(id -u)" -ne 0 ]; then
  echo "Refusing cleanup: run as root over the existing SSH connection." >&2
  exit 1
fi

canonical_dir() {
  (CDPATH= cd "$1" 2>/dev/null && pwd -P)
}

case "$RUN_ID" in
  *[!0-9TZ]*|'')
    echo "Refusing cleanup: RUN_ID must contain only digits, T, and Z." >&2
    exit 2
    ;;
esac

[ -d "$INPUT" ] && [ ! -L "$INPUT" ] || {
  echo "Refusing cleanup: input directory is missing or a symlink." >&2
  exit 1
}
[ -d "$RESULTS" ] && [ ! -L "$RESULTS" ] || {
  echo "Refusing cleanup: results directory is missing or a symlink." >&2
  exit 1
}
INPUT=$(canonical_dir "$INPUT") || exit 1
RESULTS=$(canonical_dir "$RESULTS") || exit 1

case "$INPUT" in
  "$ROOT"/navidrome-p002-input-*) ;;
  *)
    echo "Refusing cleanup: input is outside the P002 temporary prefix." >&2
    exit 1
    ;;
esac
case "$RESULTS" in
  "$ROOT"/navidrome-p002-results-*) ;;
  *)
    echo "Refusing cleanup: results are outside the P002 temporary prefix." >&2
    exit 1
    ;;
esac
[ "${INPUT%/*}" = "$ROOT" ] && [ "${RESULTS%/*}" = "$ROOT" ] || {
  echo "Refusing cleanup: both directories must be direct children of /private/var/tmp." >&2
  exit 1
}
[ "${INPUT##*/}" = "navidrome-p002-input-$RUN_ID" ] &&
  [ "${RESULTS##*/}" = "navidrome-p002-results-$RUN_ID" ] || {
    echo "Refusing cleanup: directory names do not match RUN_ID." >&2
    exit 1
  }
[ -f "$INPUT/.p002-upload-owner" ] &&
  [ "$(cat "$INPUT/.p002-upload-owner")" = "$RUN_ID" ] || {
    echo "Refusing cleanup: uploaded-bundle ownership marker did not match." >&2
    exit 1
  }
[ -f "$RESULTS/.p002-results-owner" ] || {
  echo "Refusing cleanup: results ownership marker is missing." >&2
  exit 1
}
OWNER=$(cat "$RESULTS/.p002-results-owner")
case "$OWNER" in
  navidrome-p002-device-*:navidrome-p002-results-"$RUN_ID") ;;
  *)
    echo "Refusing cleanup: results ownership marker does not match this run." >&2
    exit 1
    ;;
esac

rm -rf "$INPUT" "$RESULTS"
echo "Removed only the verified P002 input and results directories."
