# Spike 1.1: locking APIs

Status: **Linux verified (REAPER 7.79, Lua 5.4). Windows verification pending** (needs the Windows test machine, task 1.7).

Scripts: `docs/spikes/scripts/spike_lock.lua`, `spike_lock2.lua`. Run in a throwaway profile:

```
SPIKE_OUT_DIR=/some/dir reaper -cfgfile /some/dir/profile/reaper.ini -nosplash -newinst docs/spikes/scripts/spike_lock2.lua
```

## Findings

| Need | Mechanism | Result |
|---|---|---|
| Lock an item | `SetMediaItemInfo_Value(item, "C_LOCK", 1)` | Works; read back as `1`; item chunk gains a `LOCK 1` line |
| Lock all items on tracks | Action `43696` "Item: Lock all items on selected tracks" | Works; sets `C_LOCK` on every item of the selected tracks |
| Lock track controls | Actions `41312` lock / `41313` unlock / `41314` toggle, acting on **selected** tracks | Works; adds exactly one line `LOCK 1` to the track chunk, unlock restores the original chunk byte for byte |
| Persist a locked track | Track chunk line `LOCK 1` via `SetTrackStateChunk` | Round trip keeps the lock, so a workspace can be built by writing chunks |
| Collapse a stem folder | `I_FOLDERDEPTH` (1 parent, -1 last child) and `I_FOLDERCOMPACT = 2` | Works |
| Hide tracks | `B_SHOWINTCP = 0`, `B_SHOWINMIXER = 0` | Works |
| Hidden ownership markers | `GetSetMediaTrackInfo_String(track, "P_EXT:<key>", value, true)` | Round trip works (used by task 3.1) |
| Lock-related actions in general | 58 actions found with "lock" in the name (excluding clock/block) (locking modes, lock settings, item lock, lock track height) | Enumerated by the script |

## Important limits

- **Scripts bypass locks.** Setting a volume on a locked track through the API succeeds. So our own fetch and import can update locked stems without unlocking, which is what we want, and it confirms locks are only a guardrail for people using the UI (design D11).
- **UI enforcement is not verifiable from a script.** That a locked item cannot be dragged, and that locked track controls refuse volume/pan edits, needs a hand test in the UI. That check belongs to task 6.2 and is done by hand on Windows and Linux.
- Track-level locking exists (the design already treated it as optional), so D11 keeps: item locks + track lock + collapse + hide.
- Plugin APIs (ReaImGui, ReaPack, SWS, js_ReaScriptAPI) are absent in a vanilla profile, as expected (`APIExists` returns false). Nothing here depends on SWS or js_ReaScriptAPI.

## Recommendation for the workspace builder (task 6.2)

1. Build stems as tracks in one folder, `I_FOLDERCOMPACT = 2`.
2. Select those tracks, run action `43696` (items) and `41312` (track controls).
3. Write the member's own folder normally (unlocked).
4. Hand-verify in the UI that dragging a stem item and changing its fader behave as expected on both OSes.

## Still open

- Repeat both scripts on Windows.
