import 'package:routed/src/context/context.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';

/// Internal request-scoped storage for fast-path mode.
class RequestScope {
  const RequestScope({
    required this.request,
    required this.response,
    required this.context,
  });

  final Request request;
  final Response response;
  final EngineContext context;
}

final Expando<RequestScope> requestScopeExpando = Expando<RequestScope>(
  'routed.request_scope',
);
