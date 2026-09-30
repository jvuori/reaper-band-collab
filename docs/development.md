# Development notes

How the tests run, and what to know before running REAPER unattended.

## Tests

- Plain Lua 5.4 (fast, no REAPER): `uv run tests/run.py`
- Inside REAPER's own Lua (needed for anything that uses the REAPER API, real directory listing, rendering):
  `tools/run_reaper_tests.sh <throwaway profile dir> <result file> [max seconds] ["test_file.lua ..."]`
  Tests that need REAPER are skipped in plain Lua and say so.
- Screens: `tools/ui_shots.sh <profile> <output dir>` draws every panel in a throwaway REAPER and saves a
  PNG of each window (only that process's own windows are captured).
- End to end over a real `scp` (loopback): `tools/scp_e2e.sh <profile> <work dir>`.

## The throwaway REAPER profile

Never test against your own REAPER profile. Make a separate one (`reaper -cfgfile <dir>/reaper.ini`) with
ReaImGui in `UserPlugins/`, and in `reaper.ini` under `[reaper]`:

```
linux_audio_mode=2        ; Dummy Audio. Without it a fresh profile tries JACK/ALSA and shows a modal
                          ; "Error opening devices" dialog at unpredictable moments.
```

## Rules that keep unattended runs from blocking on a dialog

- **Never modify a project tab that is not bound to its own file.** `Main_SaveProjectEx` saves a *copy* and
  leaves an untitled tab untitled (relative media then does not resolve) and a tab opened from another
  file bound to that file (Ctrl+S would overwrite it). Open the file first, then change and save with
  action 40026. See `lib/bandcollab/projects.lua`.
- **Quit through `safe_quit`** (see `tests/reaper_runner.lua`): quitting with a changed project open asks
  "save changes?" in a modal dialog.
- **Directory listings are cached per folder by REAPER**; `fs_std.list` flushes the cache with index `-1`.
- The watchdog in `tools/run_reaper_tests.sh` stops a REAPER whose window looks like a question or an error
  (and keeps a picture of it next to the result file); harmless progress windows are tolerated.
