## 0.1.1 - 2026-08-25

- Raise the minimum Dart SDK to 3.13 to match the hosted Stem 0.5.0 runtime
  pulled in through `routed_node`.

- Complete public API documentation and adopt the shared
  `very_good_analysis` lint baseline.
- Add file-backed and in-memory setup, migration, and shutdown examples for
  the SQLite adapter.

## 0.1.0

- Add a Dart IO SQLite `AuthStore` adapter with typed stores, append-only
  migrations, durable file or in-memory operation, and the shared auth-store
  conformance contract.
- Reuse the proven SQL-backed auth lifecycle, deletion coordinator, historical
  namespace guards, bounded credential stores, and transaction boundaries from
  the D1 implementation through a local SQLite binding.
