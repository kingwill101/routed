# Routed subsystem skills

One self-contained skill is maintained for each routed package in this
checkout. Each skill embeds its subsystem API, composition rules, usage
example, hazards, and validation intent.

The generator derives package names, versions, imports, and dependency facts
from manifests and public `lib/*.dart` entrypoints, then combines them with
the subsystem-specific contract embedded in the generator. Refresh with:

```bash
node tool/generate_routed_skills.mjs
node tool/generate_routed_skills.mjs --check
```

| Package | Skill name | Version | Source package |
| --- | --- | --- | --- |
| [`routed`](./routed/SKILL.md) | `routed` | `0.5.0` | [package](../packages/routed) |
| [`routed_analyzer`](./routed_analyzer/SKILL.md) | `routed-analyzer` | `0.1.0` | [package](../packages/routed_analyzer) |
| [`routed_auth`](./routed_auth/SKILL.md) | `routed-auth` | `0.2.0` | [package](../packages/routed_auth) |
| [`routed_cache`](./routed_cache/SKILL.md) | `routed-cache` | `0.2.0` | [package](../packages/routed_cache) |
| [`routed_cli`](./routed_cli/SKILL.md) | `routed-cli` | `0.3.0` | [package](../packages/routed_cli) |
| [`routed_core`](./routed_core/SKILL.md) | `routed-core` | `0.4.0` | [package](../packages/routed_core) |
| [`routed_hotwire`](./routed_hotwire/SKILL.md) | `routed-hotwire` | `0.1.4` | [package](../packages/routed_hotwire) |
| [`routed_http`](./routed_http/SKILL.md) | `routed-http` | `0.1.0` | [package](../packages/routed_http) |
| [`routed_io`](./routed_io/SKILL.md) | `routed-io` | `0.1.0` | [package](../packages/routed_io) |
| [`routed_logging`](./routed_logging/SKILL.md) | `routed-logging` | `0.2.0` | [package](../packages/routed_logging) |
| [`routed_node`](./routed_node/SKILL.md) | `routed-node` | `0.1.0` | [package](../packages/routed_node) |
| [`routed_observability`](./routed_observability/SKILL.md) | `routed-observability` | `0.1.0` | [package](../packages/routed_observability) |
| [`routed_openapi`](./routed_openapi/SKILL.md) | `routed-openapi` | `0.1.0` | [package](../packages/routed_openapi) |
| [`routed_openapi_builder`](./routed_openapi_builder/SKILL.md) | `routed-openapi-builder` | `0.1.0` | [package](../packages/routed_openapi_builder) |
| [`routed_rate_limit`](./routed_rate_limit/SKILL.md) | `routed-rate-limit` | `0.1.0` | [package](../packages/routed_rate_limit) |
| [`routed_security`](./routed_security/SKILL.md) | `routed-security` | `0.1.0` | [package](../packages/routed_security) |
| [`routed_sessions`](./routed_sessions/SKILL.md) | `routed-sessions` | `0.2.0` | [package](../packages/routed_sessions) |
| [`routed_storage`](./routed_storage/SKILL.md) | `routed-storage` | `0.2.0` | [package](../packages/routed_storage) |
| [`routed_testing`](./routed_testing/SKILL.md) | `routed-testing` | `0.4.0` | [package](../packages/server_testing/routed_testing) |
| [`routed_validation`](./routed_validation/SKILL.md) | `routed-validation` | `0.1.0` | [package](../packages/routed_validation) |
| [`routed_views`](./routed_views/SKILL.md) | `routed-views` | `0.2.0` | [package](../packages/routed_views) |
