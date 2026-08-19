## 0.2.0

- **Breaking:** Remove driver documentation callbacks and string-based
  `requiresConfig` metadata from `LogDriverRegistry`; configure and validate
  driver options in Dart.
- **Breaking:** Replace string-based built-in logging channel definitions with
  typed channel configuration classes. Custom drivers now use
  `CustomLoggingChannelConfig` explicitly.
- Added request-scoped logging context and centralized routing-error logging.
- Ensured the logging middleware is installed and cleaned up with the provider
  lifecycle.
- Remove stale analyzer exclusions inherited from the pre-extraction package;
  retain only the intentional allowance for importing routed core internals.

## 0.1.0

- Extracted logging from foundation routed.
