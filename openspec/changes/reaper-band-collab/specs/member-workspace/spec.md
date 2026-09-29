## Purpose

Defines the member's experience: creating an isolated per-instrument workspace, keeping it aligned with the master, and sending a proposal, all through simple guided actions in Finnish and without exposing files or technical concepts.

## ADDED Requirements

### Requirement: Create an own workspace from a publication
The system SHALL list songs that have a valid publication and let the member create an own workspace ("Luo oma työtila") for their role(s). The workspace SHALL contain the member's folder(s) as editable and all other members' stems as locked, and SHALL be created without the member choosing any file or folder.

#### Scenario: Creating a bass workspace
- **WHEN** a member with the bass role creates a workspace for a song
- **THEN** a new project opens with the bass folder editable and every other member's folder present as a locked stem

#### Scenario: No valid publication
- **WHEN** a song has no complete publication
- **THEN** it is not offered, and the panel states that the producer has not published it yet

### Requirement: Recording lands inside the workspace
The system SHALL configure the workspace so that new recordings are stored inside it.

#### Scenario: Recording a new take
- **WHEN** the member records a new take in the workspace
- **THEN** the audio file is stored within the workspace's own media location

### Requirement: Foreign material is protected
The system SHALL lock and visually collapse other members' stems in the workspace. Members SHALL still be able to change stem volume for their own listening.

#### Scenario: Attempting to edit another member's item
- **WHEN** a member tries to move a locked stem item
- **THEN** REAPER does not move it

### Requirement: Single guided Synkronoi flow
The system SHALL provide one "Synkronoi" action that inspects the workspace state and offers only the meaningful directions, with the recommended one preselected. It SHALL NOT choose a direction automatically, and its wording SHALL make clear that fetching is immediate while proposing needs the producer's acceptance.

#### Scenario: Only the master is newer
- **WHEN** the master has a newer revision and the member has no changes
- **THEN** only "Hae pääversio" is active

#### Scenario: Both sides changed
- **WHEN** the master is newer and the member has made changes
- **THEN** the flow presents two ordered steps, fetching first and proposing second

#### Scenario: Everything is current
- **WHEN** the workspace matches the latest revision and has no changes
- **THEN** the panel states that everything is up to date

### Requirement: Fetch the master without touching own work
"Hae pääversio" SHALL replace the other members' stems and timing information with the latest revision and SHALL leave the member's own folder(s) unchanged. Before doing so it SHALL back up the member's own folder(s).

#### Scenario: Fetch after producer publishes r8
- **WHEN** the member fetches while on r7
- **THEN** other members' stems become r8 versions and the member's own tracks are unchanged

### Requirement: Warn about structural changes when fetching
The system SHALL warn when the newer revision has a different tempo map, length or structure than the member's base.

#### Scenario: Chorus lengthened
- **WHEN** revision r8 has a chorus longer than r7
- **THEN** the fetch shows a warning that the member's tracks may no longer line up

### Requirement: Undo the last fetch
The system SHALL offer to restore the state prior to the most recent fetch.

#### Scenario: Undoing
- **WHEN** the member chooses "Palauta edellinen tila"
- **THEN** their own folder(s) and stems return to the state before the last fetch

### Requirement: Send a proposal after a preflight check
"Ehdota pääversioon" SHALL first check that all media is present and consolidated into the delivery, that timing matches the base, that the member's folder is not empty, and that no tracks exist outside the member's folder. It SHALL explain each problem in plain language with a single suggested fix.

#### Scenario: Track outside own folder
- **WHEN** the member created a track outside their folder
- **THEN** the check offers to move it into their folder, and does not silently drop it

#### Scenario: Empty folder
- **WHEN** the member's folder contains nothing
- **THEN** the check asks whether they really meant to send

#### Scenario: Media outside the workspace
- **WHEN** an item uses a file stored outside the workspace
- **THEN** the tool copies it into the delivery and informs the member

### Requirement: Deliveries are frozen and versioned
Each proposal SHALL be a complete, frozen, timestamped delivery with a manifest and completion marker. A newer delivery SHALL supersede but not remove older ones.

#### Scenario: Sending again
- **WHEN** the member sends a second proposal for the same song
- **THEN** both deliveries exist and the newer is marked current

### Requirement: Note to the producer
The proposal SHALL include a note field, with a summary line and optional body, recorded with the delivery.

#### Scenario: Writing a note
- **WHEN** the member writes "tiukennettu säkeistö 2" and sends
- **THEN** the note is stored with the delivery

### Requirement: Proposal status visibility
After sending, the panel SHALL show the time of sending and whether the producer has accepted it.

#### Scenario: Not yet handled
- **WHEN** the producer has not imported the delivery
- **THEN** the panel shows the send time and that it is pending

### Requirement: Route for members working offline
The system SHALL treat the band folder as any folder, so that a member working offline can use identical screens with a locally copied band folder and hand deliveries to the producer by removable media.

#### Scenario: USB workflow
- **WHEN** a member working offline sends a proposal
- **THEN** a complete delivery folder is produced in their local band folder that can be copied to another machine and imported unchanged
