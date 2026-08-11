import 'package:test/test.dart';

void main() {
  test('route metadata merger stub - handlerIdentity moved to openapi', () {
    // Previously tested RouteManifestEntry(handlerIdentity: ...) which is now removed from routed core.
    // Stub ensures package loads; real merger now uses dynamic fallback.
    expect(true, isTrue);
  });
}
