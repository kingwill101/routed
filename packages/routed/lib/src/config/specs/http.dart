import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';

import '../spec.dart';

class HttpConfigSpec extends ConfigSpec<Map<String, dynamic>> {
  const HttpConfigSpec();

  @override
  String get root => 'http';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'HTTP Configuration',
    description: 'Global HTTP and server settings.',
    properties: {
      'providers': ConfigSchema.list(
        description: 'Service providers registered for the HTTP pipeline.',
        items: ConfigSchema.string(),
        defaultValue: const [
          'routed.core',
          'routed.routing',
          'routed.cache',
          'routed.sessions',
          'routed.uploads',
          'routed.cors',
          'routed.security',
          'routed.auth',
          'routed.logging',
          'routed.observability',
          'routed.compression',
          'routed.rate_limit',
          'routed.storage',
          'routed.static',
          'routed.localization',
          'routed.views',
        ],
      ),
      'middleware': ConfigSchema.object(
        properties: {
          'global': ConfigSchema.list(
            description: 'Middleware executed for every HTTP request.',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'groups': ConfigSchema.object(
            description:
                'Named middleware groups applied to route collections.',
            additionalProperties: ConfigSchema.list(
              items: ConfigSchema.string(),
            ),
            defaultValue: const {},
          ),
        },
      ),
      'middleware_sources': ConfigSchema.object(
        description:
            'Declarative middleware mappings contributed by service providers.',
        additionalProperties: ConfigSchema.object(
          properties: {
            'global': ConfigSchema.list(items: ConfigSchema.string()),
            'groups': ConfigSchema.object(
              additionalProperties: ConfigSchema.list(
                items: ConfigSchema.string(),
              ),
            ),
          },
        ),
        defaultValue: const {},
      ),
      'http2': ConfigSchema.object(
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable HTTP/2 (ALPN h2) on secure listeners.',
          ),
          'allow_cleartext': ConfigSchema.boolean(
            description:
                'Allow HTTP/2 without TLS (h2c). Typically false in production.',
          ),
          'max_concurrent_streams': ConfigSchema.integer(
            description:
                'Advertised max concurrent streams per HTTP/2 connection.',
          ),
          'idle_timeout': ConfigSchema.duration(
            description: 'Optional idle timeout applied to HTTP/2 connections.',
          ),
        },
      ),
      'tls': ConfigSchema.object(
        properties: {
          'certificate_path': ConfigSchema.string(
            description: 'Path to the PEM certificate chain used for TLS.',
          ),
          'key_path': ConfigSchema.string(
            description:
                'Path to the private key corresponding to the TLS certificate.',
          ),
          'password': ConfigSchema.string(
            description:
                'Optional password protecting the certificate/key files.',
          ),
          'request_client_certificate': ConfigSchema.boolean(
            description: 'Request client certificates during TLS handshakes.',
          ),
          'shared': ConfigSchema.boolean(
            description:
                'Allow multiple isolates/processes to share the TLS listener.',
          ),
          'v6_only': ConfigSchema.boolean(
            description:
                'Restrict TLS listener to IPv6 only (disables IPv4 dual stack).',
          ),
        },
      ),
    },
  );

  @override
  Map<String, dynamic> fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return map;
  }

  @override
  Map<String, dynamic> toMap(Map<String, dynamic> value) {
    return value;
  }
}
