import 'package:routed/routed.dart';
import 'package:openapi_demo/admin_doc_routes.dart';
import 'package:openapi_demo/catalog_annotation_routes.dart';
import 'package:openapi_demo/catalog_doc_routes.dart';
import 'package:openapi_demo/catalog_raw_routes.dart';

void registerMetadataRoutes(Router router) {
  router.group(
    path: '/catalog',
    builder: (r) {
      r.group(
        path: '/v2',
        builder: (ee) {
          registerCatalogDocRoutes(ee);
          registerCatalogAnnotationRoutes(ee);
          registerCatalogRawRoutes(ee);
        },
      );
    },
  );

  router.group(
    path: '/admin',
    builder: (r) {
      r.group(
        path: '/v2',
        builder: (ee) {
          registerAdminDocRoutes(ee);
        },
      );
    },
  );
}
