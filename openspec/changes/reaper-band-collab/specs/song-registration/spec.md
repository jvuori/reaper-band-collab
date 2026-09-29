## Purpose

Defines how songs recorded on a separate capture machine enter the collaboration system: verifying that everything arrived, registering each song with a unique identity, handling copies, and organizing songs into libraries and closable cycles.

## ADDED Requirements

### Requirement: Receive a rehearsal from any folder
The system SHALL let the producer point at a staging folder and treat every project file found in it as a song. The capture machine SHALL NOT require the extension, and the system SHALL NOT require any folder naming convention there.

#### Scenario: Several songs in one rehearsal
- **WHEN** the producer receives a folder containing three project files
- **THEN** the tool lists three songs and registers each one selected

#### Scenario: Unconventional folder names
- **WHEN** the staging folder uses arbitrary names
- **THEN** receiving still works and the tool assigns its own normalized names

### Requirement: Completeness verification on receipt
The system SHALL verify that all files a received project depends on are present and intact before registering it. It SHALL refuse or clearly flag incomplete material.

#### Scenario: Interrupted transfer
- **WHEN** a media file referenced by a project is missing or its size differs from the manifest
- **THEN** the tool blocks registration of that song and names the problem in plain language

#### Scenario: No manifest available
- **WHEN** the capture machine produced no manifest
- **THEN** the tool verifies at minimum that every referenced media file exists and is non-empty

### Requirement: Song identity registry
The system SHALL assign each song a unique ID at first registration and record it in a registry in the band folder. The song ID SHALL NOT depend on the file location.

#### Scenario: First arrival after transfer
- **WHEN** a project with no registered ID arrives at a new location
- **THEN** the tool assigns an ID and registers it without asking any question

### Requirement: Copy detection
The system SHALL detect a project whose ID is already registered at a different location and SHALL ask whether it is a copy. If confirmed, it SHALL assign a fresh ID and record the origin.

#### Scenario: Manual copy into an official library
- **WHEN** the producer opens or registers a project copied from a rehearsal into the official library
- **THEN** the tool asks "Onko tämä kopio?" and on yes assigns a new song ID noting the original

#### Scenario: Legitimate move
- **WHEN** a project's ID is registered and its old location no longer exists
- **THEN** the tool treats it as moved and updates the registry without asking

### Requirement: Libraries and cycles
The system SHALL support multiple libraries (for example rehearsals and official recordings) with identical structure. Within the rehearsal library it SHALL group songs into dated cycles.

#### Scenario: Weekly cycle
- **WHEN** the producer receives Tuesday's rehearsal
- **THEN** the songs are grouped under that date in the rehearsal library

### Requirement: Closing a cycle
The system SHALL let the producer close a cycle. A closed cycle SHALL refuse new proposals and remain available for listening.

#### Scenario: Proposal to a closed cycle
- **WHEN** a member tries to send a proposal for a song in a closed cycle
- **THEN** the tool refuses and explains that the cycle is closed

### Requirement: Safe folder and file naming
The system SHALL create only names that are valid on Windows and Linux: lowercase ASCII, unique case-insensitively, not Windows-reserved, and free of forbidden characters. The human-readable song name SHALL be stored separately.

#### Scenario: Song title with special characters
- **WHEN** a song titled "Yö: kuka? Minä" is registered
- **THEN** its folder name is a valid slug and the UI shows the original title
