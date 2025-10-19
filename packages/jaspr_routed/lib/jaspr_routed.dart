library;

export 'src/jaspr_route_io.dart'
    if (dart.library.js_interop) 'src/jaspr_route_stub.dart'
    show jasprRoute, JasprComponentBuilder;
export 'src/inherited_engine_context_io.dart'
    if (dart.library.js_interop) 'src/inherited_engine_context_stub.dart'
    show InheritedEngineContext, BuildContextEngineContextX;
