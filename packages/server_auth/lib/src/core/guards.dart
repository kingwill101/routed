import 'dart:async';

/// Result for a guard evaluation.
class GuardResult<TResponse> {
  const GuardResult.allow() : allowed = true, response = null;

  const GuardResult.deny([this.response]) : allowed = false;

  final bool allowed;
  final TResponse? response;
}

/// Guard callback contract.
typedef AuthGuard<TContext, TResponse> =
    FutureOr<GuardResult<TResponse>> Function(TContext ctx);
