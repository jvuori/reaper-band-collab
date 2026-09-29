## Context

See `proposal.md` for motivation and scope. Constraints that shape the approach:

- Members are Finnish-speaking and use **Windows**; their experience with audio software and file management varies, so no such background is assumed. The producer uses **Windows and Linux** (Linux becoming primary). At least one member works offline, so the tool must not require an internet connection on their machine.
- Collaboration happens through a shared folder synced by an arbitrary provider (Google Drive for this band). The extension must not depend on the provider. Sync services deliver files in arbitrary order, may expose not-yet-downloaded placeholders, and may create conflict copies.
- Rehearsals are recorded on an offline Linux laptop running plain REAPER. Material reaches the producer's desktop by SCP. Collaboration starts only after that.
- REAPER project files (`.RPP`) are text; tracks have stable GUIDs; ReaScript can read/write project state, render, and show ReaImGui windows. REAPER has no read-only project mode and no way to intercept Save.
- No existing code or specs. Greenfield.

## Goals / Non-Goals

**Goals:**
- A member can do everything they need through one panel, without seeing files, paths or technical terms, and without any way to affect the master unintentionally.
- The master project is written only by the producer's tool on the producer's machine.
- Every hand-off (SCP, sync, USB) is verifiable: partial or corrupt content is detected and refused.
- Band structure is data (template + `band.json`) so other bands can use the extension unchanged.

**Non-Goals:**
- Preventing a determined user from unlocking or editing things (locks are speed bumps, not security).
- Any sync/transport logic, cloud APIs or permission management.
- Git/LFS integration, promotion to official recording, macOS, merging concurrent edits of the same tracks, real-time collaboration.
- Fixing timing differences caused by structural changes to the master after members recorded (only detecting and warning).

## Decisions

### D1. Lua ReaScript + ReaImGui, distributed with ReaPack
Lua ships inside REAPER (no interpreter to install), behaves identically on Windows and Linux, and needs no external programs. ReaImGui gives a real panel; ReaPack gives one-URL install and automatic updates.
*Alternatives:* C++ REAPER extension (per-platform builds and signing, much heavier); Python ReaScript (requires a Python install on every member machine); a standalone app (cannot see or safely modify project state).

### D2. Band structure lives in a template, identity is by track GUID
The project template contains one **folder track per member/role**, carrying hidden markers (role id, owner slot) stored in track extended state. `band.json` maps members to roles and holds language, labels and locations. **Nothing in the extension is specific to one band**: the code uses the neutral namespace `bandcollab`, and band, member, song and folder names exist only in `band.json`, the template and the band folder (example names appear in documentation and tests only). A new song created from the template inherits the structure. Track and folder **names are display labels only**.
*Alternatives:* naming conventions (people rename and mistype), color coding (too easy to change), a global config listing track names (drifts from the projects).

### D3. "Everything inside your folder is yours" is the ownership rule
A member may add, rename, delete and reorganize tracks inside their folder freely. A proposal replaces the member's whole folder(s) in the master. Tracks created outside the folder are caught by the pre-send check ("orphans") and the member is offered to move them in. A member can own several folders. Import takes **only** owned folders from a proposal; everything else in it (stems, tempo, master FX, other folders) is ignored, which means unexpected changes elsewhere in a delivery have no effect.
*Alternative:* item- or track-level merge with conflict resolution: far more complex and unnecessary while each track has one owner.

### D4. Single-writer, immutable, area-based layout
Content is split into three logical areas, configured in `band.json`: **master** (producer only), **publications** (written by the producer, read by members), **proposals** (each member writes only their own subfolder). Files are never rewritten after completion; a new version gets a new name. Recommended provider permissions (view-only publications, per-member write) are documented, not relied on.
This makes conflict copies impossible in normal use and keeps behavior independent of the sync provider.
*Alternative:* members opening a shared live master with locking: unsafe with cloud sync, and too risky for a workflow shared by people with varied tooling experience.

### D5. Publications are numbered snapshots of the master with true-bounce stems
"Julkaise" creates revision `rN` containing: **one stem per role folder** outside the recipient's own folders, rendered as the sum of everything in that folder (nested folders included), **post-FX and including fader, pan, automation and the folder's own bus processing** (what the producer hears from that group) but **excluding master-bus processing**; a stereo reference mix **with** master-bus processing for listening; the tempo map and song length; each member's own-folder media; a manifest. Members' stems start at 0 dB, so they can rebalance groups against each other but need no plugins. Rendering uses REAPER's stem render of the selected role folder tracks with no master bus (measured in `docs/spikes/stems.md`: settings value 3 includes track and folder processing and excludes the master bus). **Why per folder and not per track:** the spike showed that a child track rendered on its own does not include its folder's bus processing, so per-track stems would not sound like the mix; rendering the folder track does. Members therefore balance whole groups (for example drums against bass), not single tracks inside another member's folder.
*Alternatives:* live copies of tracks with plugins (missing plugins would break sessions); REAPER "freeze" (keeps the FX chain and needs the plugins to unfreeze); a single stereo guide (members could not balance).

