import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import 'plugin.dart';
import 'tokens.dart' show base64UrlNoPadding, constantTimeStringEquals;

const String authLastAuthenticationMethodPluginId =
    'last_authentication_method';

/// A bounded, stable identifier for one authentication method.
///
/// This value is deliberately not an account, provider response, credential,
/// token, or user identifier. OAuth providers are represented as the stable
/// namespace `oauth:<provider>`.
final class AuthLastAuthenticationMethodId {
  static const int maximumLength = 64;
  static final RegExp _identifierPattern = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');
  static final RegExp _oauthProviderPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]{0,31}$',
  );

  static const credentials = AuthLastAuthenticationMethodId._('credentials');
  static const usernamePassword = AuthLastAuthenticationMethodId._(
    'username_password',
  );
  static const phone = AuthLastAuthenticationMethodId._('phone');
  static const emailOtp = AuthLastAuthenticationMethodId._('email_otp');
  static const anonymous = AuthLastAuthenticationMethodId._('anonymous');
  static const passkey = AuthLastAuthenticationMethodId._('passkey');

  const AuthLastAuthenticationMethodId._(this.value);

  /// Parses one canonical method ID and rejects delimiters or control input.
  factory AuthLastAuthenticationMethodId.parse(String value) {
    final candidate = value;
    if (candidate.startsWith('oauth:')) {
      final provider = candidate.substring('oauth:'.length);
      if (!_oauthProviderPattern.hasMatch(provider)) {
        throw FormatException('Invalid OAuth provider namespace');
      }
      return AuthLastAuthenticationMethodId._(candidate);
    }
    if (!_identifierPattern.hasMatch(candidate)) {
      throw FormatException('Invalid authentication method identifier');
    }
    return AuthLastAuthenticationMethodId._(candidate);
  }

  /// Creates an OAuth namespace without accepting an arbitrary provider
  /// payload or path-like value.
  factory AuthLastAuthenticationMethodId.oauthProvider(String provider) {
    final candidate = provider.trim().toLowerCase();
    if (!_oauthProviderPattern.hasMatch(candidate)) {
      throw FormatException('Invalid OAuth provider namespace');
    }
    return AuthLastAuthenticationMethodId._('oauth:$candidate');
  }

  /// Maps the generic host lifecycle labels to canonical method IDs.
  static AuthLastAuthenticationMethodId? fromLifecycle({
    required String? authenticationMethod,
    String? oauthProviderNamespace,
  }) {
    final oauthProvider = oauthProviderNamespace?.trim();
    if (oauthProvider != null && oauthProvider.isNotEmpty) {
      try {
        return AuthLastAuthenticationMethodId.oauthProvider(oauthProvider);
      } on FormatException {
        return null;
      }
    }

    final candidate = authenticationMethod?.trim();
    if (candidate == null || candidate.isEmpty) return null;
    switch (candidate) {
      case 'credentials':
        return credentials;
      case 'username_password':
        return usernamePassword;
      case 'phone':
      case 'phone_number':
        return phone;
      case 'email_otp':
        return emailOtp;
      case 'anonymous':
        return anonymous;
      case 'passkey':
      case 'webauthn':
        return passkey;
      default:
        try {
          return AuthLastAuthenticationMethodId.parse(candidate);
        } on FormatException {
          return null;
        }
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AuthLastAuthenticationMethodId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum AuthLastAuthenticationMethodBrowserPersistence { session, persistent }

enum AuthLastAuthenticationMethodSameSite { lax, strict }

/// Explicit policy for the last-method browser state.
final class AuthLastAuthenticationMethodPolicy {
  AuthLastAuthenticationMethodPolicy({
    required Iterable<AuthLastAuthenticationMethodId> allowedMethods,
    this.retention = const Duration(days: 30),
    this.browserPersistence =
        AuthLastAuthenticationMethodBrowserPersistence.persistent,
    this.maximumStateBytes = 512,
    this.cookieName = '__Host-routed_last_auth_method',
    this.cookiePath = '/',
    this.sameSite = AuthLastAuthenticationMethodSameSite.lax,
  }) : allowedMethods = Set<AuthLastAuthenticationMethodId>.unmodifiable(
         allowedMethods,
       ) {
    if (this.allowedMethods.isEmpty) {
      throw ArgumentError.value(
        allowedMethods,
        'allowedMethods',
        'must contain at least one method',
      );
    }
    if (retention < const Duration(seconds: 1) ||
        retention > const Duration(days: 365)) {
      throw ArgumentError.value(
        retention,
        'retention',
        'must be between one second and 365 days',
      );
    }
    if (maximumStateBytes < 128 || maximumStateBytes > 2048) {
      throw ArgumentError.value(
        maximumStateBytes,
        'maximumStateBytes',
        'must be between 128 and 2048',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(cookieName)) {
      throw ArgumentError.value(cookieName, 'cookieName', 'is not a safe name');
    }
    if (!cookiePath.startsWith('/') ||
        cookiePath.length > 256 ||
        cookiePath.contains(';') ||
        cookiePath.runes.any((value) => value < 0x20 || value == 0x7f)) {
      throw ArgumentError.value(cookiePath, 'cookiePath', 'is not a safe path');
    }
    if (cookieName.startsWith('__Host-') && cookiePath != '/') {
      throw ArgumentError.value(
        cookiePath,
        'cookiePath',
        'must be / for a __Host- cookie',
      );
    }
  }

  final Set<AuthLastAuthenticationMethodId> allowedMethods;
  final Duration retention;
  final AuthLastAuthenticationMethodBrowserPersistence browserPersistence;
  final int maximumStateBytes;
  final String cookieName;
  final String cookiePath;
  final AuthLastAuthenticationMethodSameSite sameSite;

  /// These flags are fixed by the plugin contract and cannot be relaxed by a
  /// caller through the policy object.
  bool get secureCookie => true;
  bool get httpOnlyCookie => true;
}

/// Host-owned browser cookie instructions produced by the plugin.
final class AuthLastAuthenticationMethodCookie {
  AuthLastAuthenticationMethodCookie({
    required this.name,
    required this.value,
    required this.path,
    required this.sameSite,
    this.maxAge,
    this.secure = true,
    this.httpOnly = true,
  }) {
    if (!secure || !httpOnly) {
      throw ArgumentError('The last-method cookie must be Secure and HttpOnly');
    }
  }

  final String name;
  final String value;
  final String path;
  final AuthLastAuthenticationMethodSameSite sameSite;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;
}

/// Minimal host adapter used by the portable plugin to own one browser cookie.
abstract interface class AuthLastAuthenticationMethodBrowserStore<TContext> {
  String? readCookie(TContext context, String name);

  void writeCookie(TContext context, AuthLastAuthenticationMethodCookie cookie);
}

/// Public, typed result returned by the server and client read APIs.
final class AuthLastAuthenticationMethodReadResult {
  const AuthLastAuthenticationMethodReadResult({
    required this.method,
    required this.expiresAt,
  });

  final AuthLastAuthenticationMethodId method;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'method': method.value,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory AuthLastAuthenticationMethodReadResult.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json.length != 2 ||
        !json.containsKey('method') ||
        !json.containsKey('expiresAt')) {
      throw const FormatException('Invalid last authentication method result');
    }
    final methodValue = json['method'];
    final expiresAtValue = json['expiresAt'];
    if (methodValue is! String || expiresAtValue is! String) {
      throw const FormatException('Invalid last authentication method result');
    }
    final method = AuthLastAuthenticationMethodId.parse(methodValue);
    final expiresAt = DateTime.tryParse(expiresAtValue);
    if (expiresAt == null) {
      throw const FormatException('Invalid last authentication method expiry');
    }
    return AuthLastAuthenticationMethodReadResult(
      method: method,
      expiresAt: expiresAt.toUtc(),
    );
  }
}

/// Opt-in server plugin that records only a signed, bounded method ID.
final class AuthLastAuthenticationMethodPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthClientOperationContributor,
        AuthAuthenticationLifecycleContributor<TContext> {
  AuthLastAuthenticationMethodPlugin({
    required String signingKey,
    required this.browserStore,
    required this.policy,
    DateTime Function()? clock,
  }) : _signingKey = List<int>.unmodifiable(utf8.encode(signingKey)),
       _clock = clock ?? DateTime.now {
    if (_signingKey.length < 32 || _signingKey.length > 256) {
      throw ArgumentError(
        'signingKey must contain between 32 and 256 UTF-8 bytes',
      );
    }
  }

  final AuthLastAuthenticationMethodBrowserStore<TContext> browserStore;
  final AuthLastAuthenticationMethodPolicy policy;
  final List<int> _signingKey;
  final DateTime Function() _clock;

  @override
  String get id => authLastAuthenticationMethodPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {}

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      const <AuthClientOperationDescriptor>[
        AuthClientOperationDescriptor(
          id: 'lastAuthenticationMethod.read',
          method: AuthOperationMethod.get,
          path: '/last-authentication-method',
        ),
      ];

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      <AuthEndpointDescriptor<TContext>>[
        TypedAuthEndpointDescriptor<
          TContext,
          Map<String, dynamic>,
          AuthLastAuthenticationMethodReadResult?
        >(
          id: 'lastAuthenticationMethod.read',
          method: AuthOperationMethod.get,
          path: '/last-authentication-method',
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          requestCodec: _requestCodec,
          responseCodec: _responseCodec,
          handler: (invocation, _) => read(invocation.context),
        ),
      ];

  @override
  Future<void> onAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<TContext> event,
  ) async {
    switch (event.type) {
      case AuthAuthenticationLifecycleEventType.authenticationSucceeded:
        final method = AuthLastAuthenticationMethodId.fromLifecycle(
          authenticationMethod: event.authenticationMethod,
          oauthProviderNamespace: event.oauthProviderNamespace,
        );
        if (method == null || !policy.allowedMethods.contains(method)) return;

        final now = _clock().toUtc();
        final expiresAt = now.add(policy.retention);
        final state = _encode(method, expiresAt);
        if (state.length > policy.maximumStateBytes) return;
        _writeCookie(
          event.context,
          AuthLastAuthenticationMethodCookie(
            name: policy.cookieName,
            value: state,
            path: policy.cookiePath,
            sameSite: policy.sameSite,
            secure: policy.secureCookie,
            httpOnly: policy.httpOnlyCookie,
            maxAge:
                policy.browserPersistence ==
                    AuthLastAuthenticationMethodBrowserPersistence.persistent
                ? policy.retention.inSeconds
                : null,
          ),
        );
      case AuthAuthenticationLifecycleEventType.signedOut:
      case AuthAuthenticationLifecycleEventType.accountDeleted:
        _clear(event.context);
    }
  }

  /// Reads and verifies the cookie without exposing its signed contents.
  Future<AuthLastAuthenticationMethodReadResult?> read(TContext context) async {
    String? raw;
    try {
      raw = browserStore.readCookie(context, policy.cookieName);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;

    final state = _decode(raw);
    if (state == null || !policy.allowedMethods.contains(state.method)) {
      _clear(context);
      return null;
    }
    return AuthLastAuthenticationMethodReadResult(
      method: state.method,
      expiresAt: state.expiresAt,
    );
  }

  String _encode(AuthLastAuthenticationMethodId method, DateTime expiresAt) {
    final payload =
        'v1|${method.value}|${expiresAt.toUtc().microsecondsSinceEpoch}';
    final body = base64UrlNoPadding(utf8.encode(payload));
    final signature = base64UrlNoPadding(
      Hmac(sha256, _signingKey).convert(utf8.encode(body)).bytes,
    );
    return '$body.$signature';
  }

  _AuthLastAuthenticationMethodState? _decode(String raw) {
    if (raw.isEmpty || raw.length > policy.maximumStateBytes) return null;
    final parts = raw.split('.');
    if (parts.length != 2) return null;
    final body = parts[0];
    final signature = parts[1];
    if (!_isBase64Url(body) || !_isBase64Url(signature)) return null;
    final expected = base64UrlNoPadding(
      Hmac(sha256, _signingKey).convert(utf8.encode(body)).bytes,
    );
    if (!constantTimeStringEquals(expected, signature)) return null;

    final payloadBytes = _decodeBase64Url(body);
    if (payloadBytes == null) return null;
    late final String payload;
    try {
      payload = utf8.decode(payloadBytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
    final fields = payload.split('|');
    if (fields.length != 3 || fields[0] != 'v1') return null;
    final method = AuthLastAuthenticationMethodId.fromLifecycle(
      authenticationMethod: fields[1],
    );
    if (method == null) return null;
    final microseconds = int.tryParse(fields[2]);
    if (microseconds == null || microseconds <= 0) return null;
    final expiresAt = DateTime.fromMicrosecondsSinceEpoch(
      microseconds,
      isUtc: true,
    );
    final now = _clock().toUtc();
    if (!now.isBefore(expiresAt) ||
        expiresAt.isAfter(now.add(policy.retention))) {
      return null;
    }
    return _AuthLastAuthenticationMethodState(
      method: method,
      expiresAt: expiresAt,
    );
  }

  void _clear(TContext context) {
    _writeCookie(
      context,
      AuthLastAuthenticationMethodCookie(
        name: policy.cookieName,
        value: '',
        path: policy.cookiePath,
        sameSite: policy.sameSite,
        secure: policy.secureCookie,
        httpOnly: policy.httpOnlyCookie,
        maxAge: 0,
      ),
    );
  }

  void _writeCookie(
    TContext context,
    AuthLastAuthenticationMethodCookie cookie,
  ) {
    try {
      browserStore.writeCookie(context, cookie);
    } catch (_) {
      // This plugin runs after host-owned session/JWT lifecycle work. Optional
      // browser-state persistence must never invalidate completed auth work.
    }
  }

  static bool _isBase64Url(String value) =>
      value.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static List<int>? _decodeBase64Url(String value) {
    final padding = (4 - value.length % 4) % 4;
    try {
      return base64Url.decode('$value${'=' * padding}');
    } on FormatException {
      return null;
    }
  }

  static final AuthOperationCodec<Map<String, dynamic>> _requestCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
        schema: <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
        },
      );

  static final AuthOperationCodec<AuthLastAuthenticationMethodReadResult?>
  _responseCodec = AuthOperationCodec<AuthLastAuthenticationMethodReadResult?>(
    decode: AuthLastAuthenticationMethodReadResult.fromJson,
    encode: (value) => value?.toJson(),
    schema: <String, Object?>{
      'oneOf': <Map<String, Object?>>[
        <String, Object?>{'type': 'null'},
        <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['method', 'expiresAt'],
          'properties': <String, Object?>{
            'method': <String, Object?>{
              'type': 'string',
              'maxLength': AuthLastAuthenticationMethodId.maximumLength,
            },
            'expiresAt': <String, Object?>{'type': 'string'},
          },
        },
      ],
    },
  );
}

final class _AuthLastAuthenticationMethodState {
  const _AuthLastAuthenticationMethodState({
    required this.method,
    required this.expiresAt,
  });

  final AuthLastAuthenticationMethodId method;
  final DateTime expiresAt;
}
