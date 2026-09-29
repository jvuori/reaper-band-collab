## Purpose

Defines how the producer publishes numbered, self-verifying snapshots of the master project that members can safely work against without owning the producer's plugins.

## ADDED Requirements

### Requirement: Numbered publications
The system SHALL create a new numbered revision (`r1`, `r2`, ...) each time the producer publishes a song. A published revision SHALL never be modified afterwards.

#### Scenario: Second publish
- **WHEN** the producer publishes a song that already has revision r1
- **THEN** a new revision r2 is created and r1 is left unchanged

### Requirement: Stems for other members' folders
A publication SHALL contain one audio stem per role folder outside each recipient's own folders. Each stem SHALL be the sum of all tracks in that folder, including nested folders, rendered through the folder's own effects, fader, pan and automation and each track's effects, fader, pan and automation, and without master-bus processing. Recipients SHALL NOT need any plugin to play them.

#### Scenario: Member without the producer's plugins
- **WHEN** a member opens a workspace built from a publication on a machine lacking the producer's plugins
- **THEN** all other members' tracks play exactly as rendered

#### Scenario: Folder bus processing is included
- **WHEN** the producer has processed a member's folder through a bus effect such as compression
- **THEN** that member's stem contains the processed sound of the whole folder, not the dry individual tracks

#### Scenario: Master bus processing is excluded
- **WHEN** the producer has effects on the master bus
- **THEN** the stems do not contain them, and only the reference mix does

### Requirement: Reference mix
A publication SHALL include a stereo reference mix with master-bus processing for listening.

#### Scenario: Listening to the reference
- **WHEN** a member opens the reference mix
- **THEN** it reflects the producer's complete mix at that revision

### Requirement: Timing information
A publication SHALL record the tempo map and song length at that revision.

#### Scenario: Structural change between revisions
- **WHEN** the tempo map or length differs from the previous revision
- **THEN** the manifest flags a structural change

### Requirement: Own-folder media included
A publication SHALL include each member's own folder media so that a workspace can be created without any other source.

#### Scenario: Creating a workspace from a publication only
- **WHEN** a member creates a workspace using only the published content
- **THEN** their own recorded material is present and editable

### Requirement: Verifiable completeness
Each publication SHALL contain a manifest listing every file with size and checksum, and a completion marker written last. Consumers SHALL refuse to use a publication that lacks the marker or whose files do not match the manifest.

#### Scenario: Half-synced publication
- **WHEN** a member's machine has only some files of a new revision
- **THEN** the tool reports that files are still downloading and does not offer the revision

#### Scenario: Corrupted file
- **WHEN** a file's checksum does not match the manifest
- **THEN** the tool refuses the revision and names the affected song

### Requirement: Publication note
The producer SHALL be able to attach a note (a summary line plus optional body) to a publication, which SHALL be recorded in the change log.

#### Scenario: Publish with note
- **WHEN** the producer publishes with a note
- **THEN** the note appears in the song's change log entry for that revision
