# Spike 1.2: automatic start of the guardian

Status: **Linux verified (REAPER 7.79). Windows verification pending** (task 1.7).

Script: `docs/spikes/scripts/guardian_probe__startup.lua` (copy it to `<resource path>/Scripts/__startup.lua` of a throwaway profile; set `SPIKE_OUT_DIR`, `SPIKE_PROJ_A`, `SPIKE_PROJ_B`).

## Findings

| Question | Result |
|---|---|
| Does REAPER run `Scripts/__startup.lua` at startup by itself? | **Yes.** It ran in a fresh profile with no SWS, no ReaPack and no configuration. The full `reaper.*` API is available in it. |
| Does a `reaper.defer` loop started there keep running? | **Yes.** The loop ran for the whole test (140 ticks) alongside normal REAPER operation. |
| Can it notice a project being opened? | **Yes.** Polling `reaper.EnumProjects(-1, "")` (active project handle and path) reports the change within one tick, for both a first open and opening another project. |
| Is there a native "startup action" in vanilla REAPER? | **No.** A search of every action name in the main section for "startup" finds only "Show startup splash screen". (The "global startup action" comes from the SWS extension, which we do not want as a dependency.) |
| Can ReaPack install `__startup.lua` itself? | **Not verified, and probably not.** ReaPack installs under `Scripts/<repository>/...`, while REAPER runs only `__startup.lua` in the `Scripts` root. To be confirmed in task 11.1. |

## Decision for the installer (feeds task 9.7)

Provide a ReaPack-installed script action, **"Enable band guardian"**, run once at install time. It:

1. Creates `Scripts/__startup.lua` if missing, or if it exists, **adds a clearly marked block** (`-- BEGIN bandcollab ... -- END bandcollab`) and leaves the user's own content untouched.
2. The block only loads the guardian from the ReaPack install path, so updates through ReaPack take effect without rewriting the startup file.
3. Has a matching "Disable band guardian" action that removes only its own block.

The fallback defined in design D12 stays: opening the panel runs the same check once.

## Verified end to end (Linux)

`tools/guardian_e2e.sh` installs the start-up block into a throwaway profile, restarts REAPER and checks, without
touching anything by hand, that (1) the guardian starts by itself (its heartbeat in `ExtState` appears within a fraction
of a second, no start-up error), (2) opening the master as a member makes the warning window appear, and (3) the event
is logged. It always removes the block afterwards. Lessons it taught, now built in:

- **ReaImGui discards a context that is not used for a while.** A guardian that creates its context at start-up and only
  draws when something happens crashed with `ImGui_Begin: expected a valid ImGui_Context`. The context is now made when
  needed and made again if it was discarded (`ImGui_ValidatePtr`).
- **An error inside a background loop must not reach a band member as a "ReaScript Error" window.** The loop is wrapped
  in `xpcall`; the error text goes to `ExtState bandcollab/guardian_error`, the loop carries on, and after five failures
  it stops quietly.
- **Auto-resizing windows with wrapped text shrink to a sliver**; the window gets a minimum width.

## Still open

- Repeat the probe on Windows, including with a pre-existing `__startup.lua`.
- Check tab switching with two open project tabs (only one tab existed in this run; the poll key includes the project handle, so a switch should register).
- Check that the guardian loop stays cheap when idle (a poll per defer tick should cost very little; measure in task 9.7).
