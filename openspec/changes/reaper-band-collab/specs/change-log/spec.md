## Purpose

Defines the per-song Markdown change log that tells band members what changed, who did it, when, and whether it affects them, while remaining safe from sync conflicts.

## ADDED Requirements

### Requirement: One log per song written by one writer
Each song SHALL have a `MUUTOSLOKI.md` that is written only by the producer's tool.

#### Scenario: Member sends a proposal
- **WHEN** a member sends a proposal
- **THEN** the log file is not modified until the producer imports it

### Requirement: Entry contents
Each entry SHALL state revision, local date and time, event type (publication, proposal imported, rehearsal received), the actor, the note, and generated facts such as tracks replaced and tempo or length changes.

#### Scenario: Import entry
- **WHEN** a proposal from a member is accepted
- **THEN** the entry shows the member, both the sent and imported time, the note, and the tracks replaced

### Requirement: Newest first with times
Entries SHALL be ordered newest first, and every entry SHALL include the time as well as the date.

#### Scenario: Two entries the same day
- **WHEN** two events occur on one day
- **THEN** their times distinguish and order them

### Requirement: Attention line for affecting changes
The system SHALL add a `HUOM` line only when a change affects other members, such as a structural or timing change.

#### Scenario: Chorus lengthened
- **WHEN** a publication changes the song structure
- **THEN** its entry includes a HUOM line naming the change and recommends fetching the latest master

#### Scenario: Ordinary change
- **WHEN** a publication has no structural change
- **THEN** the entry has no HUOM line

### Requirement: Requests to members
The producer SHALL be able to add optional "Tehtävää" requests, each addressed to a member or role.

#### Scenario: Request for drums
- **WHEN** the producer adds "Rummut: uusi otto kertosäkeeseen"
- **THEN** the entry contains the request under its own heading

### Requirement: Note structure
A note SHALL consist of a summary line and an optional body, the first line being usable on its own as a short summary.

#### Scenario: Multi-line note
- **WHEN** a note has several lines
- **THEN** the first line is treated as the summary and the rest as the body

### Requirement: Producer can edit the note at import
The producer SHALL be able to edit a member's note before it becomes part of the log.

#### Scenario: Editing wording
- **WHEN** the producer changes the note text in the import preview
- **THEN** the log records the edited text

### Requirement: Log surfaced in the panel
The member's panel SHALL show log entries newer than the member's base revision, so that reading the file is unnecessary.

#### Scenario: Two new revisions
- **WHEN** the member is on r6 and the master is r8
- **THEN** the panel shows the r7 and r8 entries
