## 1. Spikes and project setup

- [ ] 1.1 Spike: determine the REAPER API/actions for item locking and track-level locking (or hiding) on Windows and Linux; record findings in a `docs/spikes/locking.md` and verify each finding with a small script run in REAPER
- [ ] 1.2 Spike: verify whether a script runs automatically at REAPER startup on Windows and Linux and how ReaPack can install it; record the result and the fallback in `docs/spikes/startup-hook.md`, verified by restarting REAPER on both OSes
- [x] 1.3 Spike: measure checksum speed in pure Lua on a multi-hundred-MB WAV and choose the algorithm and size policy; record numbers in `docs/spikes/checksum.md`
- [ ] 1.4 Spike: render a stem of a single track post-FX with fader/pan/automation and no master bus via script, on both OSes; record the settings that work in `docs/spikes/stems.md`
- [x] 1.5 Create the repository layout (`lib/`, `ui/`, `strings/`, `tests/`, ReaPack index skeleton) and verify a hello-world ReaImGui window opens from a ReaPack-style install on a clean REAPER profile
- [x] 1.6 Set up a test harness for the pure-logic modules that runs outside REAPER, and verify a sample test passes and fails correctly
- [ ] 1.7 Prepare a Windows test machine or VM with REAPER, ReaPack and ReaImGui, and verify the hello-world window opens there

## 2. Foundations

- [x] 2.1 Implement a dependency-free JSON encode/decode module and verify unit tests cover nesting, unicode (ä, ö, å), escapes and malformed input
- [x] 2.2 Implement safe-name slug generation (lowercase ASCII, Windows-reserved words, forbidden characters, case-insensitive uniqueness, short paths) and verify unit tests including "Yö: kuka? Minä" and `con`
- [x] 2.3 Implement path helpers that use REAPER's separator and verify tests run with both separator styles
- [x] 2.4 Implement the manifest format (file list, sizes, checksums, schema version, completion marker written last) with a writer and a verifier, and verify tests detect missing marker, missing file, size mismatch and checksum mismatch
- [x] 2.5 Implement the string-table loader with `fi` default, `en` fallback for missing keys, and verify tests for fallback and key lookup
- [x] 2.6 Implement the band folder reader/writer for `band.json` including schema-version refusal, and verify tests for valid, invalid and too-new files
- [x] 2.7 Implement machine-local settings storage (member identity, band folder) and verify values persist across a REAPER restart
- [x] 2.8 Implement a plain-language message helper (what happened + one suggested action) and verify unit tests assert both parts exist for every error key

## 3. Band definition (spec: band-definition)

- [ ] 3.1 Implement reading and writing hidden role/owner markers on folder tracks and verify markers survive save/reopen and track rename
- [ ] 3.2 Implement the band setup wizard UI (members, instruments, track counts) and verify it generates a template and `band.json` for a three-member band
- [ ] 3.3 Implement creating a song project from the band template and verify the folders appear in the agreed order with markers
- [ ] 3.4 Implement the first-run flow ("Kuka sinä olet?", band folder selection) with rejection of folders without a band marker, and verify manually with a valid and an invalid folder
- [ ] 3.5 Support one member owning several folders and verify the roster and a workspace reflect it

## 4. Song registration (spec: song-registration)

- [ ] 4.1 Implement scanning a staging folder for project files and listing them as songs, and verify with a folder of arbitrary names and three projects
- [ ] 4.2 Implement receipt verification (referenced media present and non-empty, manifest check when present) and verify with a truncated media file and a missing file
- [ ] 4.3 Implement the song ID registry and first-arrival registration and verify a moved project registers silently
- [ ] 4.4 Implement copy detection with the "Onko tämä kopio?" prompt and fresh ID assignment noting the origin, and verify by copying a registered project into another library
- [ ] 4.5 Implement libraries and dated cycles and verify a rehearsal with several songs is grouped under its date
- [ ] 4.6 Implement closing a cycle and verify a proposal to a closed cycle is refused with an explanation
- [ ] 4.7 Implement the "Ota harjoitus vastaan" panel and verify an end-to-end receive of a real SCP-copied rehearsal folder (including an interrupted-copy case)

## 5. Master publishing (spec: master-publishing)

