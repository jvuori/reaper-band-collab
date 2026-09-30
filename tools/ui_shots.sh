#!/usr/bin/env bash
# Renders every UI screen in a throwaway REAPER profile and saves a PNG of each window.
# Only windows owned by that REAPER process are captured, never the whole desktop.
# Usage: tools/ui_shots.sh <profile dir with reaper.ini and ReaImGui installed> <output dir>
set -euo pipefail
PROFILE="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"; rm -f "$OUT"/ready_* "$OUT"/ack_* "$OUT"/finished "$OUT"/errors.txt "$OUT"/scenarios.txt
BANDCOLLAB_ROOT="$ROOT" SHOT_DIR="$OUT" reaper -cfgfile "$PROFILE/reaper.ini" -nosplash -newinst "$ROOT/tools/ui_shots.lua" >/dev/null 2>&1 &
for _ in $(seq 1 100); do [ -f "$OUT/scenarios.txt" ] && break; sleep 0.2; done
mapfile -t NAMES < "$OUT/scenarios.txt"
for name in "${NAMES[@]}"; do
  for _ in $(seq 1 150); do [ -f "$OUT/ready_$name" ] && break; sleep 0.2; done
  title="$(head -n1 "$OUT/ready_$name")"
  pids="$(pgrep -f "$PROFILE/reaper.ini" | tr '\n' ' ')"
  wid=""
  for pid in $pids; do
    wid="$(wmctrl -lp | awk -v pid="$pid" -v t="$title" '$3==pid { $1=$1; if (index($0, t)) print $1 }' | head -n1)"
    [ -n "$wid" ] && break
  done
  if [ -n "$wid" ]; then import -window "$wid" "$OUT/$name.png" && echo "captured $name ($title)"; else echo "NO WINDOW for $name ($title)"; fi
  touch "$OUT/ack_$name"
done
for _ in $(seq 1 100); do [ -f "$OUT/finished" ] && break; sleep 0.2; done
cat "$OUT/errors.txt"
