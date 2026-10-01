#!/usr/bin/env bash
# Runs the test suite inside a throwaway REAPER profile, with a watchdog. A modal dialog would block
# the run (and interrupt the person at the keyboard), so while REAPER runs its windows are watched:
#   - a window whose title looks like a question or an error (REAPER Query, Error..., Save...,
#     Warning...) stops that REAPER process at once, and its picture is kept next to the result file;
#   - any other extra window (progress windows such as "Building Peaks...") is tolerated for up to
#     20 seconds, because those close by themselves.
# Only REAPER processes started with this profile are ever touched.
# Usage: tools/run_reaper_tests.sh <profile dir> <result file> [max seconds] [test files (quoted)]
set -uo pipefail
PROFILE="$1"; OUT="$2"; MAX="${3:-180}"; FILES="${4:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOLERATE=20
rm -f "$OUT" "$OUT.dialog.png"
BANDCOLLAB_ROOT="$ROOT" TEST_OUT="$OUT" TEST_FILES="$FILES" \
  reaper -cfgfile "$PROFILE/reaper.ini" -nosplash -newinst "$ROOT/tests/reaper_runner.lua" >/dev/null 2>&1 &
sleep 1

mine() { for pid in $(pgrep -x reaper); do tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- "$PROFILE/reaper.ini" && echo "$pid"; done; }
stop_all() { for p in $(mine); do kill "$p" 2>/dev/null; done; }
# extra windows of one process: id<TAB>title, leaving out REAPER's own main windows and start-up windows
extras() {
  wmctrl -lp 2>/dev/null | awk -v pid="$1" '$3==pid { id=$1; $1=$2=$3=$4=""; sub(/^ +/, ""); if ($0 !~ /REAPER v[0-9]/ && $0 !~ /\(loading\)/) print id "\t" $0 }'
}

declare -A first_seen
start=$(date +%s)
while [ $(( $(date +%s) - start )) -lt "$MAX" ]; do
  [ -f "$OUT" ] && break
  pids="$(mine)"
  [ -z "$pids" ] && break                          # REAPER has exited
  now=$(date +%s)
  declare -A present=()
  for pid in $pids; do
    while IFS=$'\t' read -r id title; do
      [ -z "$title" ] && continue
      blocking=0
      [[ "$title" =~ ^(REAPER\ Query|Error|Save|Warning|Missing|Confirm) ]] && blocking=1
      key="$pid|$title"
      present[$key]=1
      [ -z "${first_seen[$key]:-}" ] && first_seen[$key]=$now
      if [ "$blocking" = 1 ] || [ $(( now - first_seen[$key] )) -gt "$TOLERATE" ]; then
        import -window "$id" "$OUT.dialog.png" 2>/dev/null
        echo "STOPPED: REAPER opened a window that needs a person: $title"
        stop_all
        exit 3
      fi
    done < <(extras "$pid")
  done
  # a window that has closed starts a fresh clock the next time it appears (each render shows one)
  for key in "${!first_seen[@]}"; do [ -z "${present[$key]:-}" ] && unset "first_seen[$key]"; done
  sleep 0.5
done
if [ ! -f "$OUT" ]; then
  echo "NO RESULT (REAPER exited or timed out)"; stop_all; exit 2
fi
# the result is in: REAPER should quit by itself; give it a few seconds, then make sure none is left behind
for _ in $(seq 1 10); do [ -z "$(mine)" ] && break; sleep 0.5; done
stop_all
cat "$OUT"
