# Contributing to the Routed Ecosystem

Thanks for helping improve Routed and the surrounding tooling! This workspace hosts several Dart packages (`packages/routed`, `packages/routed_cli`, `packages/server_testing`, `packages/property_testing`, etc.), so a few conventions keep changes easy to review.

## Getting Set Up

1. Install the Dart SDK (>= 3.9.0).
2. Run `dart pub get` from the repository root to hydrate the workspace.
3. (Optional) Install Node.js if you want to build or preview the documentation in `docs/`.

## Development Workflow

- **Formatting & static analysis**
  Run `dart format .` followed by `dart analyze` before opening a PR. Each package inherits strict analysis options; CI will fail on formatting drift or analyzer warnings.

- **Tests**
  Execute the package-level test suites relevant to your changes:
  - `dart test packages/routed`
  - `dart test packages/server_testing`
  - `dart test packages/property_testing`
  - `dart test packages/routed_cli`
  For docs-only updates, make sure Docusaurus builds via `npm run build` (from `docs/`).

- **Examples & tooling**
  When touching examples or CLI commands, run the affected scripts (for example, `dart run packages/routed_cli bin/routed_cli.dart dev`).

## Commit & PR Guidelines

- Keep pull requests focused. Cross-package changes are fine, just explain the relationship in the PR description.
- Include regression tests whenever possible. For bug fixes, a failing test in the current mainline is the quickest way to show the fix.
- Update docs (`README.md`, `docs/`, CHANGELOGs) when behaviour or public APIs change.
- Follow the existing style for comments and use concise, actionable commit messages. Prefixing commits with the package name (`routed: ...`) helps reviewers skim history.

## Documentation

Docs live in `docs/` (Docusaurus). Run `npm install` there once, then `npm run dev` to preview your changes locally. If a doc page references code snippets, make sure it matches the latest examples/tests.

## Need Help?

Open a discussion or issue on GitHub if you’re unsure about an approach, need feedback on a larger refactor, or want to propose a new package in the ecosystem. We’re happy to collaborate early so reviews go smoothly.

Happy hacking!
