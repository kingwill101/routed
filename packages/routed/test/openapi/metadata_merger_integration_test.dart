import 'dart:io';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('metadata merger integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'routed-metadata-merger-',
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'uses source identity to resolve cross-file mounted closure routes',
      () async {
        const usersSource = '''
import 'package:routed/routed.dart';

void registerUserRoutes(Router router) {
  /// Users inline route.
  router.get('/inline', (ctx) => ctx.string('users'));
}
''';

        const adminSource = '''
import 'package:routed/routed.dart';

void registerAdminRoutes(Router router) {
  /// Admin inline route.
  router.get('/inline', (ctx) => ctx.string('admin'));
}
''';

        await _writeFile(tempDir, 'lib/users_routes.dart', usersSource);
        await _writeFile(tempDir, 'lib/admin_routes.dart', adminSource);

        final usersLocation = _locationOf(usersSource, "get('/inline'");
        final adminLocation = _locationOf(adminSource, "get('/inline'");

        final manifest = RouteManifest(
          routes: [
            RouteManifestEntry(
              method: 'GET',
              path: '/api/v1/users/inline',
              handlerIdentity: HandlerIdentity(
                method: 'GET',
                path: '/api/v1/users/inline',
                sourceFile: 'package:test_app/users_routes.dart',
                sourceLine: usersLocation.$1,
                sourceColumn: usersLocation.$2,
              ),
            ),
            RouteManifestEntry(
              method: 'GET',
              path: '/api/v1/admin/inline',
              handlerIdentity: HandlerIdentity(
                method: 'GET',
                path: '/api/v1/admin/inline',
                sourceFile: 'package:test_app/admin_routes.dart',
                sourceLine: adminLocation.$1,
                sourceColumn: adminLocation.$2,
              ),
            ),
          ],
        );

        final enriched = await enrichManifestWithProjectMetadata(
          manifest,
          projectRoot: tempDir.path,
          packageName: 'test_app',
        );

        final spec = manifestToOpenApi(enriched);
        final usersGet = spec.paths['/api/v1/users/inline']!.get!;
        final adminGet = spec.paths['/api/v1/admin/inline']!.get!;

        expect(usersGet.summary, 'Users inline route.');
        expect(adminGet.summary, 'Admin inline route.');
        expect(usersGet.summary, isNot(adminGet.summary));
      },
    );
  });
}

Future<void> _writeFile(
  Directory root,
  String relativePath,
  String contents,
) async {
  final path = '${root.path}${Platform.pathSeparator}$relativePath';
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

(int, int) _locationOf(String source, String needle) {
  final offset = source.indexOf(needle);
  if (offset < 0) {
    throw StateError('Needle not found: $needle');
  }

  final before = source.substring(0, offset);
  final lines = before.split('\n');
  final line = lines.length;
  final column = lines.last.length + 1;
  return (line, column);
}
