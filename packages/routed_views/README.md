# routed_view

View and translation presentation for Routed.

Owns `liquify` (Liquid), `mustache_template`, `image`, `intl`, `timezone`
dependencies per `refactor.md` §15 dependency-budget meta-only foundation.
`EngineContext` render helpers (`view`, `trans`, `transChoice`) will migrate
from `routed` to this package as extensions in PR J/K.
