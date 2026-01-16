import 'package:ormed/ormed.dart';

part 'todo.orm.dart';

@OrmModel(table: 'todos')
class Todo extends Model<Todo> with ModelFactoryCapable, TimestampsTZ {
  const Todo({this.id, required this.title, this.completed = false});

  @OrmField(isPrimaryKey: true, autoIncrement: true)
  final int? id;

  @OrmField()
  final String title;

  @OrmField()
  final bool completed;
}