### D6. Completeness is proven by manifest, checksums and a last-written `valmis` marker
Every publication and proposal contains a manifest listing each file with size and checksum and a `valmis` marker written last. Any consumer (member syncing down, producer importing, producer receiving a rehearsal over SCP) verifies before use and refuses incomplete content with a plain message ("Tiedostot ovat vielä latautumassa"). Placeholder/on-demand files are detected by missing or mismatching content. The same mechanism serves every transport, including the removable-media route for members working offline.
*Alternative:* trusting the sync client's status: not observable and provider-specific.

### D7. Member workspace is separate from what is delivered
A member works in `work/` (messy, synced at will, never consumed by anyone). "Ehdota" makes a **frozen, timestamped delivery** in their proposals area after a preflight (media all present and consolidated into the pack, timing matches the base, folder non-empty, no orphans, base revision noted). A newer delivery supersedes older ones; older ones are kept. The producer only ever imports a delivery.
A member working offline uses identical screens; their "band folder" is a local folder carried on removable media.

### D8. Producer import is preview → explicit accept → backup → undo
"Ota ehdotus pääversioon" shows what will be replaced (folders, track counts, length, tempo comparison, the member's note, base revision vs. current) and any warnings, then requires confirmation. Before writing, the tool saves a timestamped backup of the master. The tool replaces only the proposer's owned folders, then records the event in the change log. "Kumoa" restores the backup. Only the producer's tool writes the master.
*Alternative:* in-project archive folders of old versions: clutters the master.

### D9. One "Synkronoi" entry with guided, never-automatic direction
The panel has one **Synkronoi** button. It inspects state and shows only sensible choices with the recommended one preselected: **Hae pääversio** (down) and **Ehdota pääversioon** (up). If both apply, it presents a two-step flow, down first. The direction is never chosen silently, and the wording preserves the asymmetry: down is immediate, local and undoable; up changes nothing until the producer accepts. Before every "Hae", the member's own folders are backed up; "Palauta edellinen tila" undoes it. Pull warns when the tempo map, length or structure changed since the member's base.
*Alternative:* two separate buttons with technical names: more to learn and more room for choosing wrongly.

### D10. Vocabulary is fixed and inflection-safe
Finnish terms: **pääversio** (master), **oma työtila** (isolated project), **ehdotus** (merge request), **julkaisu rN** (snapshot), **toimitus** (a frozen delivery). "Virallinen" is reserved for official recording projects. The producer-role label is configurable; because Finnish inflects, sentences avoid embedding it, and where unavoidable `band.json` stores the needed forms.

### D11. Locking is layered soft protection
The workspace locks stem material with REAPER item locking, locks or hides track controls where the API allows, and collapses the stem folder. Real safety comes from D3 (owned-only import), D4 (single writer) and the guardian (D12). The exact locking calls are confirmed in an early spike; the design does not depend on track-level lock existing.

### D12. Guardian watches managed projects only, and can only warn
A background script (started with REAPER if a startup hook is available) recognizes a **managed** project by its manifest and role: master, workspace, publication, archive. It warns once per open for: a member opening the master; a workspace belonging to someone else; a workspace of a closed cycle; a workspace based on an outdated master (soft); a workspace that has been moved or copied out of the band folder. Unmanaged projects are never touched. The master also carries passive protection that works without the extension: a visible marker/region at the start and a distinct file name. It cannot block Save; its strongest action is offering to close the project and logging the event.

### D13. Song identity is a registry ID, not a path
Each song gets an ID on first receipt ("Ota harjoitus vastaan"). The registry sits in the band folder. A project arriving with an already-registered ID at a different location (for example a manual copy into an official library) prompts "Onko tämä kopio?" and, on yes, assigns a fresh ID and records the origin. First arrival after SCP registers silently, so a legitimate move is never flagged. Receiving accepts any folder containing `.rpp` files, so the capture laptop needs no extension and no naming discipline.

### D14. Rehearsals are dated cycles that can be closed
A **library** is a root folder (rehearsals; official recordings) with identical structure. Within the rehearsal library, a dated cycle groups that week's songs. Closing a cycle makes it read-only for workflow purposes: new proposals are refused, the archive stays available for listening. Multiple songs per rehearsal are supported in one "Uusi/Vastaanota harjoitus" step.

### D15. Change log is single-writer Markdown built from notes
`MUUTOSLOKI.md` per song is written only by the producer's tool at publish and at import. Entries are newest-first with a header carrying revision, **date and time** (local time; ISO with offset in metadata), event type and actor. Entries hold the member's/producer's note, generated facts (tracks replaced, tempo/length change, structure warning), a `HUOM` line only when other members are affected, and an optional "Tehtävää" (requests). A proposal has two timestamps: sent and imported. The note has a first line (summary) and optional body, so a future git module can reuse it as a commit message unchanged. The panel shows entries newer than the member's base revision.

### D16. Cross-platform hygiene for a Linux/Windows producer
Internal file and folder names are **lowercase ASCII slugs**, unique case-insensitively, never Windows-reserved or containing forbidden characters; the display name is in the manifest. Paths are joined with REAPER's separator; internal paths stay short (Windows 260-character limit). The tool creates and moves all folders itself, so members never do.

### D17. Data, state and format
- `manifest.json` next to each project/pack/publication, with a `schema` version field; a small pure-Lua JSON codec (no dependencies).
- `band.json` and the song registry in the band folder (synced to everyone).
- Machine-local state (who the member is, the band folder location) in REAPER's extended state, set once by a first-run step ("Kuka sinä olet?", "Missä bändikansio on?").
- Localization via key-based string tables, `fi` default, `en` included from the start.

### D18. Documentation is a first-class, bilingual, repo-hosted deliverable
Docs are Markdown in the repository so GitHub renders them for band members: a root `README.md` (short pitch, language links) plus parallel trees `docs/fi/` and `docs/en/` with identical file names and heading structure. Content is organized by reader, not by feature: **personas** (producer, member, member working offline) → **use cases** (step-by-step, exact button names) → **operations reference** (what each operation changes, never changes, and how to undo) → **installation into vanilla REAPER** (Windows primary, Linux for the producer, offline bundle route) → **shared-folder setup** → **troubleshooting** → **glossary**. Finnish is the primary text for members; English serves other bands.
Screenshots are taken from the real extension, one set per language (the UI is localized, so a shared set would mislead), stored under `docs/images/<lang>/` and referenced by relative paths so GitHub renders them. A maintained screenshot list (what each shows, which state to set up, which OS) makes retaking them repeatable when the UI changes. Installation screenshots come from a clean Windows profile because that is what members will see.
A docs check in the test harness enforces: identical file and heading sets across languages, all relative links and images resolve, images have alt text, and member documents contain none of the forbidden terms from D10.
*Alternatives:* a wiki or Google Doc (drifts from the code, cannot be checked in CI, not versioned with releases); one shared screenshot set (wrong language); English-first docs translated later (members are the primary readers and read Finnish); a docs site generator (unnecessary for the size; GitHub rendering is enough for now).

## Risks / Trade-offs

- **Documentation and screenshots go stale as the UI evolves, or the two languages drift** → docs check in the harness, maintained screenshot list, and a release checklist that requires re-verifying docs and screenshots.
- **Install docs are validated only if actually followed** → written from a real clean-profile install and tried unassisted by a member with no audio-software background before release.

- **Members can unlock or edit locked material or the master** → owned-only import (D3), guardian warnings (D12), passive markers, and documented view-only permissions.
- **Guardian only works if it starts with REAPER** → it is installed as part of a guided first install; a startup-hook spike confirms the mechanism on both platforms; fallback is a panel that also runs the check when opened.
- **Structural change to the master after members recorded** (tempo, inserted bars) desynchronizes their tracks → detected and warned (D9); mitigated by convention: lock structure once recording begins.
- **Stems cost disk and render time; large multitrack audio is heavy for sync** → only stems and the member's own media are published, not raw audio of others; master and raw audio stay producer-side.
- **On-demand/streaming sync modes hide files** → D6 detects them; documentation recommends "keep on device".
- **Producer moving to Linux may lack an official client for the chosen sync provider** → outside the extension's scope; D4/D6 make third-party sync tools safe to use; to be settled before migration.
- **First install** (ReaPack + ReaImGui + startup hook) is the largest friction point for everyone → a screenshot guide is written, the producer offers to walk through it once, and members working offline receive an installer bundle on removable media.
- **Only tested on the developer's Linux at first** but members run Windows → a Windows test machine/VM is required before the first member uses a release.
- **Finnish inflection of configurable role labels** → avoid embedding role labels in sentences; store forms where needed (D10).
- **Same-name and near-duplicate songs across libraries** → registry IDs and the copy prompt (D13).

## Migration Plan

This is a new tool, so there is nothing to migrate. Rollout, in order:

1. Producer installs and runs the extension on the desktop; creates the band definition and template, and registers an existing rehearsal.
2. One volunteer member installs with guidance and completes one full loop (workspace → send → import) on a low-stakes song.
3. Remaining members join. Members working offline are onboarded through the removable-media route.
4. Linux migration of the producer's desktop happens independently; the extension must work on both.

Rollback: nothing outside the band folder is modified; the master is backed up before every import; uninstalling means removing the ReaPack repo, and the master remains a normal REAPER project.

## Open Questions

- Exact ReaScript API for track-level locking and the best way to lock stems (spike; D11 does not depend on the outcome).
- Whether a startup hook runs automatically on both platforms and how it is installed (spike; a fallback is defined in D12).
- Exact stem naming and rendering options (sample rate/bit depth policy, dither) once we measure real project sizes.
- Hash algorithm and file size limits for checksumming large media in pure Lua (performance measurement).
