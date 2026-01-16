import 'dart:io';

import 'package:routed/routed.dart';

/// A service provider that registers request-scoped services.
///
/// This provider is responsible for registering services that are specific
/// to a single request/response cycle:
/// - HTTP request/response
/// - Request/Response wrappers
/// - Engine context
///
/// These services are typically scoped to a single request and cleaned up
/// after the request is complete.
class RequestServiceProvider extends ServiceProvider {
  /// The HTTP request instance
  final HttpRequest request;

  /// The HTTP response instance
  final HttpResponse response;

  /// Creates a new request service provider.
  ///
  /// Parameters:
  /// - [request]: The HTTP request instance
  /// - [response]: The HTTP response instance
  RequestServiceProvider(this.request, this.response);

  @override
  ContainerScope get scope => ContainerScope.request;

  @override
  void register(Container container) {
    // Register request-scoped services
    container.instance<HttpRequest>(request);
    container.instance<HttpResponse>(response);

    // Register request/response services that need to be constructed
    container.bind<Request>((c) async {
      final req = await c.make<HttpRequest>();
      final config = await c.make<EngineConfig>();
      return Request(req, {}, config);
    }, singleton: true);

    container.bind<Response>((c) async {
      // ignore: close_sinks
      final res = await c.make<HttpResponse>();
      return Response(res);
    }, singleton: true);

    container.bind<EngineContext>((c) async {
      final req = await c.make<Request>();
      final res = await c.make<Response>();
      final engine = await c.make<Engine>();
      return EngineContext(
        request: req,
        response: res,
        engine: engine,
        container: c,
      );
    }, singleton: true);
  }

  @override
  Future<void> cleanup(Container container) async {
    await response.close();
  }
}
