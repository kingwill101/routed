import 'dart:convert';

import 'package:ormed/migrations.dart';

// <ORM-MIGRATION-IMPORTS>
import 'migrations/m_20260115140013_create_todo_table.dart';// </ORM-MIGRATION-IMPORTS>

final List<MigrationEntry> _entries = [
  // <ORM-MIGRATION-REGISTRY>
  MigrationEntry(
    id: MigrationId.parse('m_20260115140013_create_todo_table'),
    migration: const CreateTodoTable(),
  ),// </ORM-MIGRATION-REGISTRY>
];

/// Build migration descriptors sorted by timestamp.
List<MigrationDescriptor> buildMigrations() =>
    MigrationEntry.buildDescriptors(_entries);

MigrationEntry? _findEntry(String rawId) {
  for (final entry in _entries) {
    if (entry.id.toString() == rawId) return entry;
  }
  return null;
}

void main(List<String> args) {
  if (args.contains('--dump-json')) {
    final payload = buildMigrations().map((m) => m.toJson()).toList();
    print(jsonEncode(payload));
    return;
  }

  final planIndex = args.indexOf('--plan-json');
  if (planIndex != -1) {
    final id = args[planIndex + 1];
    final entry = _findEntry(id);
    if (entry == null) {
      throw StateError('Unknown migration id $id.');
    }
    final directionName = args[args.indexOf('--direction') + 1];
    final direction = MigrationDirection.values.byName(directionName);
    final snapshotIndex = args.indexOf('--schema-snapshot');
    SchemaSnapshot? snapshot;
    if (snapshotIndex != -1) {
      final decoded =
          utf8.decode(base64.decode(args[snapshotIndex + 1]));
      final payload = jsonDecode(decoded) as Map<String, Object?>;
      snapshot = SchemaSnapshot.fromJson(payload);
    }
    final plan = entry.migration.plan(direction, snapshot: snapshot);
    print(jsonEncode(plan.toJson()));
    return;
  }
}
