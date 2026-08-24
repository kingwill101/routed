/// Cloudflare D1 persistence for `package:server_auth`.
///
/// This library provides a host-neutral [CloudflareD1AuthStore] and its typed
/// migration schema. It uses the D1 binding from `package:routed_node` so the
/// same adapter contract can be exercised by Cloudflare Workers and compatible
/// SQL-backed hosts.
library;

export 'src/cloudflare_d1_auth_schema.dart';
export 'src/cloudflare_d1_auth_store.dart';
