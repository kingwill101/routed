// import 'package:file/memory.dart'; // Import for MemoryFileSystem
// import 'package:routed/routed.dart';
// import 'package:routed/src/view/class_view/list.dart';
//
// // Example model
// class Product {
//   final String id;
//   final String name;
//   final double price;
//
//   Product(this.id, this.name, this.price);
// }
//
// // Example repository
// class ProductRepository {
//   final List<Product> _products = [
//     Product('1', 'Laptop', 999.99),
//     Product('2', 'Phone', 499.99),
//     Product('3', 'Tablet', 299.99),
//   ];
//
//   Future<List<Product>> getAll() async {
//     return _products;
//   }
//
//   Future<Product?> getById(String id) async {
//     try {
//       return _products.firstWhere((p) => p.id == id);
//     } catch (_) {
//       return null;
//     }
//   }
//
//   Future<void> add(Product product) async {
//     _products.add(product);
//   }
// }
//
// // Example views
// class ProductListView extends TemplateListView<Product> {
//   final ProductRepository repository;
//
//   ProductListView(this.repository)
//       : super('products/list.html', objectListName: 'products');
//
//   @override
//   Future<List<Product>> getObjectList(EngineContext context) async {
//     return await repository.getAll();
//   }
//
//   @override
//   Future<Map<String, dynamic>> getContextData(EngineContext context) async {
//     final data = await super.getContextData(context);
//     data['title'] = 'Product List';
//     return data;
//   }
//
//   @override
//   Future<void> renderToResponse(EngineContext context, Map<String, dynamic> templateContext, {Map<String, dynamic>? extraOptions}) {
//     // TODO: implement renderToResponse
//     throw UnimplementedError();
//   }
// }
//
// class ProductDetailView extends TemplateDetailView<Product> {
//   final ProductRepository repository;
//
//   ProductDetailView(this.repository)
//       : super('products/detail.html', objectName: 'product');
//
// // @override
// // Future<Product?> getObject(String id, EngineContext context) async {
// //   return await repository.getById(id);
// // }
// //
// // @override
// // Future<Map<String, dynamic>> getContextData(
// //     Product object, EngineContext context) async {
// //   final data = await super.getContextData(object, context);
// //   data['title'] = 'Product: ${object.name}';
// //   return data;
// // }
// }
//
// class ProductFormView extends FormView {
//   final ProductRepository repository;
//
//   ProductFormView(this.repository);
//
//   @override
//   String get templateName => 'products/form.html';
//
//   @override
//   String get successUrl => '/products';
//
//   @override
//   Map<String, String> get validationRules => {
//         'name': 'required',
//         'price': 'required|numeric|min:0.01',
//       };
//
//   @override
//   Future<void> renderForm(EngineContext context) async {
//     final data = await getContextData(context);
//     context.template(templateName: templateName, data: data);
//   }
//
//   @override
//   Future<void> post(EngineContext context) async {
//     try {
//       // Use the built-in validation and binding
//       final data = <String, dynamic>{};
//
//       // Define validation rules
//       await context.validate({
//         'name': 'required',
//         'price': 'required|numeric|min:0.01',
//       });
//
//       // Bind the form data
//       await context.bind(data);
//
//       // Process the form data
//       final id = (await repository.getAll()).length + 1;
//       final name = data['name'] as String;
//       final price = double.parse(data['price'].toString());
//
//       final product = Product(id.toString(), name, price);
//       await repository.add(product);
//
//       // Redirect to success URL
//       context.redirect(successUrl);
//     } catch (e) {
//       if (e is ValidationError) {
//         // If validation fails, re-render the form with errors
//         final data = await getContextData(context);
//         data['errors'] = e.errors;
//         data['formData'] = await context.form();
//
//         context.response.statusCode = 400;
//         context.template(templateName: templateName, data: data);
//       } else {
//         // Handle other errors
//         context.response.statusCode = 500;
//         context.template(templateName: 'error.html', data: {
//           'error': 'An error occurred while processing your request.',
//           'details': e.toString(),
//         });
//       }
//     }
//   }
//
//   @override
//   Future<Map<String, dynamic>> getContextData(EngineContext context) async {
//     return {
//       'title': 'Add New Product',
//       'submitUrl': '/products/add',
//     };
//   }
//
//   @override
//   Future<void> processForm(Map<String, dynamic> data, EngineContext context) {
//     // TODO: implement processForm
//     throw UnimplementedError();
//   }
// }
//
// // Custom view that combines multiple views
// class DashboardView extends View {
//   final ProductRepository repository;
//
//   DashboardView(this.repository);
//
//   @override
//   Future<void> get(EngineContext context) async {
//     final products = await repository.getAll();
//     final totalProducts = products.length;
//     final totalValue =
//         products.fold(0.0, (sum, product) => sum + product.price);
//
//     context.template(
//       templateName: 'dashboard.html',
//       data: {
//         'title': 'Dashboard',
//         'totalProducts': totalProducts,
//         'totalValue': totalValue,
//         'recentProducts': products.take(3).toList(),
//       },
//     );
//   }
// }
//
// // Add a RedirectView class
// class RedirectView extends View {
//   final String targetUrl;
//
//   RedirectView(this.targetUrl);
//
//   @override
//   Future<void> get(EngineContext context) async {
//     context.redirect(targetUrl);
//   }
// }
//
// void main() async {
//   final engine = Engine();
//   final repository = ProductRepository();
//
//   // Setup template engine
//   engine.useViewEngine(LiquidViewEngine(
//     root: LiquidRoot(
//         fileSystem:
//             MemoryFileSystem()), // Use MemoryFileSystem instead of FileSystem
//   ));
//
//   // Create router
//   final router = Router();
//
//   // Register views
//   router.view('/products', ProductListView(repository)).name('product.list');
//   router
//       .view('/products/{id}', ProductDetailView(repository))
//       .name('product.detail');
//   router.view('/products/add', ProductFormView(repository)).name('product.add');
//   router.view('/dashboard', DashboardView(repository)).name('dashboard');
//
//   // Add a redirect view
//   router.view('/', RedirectView('/dashboard')).name('home');
//
//   // Mount router
//   engine.use(router);
//
//   engine.serve(port: 8080);
// }
