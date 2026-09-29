# Spike 1.4: rendering stems from a script

Status: **Linux verified (REAPER 7.79). Windows verification pending** (task 1.7).

Scripts (`docs/spikes/scripts/`, all take `STEM_DIR`): `stem_render.lua` (levels and master-bus check), `stem_settings_probe.lua` (which `RENDER_SETTINGS` values give stems), `stem_folder.lua` (folder bus behaviour). Run each in a throwaway profile with `-nosplash -newinst`; they quit REAPER when done.

## What works

Rendering is driven entirely through the project's render settings, then action `42230` ("Render project, using the most recent render settings, auto-close render dialog"). No dialog appears and the call returns when the render is done.

| Setting | Value used |
|---|---|
| `GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)` | target directory |
| `GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)` | one file per track, named after the track |
| `GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAQ==", true)` | WAV, 24 bit (confirmed from the rendered header) |
| `GetSetProjectInfo(0, "RENDER_SRATE", 48000, true)`, `"RENDER_CHANNELS", 2` | 48 kHz stereo |
| `GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)` | entire project |
| `GetSetProjectInfo(0, "RENDER_SETTINGS", 3, true)` | **stems of the selected tracks, no master mix** |
| `GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)` | do not add the render back into the project |

`RENDER_SETTINGS` meanings found by brute force (`stem_settings_probe.lua`, values 0-47 plus a few larger):

| Value | Files produced (tracks A and B selected) |
|---|---|
| 0 | master mix only |
| 1 | master mix + one stem per selected track |
| **3** | **stems only** (the one we use) |
| 7 | stems only (with the "multichannel tracks" flag) |
| 32, 36, 64, 128 | stems only (see the next table for how they differ) |
| 2, 4, 8, ... others | master mix, or nothing |

Do **not** rely on the bit meanings from memory: `2` produced a master mix, not stems.

## What a stem contains

Test project: tone A (dry peak 0.5 = -6 dBFS) with fader -6 dB and pan hard left; tone B with a -6 dB FX and a -12 dB volume envelope; a -20 dB effect on the master bus.

| Render setting | Stem A (expected 0.25 on L, 0 on R) | Stem B (expected 0.0625) | Master bus effect |
|---|---|---|---|
| 3 and 32 | L 0.2500, R 0.0000 | 0.0625 both sides | **not applied** |
| 64 and 128 | L 0.0248, R 0.0000 | 0.0062 | applied (about -20 dB lower) |
| master mix (0) | | | applied (A+B through the master) |

So with value **3**, a stem includes track effects, fader, pan and volume automation, and excludes master-bus processing, exactly what design D5 requires. The master-mix render (value 0) supplies the reference mix. Pan is flat here (hard left gives 0.25 on L, no boost); this depends on the project pan law, so the publisher should copy the producer's pan law setting into what it renders.

## Folders: the finding that affects the design

`stem_folder.lua`: a folder track with -6 dB fader and -6 dB FX holding two tones of peak 0.5.

| Selected for render | Result |
|---|---|
| The two child tracks | `kid_a.wav`, `kid_b.wav`: peak **0.5 each**, so **the folder bus processing is not included** |
| The folder track | one `bus.wav`: peak **0.22**, both children summed through the bus (-12 dB) |

Consequence: if the producer processes a group through a folder bus (drum bus compression, a guitar bus EQ), **per-track stems do not sound like the mix**. Rendering the folder track gives what the producer hears from that group, including nested sub-busses.

## Other observations

- REAPER wrote a `peaks/` folder with `.reapeaks` files next to the test media. Those files are cache clutter that would sync between members. The install docs should advise storing peak caches in REAPER's alternate location (Preferences → Media → Peaks), and the folder check can flag stray `.reapeaks` files.
- Rendering the 2-second test projects was instantaneous; real-length songs must be timed in task 5.2.
- Tracks must be **selected** for stem rendering; the publisher selects them programmatically and must restore the producer's selection.

## Recommendation (needs a decision, see the open design question)

Render **one stem per role folder** (as the producer hears it), instead of one per track. Optionally also offer dry per-track stems for members who want to hear a single track.

## Still open

- Repeat on Windows.
- Time a full-length multitrack render.
