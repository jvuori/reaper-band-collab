#!/usr/bin/env bash
# End to end: install the start-up block, restart REAPER (a throwaway profile), and check that the
# guardian runs by itself and warns when a member opens the master. Always removes the start-up block.
# Usage: tools/guardian_e2e.sh <profile dir> <work dir>
set -uo pipefail
PROFILE="$1"; WORK="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STARTUP="$PROFILE/Scripts/__startup.lua"
rm -rf "$WORK"; mkdir -p "$WORK" "$PROFILE/Scripts"
cleanup() { rm -f "$STARTUP"; for p in $(pgrep -x reaper); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "$PROFILE/reaper.ini" && kill "$p" 2>/dev/null; done; }
trap cleanup EXIT
[ -e "$STARTUP" ] && { echo "refusing to run: $STARTUP already exists (it is not ours to remove)"; exit 2; }

mine() { for p in $(pgrep -x reaper); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "$PROFILE/reaper.ini" && echo "$p"; done; }

echo "== 1. set the profile up as member eero, with a band folder and a master"
BANDCOLLAB_ROOT="$ROOT" E2E_BAND="$WORK/band" timeout 60 reaper -cfgfile "$PROFILE/reaper.ini" -nosplash -newinst "$ROOT/tools/guardian_e2e_setup.lua" >/dev/null 2>&1
[ -f "$WORK/band/band.json" ] || { echo "setup failed"; exit 1; }

echo "== 2. install the start-up block"
uv run --project "$ROOT" python - "$ROOT" "$STARTUP" <<'PY'
import sys
from lupa.lua54 import LuaRuntime
root, startup = sys.argv[1], sys.argv[2]
lua = LuaRuntime()
lua.execute(f'package.path = "{root}/lib/?.lua;" .. package.path')
installer = lua.eval('(require("bandcollab.guardian_install"))')
fs = lua.eval('(require("bandcollab.fs_std"))')
print("enabled:", installer.enable(fs, startup, root + "/ui/guardian_watch.lua"))
PY
grep -c "BEGIN bandcollab" "$STARTUP" | sed 's/^/blocks in __startup.lua: /'

echo "== 3. restart REAPER; the guardian must start by itself"
BANDCOLLAB_ROOT="$ROOT" E2E_MASTER="$WORK/band/tuottaja/harjoitukset/2026-09-29/biisi/PAAVERSIO_biisi.rpp" E2E_DIR="$WORK" \
  reaper -cfgfile "$PROFILE/reaper.ini" -nosplash -newinst "$ROOT/tools/guardian_e2e_run.lua" >/dev/null 2>&1 &
for _ in $(seq 1 120); do [ -f "$WORK/opened" ] && break; sleep 0.5; done
[ -f "$WORK/opened" ] && echo "the guardian started on its own; the master was then opened as eero" || echo "NO HEARTBEAT: the guardian did not start"

echo "== 4. the warning must appear"
found=""
for _ in $(seq 1 40); do
  for pid in $(mine); do
    id="$(wmctrl -lp 2>/dev/null | awk -v pid="$pid" '$3==pid && /Band Collab: tarkistus/ { print $1; exit }')"
    [ -n "$id" ] && { sleep 1.5; import -window "$id" "$WORK/warning.png" 2>/dev/null; found=yes; break; }
  done
  [ -n "$found" ] && break
  sleep 0.5
done
if [ -n "$found" ]; then echo "WARNING SHOWN (picture: $WORK/warning.png)"; else
  echo "NO WARNING WINDOW. Windows of REAPER right now:"
  for pid in $(mine); do
    eid="$(wmctrl -lp 2>/dev/null | awk -v pid="$pid" '$3==pid && /ReaScript Error/ { print $1; exit }')"
    [ -n "$eid" ] && import -window "$eid" "$WORK/script-error.png" 2>/dev/null
  done
  for pid in $(mine); do wmctrl -lp 2>/dev/null | awk -v pid="$pid" '$3==pid { $1=$2=$3=$4=""; print "   -" $0 }'; done
fi
touch "$WORK/stop"
for _ in $(seq 1 20); do [ -z "$(mine)" ] && break; sleep 0.5; done
cat "$WORK/result.txt" 2>/dev/null
echo "== 5. the event was logged"
grep -c '"code":"master"' "$WORK/band/ehdotukset/eero/guardian.log" 2>/dev/null | sed 's/^/log lines about the master: /'
