## Why

A band records in several home studios, but the recording project lives in one place and is owned by one person (the producer). Today, collaboration means passing around whole projects or exported audio, which either risks breaking the master project or shuts members out of the recording process. Members are musicians first: the tool must work for people with very different amounts of experience with audio software and file management, and for members who work without a permanent internet connection.

We want a REAPER extension that lets each member work freely on their own instrument in an isolated workspace (re-record, correct timing, add effects), hear the rest of the band as it currently sounds, and propose the result back, while the master project stays under the producer's sole control.

## What Changes

- New REAPER extension (ReaScript/Lua + ReaImGui, distributed via ReaPack), usable by any band, not only ours. Band-specific structure is data, not code.
- **Band definition**: a project template whose folder tracks carry hidden role/owner markers, plus a small `band.json` (members, roles, language, role labels, locations).
- **Song registration**: "receive rehearsal" registers songs recorded on a separate capture machine, verifies completeness, assigns song IDs, and detects copied projects.
- **Publishing**: the producer publishes numbered snapshots of the master (`pääversio`) containing one stem per member folder, rendered as the producer hears it (folder bus processing included), so members need no plugins.
- **Member workspace**: a member creates an isolated project containing their own folder(s) editable and everyone else's stems locked. One guided "Synkronoi" flow fetches the latest master (down) and sends a proposal (up).
- **Proposal import**: the producer previews and explicitly accepts a proposal. Only the member's owned folder(s) are taken; a backup and undo are always available.
- **Change log**: a human-readable `MUUTOSLOKI.md` per song, written only by the producer's tool, built from the members' notes and generated facts, with date and time.
- **Project guardian**: warns when a member opens the wrong managed project (master, someone else's workspace, closed cycle, stale, misplaced) and checks the health of the directory structure. It stays silent for unmanaged projects.
- **Localization**: Finnish UI by default, English available; all text from string tables.
- **User documentation** in Finnish and English, written in Markdown with screenshots and rendered by GitHub: personas, main use cases, operations, and installation into a vanilla REAPER. The repository is pushed to GitHub and the docs are what band members read to install and understand the tool, so the docs are a deliverable, not an afterthought.
- **Storage-agnostic**: the extension only sees folders. Google Drive, OneDrive, Syncthing or a USB stick are equivalent. Completeness of synced content is verified by manifests, checksums and a `valmis` marker written last.
- Non-goals for now: git/LFS integration, promotion of a rehearsal song to an official recording project (done manually), macOS support, real-time collaboration, merging edits from two people into the same tracks.

## Capabilities

### New Capabilities

- `band-definition`: band template with role/owner markers, `band.json`, member identity ("Kuka sinä olet?"), configurable role labels.
- `song-registration`: receiving rehearsals from a capture machine, verifying completeness, song ID registry, copy detection, libraries (rehearsal vs. official) and closable cycles.
- `master-publishing`: numbered master snapshots with stems, manifests, checksums and completeness markers.
- `member-workspace`: creating isolated per-instrument workspaces, locking foreign material, fetching the latest master, sending proposals through the guided Synkronoi flow, and undo.
- `proposal-import`: producer-side preview, acceptance, backup and undo of proposals, restricted to the proposer's owned folders.
- `change-log`: `MUUTOSLOKI.md` content, authorship, timestamps and per-member relevance.
- `project-guardian`: warnings for wrong or misplaced managed projects, and the directory structure health check.
- `localization`: Finnish and English UI, string tables, inflection-safe role labels.
- `user-documentation`: bilingual (Finnish/English) Markdown documentation with screenshots covering personas, use cases, operations, installation into vanilla REAPER, troubleshooting, and consistency between languages and with the UI.

### Modified Capabilities

<!-- None: this is a new project with no existing specs. -->

## Impact

- New code only: a Lua/ReaImGui package with a ReaPack index. No existing code is changed.
- Runtime dependencies for users: REAPER, ReaPack, ReaImGui (all installed once per machine, with the producer guiding the first install). No external programs are required for members.
- Target platforms: Windows (all members, the producer) and Linux (the producer, soon to be the main machine). The capture laptop runs plain REAPER on Linux with the project template only.
- Documentation lives in the same repository (`README.md` plus `docs/fi` and `docs/en`, with screenshots), is read on GitHub by band members, and must be kept in step with the UI.
- Shared-folder conventions (recommended, not enforced by the tool): top-level areas for producer-only masters, view-only publications, and per-member proposal folders.
- Open items to resolve during design/spikes: exact ReaScript locking APIs, whether a startup hook can run automatically on both platforms, and Linux-side sync tooling for the producer.
