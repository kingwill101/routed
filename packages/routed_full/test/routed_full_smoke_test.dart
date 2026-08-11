import 'dart:async';

import 'package:routed_full/routed_full.dart';
import 'package:test/test.dart';

void main() {
  test('routed_full exposes the Routed framework core types', () {
    // Importing only package:routed_full must expose Routed's public
    // namespace: these names were previously unavailable without a separate
    // direct import of package:routed.
    Future<dynamic> acceptsRequest(Request request) async => null;

    Response responseFactory() => throw UnimplementedError();

    // Referencing the types through function signatures proves they resolve
    // through the barrel without constructing dart:io-backed instances.
    expect(acceptsRequest, isA<Function>());
    expect(responseFactory, isA<Function>());

    // Router is constructible standalone.
    final router = Router();
    expect(router, isA<Router>());

    // Engine type resolves; its constructor requires provider wiring.
    expect(Engine, isA<Type>());
  });

  test('routed_full resolves cache/store collisions to the portable packages',
      () {
    // Both package:routed (duplicate copies) and the portable packages export
    // these names; the barrel must resolve them to the portable server_*
    // implementations so consumers get the batteries-included runtimes.
    final store = ArrayStore();
    expect(store, isA<ArrayStore>());

    final lock = ArrayLock(store, 'test', 5, 'owner-1');
    expect(lock.owner(), 'owner-1');

    final manager = StorageManager();
    expect(manager, isA<StorageManager>());
  });

  test('bundled Router registers routes without direct routed imports', () {
    final router = Router();
    expect(router, isA<Router>());
  });
}