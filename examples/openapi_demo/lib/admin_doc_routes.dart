import 'package:routed/routed.dart';

void registerAdminDocRoutes(Router router) {
  /// Admin inline docs route.
  ///
  /// Mirrors catalog inline path segment to stress cross-file matching.
  router.get('/inline', (ctx) => ctx.string('admin-inline'));
}
