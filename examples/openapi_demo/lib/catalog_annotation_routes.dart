import 'package:routed/routed.dart';

void registerCatalogAnnotationRoutes(Router router) {
  final handlers = _CatalogHandlers();

  router
      .get('/products', handlers.listProducts)
      .schema(
        const RouteSchema(
          summary: 'List catalog products',
          description: 'Returns products available in the catalog.',
          operationId: 'catalogProducts',
          tags: ['Catalog'],
          responses: [ResponseSchema(200, description: 'Catalog product list')],
        ),
      );

  router
      .get('/products/{sku}', handlers.getProductBySku)
      .schema(
        const RouteSchema(
          summary: 'Get catalog product by sku',
          description: 'Returns one catalog product for the provided SKU.',
          tags: ['Catalog'],
          params: [
            ParamSchema(
              'sku',
              location: ParamLocation.path,
              required: true,
              description: 'Catalog SKU',
              jsonSchema: {'type': 'string'},
            ),
          ],
          responses: [
            ResponseSchema(200, description: 'Catalog product'),
            ResponseSchema(404, description: 'Catalog product not found'),
          ],
        ),
      );
}

class _CatalogHandlers {
  @Summary('List catalog products')
  @Description('Returns products available in the catalog.')
  @OperationId('catalogProductsFromAttributes')
  @Tags(['Catalog'])
  @ApiResponse(200, description: 'Catalog product list')
  Future<Response> listProducts(EngineContext ctx) async {
    return ctx.json({
      'data': [
        {'sku': 'sku-1', 'name': 'Widget'},
        {'sku': 'sku-2', 'name': 'Gadget'},
      ],
    });
  }

  @Summary('Get catalog product by sku')
  @Description('Returns one catalog product for the provided SKU.')
  @Tags(['Catalog'])
  @ApiParam(
    'sku',
    location: ParamLocation.path,
    required: true,
    description: 'Catalog SKU',
    schema: {'type': 'string'},
  )
  @ApiResponse(200, description: 'Catalog product')
  @ApiResponse(404, description: 'Catalog product not found')
  Future<Response> getProductBySku(EngineContext ctx) async {
    final sku = ctx.mustGetParam<String>('sku');
    if (sku != 'sku-1' && sku != 'sku-2') {
      return ctx.json({'error': 'Not found'}, statusCode: 404);
    }
    return ctx.json({'sku': sku});
  }
}
