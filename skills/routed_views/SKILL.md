---
name: routed-views
description: Maintain, extend, document, test, or troubleshoot the routed_views subsystem in the Routed Dart monorepo. Use when a task touches routed_views APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_views

This skill is the complete working guide for the `routed_views` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_views`
- **Directory:** `packages/routed_views`
- **Version in this checkout:** `0.2.0`
- **Role:** View rendering, localization, and translation helpers
- **Purpose:** View rendering and translation integration for Routed. It owns view engines, provider configuration, locale resolution, translation loading, and EngineContext rendering extensions.

### Public API

- `ViewServiceProvider(RoutedViewConfig(...))` installs rendering and `LocalizationServiceProvider(LocalizationConfig(...))` installs translation.
- `ctx.template`, `ctx.view`, `ctx.viewTrans`, and `ctx.viewTransChoice` are the main request-facing extensions.
- `LiquidViewEngine`, `LiquidRoot`, `ViewEngineManager`, `ViewExtensionRegistry`, and view engine contracts define rendering.
- `Translator`, `LocaleManager`, `MessageSelector`, `TranslationLoader`, and `FileTranslationLoader` define translation.
- `QueryLocaleResolver`, `CookieLocaleResolver`, `SessionLocaleResolver`, and `HeaderLocaleResolver` resolve request locale.
- `registerRoutedViewsProviders()` registers the adapter’s provider catalogue; `kRequestLocaleAttribute` identifies request locale state.

### Public imports

- `package:routed_views/routed_views.dart`

### Runtime package dependencies

- `routed_core`
- `server_contracts`
- `server_storage`

### Composition rules

- Pass typed view directory and translation path configuration before engine creation; configuration is fixed for engine lifetime.
- Most applications use the routed facade; slim apps add both providers explicitly when they need rendering/localization.
- Keep templates, translation files, and locale policy separate; use a custom resolver for application-specific precedence.

### Known hazards

- Return a clear TemplateNotFoundException/TemplateRenderException path; do not turn missing templates into silent empty responses.
- Avoid locale fallback behavior that ignores explicit request/cookie/session/header precedence.
- Test escaping, engine selection, translation parameters/plurals, missing keys, and file loader failures.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  ViewServiceProvider(RoutedViewConfig(directory: 'views')),
  LocalizationServiceProvider(LocalizationConfig(defaultLocale: 'en')),
])..get('/welcome', (ctx) => ctx.view('welcome.liquid', data: {'name': 'Routed'}));
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_views`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a `lib/src` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

Cover provider config, Liquid rendering, view/context extensions, custom engines/extensions, locale resolver precedence, translation loading, and message selection.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_views
dart analyze --fatal-infos packages/routed_views
dart test packages/routed_views/test
```

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use `routed` for the full provider catalogue or
  `routed_core` plus explicit adapters for slim compositions.
- Routed adapters depend on `routed_core` and matching `server_*` runtimes;
  they must not depend on the batteries-included `routed` facade.
- Host I/O belongs in `routed_io`, `routed_node`, or `server_native`, not in
  feature adapters.
- Framework-agnostic `server_*` implementations must not import Routed from
  `lib/`.
