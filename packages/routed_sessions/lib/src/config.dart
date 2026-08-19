import 'dart:io';

import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';
import 'package:server_sessions/server_sessions.dart';

/// Configuration for session management.
class SessionConfig implements ValidatableConfiguration {
  /// The name of the session cookie. Defaults to 'routed_session'.
  final String cookieName;

  /// The session store implementation.
  final SessionStore store;

  /// The maximum age of the session. Defaults to 1 hour.
  final Duration maxAge;

  /// The path for which the cookie is valid. Defaults to '/'.
  final String path;

  /// Whether the cookie should only be sent over HTTPS. Defaults to `false`.
  final bool secure;

  /// Whether the cookie should be marked as HttpOnly, preventing client-side JavaScript access. Defaults to `true`.
  final bool httpOnly;

  /// Base cookie options applied when constructing sessions.
  final SessionOptions defaultOptions;

  /// Whether the cookie should expire when the browser closes.
  final bool expireOnClose;

  /// SameSite configuration derived from options.
  final SameSite? sameSite;

  /// Partitioned cookie flag.
  final bool? partitioned;

  /// Codecs used when encoding/decoding cookies.
  final List<SecureCookie> codecs;

  /// Lottery configuration surfaced for tooling/tests.
  final List<int>? lottery;

  /// Creates a [SessionConfig].
  ///
  /// The [cookieName] parameter specifies the name of the session cookie.
  /// The [store] parameter specifies the session store implementation.
  /// The [maxAge] parameter specifies the maximum age of the session.
  /// The [path] parameter specifies the path for which the cookie is valid.
  /// The [secure] parameter specifies whether the cookie should only be sent over HTTPS.
  /// The [httpOnly] parameter specifies whether the cookie should be marked as HttpOnly, preventing client-side JavaScript access.
  SessionConfig({
    this.cookieName = 'routed_session',
    required this.store,
    this.maxAge = const Duration(hours: 1),
    this.path = '/',
    this.secure = false,
    this.httpOnly = true,
    SessionOptions? defaultOptions,
    this.expireOnClose = false,
    this.sameSite,
    this.partitioned,
    List<SecureCookie>? codecs,
    this.lottery,
  }) : defaultOptions =
           defaultOptions ??
           SessionOptions(
             path: path,
             maxAge: expireOnClose ? null : maxAge.inSeconds,
             secure: secure,
             httpOnly: httpOnly,
             sameSite: sameSite,
             partitioned: partitioned,
           ),
       codecs = codecs ?? const [];

  /// Creates a [SessionConfig] that uses cookie storage.
  ///
  /// The [appKey] parameter is required and is used to encrypt and sign the session data.
  /// The [cookieName] parameter specifies the name of the session cookie. Defaults to 'routed_session'.
  /// The [maxAge] parameter specifies the maximum age of the session. Defaults to 1 hour.
  factory SessionConfig.cookie({
    String? appKey,
    List<SecureCookie>? codecs,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
    bool expireOnClose = false,
    SessionOptions? options,
  }) {
    final resolvedCodecs = (codecs != null && codecs.isNotEmpty)
        ? codecs
        : [SecureCookie(key: appKey, useEncryption: true, useSigning: true)];
    final resolvedSessionOptions =
        options ??
        SessionOptions(
          path: '/',
          maxAge: expireOnClose ? null : maxAge.inSeconds,
          secure: true,
          httpOnly: true,
          sameSite: SameSite.lax,
        );
    return SessionConfig(
      cookieName: cookieName,
      store: CookieStore(
        codecs: resolvedCodecs,
        defaultOptions: resolvedSessionOptions,
      ),
      maxAge: maxAge,
      path: resolvedSessionOptions.path ?? '/',
      secure: resolvedSessionOptions.secure ?? true,
      httpOnly: resolvedSessionOptions.httpOnly ?? true,
      defaultOptions: resolvedSessionOptions,
      expireOnClose: expireOnClose,
      sameSite: resolvedSessionOptions.sameSite,
      partitioned: resolvedSessionOptions.partitioned,
      codecs: resolvedCodecs,
    );
  }

  /// Creates a [SessionConfig] that uses file storage.
  ///
  /// The [appKey] parameter is required and is used to encrypt and sign the session data.
  /// The [storagePath] parameter specifies the directory where session files will be stored.
  /// The [cookieName] parameter specifies the name of the session cookie. Defaults to 'routed_session'.
  /// The [maxAge] parameter specifies the maximum age of the session. Defaults to 1 hour.
  factory SessionConfig.file({
    required String appKey,
    List<SecureCookie>? codecs,
    required String storagePath,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
    bool expireOnClose = false,
    SessionOptions? options,
    List<int>? lottery,
    FileSystem? fileSystem,
  }) {
    final resolvedCodecs = (codecs != null && codecs.isNotEmpty)
        ? codecs
        : [SecureCookie(key: appKey, useEncryption: true, useSigning: true)];
    final resolvedSessionOptions =
        options ??
        SessionOptions(
          path: '/',
          maxAge: expireOnClose ? null : maxAge.inSeconds,
          secure: true,
          httpOnly: true,
        );
    return SessionConfig(
      cookieName: cookieName,
      store: FilesystemStore(
        storageDir: storagePath,
        codecs: resolvedCodecs,
        defaultOptions: resolvedSessionOptions,
        fileSystem: fileSystem,
        lottery: lottery,
      ),
      maxAge: maxAge,
      path: resolvedSessionOptions.path ?? '/',
      secure: resolvedSessionOptions.secure ?? true,
      httpOnly: resolvedSessionOptions.httpOnly ?? true,
      defaultOptions: resolvedSessionOptions,
      expireOnClose: expireOnClose,
      sameSite: resolvedSessionOptions.sameSite,
      partitioned: resolvedSessionOptions.partitioned,
      codecs: resolvedCodecs,
      lottery: lottery,
    );
  }

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      cookieName.trim().isNotEmpty,
      'cookieName',
      'must not be empty',
    );
    context.require(path.trim().isNotEmpty, 'path', 'must not be empty');
    context.require(maxAge >= Duration.zero, 'maxAge', 'must not be negative');
  }
}
