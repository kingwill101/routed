## Why
- The Routed ecosystem currently uses workspace-only configuration that blocks publishing (`publish_to: none`, `resolution: workspace`, and path dependencies).
- We need to publish the core set of libraries (`server_contracts`, `server_data`, `server_auth`, `server_testing`, `server_testing_shelf`, `routed`, `routed_testing`, `property_testing`) to pub.dev so downstream users can depend on them.
- Establishing the publishing baseline ensures future releases are repeatable and verifiable.

## What Changes
- Normalize pubspec metadata for the six targeted packages so they comply with pub.dev requirements (repository URLs, SDK constraints, versioned cross-dependencies, removed workspace resolution markers).
- Replace local workspace dependency wiring with semantic version constraints that mirror the packages we intend to ship together.
- Add a validation step (`dart pub publish --dry-run`) for each package and document the publishing checklist for release engineering.

## Impact
- Developers gain the ability to publish and consume the core Routed packages from pub.dev.
- Local development continues to work via workspace dependency overrides, but release artifacts now reflect the versions we ship publicly.
- Publishing automation can rely on the documented checklist to verify future releases.
