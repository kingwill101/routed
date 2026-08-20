import 'package:routed_core/routed_core.dart';

import '../runtime/host_context.dart';
import '../runtime/runtime.dart';
import 'cloudflare_types.dart';

/// Returns the Worker environment associated with [context], when present.
CloudflareEnvironment? cloudflareEnvironmentOf(EngineContext context) {
  final extension = routedNodeExtensionOf<FetchRuntimeExtension>(context);
  final environment = extension?.environment;
  if (environment is CloudflareEnvironment) return environment;
  return environment == null
      ? null
      : cloudflareEnvironmentFromJavaScript(environment);
}

/// Reads a text or secret Worker binding without exposing JavaScript interop.
String cloudflareTextBinding(CloudflareEnvironment environment, String name) {
  final value = environment.binding(name);
  if (value is String) return value;
  throw StateError('Cloudflare binding is not text: $name.');
}

/// Returns the native Fetch request associated with [context], when present.
CloudflareRequest? cloudflareRequestOf(EngineContext context) => null;

CloudflareRequest createCloudflareRequest(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  Object? body,
}) =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Returns the Cloudflare Cache API namespace.
Future<CloudflareCache> cloudflareCache({String? name}) =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Creates a Cloudflare WebSocket pair on a JavaScript Worker runtime.
CloudflareWebSocketPair cloudflareWebSocketPair() =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Wraps a native Worker environment.
CloudflareEnvironment cloudflareEnvironmentFromJavaScript(Object environment) =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Returns the Worker execution context associated with [context], when present.
CloudflareExecutionContext? cloudflareExecutionContextOf(
  EngineContext context,
) {
  final extension = routedNodeExtensionOf<FetchRuntimeExtension>(context);
  final executionContext = extension?.executionContext;
  return executionContext == null
      ? null
      : cloudflareExecutionContextFromJavaScript(executionContext);
}

/// Wraps a native Worker execution context.
CloudflareExecutionContext cloudflareExecutionContextFromJavaScript(
  Object executionContext,
) =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Wraps Durable Object state supplied by a native Worker entrypoint.
CloudflareDurableObjectState cloudflareDurableObjectStateFromJavaScript(
  Object state,
) =>
    throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');

/// Registers Durable Object factories for a JavaScript Worker module wrapper.
void defineCloudflareDurableObjects(
  Map<String, CloudflareDurableObjectFactory> factories,
) {
  throw UnsupportedError('Cloudflare bindings require a JavaScript runtime.');
}
