import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'tokens.dart' show hashOpaqueToken, secureRandomToken;

/// Attribute key used to store the authenticated principal in request context.
const String authPrincipalAttribute = 'auth.principal';

/// Session key used to store auth session issued-at timestamps.
const String authSessionIssuedAtKey = '_auth.session.issued_at';

/// Parses an ISO-8601 session issued-at timestamp into UTC.
DateTime? parseAuthSessionIssuedAt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

/// Session refresh action derived from issued-at metadata.
enum AuthSessionRefreshAction {
  /// Initializes missing issued-at metadata.
  initialize,

  /// Refreshes metadata that has reached its update threshold.
  refresh,

  /// Keeps issued-at metadata that is still within its update interval.
  keep,
}

/// Serializes issued-at timestamps for auth session metadata.
///
/// Converts [issuedAt] to UTC before producing an ISO-8601 string.
String serializeAuthSessionIssuedAt(DateTime issuedAt) {
  return issuedAt.toUtc().toIso8601String();
}

/// Returns whether a session has reached its refresh threshold.
///
/// The comparison is inclusive: a session refreshes when elapsed time is
/// greater than or equal to [updateAge]. Both [issuedAt] and [now] are
/// compared in UTC; no validation is performed on a negative duration.
bool shouldRefreshAuthSession(
  DateTime issuedAt,
  Duration updateAge, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  return current.difference(issuedAt.toUtc()) >= updateAge;
}

/// Decides how auth session issued-at metadata should be updated.
///
/// A null, empty, or malformed [issuedAtValue] selects
/// [AuthSessionRefreshAction.initialize]. Valid values select
/// [AuthSessionRefreshAction.refresh] when [updateAge] has elapsed and
/// [AuthSessionRefreshAction.keep] otherwise.
AuthSessionRefreshAction authSessionRefreshAction({
  required String? issuedAtValue,
  required Duration updateAge,
  DateTime? now,
}) {
  final issuedAt = parseAuthSessionIssuedAt(issuedAtValue);
  if (issuedAt == null) {
    return AuthSessionRefreshAction.initialize;
  }
  return shouldRefreshAuthSession(issuedAt, updateAge, now: now)
      ? AuthSessionRefreshAction.refresh
      : AuthSessionRefreshAction.keep;
}

/// Applies issued-at refresh semantics through write and touch callbacks.
///
/// Returns without invoking a callback when [updateAge] is null. Initialization
/// and refresh write the current UTC time; refresh also invokes [touchSession]
/// when supplied.
void syncAuthSessionRefresh({
  required String? issuedAtValue,
  required Duration? updateAge,
  DateTime? now,
  required void Function(DateTime issuedAtUtc) writeIssuedAt,
  void Function()? touchSession,
}) {
  final age = updateAge;
  if (age == null) {
    return;
  }

  final current = (now ?? DateTime.now()).toUtc();
  final action = authSessionRefreshAction(
    issuedAtValue: issuedAtValue,
    updateAge: age,
    now: current,
  );

  switch (action) {
    case AuthSessionRefreshAction.initialize:
      writeIssuedAt(current);
      return;
    case AuthSessionRefreshAction.refresh:
      writeIssuedAt(current);
      touchSession?.call();
      return;
    case AuthSessionRefreshAction.keep:
      return;
  }
}

