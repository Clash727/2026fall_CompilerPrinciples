#!/usr/bin/env bash
# Use official prebuilt tools. No download, build, install, or device execution.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT=${1:-"$ROOT/results/run-$(date +%Y%m%dT%H%M%S)"}
EXPECTED=bde03a186183d9a5e78b1e4c48a5f9f00692935bc3656b678625d554db88673e
OPT=${BISHENGIR_OPT:-"$ROOT/ir-tools/bishengir/bin/bishengir-opt"}
test -x "$OPT" || { echo "Tool not found: $OPT" >&2; exit 1; }
test ! -e "$OUT" || { echo "Use a new output directory: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd -- "$OUT" && pwd)
# Unbuffered MLIR IR printing is very slow on WSL DrvFS. Keep transient logs
# in RAM, then copy the complete results to the user-selected A: directory.
WORK=$(mktemp -d /dev/shm/milr-vecadd.XXXXXX)
finish() {
  local status=$?
  trap - EXIT
  printf '%s\n' "$status" > "$WORK/run.exitcode"
  cp -a "$WORK/." "$OUT/" || status=1
  case "$WORK" in /dev/shm/milr-vecadd.*) rm -rf -- "$WORK";; esac
  echo "Results: $OUT (exit $status)"
  exit "$status"
}
trap finish EXIT
cd -- "$WORK"
mkdir snapshots stages diffs repeat
cp "$ROOT/add.mlir" input.mlir
printf '%s  input.mlir\n' "$EXPECTED" | sha256sum --check > input-check.txt
sha256sum "$ROOT/add.mlir" > input-original-before.sha256
"$OPT" --version > tool-version.txt 2>&1
printf 'tool=%s\ntarget=Ascend910B1\nworking_directory=%s\n' "$OPT" "$WORK" > environment.txt
date -Is >> environment.txt
uname -a >> environment.txt
cat /etc/os-release >> environment.txt
PIPELINE='builtin.module(canonicalize-module,hacc-append-device-spec{target=Ascend910B1},convert-to-hivm-pipeline,optimize-hivm-pipeline)'
printf '%s\n' "$PIPELINE" > pipeline.txt
record() {
  local label=$1 stdout=$2 stderr=$3 status
  shift 3
  { printf '%q ' "$@"; printf '> %q 2> %q\n' "$stdout" "$stderr"; } >> commands.sh
  set +e
  "$@" >"$stdout" 2>"$stderr"
  status=$?
  set -e
  printf '%s\t%d\n' "$label" "$status" >> exitcodes.tsv
  return "$status"
}
printf 'step\texitcode\n' > exitcodes.tsv
record parse parse.stdout.log parse.stderr.log "$OPT" input.mlir --verify-each -o parsed.mlir
FLAGS=("--pass-pipeline=$PIPELINE" --mlir-disable-threading --verify-each
  --mlir-print-ir-before-all --mlir-print-ir-after-all --mlir-print-ir-module-scope)
start=$(date +%s%N)
record middle stdout.log passes.log "$OPT" input.mlir "${FLAGS[@]}" -o final.mlir
end=$(date +%s%N)
printf 'middle_milliseconds=%s\n' "$(((end-start)/1000000))" > timing.txt
record final-verify verify.stdout.log verify.stderr.log "$OPT" final.mlir --verify-each -o final-verified.mlir
record repeat repeat/stdout.log repeat/passes.log "$OPT" input.mlir "${FLAGS[@]}" -o repeat/final.mlir
cmp final.mlir repeat/final.mlir
cmp passes.log repeat/passes.log
printf 'final.mlir: byte-identical\npasses.log: byte-identical (all before/after dumps)\n' > reproducibility.txt
awk -v out="$WORK" -f "$ROOT/extract-stages.awk" passes.log
cp input.mlir stages/00-input.mlir
printf 'stage\tpass\tbefore_log_start\tafter_log_start\tafter_log_end\tbefore_file\tafter_file\tdiff_file\n' > stages.tsv
previous_phase= previous_pass= previous_file= previous_start=
count=0
while IFS=$'\t' read -r serial phase pass first last file; do
  if [[ "$phase" == After && "$previous_phase" == Before && "$pass" == "$previous_pass" ]]; then
    if ! cmp -s "snapshots/$previous_file" "snapshots/$file"; then
      count=$((count+1))
      name=$(printf '%02d-%s' "$count" "$pass")
      cp "snapshots/$previous_file" "stages/$name-before.mlir"
      cp "snapshots/$file" "stages/$name-after.mlir"
      set +e
      diff -u --label "$pass:before" --label "$pass:after" \
        "snapshots/$previous_file" "snapshots/$file" > "diffs/$name.diff"
      diff_status=$?
      set -e
      test "$diff_status" = 1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$count" "$pass" "$previous_start" "$first" "$last" \
        "stages/$name-before.mlir" "stages/$name-after.mlir" "diffs/$name.diff" >> stages.tsv
    fi
  fi
  previous_phase=$phase previous_pass=$pass previous_file=$file previous_start=$first
done < <(tail -n +2 snapshots.tsv)
test "$count" -ge 2
sha256sum "$ROOT/add.mlir" > input-original-after.sha256
cmp input-original-before.sha256 input-original-after.sha256
sha256sum input.mlir final.mlir stages/*.mlir > artifacts.sha256
printf 'changed_stages=%s\n' "$count" > summary.txt
cat timing.txt summary.txt reproducibility.txt
