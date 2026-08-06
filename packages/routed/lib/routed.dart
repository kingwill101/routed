// Foundation barrel per refactor.md §12 — exports foundation APIs only.
// Feature packages (auth/cache/sessions/views/http/openapi/observability) are
// re-exported via `routed_full` to keep `routed` lean.
export 'dart:io' show HttpHeaders, HttpStatus;

export 'src/container/container.dart' hide Binding;
export 'src/container/service_resolver.dart' show ServiceResolver;
export 'src/context/context.dart';
export 'src/context/context_key.dart' show ContextKey;
export 'src/context/typed_context_state.dart' show TypedContextState;
export 'src/contracts/contracts.dart';
export 'src/engine/config.dart';
export 'src/engine/engine.dart';
export 'src/engine/engine_opt.dart';
export 'src/engine/engine_template.dart';
export 'src/engine/middleware_registry.dart';
export 'src/engine/provider_manifest.dart';
export 'src/engine/route_manifest.dart';
export 'src/events/event.dart';
export 'src/events/events.dart';
export 'src/events/signals.dart';
export 'src/http/transport.dart'
    show RequestAdapter, ResponseAdapter, ServerTransport, ServerOptions, ServerHandle;
export 'src/provider/provider.dart';
export 'src/request.dart';
export 'src/response.dart';
export 'src/router/middleware_reference.dart';
export 'src/router/router.dart';
export 'src/router/controller.dart';
export 'src/router/types.dart';
export 'src/router/route_metadata.dart' show RouteMetadataKey, RouteMetadata;
export 'src/render/render.dart' show Render;
export 'src/utils/request_id.dart';
export 'src/runtime/shutdown.dart';
export 'src/support/zone.dart';
