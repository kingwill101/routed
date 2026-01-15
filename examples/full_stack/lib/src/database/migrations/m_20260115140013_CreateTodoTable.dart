import 'package:ormed/migrations.dart';

class CreateTodoTable extends Migration {
  const CreateTodoTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('todos', (table) {
      table.increments('id').primaryKey();
      table.string('title');
      table.boolean('completed');
      table.timestampsTz();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('todos');
  }
}
