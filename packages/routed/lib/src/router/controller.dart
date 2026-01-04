import 'router.dart';
import 'types.dart';

/// Base class for controllers in routed.
///
/// Controllers provide a way to organize related route handlers into a class.
/// Each controller has its own [Router] instance that can be mounted on an [Engine].
///
/// Example:
/// ```dart
/// class UserController extends Controller {
///   UserController() : super(prefix: '/users', name: 'users');
///
///   @override
///   void routes() {
///     router.get('/', _index);
///     router.get('/:id', _show);
///     router.post('/', _store);
///   }
///
///   // @Summary Get all users
///   Future<Response> _index(EngineContext ctx) async {
///     return ctx.json([/* users */]);
///   }
///
///   // @Summary Get user by ID
///   Future<Response> _show(EngineContext ctx) async {
///     final id = ctx.param('id');
///     return ctx.json({'id': id});
///   }
///
///   // @Summary Create user
///   Future<Response> _store(EngineContext ctx) async {
///     final req = await ctx.bind(CreateUserRequest());
///     return ctx.json({'name': req.name}, statusCode: 201);
///   }
/// }
///
/// // Mount controller routes
/// engine.use(UserController().router, prefix: '/users');
///
/// // Or using call() syntax
/// engine.use(UserController()(), prefix: '/users');
/// ```
abstract class Controller {
  /// Creates a controller with optional configuration.
  ///
  /// [prefix] - URL prefix for all routes in this controller (e.g., '/users')
  /// [name] - Optional name for this controller's route group
  /// [middlewares] - Middlewares applied to all routes in this controller
  Controller({this.prefix = '', this.name, this.middlewares = const []}) {
    routes();
  }

  /// The URL prefix for all routes in this controller.
  final String prefix;

  /// Optional name for this controller's route group.
  final String? name;

  /// Middlewares applied to all routes in this controller.
  final List<Middleware> middlewares;

  /// The internal router for this controller.
  final Router router = Router();

  /// Override this method to define routes.
  ///
  /// Called automatically in the constructor.
  void routes() {}

  /// Makes the controller callable, returning its router.
  ///
  /// This allows the syntax: `engine.use(UserController()(), prefix: '/users')`
  Router call() => router;
}
