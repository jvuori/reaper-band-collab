## Purpose

Defines how a band's structure (members, roles, track layout, language and locations) is described as data so that the same extension serves any band, and how each user is identified on their own machine.

## ADDED Requirements

### Requirement: Band structure is defined by a project template
The system SHALL treat a project template as the definition of a band's track structure. The template SHALL contain one folder track per role, each carrying hidden markers that identify the role and its owner slot. A song project created from the template SHALL inherit that structure without further configuration.

#### Scenario: New song from template
- **WHEN** the producer creates a song project from the band template
- **THEN** the project contains one marked folder track per role in the agreed order

#### Scenario: Renaming a folder does not change ownership
- **WHEN** a folder track's visible name is changed
- **THEN** the system still recognizes it as the same role and owner

### Requirement: Band configuration file
The system SHALL read band-level settings from a `band.json` in the band folder: band name, members and their roles, UI language, role labels, and the locations of the master, publication and proposal areas. The file SHALL carry a schema version.

#### Scenario: Members share one configuration
- **WHEN** a member's machine receives the synced band folder
- **THEN** the member's tool uses the same members, roles, language and locations as the producer's

#### Scenario: Unknown schema version
- **WHEN** `band.json` declares a schema version newer than the tool supports
- **THEN** the tool refuses to proceed and tells the user to update the extension

### Requirement: Band setup wizard
The system SHALL provide a setup wizard that asks for members, instruments and tracks per instrument, and generates the band template and `band.json`. The producer SHALL be able to edit the generated template afterwards in REAPER.

#### Scenario: Generating a template
- **WHEN** the producer enters three members with their instruments and track counts
- **THEN** the wizard produces a template with three marked folders sized accordingly and a `band.json` listing them

### Requirement: Member identity is chosen once per machine
The system SHALL ask each user once, on first run, who they are from the list of members in `band.json`, and where the band folder is. The answers SHALL be stored on that machine only and remembered afterwards.

#### Scenario: First run
- **WHEN** a member starts the tool for the first time
- **THEN** it asks "Kuka sinä olet?" with the member list and asks for the band folder location, then stores both locally

#### Scenario: Wrong band folder selected
- **WHEN** the chosen folder does not contain a valid band marker
- **THEN** the tool rejects it with a plain-language message and asks again

### Requirement: One member may own several folders
The system SHALL allow a member to be assigned multiple role folders in one song.

#### Scenario: Drummer who also plays keys
- **WHEN** a member is assigned both the drums and keys roles
- **THEN** their workspace contains both folders as editable and a proposal covers both

### Requirement: No band-specific content is built in
The extension SHALL NOT contain any built-in band, member or song names, folder names, or branding. All band-specific text and structure SHALL come from `band.json`, the band template, and the band folder. Example names MAY appear in documentation and tests only.

#### Scenario: A different band installs the extension
- **WHEN** a band other than the original one installs the extension and runs the setup wizard
- **THEN** no UI text, folder name, file name or stored key refers to the original band

#### Scenario: Extension code is scanned
- **WHEN** the code, string tables and UI scripts are searched for the original band's name
- **THEN** no occurrence is found
