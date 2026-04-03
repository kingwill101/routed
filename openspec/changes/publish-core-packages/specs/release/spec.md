## ADDED Requirements
### Requirement: Core packages are publishable
The release workflow SHALL ensure the following packages are configured for pub.dev distribution: `server_contracts`, `server_data`, `server_auth`, `server_testing`, `server_testing_shelf`, `routed`, `routed_testing`, and `property_testing`.

#### Scenario: Dry-run succeeds for each package
- **GIVEN** the repository is prepared for release
- **WHEN** `dart pub publish --dry-run` runs inside each targeted package directory
- **THEN** the command completes successfully without errors or warnings that block publishing

#### Scenario: Versioned cross-dependencies
- **GIVEN** packages in the set depend on each other
- **WHEN** reviewing their `pubspec.yaml`
- **THEN** they reference one another using semantic version constraints (e.g., `^0.1.0`) instead of workspace-specific overrides or path dependencies

#### Scenario: Repository metadata present
- **GIVEN** a package consumer inspects pub.dev metadata
- **WHEN** they view the published package page
- **THEN** the `repository` or `homepage` fields link to the appropriate folder in `https://github.com/kingwill101/routed`
