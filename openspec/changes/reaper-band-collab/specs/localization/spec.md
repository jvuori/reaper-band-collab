## Purpose

Defines that all user-facing text is Finnish by default and translatable, with a fixed vocabulary that avoids technical terms and stays grammatical despite Finnish inflection.

## ADDED Requirements

### Requirement: Finnish by default
All user-facing text SHALL be available in Finnish, and Finnish SHALL be the default language.

#### Scenario: Fresh install
- **WHEN** a member opens the panel with no language setting
- **THEN** all text appears in Finnish

### Requirement: Language selectable, English included
The system SHALL ship an English language as well and SHALL use the language set in `band.json`.

#### Scenario: English band
- **WHEN** `band.json` sets the language to English
- **THEN** all UI text appears in English

### Requirement: All text from string tables
User-facing text SHALL come from keyed string tables so that adding a language requires no code changes. A missing translation SHALL fall back to English rather than showing a raw key.

#### Scenario: Missing key
- **WHEN** a Finnish string is missing
- **THEN** the English text appears

### Requirement: Fixed member vocabulary
Member-facing screens SHALL use the terms pääversio, oma työtila, ehdotus, julkaisu and toimitus, and SHALL NOT display technical terms such as branch, merge, pull, GUID or manifest. The term "virallinen" SHALL be reserved for official recording projects.

#### Scenario: Panel wording
- **WHEN** a member views any screen
- **THEN** none of the forbidden technical terms appears

### Requirement: Configurable producer label
The role label of the producer SHALL be configurable. Sentences SHALL be written to avoid embedding the label, and where unavoidable the required inflected forms SHALL be provided by configuration.

#### Scenario: Label changed to "vetäjä"
- **WHEN** the label is changed
- **THEN** every message using it remains grammatically correct

### Requirement: Plain-language errors with one suggested action
Every warning and error SHALL be written in plain language, state what happened, and suggest one next step.

#### Scenario: Incomplete download
- **WHEN** a publication is still downloading
- **THEN** the message says files are still arriving and suggests trying again shortly