- [ ] 5.1 Implement revision numbering and immutability and verify a second publish creates r2 and leaves r1 byte-identical
- [ ] 5.2 Implement stem rendering per role folder outside each recipient's folders per the spike results (docs/spikes/stems.md), and verify a stem matches what the producer hears from that folder, folder bus included and master bus excluded
- [ ] 5.3 Implement the reference mix render with master-bus processing and verify it plays as the full mix
- [ ] 5.4 Implement recording the tempo map and length and flagging structural changes between revisions, and verify with a revision that lengthens a section
- [ ] 5.5 Include each member's own-folder media in the publication and verify a workspace can be built from the publication alone
- [ ] 5.6 Write the manifest and completion marker last and verify consumers refuse a publication interrupted mid-write
- [ ] 5.7 Implement the "Julkaise" panel with note entry and verify the note reaches the change log

## 6. Member workspace (spec: member-workspace)

- [ ] 6.1 Implement listing songs with a valid publication and hiding those without, and verify the "not published yet" message
- [ ] 6.2 Implement "Luo oma työtila" building the project with editable own folder(s) and locked collapsed stems, and verify locked items cannot be moved on Windows and Linux
- [ ] 6.3 Configure the workspace recording location and verify a new take lands inside the workspace
- [ ] 6.4 Implement state detection (master newer, own changes, both, none) and verify each of the four Synkronoi states in the UI
- [ ] 6.5 Implement "Hae pääversio" with own-folder backup, replacing only others' stems and timing, and verify own tracks remain unchanged
- [ ] 6.6 Implement the structural-change warning on fetch and verify with a lengthened chorus
- [ ] 6.7 Implement "Palauta edellinen tila" and verify the pre-fetch state is restored
- [ ] 6.8 Implement the send preflight (media consolidation, timing vs. base, empty folder, orphan tracks) with plain-language fixes and verify each case
- [ ] 6.9 Implement frozen, timestamped deliveries that supersede without removing older ones and verify two sends keep both
- [ ] 6.10 Implement the note field and proposal status line (sent time, pending/accepted) and verify the panel shows both after sending
- [ ] 6.11 Verify the offline route end to end: send a proposal into a local band folder, copy it on removable media, and import it unchanged

## 7. Proposal import (spec: proposal-import)

- [ ] 7.1 Implement the proposals inbox with member, time, note and outdated-base marker and verify with proposals on r5 and r8
- [ ] 7.2 Implement the import preview (folders, counts, timing comparison, note, base vs. current, warnings) with Accept/Cancel and verify nothing changes on Cancel
- [ ] 7.3 Implement pre-import integrity verification and verify a delivery lacking its marker is refused
- [ ] 7.4 Implement timestamped master backup before import and verify the backup exists before any write
- [ ] 7.5 Implement replacing only the proposer's owned folders and verify unexpected changes elsewhere in a delivery are ignored
- [ ] 7.6 Implement conflict detection when the producer changed the member's folder after the base and verify the preview warns
- [ ] 7.7 Implement "Kumoa" restoring the backup and verify the master is identical to its pre-import state
- [ ] 7.8 Verify import writes the change-log entry with sent and imported times and the note

## 8. Change log (spec: change-log)

- [ ] 8.1 Implement the log writer (single writer, newest first, date and time, event, actor, note, generated facts) and verify golden-file tests for publication and import entries
- [ ] 8.2 Implement the `HUOM` line rules and verify present for a structural change and absent for an ordinary one
- [ ] 8.3 Implement "Tehtävää" requests addressed to members and verify rendering under its own heading
- [ ] 8.4 Implement the summary-plus-body note model and producer editing of the note at import, and verify the edited text is logged
- [ ] 8.5 Implement showing entries newer than the member's base revision in the panel and verify with a member on r6 and master r8

## 9. Project guardian (spec: project-guardian)

- [ ] 9.1 Implement recognition of managed projects (manifest + role) and verify no message appears for an unrelated project
- [ ] 9.2 Implement the master-opened warning with close action and event logging, and verify manually as a member identity
- [ ] 9.3 Implement warnings for another member's workspace, closed cycle, misplaced or copied workspace, and verify each case
- [ ] 9.4 Implement the soft outdated-workspace notice with Synkronoi shortcut and verify it is non-blocking
- [ ] 9.5 Implement warn-once-per-open behavior and verify a dismissed warning does not reappear until reopen
- [ ] 9.6 Write the master's passive marker and distinctive file name and verify they are visible with the extension uninstalled
- [ ] 9.7 Install the guardian startup hook per the spike (with panel-open fallback) and verify it runs after a REAPER restart on both OSes
- [ ] 9.8 Implement "Tarkista kansiot" (incomplete packs, unregistered projects, duplicate IDs, wrong-area files, proposals in closed cycles, unreferenced media, bad names) as report-only with confirmed fixes, and verify each finding on a deliberately broken folder
- [ ] 9.9 Verify all guardian and lock wording avoids implying editing is impossible

