## Purpose

Defines the protective layer that warns users who open the wrong managed project and lets the producer verify and keep the shared directory structure in good condition, without ever nagging about ordinary REAPER projects.

## ADDED Requirements

### Requirement: Managed projects only
The guardian SHALL act only on projects identified as managed by a manifest and role. It SHALL NOT display anything for unmanaged projects.

#### Scenario: Ordinary project
- **WHEN** a user opens a project unrelated to the band
- **THEN** no guardian message appears

### Requirement: Warn when a member opens the master
When a member opens the master project, the guardian SHALL show a strong warning that only the producer edits it, offer to close the project, and log the event.

#### Scenario: Member opens the master
- **WHEN** a member opens a project recognized as the master
- **THEN** a dialog says so and the primary action is to close the project

### Requirement: Warn on another member's workspace
The guardian SHALL warn when the open workspace belongs to a different member than the one identified on this machine.

#### Scenario: Wrong workspace
- **WHEN** the drummer opens the bassist's workspace
- **THEN** the message names both members and offers to close it

### Requirement: Warn on closed cycles
The guardian SHALL warn when a workspace belongs to a closed cycle.

#### Scenario: Old rehearsal workspace
- **WHEN** a member opens a workspace whose cycle is closed
- **THEN** it states that proposals are no longer accepted

### Requirement: Soft notice for outdated workspaces
The guardian SHALL show a non-blocking notice when the workspace is based on an older master revision, with a shortcut to Synkronoi.

#### Scenario: Newer revision exists
- **WHEN** a member opens a workspace based on r7 while r8 exists
- **THEN** a gentle notice appears offering Synkronoi

### Requirement: Detect misplaced or copied workspaces
The guardian SHALL warn when a workspace is located outside the band folder or differs from its expected location, and offer to move it back.

#### Scenario: Save-as to the desktop
- **WHEN** a member saves the workspace elsewhere and opens it there
- **THEN** the message says a proposal cannot be sent from that place and offers to fix it

### Requirement: Warn once per open
The guardian SHALL show each warning once per open of a project, not repeatedly.

#### Scenario: Continuing to work
- **WHEN** the user dismisses a warning and keeps working
- **THEN** the same warning does not reappear until the project is opened again

### Requirement: Passive protection on the master
The master project SHALL carry a visible marker at its start stating it is the master, and a distinctive file name, so that the warning is visible even when the extension is not running.

#### Scenario: Extension not installed
- **WHEN** someone opens the master without the extension
- **THEN** the master's marker and file name show that it is the producer's master

### Requirement: Cannot block saving
The guardian SHALL NOT claim to prevent editing or saving; its documentation and messages SHALL not imply that locks are security.

#### Scenario: Message wording
- **WHEN** a warning is shown
- **THEN** it asks the user to close the project instead of stating that editing is impossible

### Requirement: Directory structure check
The system SHALL offer the producer an on-demand check ("Tarkista kansiot") that reports incomplete packs, unregistered projects, duplicate song IDs, files in the wrong area, proposals in closed cycles, unreferenced media and non-conforming names. It SHALL report and offer fixes, and SHALL NOT change anything without confirmation.

#### Scenario: Incomplete pack found
- **WHEN** the check finds a delivery without a completion marker
- **THEN** it reports it with a suggested action and changes nothing until the producer confirms

### Requirement: Members never manage folders
The system SHALL create and place all folders itself, so members are never required to create, move or rename them.

#### Scenario: Creating a workspace
- **WHEN** a member creates a workspace
- **THEN** the tool creates every needed folder without asking for a location
