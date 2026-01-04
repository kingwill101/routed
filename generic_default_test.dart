// Actual working approach for optional generics in Dart

// Base class
abstract class Request {
  String get type;
}

// Default implementation
class BaseRequest extends Request {
  @override
  String get type => 'BaseRequest';
}

// Custom implementation
class CreateUserRequest extends Request {
  final String email;
  final String name;
  
  CreateUserRequest(this.email, this.name);
  
  @override
  String get type => 'CreateUserRequest';
}

// APPROACH 1: Use non-generic base class + generic subclass
abstract class EngineContextBase {
  final Request request;
  
  EngineContextBase(this.request);
  
  void printRequestType() {
    print('Context has request of type: ${request.type}');
  }
}

class EngineContext<TRequest extends Request> extends EngineContextBase {
  @override
  TRequest get request => super.request as TRequest;
  
  EngineContext(super.request);
}

// Factory for backward compatibility
EngineContextBase createContext([Request? request]) {
  return EngineContext(request ?? BaseRequest());
}

// APPROACH 2: Use dynamic and downcast
class Context<TRequest extends Request> {
  final TRequest request;
  
  Context(this.request);
  
  void printRequestType() {
    print('Context has request of type: ${request.type}');
  }
}

// Helper to create untyped context (acts like default generic)
Context<BaseRequest> context([Request? request]) {
  return Context(request as BaseRequest? ?? BaseRequest());
}

void main() {
  print('=== Testing Optional Generics Approaches ===\n');
  
  // APPROACH 1: Base class approach
  print('Approach 1: Base class');
  final ctx1 = createContext(); // No generic needed
  ctx1.printRequestType();
  
  final ctx2 = EngineContext<CreateUserRequest>(
    CreateUserRequest('user@example.com', 'John')
  );
  ctx2.printRequestType();
  print('Type: ${ctx2.runtimeType}\n');
  
  // APPROACH 2: Factory function approach
  print('Approach 2: Factory function');
  final ctx3 = context(); // Returns Context<BaseRequest>
  ctx3.printRequestType();
  
  final ctx4 = Context<CreateUserRequest>(
    CreateUserRequest('test@example.com', 'Jane')
  );
  ctx4.printRequestType();
  print('Type: ${ctx4.runtimeType}\n');
  
  // Both work with handlers
  print('Testing handlers:');
  void simpleHandler(EngineContextBase ctx) {
    print('Simple: ${ctx.request.type}');
  }
  
  void typedHandler(EngineContext<CreateUserRequest> ctx) {
    print('Typed: ${ctx.request.email}');
  }
  
  simpleHandler(createContext());
  typedHandler(EngineContext(CreateUserRequest('handler@test.com', 'User')));
  
  print('\n=== All tests passed! ===');
}