/// Resolves an auth session expiry from explicit or cookie max-age settings.
///
/// [sessionMaxAge] takes precedence, including non-positive values. When it is
/// absent, only a positive [sessionOptionsMaxAgeSeconds] produces an expiry;
/// otherwise the result is null. The optional [now] is used as supplied.
DateTime? resolveAuthSessionExpiry({
  Duration? sessionMaxAge,
  int? sessionOptionsMaxAgeSeconds,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (sessionMaxAge != null) {
    return current.add(sessionMaxAge);
  }
  final maxAge = sessionOptionsMaxAgeSeconds;
  if (maxAge == null || maxAge <= 0) {
    return null;
  }
  return current.add(Duration(seconds: maxAge));
}

/// Returns positive whole seconds represented by [sessionMaxAge].
///
/// Returns null for null, zero, negative, and sub-second durations.
int? resolveAuthSessionMaxAgeSeconds(Duration? sessionMaxAge) {
  if (sessionMaxAge == null) {
    return null;
  }
  final seconds = sessionMaxAge.inSeconds;
  if (seconds <= 0) {
    return null;
  }
  return seconds;
}

/// Builds a remember-token cookie with the supplied lifetime and attributes.
///
/// Preserves [token] as the cookie value. [domain] is omitted when null or
/// empty, and [secure] is set only when true. [httpOnly] defaults to true.
Cookie buildRememberTokenCookie(
  String cookieName,
  String token, {
  required DateTime expiresAt,
  String path = '/',
  String? domain,
  bool secure = false,
  SameSite? sameSite,
  bool httpOnly = true,
}) {
  final cookie = Cookie(cookieName, token)
    ..httpOnly = httpOnly
    ..expires = expiresAt
    ..path = path;
  if (domain != null && domain.isNotEmpty) {
    cookie.domain = domain;
  }
  if (secure) {
    cookie.secure = true;
  }
  if (sameSite != null) {
    cookie.sameSite = sameSite;
  }
  return cookie;
}

/// Builds an expired remember-token cookie for logout or invalidation.
///
/// The value is empty, the expiry is the Unix epoch, and `maxAge` is zero.
Cookie buildExpiredRememberTokenCookie(
  String cookieName, {
  String path = '/',
  String? domain,
  bool secure = false,
  SameSite? sameSite,
  bool httpOnly = true,
}) {
  final cookie = buildRememberTokenCookie(
    cookieName,
    '',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    path: path,
    domain: domain,
    secure: secure,
    sameSite: sameSite,
    httpOnly: httpOnly,
  );
  cookie.maxAge = 0;
  return cookie;
}

/// Persistence contract for long-lived "remember me" tokens.
///
/// Implementations must treat [token] as a secret: persist only a digest and
/// compare the digest during [read], [consume], and [remove]. Never log or
/// expose the raw token from a persistence adapter.
abstract class RememberTokenStore {
  /// Saves [principal] for the raw [token] until [expiresAt].
  ///
  /// Implementations must hash [token] before persistence and should ignore or
  /// reject records that are already expired.
  FutureOr<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  );

  /// Reads the principal for [token], or returns null when it is unknown or
  /// expired.
  FutureOr<AuthPrincipal?> read(String token);

  /// Atomically consumes [token] for one request and invalidates it.
  ///
  /// Persistent implementations must perform the lookup, expiry check, and
  /// deletion in one transaction or compare-and-delete operation. A
  /// read-then-remove implementation is not replay-safe under concurrency.
  FutureOr<AuthPrincipal?> consume(String token);

  /// Removes [token] without exposing whether it was present.
  FutureOr<void> remove(String token);
}

