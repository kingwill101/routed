# routed_cli

CLI runtime and command framework helpers for Routed.

This package provides reusable command-runner and dev-server utilities used by
Routed's CLI surface, including:

- `CliLogger`
- `CliVersion`
- `RoutedCommandRunner`
- `ProjectCommandsLoader`
- `DevServerRunner`

It is intended for internal ecosystem composition and advanced custom command
integrations.

`routed_cli` is a command-line package, not an `Engine` provider. Install it as
a development dependency and run commands with `dart run routed_cli ...`; keep
runtime provider initialization in `routed` or the relevant adapter package.
