# Database provider architecture

This is the smallest normal Routed composition using `routed_database`:

1. `DatabaseManager` owns a named Ormed connection.
2. `RoutedDatabaseProvider` opens it during `Engine.initialize()`.
3. The same provider applies the code-free migration list before requests.
4. Handlers use `ctx.db()` and never construct a connection per request.

There are no generated models and no `build_runner`. The default database is
in-memory; set `DATABASE_PATH=storage/app.sqlite` for a file-backed database.

```bash
dart run bin/server.dart
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/api/notes
curl -X POST http://127.0.0.1:8080/api/notes \
  -H 'content-type: application/json' \
  -d '{"title":"provider boot","body":"migrated before serving"}'
```
