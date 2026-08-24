import 'dart:io';

import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';
import 'package:server_sessions/server_sessions.dart';

/// Configuration for session middleware, cookies, and storage.
///
/// Use [SessionConfig.cookie] or [SessionConfig.file] for common store
/// configurations, or provide a custom [SessionStore].
class SessionConfig implements ValidatableConfiguration {
  /// Creates session middleware configuration for [store].
  ///
  /// [defaultOptions] overrides options derived from [path], [maxAge], and
  /// the cookie security flags.
  SessionConfig({
    required this.store,
    this.cookieName = 'routed_session',
    this.maxAge = const Duration(hours: 1),
    this.path = '/',
    this.secure = true,
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
             sameSite: sameSite ?? SameSite.lax,
             partitioned: partitioned,
           ),
       codecs = codecs ?? const [];

  /// Creates configuration backed by [CookieStore].
  ///
  /// [appKey] supplies the key used to encrypt and sign session data when
  /// [codecs] is omitted. [expireOnClose] leaves the cookie without a lifetime.
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

  /// Creates configuration backed by [FilesystemStore].
  ///
  /// [appKey] supplies the key used to encrypt and sign session IDs when
  /// [codecs] is omitted. [storagePath] identifies the session directory.
  factory SessionConfig.file({
    required String appKey,
    required String storagePath,
    List<SecureCookie>? codecs,
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

  /// The name of the session cookie. Defaults to 'routed_session'.
  final String cookieName;

  /// The session store implementation.
  final SessionStore store;

  /// The maximum age of the session. Defaults to 1 hour.
  final Duration maxAge;

  /// The path for which the cookie is valid. Defaults to '/'.
  final String path;

  /// Whether the cookie should only be sent over HTTPS. Defaults to `true`.
  final bool secure;

  /// Whether the cookie is marked as HttpOnly, preventing client-side
  /// JavaScript access. Defaults to `true`.
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

  /// Validates the cookie name, path, and non-negative [maxAge].
  @override
  void validate(ConfigValidationContext context) {
    context
      ..require(
        cookieName.trim().isNotEmpty,
        'cookieName',
        'must not be empty',
      )
      ..require(path.trim().isNotEmpty, 'path', 'must not be empty')
      ..require(maxAge >= Duration.zero, 'maxAge', 'must not be negative');
  }
}
