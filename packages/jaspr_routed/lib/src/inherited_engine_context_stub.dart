import 'package:jaspr/jaspr.dart';

typedef EngineContext = Object;
typedef Request = Object;
typedef Response = Object;
typedef Session = Object;

class InheritedEngineContext extends InheritedComponent {
  const InheritedEngineContext._({required super.child});

  static InheritedEngineContext of(BuildContext context) {
    throw AssertionError(
      'InheritedEngineContext is only available on the server runtime.',
    );
  }

  static EngineContext engineOf(BuildContext context) {
    throw AssertionError(
      'EngineContext is only available on the server runtime.',
    );
  }

  @override
  bool updateShouldNotify(InheritedEngineContext oldComponent) => false;
}

extension BuildContextEngineContextX on BuildContext {
  Never get engineContext {
    throw AssertionError(
      'engineContext is only available on the server runtime.',
    );
  }

  Never get routedRequest {
    throw AssertionError(
      'routedRequest is only available on the server runtime.',
    );
  }

  Never get routedResponse {
    throw AssertionError(
      'routedResponse is only available on the server runtime.',
    );
  }

  Never get routedSession {
    throw AssertionError(
      'routedSession is only available on the server runtime.',
    );
  }
}
