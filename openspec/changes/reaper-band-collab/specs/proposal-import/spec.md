## Purpose

Defines how the producer reviews and accepts a member's proposal into the master with full control, a preview, restriction to the proposer's own material, and reliable undo.

## ADDED Requirements

### Requirement: Producer-only acceptance
Only the producer's tool SHALL modify the master project. A proposal SHALL NOT change the master until the producer explicitly accepts it.

#### Scenario: Pending proposal
- **WHEN** a member has sent a proposal
- **THEN** the master remains unchanged until the producer accepts

### Requirement: Inbox of proposals
The system SHALL list pending proposals per song with member, send time, note, and whether the delivery is based on an outdated revision.

#### Scenario: Outdated base
- **WHEN** a proposal is based on r5 and the current revision is r8
- **THEN** the inbox marks it as based on an older revision

### Requirement: Import preview
Before accepting, the system SHALL show what will be replaced (folders and track counts), length and tempo comparison, the member's note, base versus current revision, and any warnings. It SHALL require explicit confirmation.

#### Scenario: Reviewing a proposal
- **WHEN** the producer opens a proposal
- **THEN** the preview lists the affected folders, timing differences and the note, and offers Accept and Cancel

### Requirement: Only owned folders are taken
Import SHALL apply only the proposer's owned folder(s). All other content of the delivery, including stems, tempo, master effects and other folders, SHALL be ignored.

#### Scenario: Delivery with unexpected changes
- **WHEN** a delivery contains altered stems or a changed tempo map
- **THEN** import replaces only the proposer's folder and ignores everything else

### Requirement: Integrity check before import
The system SHALL verify the delivery's manifest, checksums and completion marker before import and refuse incomplete or corrupt deliveries.

#### Scenario: Missing marker
- **WHEN** a delivery lacks the completion marker
- **THEN** import is refused with a message that the delivery is incomplete

### Requirement: Backup before import
Before modifying the master, the system SHALL save a timestamped backup of it.

#### Scenario: Import creates backup
- **WHEN** the producer accepts a proposal
- **THEN** a backup of the pre-import master exists before any change is written

### Requirement: Undo import
The system SHALL let the producer undo an import by restoring the backup.

#### Scenario: Reverting
- **WHEN** the producer chooses "Kumoa" after an import
- **THEN** the master returns to its pre-import state and the log records the reversal

### Requirement: Detect conflicting master changes
If the producer changed the proposer's folder in the master after the delivery's base revision, the system SHALL warn before replacing it.

#### Scenario: Producer edited the member's folder
- **WHEN** the master's folder for that member differs from the base revision
- **THEN** the preview warns that accepting will overwrite those changes

### Requirement: Import records to the log
Accepting a proposal SHALL add an entry to the song's change log, including the note and generated facts.

#### Scenario: Log after accept
- **WHEN** the producer accepts a proposal
- **THEN** a log entry with sent time, import time and note is written
