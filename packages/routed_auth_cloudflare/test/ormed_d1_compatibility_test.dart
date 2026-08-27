import 'package:ormed_d1/ormed_d1.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  test('Ormed D1 opens and executes against the Routed binding', () async {
    final binding = FakeCloudflareD1Database();
    addTearDown(binding.close);

    final database = await D1Database.fromBinding(binding: binding);
    addTearDown(database.close);

    await database.executeRaw(
      'CREATE TABLE ormed_probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.executeRaw(
      'INSERT INTO ormed_probe (value) VALUES (?)',
      ['works'],
    );

    final rows = await database.queryRaw(
      'SELECT value FROM ormed_probe WHERE id = ?',
      [1],
    );

    expect(rows, hasLength(1));
    expect(rows.single['value'], 'works');
    expect(binding, isA<D1DatabaseBinding>());
  });
}
