# Project Commands Demo

Companion example for `routed_cli project` / `commands` workflows. It ships
with custom commands under `lib/commands.dart` so you can see how the CLI loads
user-defined tasks.

```bash
dart pub get
dart run routed_cli project:list
dart run routed_cli schedule
```

The `schedule` command is contributed by `RoutedSchedulerProvider`; it is
discovered from the same engine provider list used by the server. This is a
great starting point for building your own CLI command packs.
