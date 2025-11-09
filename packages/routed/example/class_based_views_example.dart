import 'dart:convert';

import 'package:routed/routed.dart';

class Product {
  Product({required this.id, required this.name, required this.price});

  final String id;
  final String name;
  final num price;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
}

class ProductRepository {
  ProductRepository()
    : _products = {
        '1': Product(id: '1', name: 'Laptop', price: 1799.0),
        '2': Product(id: '2', name: 'Headphones', price: 249.0),
      };

  final Map<String, Product> _products;

  Iterable<Product> all() => _products.values;

  Product? find(String id) => _products[id];

  Product create({required String name, required num price}) {
    final id = (_products.length + 1).toString();
    final product = Product(id: id, name: name, price: price);
    _products[id] = product;
    return product;
  }
}

/// Example "view" implemented as a callable class. Using call() lets us
/// register the instance directly with router.get/post etc.
class ProductListView {
  ProductListView(this.repository);

  final ProductRepository repository;

  Future<Response> call(EngineContext ctx) async {
    final products = repository.all().map((p) => p.toJson()).toList();
    return ctx.json({'products': products});
  }
}

class ProductDetailView {
  ProductDetailView(this.repository);

  final ProductRepository repository;

  Future<Response> call(EngineContext ctx) async {
    final id = ctx.param('id');
    final product = id != null ? repository.find(id) : null;
    if (product == null) {
      return ctx.json({
        'error': 'Product not found',
      }, statusCode: HttpStatus.notFound);
    }
    return ctx.json(product.toJson());
  }
}

class ProductCreateView {
  ProductCreateView(this.repository);

  final ProductRepository repository;

  Future<Response> call(EngineContext ctx) async {
    final payload =
        jsonDecode(await ctx.request.body()) as Map<String, dynamic>;
    final name = payload['name']?.toString();
    final rawPrice = payload['price'];
    final price = rawPrice is num
        ? rawPrice
        : num.tryParse(rawPrice?.toString() ?? '');

    if (name == null || name.isEmpty || price == null) {
      return ctx.json({
        'error': 'Both "name" and numeric "price" are required.',
      }, statusCode: HttpStatus.badRequest);
    }

    final product = repository.create(name: name, price: price);
    return ctx.json(product.toJson(), statusCode: HttpStatus.created);
  }
}

Engine createProductApp({ProductRepository? repository}) {
  final repo = repository ?? ProductRepository();
  final router = Router();

  router.get('/products', ProductListView(repo).call);
  router.get('/products/{id}', ProductDetailView(repo).call);
  router.post('/products', ProductCreateView(repo).call);

  final engine = Engine()..use(router, prefix: '/store');
  return engine;
}

Future<void> main(List<String> args) async {
  final engine = createProductApp();
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 3001 : 3001;
  print('Class-based view example on http://localhost:$port/store/products');
  await engine.serve(port: port);
}
