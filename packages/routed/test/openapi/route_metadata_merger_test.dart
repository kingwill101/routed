import 'package:routed/src/engine/route_manifest.dart';
import 'package:routed/src/openapi/handler_identity.dart';
import 'package:routed/src/openapi/route_metadata_extractor.dart';
import 'package:routed/src/openapi/route_metadata_merger.dart';
import 'package:routed/src/openapi/schema.dart';
import 'package:test/test.dart';

void main() {
  group('extractRouteMetadataFromSource', () {
    test('extracts annotations and dartdoc for top-level function', () {
      const source = '''
import 'package:routed/routed.dart';

/// Lists users.
/// Returns users available to the caller.
@Summary('List users from annotation')
@Tags(['users', 'admin'])
@ApiResponse(200, description: 'OK')
Object listUsers(dynamic ctx) => {};
''';

      final extracted = extractRouteMetadataFromSource(source);
      final metadata = extracted['listUsers'];

      expect(metadata, isNotNull);
      expect(metadata!.summary, 'List users from annotation');
      expect(metadata.description, 'Returns users available to the caller.');
      expect(metadata.tags, containsAll(<String>['users', 'admin']));
      expect(metadata.responses, hasLength(1));
      expect(metadata.responses.first.statusCode, 200);
    });

    test('uses dartdoc summary when annotation summary is absent', () {
      const source = '''
/// Lists users from docs.
Object listUsers(dynamic ctx) => {};
''';

      final extracted = extractRouteMetadataFromSource(source);
      expect(extracted['listUsers']!.summary, 'Lists users from docs.');
    });

    test(
      'captures nested route builder metadata for named handlers and closures',
      () {
        const source = '''
import 'package:routed/routed.dart';

@Summary('List users from annotation')
Object listUsers(dynamic ctx) => {};

void register(Router router) {
  router.group(
    path: '/api/v1',
    builder: (router) {
      router.get('/users', listUsers);

      /// Health check endpoint.
      /// Closure route summary from docs.
      router.get('/health', (ctx) => ctx.json({'ok': true}));
    },
  );
}
''';

        final extracted = extractRouteMetadataFromSource(source);

        expect(
          extracted['route:GET /api/v1/users']?.summary,
          'List users from annotation',
        );
        expect(
          extracted['route:GET /api/v1/health']?.summary,
          'Health check endpoint.',
        );
        expect(
          extracted['route:GET /api/v1/health']?.description,
          'Closure route summary from docs.',
        );
      },
    );
  });

  group('mergeManifestWithExtractedMetadata', () {
    test('schema summary takes precedence over annotations and docs', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            handlerIdentity: const HandlerIdentity.fromFunction('listUsers'),
            schema: const RouteSchema(summary: 'Schema summary'),
          ),
        ],
      );

      final merged = mergeManifestWithExtractedMetadata(manifest, {
        'listUsers': const ExtractedRouteMetadata(
          summary: 'Annotation summary',
          description: 'Doc description',
        ),
      });

      final route = merged.routes.single;
      expect(route.schema, isNotNull);
      expect(route.schema!.summary, 'Schema summary');
      expect(route.schema!.description, 'Doc description');
    });

    test('merges tags and adds missing responses from extracted metadata', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            handlerIdentity: const HandlerIdentity.fromFunction('listUsers'),
            schema: const RouteSchema(
              tags: ['users'],
              responses: [ResponseSchema(200, description: 'Schema OK')],
            ),
          ),
        ],
      );

      final merged = mergeManifestWithExtractedMetadata(manifest, {
        'listUsers': const ExtractedRouteMetadata(
          tags: ['admin', 'users'],
          responses: [
            ResponseSchema(200, description: 'Annotation OK'),
            ResponseSchema(404, description: 'Not Found'),
          ],
        ),
      });

      final schema = merged.routes.single.schema!;
      expect(schema.tags, <String>['users', 'admin']);
      expect(schema.responses, isNotNull);
      expect(schema.responses!.length, 2);
      final ok = schema.responses!.firstWhere((r) => r.statusCode == 200);
      final notFound = schema.responses!.firstWhere((r) => r.statusCode == 404);
      expect(ok.description, 'Schema OK');
      expect(notFound.description, 'Not Found');
    });

    test('matches closure docs from mounted router via unique suffix path', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/api/v1/users')],
      );

      final merged = mergeManifestWithExtractedMetadata(manifest, {
        'route:GET /users': const ExtractedRouteMetadata(
          summary: 'List users from mounted router',
          description: 'Doc from router file before mount.',
        ),
      });

      final schema = merged.routes.single.schema;
      expect(schema, isNotNull);
      expect(schema!.summary, 'List users from mounted router');
      expect(schema.description, 'Doc from router file before mount.');
    });

    test('does not use ambiguous suffix path matches', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/api/v1/users')],
      );

      final merged = mergeManifestWithExtractedMetadata(manifest, {
        'route:GET /users': const ExtractedRouteMetadata(summary: 'A'),
        'route:GET /v1/users': const ExtractedRouteMetadata(summary: 'B'),
      });

      expect(merged.routes.single.schema, isNull);
    });

    test('prefers source location identity for mounted closure routes', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/api/v1/users',
            handlerIdentity: const HandlerIdentity(
              method: 'GET',
              path: '/api/v1/users',
              sourceFile: 'package:openapi_demo/users_routes.dart',
              sourceLine: 42,
              sourceColumn: 7,
            ),
          ),
        ],
      );

      final merged = mergeManifestWithExtractedMetadata(manifest, {
        'source:lib/users_routes.dart:42:7': const ExtractedRouteMetadata(
          summary: 'Users from source location',
        ),
        'route:GET /users': const ExtractedRouteMetadata(
          summary: 'Fallback suffix summary',
        ),
      });

      expect(merged.routes.single.schema, isNotNull);
      expect(
        merged.routes.single.schema!.summary,
        'Users from source location',
      );
    });
  });
}
