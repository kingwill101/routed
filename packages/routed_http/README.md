# routed_http

HTTP utilities for Routed — binding, multipart, content negotiation, SSE and conditional requests.

Owns `http_parser`, `mime` per `refactor.md` §15. `EngineContext` binding/negotiation helpers will migrate from `routed` to here in PR J/K.
