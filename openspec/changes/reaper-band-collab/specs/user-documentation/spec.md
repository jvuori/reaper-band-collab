## Purpose

Defines the user documentation that band members and producers read on GitHub to install the extension into a vanilla REAPER and to understand how to use it, in Finnish and English, with screenshots.

## ADDED Requirements

### Requirement: Bilingual documentation in Markdown
The repository SHALL contain complete user documentation in Finnish and English, written in Markdown that renders correctly on GitHub. A root `README.md` SHALL introduce the tool briefly and link to both language versions.

#### Scenario: Reading on GitHub
- **WHEN** a band member opens the repository on GitHub
- **THEN** the README explains in a few sentences what the tool is for and offers a clear link to the Finnish and the English documentation

#### Scenario: Same content in both languages
- **WHEN** a document exists in one language
- **THEN** a corresponding document with the same structure exists in the other language

### Requirement: Personas
The documentation SHALL describe the roles of the people who use the tool: the producer, a band member with an online computer, and a band member who works offline, stating what each of them does and does not need to know.

#### Scenario: A member finds their role
- **WHEN** a member reads the personas
- **THEN** they can identify which guide applies to them without reading the producer's material

### Requirement: Main use cases
The documentation SHALL describe each main use case step by step in plain language: receiving a rehearsal, publishing a version, creating an own workspace, fetching the latest master, sending a proposal, accepting a proposal, undoing an import or fetch, working offline through removable media, and checking the folder structure.

#### Scenario: A member sends a proposal
- **WHEN** a member follows the "send a proposal" guide
- **THEN** every step names the exact button or field as it appears in the UI and explains what happens next

### Requirement: Operations reference
The documentation SHALL include a reference of every user-visible operation, its purpose, when it is available, what it changes, what it never changes, and how to undo it.

#### Scenario: Looking up an operation
- **WHEN** a user looks up "Hae pääversio" (or its English counterpart)
- **THEN** the reference states that it replaces only other members' stems, backs up own tracks, and can be undone

### Requirement: Installation into a vanilla REAPER
The documentation SHALL describe installing the extension into a vanilla REAPER on Windows, and on Linux for the producer, including installing ReaPack and ReaImGui, adding the repository, installing the extension, enabling automatic start of the guardian, and completing the first-run questions. It SHALL include the route for a machine without internet access.

#### Scenario: Clean Windows install
- **WHEN** a member follows the Windows installation guide on a machine with vanilla REAPER
- **THEN** they end with a working panel and the first-run questions answered, without any step missing from the guide

#### Scenario: Machine without internet
- **WHEN** a member working offline follows the offline route
- **THEN** they can install from the provided bundle without network access

### Requirement: Screenshots
The documentation SHALL include screenshots wherever a user must find or recognize something in the UI. Screenshots SHALL be taken from the real extension, SHALL show the language of the document in which they appear, and SHALL each have alternative text and a caption.

#### Scenario: Language-matched screenshots
- **WHEN** a Finnish document shows the panel
- **THEN** the screenshot shows the Finnish UI

#### Scenario: Images render on GitHub
- **WHEN** the repository is viewed on GitHub
- **THEN** every referenced image loads through a relative path

### Requirement: Troubleshooting and glossary
The documentation SHALL include troubleshooting for the common problems (files still syncing, wrong project opened, warnings from the guardian, missing plugin or ReaImGui, wrong band folder) and a glossary of the fixed terms.

#### Scenario: Warning after opening the master
- **WHEN** a member reads the troubleshooting entry for the master-opened warning
- **THEN** it explains why it appears, what to do, and that nothing has been changed

### Requirement: Member documentation uses the member vocabulary
Documentation for members SHALL use the fixed member vocabulary and SHALL NOT use technical terms such as branch, merge, pull, GUID or manifest.

#### Scenario: Checking a member guide
- **WHEN** the member guides are scanned for forbidden terms
- **THEN** none is found

### Requirement: Documentation is checked for consistency
The repository SHALL include an automated check that both languages have the same set of documents and headings, that every relative link and image resolves, and that member documents contain no forbidden terms.

#### Scenario: Missing translation
- **WHEN** a document exists only in Finnish
- **THEN** the check fails and names the file

#### Scenario: Broken image path
- **WHEN** a document references an image that does not exist
- **THEN** the check fails and names the document and image

### Requirement: Documentation reflects the released UI
Before each release, the documentation SHALL be verified against the UI, and screenshots SHALL be retaken for any screen that changed. A list of all screenshots and what each shows SHALL be maintained to make retaking them repeatable.

#### Scenario: UI text changed
- **WHEN** a button label changes
- **THEN** the release checklist requires updating the affected text and screenshots in both languages