## 10. Localization (spec: localization)

- [ ] 10.1 Provide complete Finnish and English string tables and verify a test fails when a key exists in one language but not the other
- [ ] 10.2 Apply the fixed vocabulary (pääversio, oma työtila, ehdotus, julkaisu, toimitus) and verify a test scans UI strings for forbidden terms (branch, merge, pull, GUID, manifest)
- [ ] 10.3 Implement configurable producer label with inflection forms and verify messages stay grammatical with two example labels
- [ ] 10.4 Review every Finnish string with a native speaker among the band and record the review as done

## 11. Distribution

- [ ] 11.1 Publish a ReaPack index and verify a clean REAPER profile installs and updates the extension from the repo URL on Windows and Linux
- [ ] 11.2 Produce an offline installer bundle for members working offline and verify installation from a USB folder with no network

## 12. User documentation (spec: user-documentation)

Documentation depends on a stable UI: write the Finnish text drafts early (they double as a check on the UX wording), but take final screenshots only after groups 3-9 are feature-complete.

- [ ] 12.1 Create the documentation skeleton: root `README.md` with a short pitch and links to both languages, and parallel `docs/fi/` and `docs/en/` trees with identical file names; verify both trees list the same files
- [ ] 12.2 Write the docs check in the test harness (same file and heading sets across languages, relative links and images resolve, images have alt text, forbidden terms absent in member docs) and verify it fails on a deliberately broken sample of each kind
- [ ] 12.3 Write the personas page (producer, member, member working offline: what each does and what each can ignore) in Finnish and English and verify a member can pick their guide from it in a read-through with a band member
- [ ] 12.4 Write the installation guide for vanilla REAPER on Windows (ReaPack, ReaImGui, repository URL, installing the extension, startup hook, first-run questions) with screenshots from a clean Windows profile, in both languages, and verify by following it on a fresh machine or VM with no steps missing
- [ ] 12.5 Write the Linux installation notes for the producer and verify by following them on a clean Linux REAPER profile
- [ ] 12.6 Write the offline-member guide (USB bundle installation, sending a proposal by removable media, receiving a new publication) in both languages and verify with a member who works offline or a network-less VM
- [ ] 12.7 Write the member guide (create an own workspace, Synkronoi, fetch the master, send a proposal with a note, undo a fetch, read the change log) in both languages, with the fixed vocabulary, and verify by a complete walkthrough against the real UI
- [ ] 12.8 Write the producer guide (band setup and template, receive a rehearsal, close a cycle, publish, proposals inbox and import preview, undo an import, folder check) in both languages and verify by a complete walkthrough
- [ ] 12.9 Write the operations reference (each operation: purpose, availability, what it changes, what it never changes, how to undo) in both languages and verify every UI button appears in it
- [ ] 12.10 Write the shared-folder setup guide (recommended layout, view-only publications, per-member proposal folders, keep files on the device, provider-agnostic notes with Google Drive as the worked example) and verify against a real Google Drive setup
- [ ] 12.11 Write troubleshooting and glossary pages (files still syncing, master opened unintentionally, guardian warnings, ReaImGui or ReaPack missing, wrong band folder, the fixed terms) in both languages and verify each entry against a reproduced case
- [ ] 12.12 Write the screenshot list (file name, what it shows, state to set up, language, OS) and take all screenshots from the real extension, one set per language under `docs/images/<lang>/`; verify every image loads from a relative path in GitHub's rendering of a pushed branch
- [ ] 12.13 Add a documentation section to the release checklist (re-verify guides against the UI, retake changed screenshots, run the docs check) and verify it is followed for the first release
- [ ] 12.14 Have a native Finnish speaker among the band proofread the Finnish docs and a reader of English proofread the English docs, and record both reviews as done
- [ ] 12.15 Have a band member with no audio-software background follow the Finnish install guide and the member guide unassisted, note where they got stuck, and verify that every reported problem is fixed in the docs or the UI

## 13. Integration and acceptance

- [ ] 13.1 Run the full loop on Windows (publish → workspace → fetch → propose → import → log) and verify the master and log are correct and the backup restores
- [ ] 13.2 Run the loop with the producer on Linux and a member on Windows through a real synced folder, and verify behavior is identical
- [ ] 13.3 Test adverse conditions (half-synced files, conflict copies, on-demand placeholders, interrupted SCP) and verify each is refused or reported in plain language
- [ ] 13.4 Pilot with one volunteer member on a low-stakes song, collect feedback, and record fixes needed before the other members join
- [ ] 13.5 Onboard the remaining members, including those working offline, and verify each completes one proposal
