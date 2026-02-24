# server_contracts example

Shows a minimal contracts-only implementation set:

- `Config` implementation with dotted key support.
- in-memory `Store` + `Repository` implementations.
- `TranslatorContract` implementation.

## Run

```bash
dart run example/main.dart
```

## Expected output

```text
cache.default = array
cache health = ok
Hello contracts
```
