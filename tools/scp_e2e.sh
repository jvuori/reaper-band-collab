#!/usr/bin/env bash
# End-to-end check of receiving a rehearsal that travelled through a real scp (loopback), with an
# interrupted transfer first. Usage: tools/scp_e2e.sh <REAPER profile dir> <work dir>
set -euo pipefail
PROFILE="$1"; WORK="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$WORK"; mkdir -p "$WORK/laptop/rehearsal" "$WORK/desktop"
# a rehearsal with three songs; the second has a big recording so a transfer can be interrupted
uv run --project "$ROOT" python - "$WORK/laptop/rehearsal" <<'PY'
import struct, sys, os
root = sys.argv[1]
def wav(path, seconds):
    n = 48000 * 4 * seconds  # 16-bit stereo
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 2, 48000, 192000, 4, 16) + b"data" + struct.pack("<I", n))
        block = bytes(range(256)) * 4096
        left = n
        while left > 0:
            f.write(block[:min(left, len(block))]); left -= len(block)
def project(path, media):
    with open(path, "w") as f:
        f.write('<REAPER_PROJECT 0.1 "7.0" 0\n  <ITEM\n    <SOURCE WAVE\n      FILE "media/%s"\n    >\n  >\n>\n' % media)
for name, secs in [("aaa-first", 5), ("bbb-second", 90), ("ccc-third", 5)]:
    d = os.path.join(root, name)
    wav(os.path.join(d, "media", name + ".wav"), secs)
    project(os.path.join(d, name + ".rpp"), name + ".wav")
PY
du -sh "$WORK/laptop/rehearsal" | cut -f1 | sed 's/^/rehearsal size: /'
run_reaper() { # phase, output
  BANDCOLLAB_ROOT="$ROOT" PHASE="$1" INCOMING="$WORK/desktop/incoming" BAND_FOLDER="$WORK/band" OUT="$2" \
    timeout 120 reaper -cfgfile "$PROFILE/reaper.ini" -nosplash -newinst "$ROOT/tools/scp_receive_check.lua" >/dev/null 2>&1
  cat "$2"
}
SSH="-o BatchMode=yes -o ConnectTimeout=5"
echo "== 1. scp interrupted after 3 seconds (limited to 1 MB/s so it cannot finish)"
mkdir -p "$WORK/desktop/incoming"
timeout 3 scp $SSH -q -r -l 8000 "$WORK/laptop/rehearsal/." "localhost:$WORK/desktop/incoming/" || echo "(scp interrupted, exit $?)"
echo "-- bytes of the big recording that arrived: $(stat -c %s "$WORK/desktop/incoming/bbb-second/media/bbb-second.wav" 2>/dev/null || echo 0) of $(stat -c %s "$WORK/laptop/rehearsal/bbb-second/media/bbb-second.wav")"
run_reaper 1 "$WORK/phase1.txt"
echo "== 2. scp run again, this time to the end"
scp $SSH -q -r "$WORK/laptop/rehearsal/." "localhost:$WORK/desktop/incoming/"
run_reaper 2 "$WORK/phase2.txt"
echo "== 3. are the received files identical to what the laptop had?"
for name in aaa-first bbb-second ccc-third; do
  src="$WORK/laptop/rehearsal/$name/media/$name.wav"
  dst="$(find "$WORK/band/producer" -name "$name.wav" | head -n1)"
  if [ -n "$dst" ] && [ "$(sha256sum < "$src")" = "$(sha256sum < "$dst")" ]; then echo "identical: $name"; else echo "DIFFERENT OR MISSING: $name"; fi
done
echo "== 4. registry"
grep -c '"id"' "$WORK/band/producer/registry.json" | sed 's/^/songs in registry: /'
