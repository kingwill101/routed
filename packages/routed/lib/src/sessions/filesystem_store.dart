import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/sessions/store.dart';

/// A simple Dart adaptation of Gorilla's FilesystemStore, storing session data in files.
/// For demonstration only. This is minimal and not production-hardened.
class FilesystemStore implements Store {
  /// Directory where session files will be stored.
  final String storageDir;

  /// List of codecs used to encode and decode session data.
  final List<SecureCookie> codecs;

  /// Default options for the session.
  final Options defaultOptions;

  /// Whether to encrypt session data
  final bool useEncryption;

  /// Whether to sign session data
  final bool useSigning;

  /// Constructor for FilesystemStore.
  /// Ensures the storage directory exists.
  FilesystemStore({
    required this.storageDir,
    required this.codecs,
    Options? defaultOptions,
    this.useEncryption = false,
    this.useSigning = false,
  }) : defaultOptions = defaultOptions ?? Options() {
    final dir = Directory(storageDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Retrieves a session based on the request and session name.
  /// If no session exists, a new one is created.
  @override
  Future<Session> read(Request request, String name) async {
    final cookie = request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );
    final session = Session(
      name: name,
      options: defaultOptions,
      values: {},
    );

    if (cookie.value.isEmpty) {
      session.id = _generateSessionId();
      return session;
    }

    for (final codec in codecs) {
      try {
        final data = codec.decode(name, cookie.value);
        final sid = data['id'] as String?;
        if (sid != null) {
          session.id = sid;
          session.isNew = false;
          final loaded = await _loadFromFile(sid);
          if (loaded != null) {
            session.values.addAll(loaded);
          }
          break;
        }
      } catch (_) {
        // continue trying other codecs
      }
    }

    if (session.id.isEmpty) {
      session.id = _generateSessionId();
    }
    return session;
  }

  /// Saves the session data to a file and sets the appropriate cookie.
  @override
  @override
  Future<void> write(
    Request request,
    Response response,
    Session session,
  ) async {
    final maxAge = session.options.maxAge ?? 0;
    if (maxAge <= 0) {
      await _eraseFile(session.id);
      response.setCookie(
        session.name,
        '',
        maxAge: -1,
        path: session.options.path ?? "/",
      );
      return;
    }

    await _saveToFile(session.id, session.values);

    final codec = codecs.first;
    final encoded = codec.encode(session.name, {'id': session.id});

    response.setCookie(
      session.name,
      encoded,
      path: session.options.path ?? "/",
      domain: session.options.domain ?? "",
      maxAge: session.options.maxAge,
      secure: session.options.secure ?? false,
      httpOnly: session.options.httpOnly ?? true,
    );
  }

  // ---------------------------------------------------------
  //  Internal helpers
  // ---------------------------------------------------------

  /// Saves session data to a file.
  Future<void> _saveToFile(String? sid, Map<String, dynamic> data) async {
    if (sid == null || sid.isEmpty) return;
    final filePath = p.join(storageDir, 'session_$sid');
    final file = File(filePath);
    final jsonStr = jsonEncode(data);
    await file.writeAsString(jsonStr);
  }

  /// Loads session data from a file.
  Future<Map<String, dynamic>?> _loadFromFile(String sid) async {
    final filePath = p.join(storageDir, 'session_$sid');
    final file = File(filePath);
    if (!await file.exists()) return null;
    final contents = await file.readAsString();
    return _pseudoParse(contents);
  }

  /// Erases session data file.
  Future<void> _eraseFile(String? sid) async {
    if (sid == null || sid.isEmpty) return;
    final filePath = p.join(storageDir, 'session_$sid');
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// A simple pseudo-parser. For production, use jsonDecode() instead.
  /// This tries to parse a string that looks like a Dart map literal, e.g.
  /// "{key: value, other: something}" just enough for demonstration.
  Map<String, dynamic> _pseudoParse(String contents) {
    // Very naive demonstration:
    // 1) Remove outer braces `{...}` if they exist
    final trimmed = contents.trim();
    final mapString = trimmed.startsWith('{') && trimmed.endsWith('}')
        ? trimmed.substring(1, trimmed.length - 1).trim()
        : trimmed;

    // 2) Split on commas, then on ':' to build a map
    final result = <String, dynamic>{};
    for (final pair in mapString.split(',')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = parts[1].trim();
        result[key] = value; // Not typed or deeply parsed
      }
    }
    return result;
  }

  /// Generates a random session ID for new sessions.
  /// A real implementation should produce a cryptographically secure random string.
  String _generateSessionId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