/// Bounded, process-local storage for remember-me tokens.
class InMemoryRememberTokenStore implements RememberTokenStore {
  /// Creates a store with an optional clock and positive [maxEntries] limit.
  ///
  /// Throws an [ArgumentError] when [maxEntries] is less than one. Expired
  /// records are pruned during reads and writes, and the oldest record is
  /// evicted when the limit is reached.
  InMemoryRememberTokenStore({
    DateTime Function()? clock,
    this.maxEntries = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Map<String, _RememberRecord> _storage = <String, _RememberRecord>{};
  final DateTime Function() _clock;

  /// Maximum number of remember-me tokens retained by this local store.
  ///
  /// Expired records are removed during [save], [read], and [consume]. If the
  /// store is full, the oldest record is evicted. Durable stores should
  /// enforce equivalent expiry and capacity policies in persistence.
  final int maxEntries;

  /// Stores a digest of [token] and a defensive copy of [principal].
  ///
  /// Blank tokens or principal IDs throw an [ArgumentError]. Already-expired
  /// records are ignored.
  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) async {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'must be non-empty');
    }
    if (principal.id.trim().isEmpty) {
      throw ArgumentError.value(
        principal.id,
        'principal.id',
        'must be non-empty',
      );
    }
    final now = _clock().toUtc();
    _removeExpired(now);
    if (!now.isBefore(expiresAt.toUtc())) {
      return;
    }
    final tokenHash = hashOpaqueToken(token);
    _storage.remove(tokenHash);
    while (_storage.length >= maxEntries) {
      _removeOldest();
    }
    _storage[tokenHash] = _RememberRecord(
      _safePrincipal(principal),
      expiresAt.toUtc(),
    );
  }

  /// Returns the stored principal for [token], or null when unavailable.
  @override
  Future<AuthPrincipal?> read(String token) async {
    if (token.trim().isEmpty) return null;
    final now = _clock().toUtc();
    _removeExpired(now);
    final tokenHash = hashOpaqueToken(token);
    final record = _storage[tokenHash];
    if (record == null) return null;
    return record.principal;
  }

  /// Returns and removes the principal for [token] exactly once.
  @override
  Future<AuthPrincipal?> consume(String token) async {
    if (token.trim().isEmpty) return null;
    final now = _clock().toUtc();
    _removeExpired(now);
    final record = _storage.remove(hashOpaqueToken(token));
    if (record == null) {
      return null;
    }
    return record.principal;
  }

  /// Removes [token] from the store when it is present.
  @override
  Future<void> remove(String token) async {
    if (token.trim().isEmpty) return;
    _storage.remove(hashOpaqueToken(token));
  }

  void _removeExpired(DateTime now) {
    _storage.removeWhere((_, record) => !now.isBefore(record.expiresAt));
  }

  void _removeOldest() {
    if (_storage.isNotEmpty) {
      _storage.remove(_storage.keys.first);
    }
  }
}

class _RememberRecord {
  _RememberRecord(this.principal, this.expiresAt);

  final AuthPrincipal principal;
  final DateTime expiresAt;
}

/// Adapter used by [RememberSessionAuthRuntime] to read/write framework state.
abstract class AuthSessionRuntimeAdapter<TContext> {
  /// Reads a cached principal attribute from [context].
  AuthPrincipal? readPrincipalAttribute(TContext context, String attributeKey);

  /// Writes or clears a cached principal attribute on [context].
  void writePrincipalAttribute(
    TContext context,
    String attributeKey,
    AuthPrincipal? principal,
  );

  /// Reads the serialized principal stored in the framework session.
  Map<String, dynamic>? readSessionPrincipal(
    TContext context,
    String sessionKey,
  );

  /// Writes or clears the serialized principal in the framework session.
  void writeSessionPrincipal(
    TContext context,
    String sessionKey,
    Map<String, dynamic>? principalJson,
  );

  /// Returns cookies received with the request.
  Iterable<Cookie> requestCookies(TContext context);

  /// Adds [cookie] to the response.
  void setResponseCookie(TContext context, Cookie cookie);

  /// Builds a remember cookie using the framework's cookie policy.
  Cookie buildRememberCookie(
    TContext context,
    String cookieName,
    String token,
    DateTime expiresAt,
  );

  /// Builds an expired remember cookie using the framework's cookie policy.
  Cookie buildExpiredRememberCookie(TContext context, String cookieName);
}

