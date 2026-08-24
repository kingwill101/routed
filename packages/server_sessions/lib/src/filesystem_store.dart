import 'dart:convert';
import 'dart:io' show Cookie;
import 'dart:math';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'options.dart';
import 'secure_cookie.dart';
import 'session.dart';
import 'store.dart';

/// Stores session values in files and keeps only the session ID in the cookie.
///
/// This implementation is minimal and should be hardened for production
/// deployments, including its storage directory and file permissions.
class FilesystemStore implements SessionStore {
  /// Directory where session files will be stored.
  final String storageDir;

  /// List of codecs used to encode and decode session data.
  final List<SecureCookie> codecs;

  /// Default options for the session.
  final SessionOptions defaultOptions;

  /// Whether to prune expired session files when this store is constructed.
  final bool pruneOnStartup;

  /// Lottery configuration for opportunistic pruning, such as `2/100`.
  final List<int>? lottery;

  /// File system used to manage session files.
  final file.FileSystem fileSystem;

  final Random _random = Random.secure();

  /// Creates a file-backed store and ensures [storageDir] exists.
  ///
  /// The first [codecs] entry protects new cookies. [lottery] may configure
  /// opportunistic pruning as a `wins/outOf` probability; invalid values
  /// disable the lottery.
  FilesystemStore({
    required this.storageDir,
    List<SecureCookie>? codecs,
    SessionOptions? defaultOptions,
    bool useEncryption = false,
    bool useSigning = false,
    file.FileSystem? fileSystem,
    this.pruneOnStartup = false,
    this.lottery,
  }) : codecs =
           codecs ??
           [
             SecureCookie(
               key: SecureCookie.generateKey(),
               useEncryption: useEncryption,
               useSigning: useSigning,
             ),
           ],
       defaultOptions = defaultOptions ?? SessionOptions(),
       fileSystem = fileSystem ?? const local.LocalFileSystem() {
    final dir = this.fileSystem.directory(storageDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    if (pruneOnStartup) {
      // Best-effort cleanup of expired sessions
      _pruneExpiredFiles();
    }
  }

  /// Reads the cookie ID and loads its values from `session_<id>`.
  ///
  /// Creates a session with a generated ID when the cookie is missing,
  /// invalid, or does not identify a readable file.
  @override
  Future<Session> read(SessionRequest request, String name) async {
    final cookie = request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );
    final session = Session(
      name: name,
      options: defaultOptions.clone(),
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

  /// Saves [session] to `session_<id>` and sets its response cookie.
  ///
  /// An explicit negative [SessionOptions.maxAge] or a destroyed session
  /// removes the stored file. A configured [lottery] may prune expired files.
  @override
  Future<void> write(
    SessionRequest request,
    SessionResponse response,
    Session session,
  ) async {
    // maxAge == null (default) or 0 means the session never expires (per
    // [SessionOptions] docs) and must be persisted. Only an explicit destroy
    // or a negative maxAge removes the backend record.
    final maxAge = session.options.maxAge;
    final shouldDelete = session.isDestroyed || (maxAge != null && maxAge < 0);

    if (shouldDelete) {
      await _eraseFile(session.id);
      final previous = session.previousId;
      if (previous != null && previous != session.id) {
        await _eraseFile(previous);
      }
      response.setCookie(
        session.name,
        '',
        maxAge: -1,
        path: session.options.path ?? "/",
        domain: session.options.domain ?? "",
      );
      return;
    }

    // ID rotation must invalidate the file the old cookie still references.
    final previous = session.previousId;
    if (previous != null && previous != session.id) {
      await _eraseFile(previous);
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

    await _maybePrune();
  }

  // ---------------------------------------------------------
  //  Internal helpers
  // ---------------------------------------------------------

  /// Saves session data to a file.
  Future<void> _saveToFile(String? sid, Map<String, dynamic> data) async {
    if (sid == null || sid.isEmpty) return;
    final filePath = fileSystem.path.join(storageDir, 'session_$sid');
    final file = fileSystem.file(filePath);
    final jsonStr = jsonEncode(data);
    await file.writeAsString(jsonStr);
  }

  /// Loads session data from a file.
  Future<Map<String, dynamic>?> _loadFromFile(String sid) async {
    final filePath = fileSystem.path.join(storageDir, 'session_$sid');
    final file = fileSystem.file(filePath);
    if (!await file.exists()) return null;
    final contents = await file.readAsString();

    return jsonDecode(contents) as Map<String, dynamic>;
  }

  /// Erases session data file.
  Future<void> _eraseFile(String? sid) async {
    if (sid == null || sid.isEmpty) return;
    final filePath = fileSystem.path.join(storageDir, 'session_$sid');
    final file = fileSystem.file(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Scans the storage directory and deletes session files whose age exceeds
  /// `defaultOptions.maxAge`.  This is a best-effort cleanup and will silently
  /// ignore IO errors.
  Future<void> _pruneExpiredFiles() async {
    final maxAge = defaultOptions.maxAge;
    if (maxAge == null || maxAge <= 0) return;
    final dir = fileSystem.directory(storageDir);
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is file.File &&
          fileSystem.path.basename(entity.path).startsWith('session_')) {
        try {
          final stat = await entity.stat();
          final ageSeconds = DateTime.now().difference(stat.modified).inSeconds;
          if (ageSeconds > maxAge) {
            await entity.delete();
          }
        } catch (_) {
          // Ignore file that might disappear mid-scan or other IO errors.
        }
      }
    }
  }

  Future<void> _maybePrune() async {
    if (lottery == null || lottery!.length != 2) {
      return;
    }
    final wins = lottery![0];
    final outOf = lottery![1];
    if (wins <= 0 || outOf <= 0) {
      return;
    }
    final roll = _random.nextInt(outOf);
    if (roll < wins) {
      await _pruneExpiredFiles();
    }
  }

  /// Generates a random session ID for new sessions.
  /// A real implementation should produce a cryptographically secure random string.
  String _generateSessionId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
