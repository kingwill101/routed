---
name: routed-http
description: Maintain, extend, document, test, or troubleshoot the routed_http subsystem in the Routed Dart monorepo. Use when a task touches routed_http APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_http

This skill is the complete working guide for the `routed_http` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_http`
- **Directory:** `packages/routed_http`
- **Version in this checkout:** `0.1.2`
- **Role:** JSON/XML binding, multipart, negotiation, buffered gzip compression, SSE, and conditional requests
- **Purpose:** HTTP request/response utilities layered on routed_core: typed binding, multipart uploads, content negotiation, conditional requests, SSE, proxy handling, and opt-in buffered gzip compression.

### Public API

- `ctx.bind`, `ctx.bindJSON`, `ctx.bindQuery`, `ctx.bindForm`, and `ctx.bindMultipart` provide typed request binding.
- `QueryBinding`, `JsonBinding`, `FormBinding`, `UriBinding`, `MultipartBinding`, `MultipartForm`, and `MultipartFile` implement binding and upload limits.
- `ContentNegotiator`, `ctx.negotiate`, `EtagCandidate`, `ConditionalOutcome`, and conditional helpers implement response negotiation/ETag behavior.
- `SseEvent`, `SseCodec`, and `ctx.sse` implement Server-Sent Events.
- `CompressionConfig` and `RoutedCompressionProvider` enable buffered gzip for eligible responses.
- `ProxyOptions` and the context extensions cover proxy/request helpers; query params, XML, SSE, and binding codecs are public.

### Public imports

- `package:routed_http/routed_http.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- Use directly with routed_core for only HTTP utilities; routed re-exports and registers its official provider.
- Add `RoutedCompressionProvider(CompressionConfig(...))` explicitly before engine creation; configuration is typed and fixed for the engine lifetime.
- Enforce multipart size, extension, and quota settings at the binding boundary, before writing uploaded content.

### Known hazards

- Compression is opt-in, buffered, and not a YAML/dotted-key setting; do not mutate provider configuration after startup.
- Preserve negotiation quality/priority and conditional response status semantics.
- Test upload rejection, malformed input, content-type mismatch, SSE framing, and gzip eligibility.

## Minimal usage

```dart
import 'dart:async';
import 'package:routed_core/routed_core.dart';
import 'package:routed_http/routed_http.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedCompressionProvider(CompressionConfig(enabled: true)),
])..get('/events', (ctx) async {
  await ctx.sse(Stream.value(SseEvent(data: 'ready')));
});
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_http`.
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

Cover JSON/form/query/URI/multipart binding, upload guardrails, negotiation, conditional requests, SSE encoding, proxy handling, and compression provider behavior.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_http
dart analyze --fatal-infos packages/routed_http
dart test packages/routed_http/test
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