/// Framework-agnostic remember-me and session-principal runtime.
///
/// Framework adapters are responsible for providing a concrete
/// [AuthSessionRuntimeAdapter] that maps framework request/session/cookie
/// semantics to this runtime.
class RememberSessionAuthRuntime<TContext> {
  /// Creates a runtime with framework [adapter] and remember-token settings.
  ///
  /// Uses [InMemoryRememberTokenStore] when [rememberStore] is omitted. Throws
  /// an [ArgumentError] when [defaultRememberDuration] is not positive.
  RememberSessionAuthRuntime({
    required this.adapter,
    RememberTokenStore? rememberStore,
    this.rememberCookieName = 'remember_token',
    this.defaultRememberDuration = const Duration(days: 30),
    this.sessionPrincipalKey = '__auth.principal',
    this.principalAttributeKey = authPrincipalAttribute,
    this.tokenGenerator = secureRandomToken,
    this.regenerateSession,
    DateTime Function()? clock,
  }) : rememberStore =
           rememberStore ??
           InMemoryRememberTokenStore(clock: clock ?? DateTime.now),
       _clock = clock ?? DateTime.now {
    if (defaultRememberDuration <= Duration.zero) {
      throw ArgumentError.value(
        defaultRememberDuration,
        'defaultRememberDuration',
        'must be greater than zero',
      );
    }
  }

  /// Adapter that maps framework request, session, and response state.
  final AuthSessionRuntimeAdapter<TContext> adapter;

  /// Store used for hashed remember-me tokens.
  final RememberTokenStore rememberStore;

  /// Name of the remember-me cookie.
  final String rememberCookieName;

  /// Lifetime assigned to rotated remember tokens during hydration.
  final Duration defaultRememberDuration;

  /// Session key containing the serialized principal.
  final String sessionPrincipalKey;

  /// Request attribute key containing the cached principal.
  final String principalAttributeKey;

  /// Generates raw remember tokens before they are persisted by the store.
  final String Function() tokenGenerator;

  /// Optional callback that rotates the framework session before login.
  final void Function(TContext context)? regenerateSession;

  final DateTime Function() _clock;

