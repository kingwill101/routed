/// Portable rate-limiting policies, algorithms, backends, and services.
///
/// Build a [RateLimitPolicySpec] for each protected route, compile the
/// specifications with a [RateLimiterBackend], and pass the resulting
/// policies to [RateLimitService]. The service evaluates matching policies in
/// declaration order and returns the first blocking [RateLimitOutcome].
///
/// A backend owns persistence and concurrency. Use
/// [CacheRateLimiterBackend] with a [Repository] whose store implements
/// [LockProvider] when multiple requests or isolates must update a bucket
/// atomically. Choose [RateLimitFailoverMode] explicitly for the behavior you
/// want when that backend is unavailable.

library;

import 'package:server_contracts/server_contracts.dart'
    show LockProvider, Repository;

import 'package:server_rate_limit/src/backend.dart'
    show CacheRateLimiterBackend, RateLimiterBackend;
import 'package:server_rate_limit/src/compiler.dart' show RateLimitPolicySpec;
import 'package:server_rate_limit/src/policy.dart'
    show RateLimitFailoverMode, RateLimitOutcome;
import 'package:server_rate_limit/src/service.dart' show RateLimitService;

export 'src/policy.dart';
export 'src/rate_limit.dart';
export 'src/service.dart';
