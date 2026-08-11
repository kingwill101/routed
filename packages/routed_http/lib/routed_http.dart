library;

// Facade for HTTP utilities per refactor.md §6.
// Owns `http_parser`, `mime`, negotiation, conditional, SSE deps.
// EngineContext binding helpers will migrate from `routed` to here.

export 'src/http_ext.dart';
export 'src/binding_ext.dart';