  /// Logs in [principal] and stores it in the session and request context.
  ///
  /// When [rotateSession] is true, the runtime invokes [regenerateSession]
  /// before writing state. [rememberMe] saves a one-time-rotated token using
  /// [rememberDuration] or [defaultRememberDuration]; a non-positive duration
  /// throws an [ArgumentError]. A non-remembered rotating login revokes any
  /// existing remember cookie.
  Future<void> login(
    TContext context,
    AuthPrincipal principal, {
    bool rememberMe = false,
    Duration? rememberDuration,
    bool rotateSession = true,
  }) async {
    final safePrincipal = _safePrincipal(principal);
    if (safePrincipal.id.trim().isEmpty) {
      throw ArgumentError.value(
        principal.id,
        'principal.id',
        'must be non-empty',
      );
    }
    if (rotateSession) {
      regenerateSession?.call(context);
    }
    adapter.writeSessionPrincipal(
      context,
      sessionPrincipalKey,
      safePrincipal.toJson(),
    );
    adapter.writePrincipalAttribute(
      context,
      principalAttributeKey,
      safePrincipal,
    );

    if (!rememberMe) {
      if (rotateSession) {
        final existing = _findRequestCookie(context);
        if (existing != null && existing.value.isNotEmpty) {
          await Future.sync(() => rememberStore.remove(existing.value));
          adapter.setResponseCookie(
            context,
            adapter.buildExpiredRememberCookie(context, rememberCookieName),
          );
        }
      }
      return;
    }

    final duration = rememberDuration ?? defaultRememberDuration;
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'rememberDuration',
        'must be greater than zero',
      );
    }

    final existing = _findRequestCookie(context);
    if (existing != null && existing.value.isNotEmpty) {
      await Future.sync(() => rememberStore.remove(existing.value));
    }

    final token = _generatedRememberToken();
    final expiresAt = _clock().add(duration);
    await Future.sync(
      () => rememberStore.save(token, safePrincipal, expiresAt),
    );
    adapter.setResponseCookie(
      context,
      adapter.buildRememberCookie(
        context,
        rememberCookieName,
        token,
        expiresAt,
      ),
    );
  }

  /// Clears session and request principal state and expires the remember cookie.
  ///
  /// If the request contains a remember token, it is removed from
  /// [rememberStore] before the expired cookie is added to the response.
  Future<void> logout(TContext context) async {
    adapter.writeSessionPrincipal(context, sessionPrincipalKey, null);
    adapter.writePrincipalAttribute(context, principalAttributeKey, null);

    final cookie = _findRequestCookie(context);
    if (cookie != null && cookie.value.isNotEmpty) {
      await Future.sync(() => rememberStore.remove(cookie.value));
    }
    adapter.setResponseCookie(
      context,
      adapter.buildExpiredRememberCookie(context, rememberCookieName),
    );
  }

  /// Returns the cached or session-backed principal for [context].
  ///
  /// A cached request attribute takes precedence. A serialized session
  /// principal is decoded and cached; absent data returns null.
  AuthPrincipal? current(TContext context) {
    final cached = adapter.readPrincipalAttribute(
      context,
      principalAttributeKey,
    );
    if (cached != null) {
      return _safePrincipal(cached);
    }

    final stored = adapter.readSessionPrincipal(context, sessionPrincipalKey);
    if (stored == null) {
      return null;
    }

    final principal = AuthPrincipal.fromJson(stored);
    adapter.writePrincipalAttribute(context, principalAttributeKey, principal);
    return principal;
  }

  /// Hydrates the auth principal from session or remember-token state.
  ///
  /// An existing session principal only refreshes the request attribute. When
  /// no session principal exists, [RememberTokenStore.consume] atomically consumes a
  /// request token; a valid token is replaced with a new token using
  /// [defaultRememberDuration], while an invalid or expired token is removed and
  /// its cookie expired. This prevents concurrent replay of a remembered login.
  Future<void> hydrate(TContext context) async {
    final sessionData = adapter.readSessionPrincipal(
      context,
      sessionPrincipalKey,
    );
    if (sessionData != null) {
      adapter.writePrincipalAttribute(
        context,
        principalAttributeKey,
        AuthPrincipal.fromJson(sessionData),
      );
      return;
    }

    final rememberCookie = _findRequestCookie(context);
    if (rememberCookie == null || rememberCookie.value.isEmpty) {
      return;
    }

    final principal = await Future.sync(
      () => rememberStore.consume(rememberCookie.value),
    );
    if (principal == null) {
      await Future.sync(() => rememberStore.remove(rememberCookie.value));
      adapter.setResponseCookie(
        context,
        adapter.buildExpiredRememberCookie(context, rememberCookieName),
      );
      return;
    }

    final safePrincipal = _safePrincipal(principal);
    final rotatedToken = _generatedRememberToken();
    final newExpiry = _clock().add(defaultRememberDuration);
    await Future.sync(
      () => rememberStore.save(rotatedToken, safePrincipal, newExpiry),
    );
    adapter.writeSessionPrincipal(
      context,
      sessionPrincipalKey,
      safePrincipal.toJson(),
    );
    adapter.writePrincipalAttribute(
      context,
      principalAttributeKey,
      safePrincipal,
    );
    adapter.setResponseCookie(
      context,
      adapter.buildRememberCookie(
        context,
        rememberCookieName,
        rotatedToken,
        newExpiry,
      ),
    );
  }

  Cookie? _findRequestCookie(TContext context) {
    for (final cookie in adapter.requestCookies(context)) {
      if (cookie.name == rememberCookieName) {
        return cookie;
      }
    }
    return null;
  }

  String _generatedRememberToken() {
    final token = tokenGenerator();
    if (token.trim().isEmpty) {
      throw ArgumentError.value(
        token,
        'tokenGenerator()',
        'must return a non-empty token',
      );
    }
    return token;
  }
}

AuthPrincipal _safePrincipal(AuthPrincipal principal) {
  return AuthPrincipal.fromJson(principal.toJson());
}
