import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/request.dart';
import 'package:routed_core/src/response.dart';

/// Internal request-scoped storage for fast-path mode.
class RequestScope {
  /// Creates request-scoped state for [request], [response], and [context].
  const RequestScope({
    required this.request,
    required this.response,
    required this.context,
  });

  /// The request associated with this scope.
  final Request request;

  /// The response associated with this scope.
  final Response response;

  /// The context associated with this scope.
  final EngineContext context;
}

/// Associates request-scoped state with a request object in fast-path mode.
final Expando<RequestScope> requestScopeExpando = Expando<RequestScope>(
  'routed.request_scope',
);
