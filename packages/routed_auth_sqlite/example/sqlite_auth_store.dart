import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';

/// Opens a durable local store, uses its typed lookup API, and closes it.
Future<void> main() async {
  final directory = await Directory('var').create(recursive: true);
  final store = await SqliteAuthStore.openPath(
    p.join(directory.path, 'auth.sqlite'),
  );

  try {
    final user = await store.users.findByEmail('alice@example.com');
    stdout.writeln(
      user == null ? 'No account found.' : 'Found account ${user.id}.',
    );
  } finally {
    store.close();
  }
}
