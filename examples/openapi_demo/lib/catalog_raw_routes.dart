import 'package:routed/routed.dart';

void registerCatalogRawRoutes(Router router) {
  router.get('/raw', (ctx) => ctx.json({'mode': 'raw'}));
}
