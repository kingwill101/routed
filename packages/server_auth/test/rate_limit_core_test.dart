import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

final class _BlockingLimiter implements AuthRateLimiter<String> {
  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<String> request) {
    return const AuthRateLimitDecision.block(retryAfter: Duration(seconds: 12));
  }
}

void main() {
  test('endpoint limiter identifiers are trimmed and absolutely bounded', () {
    expect(
      normalizeAuthRateLimitIdentifier('  canonical-user  '),
      'canonical-user',
    );
    expect(normalizeAuthRateLimitIdentifier(''), isNull);
    expect(normalizeAuthRateLimitIdentifier('   '), isNull);
    expect(normalizeAuthRateLimitIdentifier('user\r\nsecret'), isNull);
    expect(
      normalizeAuthRateLimitIdentifier(
        'a' * (authRateLimitIdentifierMaximumLength + 1),
      ),
      isNull,
    );
    expect(
      normalizeAuthRateLimitIdentifier(
        'a' * authRateLimitIdentifierMaximumLength,
      ),
      hasLength(authRateLimitIdentifierMaximumLength),
    );
  });

  test('typed endpoint resolver sees decoded input and fails closed', () {
    final endpoint =
        TypedAuthEndpointDescriptor<String, _LimiterInput, Object?>(
          id: 'sample.limit',
          method: AuthOperationMethod.post,
          path: '/sample',
          semantics: const AuthOperationSemantics.readOnly(),
          requestCodec: AuthOperationCodec<_LimiterInput>(
            schema: const <String, Object?>{},
            decode: (json) => _LimiterInput(json['value'] as String),
            encode: (value) => <String, dynamic>{'value': value.value},
          ),
          responseCodec: AuthOperationCodec<Object?>(
            schema: const <String, Object?>{},
            decode: (json) => json,
            encode: (value) => value,
          ),
          rateLimitIdentifier: (request) => request.value.toLowerCase(),
          handler: (_, _) => null,
        );

    expect(
      endpoint.resolveRateLimitIdentifier({'value': '  ALICE  '}),
      'alice',
    );
    expect(endpoint.resolveRateLimitIdentifier(const {}), isNull);
    expect(endpoint.resolveRateLimitIdentifier({'value': 7}), isNull);
  });

  test('rate-limit requests expose only non-secret auth context', () async {
    final request = const AuthRateLimitRequest<String>(
      action: AuthRateLimitAction.signIn,
      providerId: 'credentials',
      context: 'request-context',
      identifier: 'alice@example.test',
    );
    AuthRateLimitRequest<String>? observed;

    final limiter = _RecordingLimiter((value) {
      observed = value;
      return const AuthRateLimitDecision.allow();
    });

    await enforceAuthRateLimit(limiter: limiter, request: request);

    expect(observed?.action, AuthRateLimitAction.signIn);
    expect(observed?.providerId, 'credentials');
    expect(observed?.context, 'request-context');
    expect(observed?.identifier, 'alice@example.test');
  });

  test('blocked decisions become a stable rate-limited flow error', () async {
    expect(
      () => enforceAuthRateLimit(
        limiter: _BlockingLimiter(),
        request: const AuthRateLimitRequest<String>(
          action: AuthRateLimitAction.oauthCallback,
          providerId: 'github',
          context: 'request-context',
        ),
      ),
      throwsA(
        isA<AuthRateLimitException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          const Duration(seconds: 12),
        ),
      ),
    );
  });

  test('auth error status maps rate limiting to 429', () {
    expect(authErrorStatusCode('rate_limited'), 429);
  });
}

final class _LimiterInput {
  const _LimiterInput(this.value);

  final String value;
}

final class _RecordingLimiter implements AuthRateLimiter<String> {
  _RecordingLimiter(this._callback);

  final AuthRateLimitDecision Function(AuthRateLimitRequest<String>) _callback;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<String> request) =>
      _callback(request);
}
