import 'package:routed/routed.dart';

class Product {
  final String id;
  final String name;
  final double price;

  Product(this.id, this.name, this.price);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
}

class CreateProductRequest implements Bindable {
  String name = '';
  double price = 0.0;

  CreateProductRequest();

  @override
  void bind(Map<String, dynamic> data) {
    name = data['name'] as String? ?? '';
    price = (data['price'] as num?)?.toDouble() ?? 0.0;
  }
}

class Store {
  String name;
  String address;

  Store(this.name, this.address);
}

class CreateStoreRequest implements Bindable {
  String name = '';
  String address = '';

  CreateStoreRequest();

  @override
  void bind(Map<String, dynamic> data) {
    name = data['name'] as String? ?? '';
    address = data['address'] as String? ?? '';
  }
}

Router v1Routes() {
  final router = Router();

  router
      .group(
        path: "/store",
        builder: (store) {
          store
              .get("/", (ctx) async {
                return ctx.json([
                  Store("Store 1", "Address 1"),
                  Store("Store 2", "Address 2"),
                ]);
              })
              .name("store.index");

          store
              .get("/{id}", (ctx) async {
                final id = ctx.param("id");
                return ctx.json(Store("Store $id", "Address $id"));
              })
              .name("store.show");

          store
              .post("/", (ctx) async {
                final req = await ctx.bind(CreateStoreRequest());
                return ctx.json(Store(req.name, req.address), statusCode: 201);
              })
              .name("create");
        },
      )
      .name("store");

  return router;
}

/// Example controller using the new Controller base class
class StoreController extends Controller {
  StoreController() : super(prefix: '/stores', name: 'stores');

  @override
  void routes() {
    /// @Summary Get all stores
    /// @Tags stores
    router.get('/', _index);

    /// @Summary Get store by ID
    /// @Tags stores
    /// @Response 404 Store not found
    router.get('/{id}', _show);

    /// @Summary Create a store
    /// @Tags stores
    /// @Response 201 Store created successfully
    router.post('/', _store);
  }

  Future<Response> _index(EngineContext ctx) async {
    return ctx.json([
      Store("Store 1", "Address 1"),
      Store("Store 2", "Address 2"),
    ]);
  }

  Future<Response> _show(EngineContext ctx) async {
    final id = ctx.param("id");
    return ctx.json(Store("Store $id", "Address $id"));
  }

  Future<Response> _store(EngineContext ctx) async {
    final req = await ctx.bind(CreateStoreRequest());
    return ctx.json(Store(req.name, req.address), statusCode: 201);
  }
}

/// Handler function with comment annotations
/// @Summary Search for products
/// @Description Search products by name, category, or other criteria.
/// @Tags search, products
/// @Response 200 Search results returned successfully
/// @Response 400 Invalid search query
Future<Response> searchProducts(EngineContext ctx) async {
  final query = ctx.query('q');
  return ctx.string('Searching for: $query');
}

Future<Engine> createEngine() async {
  final engine = await Engine.createFull();
  engine.use(v1Routes());

  /// Health check endpoint for container orchestration
  engine.get('/health', (ctx) async {
    return ctx.json({
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  /// Products group
  engine.group(
    path: '/products',
    builder: (products) {
      /// @Summary Get all products
      /// @Description Returns a list of all products in the catalog.
      /// @Tags products, catalog
      /// @Response 200 List of products returned successfully
      products
          .get('/', (ctx) async {
            return ctx.json([
              Product('1', 'Laptop', 999.99),
              Product('2', 'Phone', 599.99),
            ]);
          })
          .name('products.index');

      /// @Summary Create a product
      /// @Description Creates a new product in the catalog.
      /// @Tags products
      /// @Response 201 Product created successfully
      /// @Response 400 Invalid product data
      products
          .post('/', (ctx) async {
            final req = await ctx.bind(CreateProductRequest());
            return ctx.json(Product('3', req.name, req.price), statusCode: 201);
          })
          .name('products.store');

      /// @Summary Get product by ID
      /// @Description Retrieves a single product by its unique identifier.
      /// @Tags products
      /// @Response 200 Product found
      /// @Response 404 Product not found
      products
          .get('/{id}', (ctx) async {
            final id = ctx.param('id');
            return ctx.json(Product(id!, 'Product $id', 100.0));
          })
          .name('products.show');

      /// @Summary Update product
      /// @Description Updates an existing product.
      /// @Tags products
      /// @Response 200 Product updated successfully
      /// @Response 404 Product not found
      products
          .put('/{id}', (ctx) async {
            final id = ctx.param('id');
            final req = await ctx.bind(CreateProductRequest());
            return ctx.json(Product(id!, req.name, req.price));
          })
          .name('products.update');

      // @Summary Delete a product
      // @Description Permanently removes a product from the catalog.
      // @Tags products
      // @Deprecated Use DELETE /v2/products/{id} instead
      // @Response 204 Product deleted successfully
      // @Response 404 Product not found
      products
          .delete('/{id}', (ctx) async {
            final id = ctx.param('id');
            return ctx.json({'deleted': id}, statusCode: 204);
          })
          .name('products.delete');
    },
  );

  // Use function reference - comments come from function declaration
  engine.get('/search', searchProducts);

  return engine;
}
