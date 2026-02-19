import 'package:routed/routed.dart';

void registerCatalogDocRoutes(Router router) {
  /// Catalog health check.
  ///
  /// Demonstrates Dartdoc extraction from an inline closure route.
  router.get('/health', (ctx) => ctx.json({'ok': true}));

  /// Catalog inline docs route.
  ///
  /// Used to stress source-based matching for closure handlers.
  router.get('/inline', (ctx) => ctx.string('catalog-inline'));
}
