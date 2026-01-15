// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'todo.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$TodoIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'int',
  resolvedType: 'int?',
  isPrimaryKey: true,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: true,
);

const FieldDefinition _$TodoTitleField = FieldDefinition(
  name: 'title',
  columnName: 'title',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$TodoCompletedField = FieldDefinition(
  name: 'completed',
  columnName: 'completed',
  dartType: 'bool',
  resolvedType: 'bool',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$TodoCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$TodoUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeTodoUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as Todo;
  return <String, Object?>{
    'id': registry.encodeField(_$TodoIdField, m.id),
    'title': registry.encodeField(_$TodoTitleField, m.title),
    'completed': registry.encodeField(_$TodoCompletedField, m.completed),
  };
}

final ModelDefinition<$Todo> _$TodoDefinition = ModelDefinition(
  modelName: 'Todo',
  tableName: 'todos',
  fields: const [
    _$TodoIdField,
    _$TodoTitleField,
    _$TodoCompletedField,
    _$TodoCreatedAtField,
    _$TodoUpdatedAtField,
  ],
  relations: const [],
  softDeleteColumn: 'deleted_at',
  metadata: ModelAttributesMetadata(
    hidden: const <String>[],
    visible: const <String>[],
    fillable: const <String>[],
    guarded: const <String>[],
    casts: const <String, String>{},
    appends: const <String>[],
    touches: const <String>[],
    timestamps: true,
    softDeletes: false,
    softDeleteColumn: 'deleted_at',
  ),
  untrackedToMap: _encodeTodoUntracked,
  codec: _$TodoCodec(),
);

// ignore: unused_element
final todoModelDefinitionRegistration = ModelFactoryRegistry.register<$Todo>(
  _$TodoDefinition,
);

extension TodoOrmDefinition on Todo {
  static ModelDefinition<$Todo> get definition => _$TodoDefinition;
}

class Todos {
  const Todos._();

  /// Starts building a query for [$Todo].
  ///
  /// {@macro ormed.query}
  static Query<$Todo> query([String? connection]) =>
      Model.query<$Todo>(connection: connection);

  static Future<$Todo?> find(Object id, {String? connection}) =>
      Model.find<$Todo>(id, connection: connection);

  static Future<$Todo> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$Todo>(id, connection: connection);

  static Future<List<$Todo>> all({String? connection}) =>
      Model.all<$Todo>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$Todo>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$Todo>(connection: connection);

  static Query<$Todo> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$Todo>(column, operator, value, connection: connection);

  static Query<$Todo> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$Todo>(column, values, connection: connection);

  static Query<$Todo> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$Todo>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$Todo> limit(int count, {String? connection}) =>
      Model.limit<$Todo>(count, connection: connection);

  /// Creates a [Repository] for [$Todo].
  ///
  /// {@macro ormed.repository}
  static Repository<$Todo> repo([String? connection]) =>
      Model.repository<$Todo>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $Todo fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$TodoDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $Todo model, {
    ValueCodecRegistry? registry,
  }) => _$TodoDefinition.toMap(model, registry: registry);
}

class TodoModelFactory {
  const TodoModelFactory._();

  static ModelDefinition<$Todo> get definition => _$TodoDefinition;

  static ModelCodec<$Todo> get codec => definition.codec;

  static Todo fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    Todo model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<Todo> withConnection(QueryContext context) =>
      ModelFactoryConnection<Todo>(definition: definition, context: context);

  static ModelFactoryBuilder<Todo> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<Todo>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$TodoCodec extends ModelCodec<$Todo> {
  const _$TodoCodec();
  @override
  Map<String, Object?> encode($Todo model, ValueCodecRegistry registry) {
    return <String, Object?>{
      'id': registry.encodeField(_$TodoIdField, model.id),
      'title': registry.encodeField(_$TodoTitleField, model.title),
      'completed': registry.encodeField(_$TodoCompletedField, model.completed),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$TodoCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$TodoUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $Todo decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final int? todoIdValue = registry.decodeField<int?>(
      _$TodoIdField,
      data['id'],
    );
    final String todoTitleValue =
        registry.decodeField<String>(_$TodoTitleField, data['title']) ??
        (throw StateError('Field title on Todo cannot be null.'));
    final bool todoCompletedValue =
        registry.decodeField<bool>(_$TodoCompletedField, data['completed']) ??
        (throw StateError('Field completed on Todo cannot be null.'));
    final DateTime? todoCreatedAtValue = registry.decodeField<DateTime?>(
      _$TodoCreatedAtField,
      data['created_at'],
    );
    final DateTime? todoUpdatedAtValue = registry.decodeField<DateTime?>(
      _$TodoUpdatedAtField,
      data['updated_at'],
    );
    final model = $Todo(
      id: todoIdValue,
      title: todoTitleValue,
      completed: todoCompletedValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': todoIdValue,
      'title': todoTitleValue,
      'completed': todoCompletedValue,
      if (data.containsKey('created_at')) 'created_at': todoCreatedAtValue,
      if (data.containsKey('updated_at')) 'updated_at': todoUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [Todo].
///
/// Auto-increment/DB-generated fields are omitted by default.
class TodoInsertDto implements InsertDto<$Todo> {
  const TodoInsertDto({this.title, this.completed});
  final String? title;
  final bool? completed;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
    };
  }

  static const _TodoInsertDtoCopyWithSentinel _copyWithSentinel =
      _TodoInsertDtoCopyWithSentinel();
  TodoInsertDto copyWith({
    Object? title = _copyWithSentinel,
    Object? completed = _copyWithSentinel,
  }) {
    return TodoInsertDto(
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      completed: identical(completed, _copyWithSentinel)
          ? this.completed
          : completed as bool?,
    );
  }
}

class _TodoInsertDtoCopyWithSentinel {
  const _TodoInsertDtoCopyWithSentinel();
}

/// Update DTO for [Todo].
///
/// All fields are optional; only provided entries are used in SET clauses.
class TodoUpdateDto implements UpdateDto<$Todo> {
  const TodoUpdateDto({this.id, this.title, this.completed});
  final int? id;
  final String? title;
  final bool? completed;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
    };
  }

  static const _TodoUpdateDtoCopyWithSentinel _copyWithSentinel =
      _TodoUpdateDtoCopyWithSentinel();
  TodoUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? completed = _copyWithSentinel,
  }) {
    return TodoUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as int?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      completed: identical(completed, _copyWithSentinel)
          ? this.completed
          : completed as bool?,
    );
  }
}

class _TodoUpdateDtoCopyWithSentinel {
  const _TodoUpdateDtoCopyWithSentinel();
}

/// Partial projection for [Todo].
///
/// All fields are nullable; intended for subset SELECTs.
class TodoPartial implements PartialEntity<$Todo> {
  const TodoPartial({this.id, this.title, this.completed});

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory TodoPartial.fromRow(Map<String, Object?> row) {
    return TodoPartial(
      id: row['id'] as int?,
      title: row['title'] as String?,
      completed: row['completed'] as bool?,
    );
  }

  final int? id;
  final String? title;
  final bool? completed;

  @override
  $Todo toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? titleValue = title;
    if (titleValue == null) {
      throw StateError('Missing required field: title');
    }
    final bool? completedValue = completed;
    if (completedValue == null) {
      throw StateError('Missing required field: completed');
    }
    return $Todo(id: id, title: titleValue, completed: completedValue);
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
    };
  }

  static const _TodoPartialCopyWithSentinel _copyWithSentinel =
      _TodoPartialCopyWithSentinel();
  TodoPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? completed = _copyWithSentinel,
  }) {
    return TodoPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as int?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      completed: identical(completed, _copyWithSentinel)
          ? this.completed
          : completed as bool?,
    );
  }
}

class _TodoPartialCopyWithSentinel {
  const _TodoPartialCopyWithSentinel();
}

/// Generated tracked model class for [Todo].
///
/// This class extends the user-defined [Todo] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $Todo extends Todo
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$Todo].
  $Todo({int? id, required String title, required bool completed})
    : super(id: id, title: title, completed: completed) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'title': title,
      'completed': completed,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $Todo.fromModel(Todo model) {
    return $Todo(id: model.id, title: model.title, completed: model.completed);
  }

  $Todo copyWith({int? id, String? title, bool? completed}) {
    return $Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $Todo fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$TodoDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$TodoDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  int? get id => getAttribute<int?>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(int? value) => setAttribute('id', value);

  /// Tracked getter for [title].
  @override
  String get title => getAttribute<String>('title') ?? super.title;

  /// Tracked setter for [title].
  set title(String value) => setAttribute('title', value);

  /// Tracked getter for [completed].
  @override
  bool get completed => getAttribute<bool>('completed') ?? super.completed;

  /// Tracked setter for [completed].
  set completed(bool value) => setAttribute('completed', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$TodoDefinition);
  }
}

class _TodoCopyWithSentinel {
  const _TodoCopyWithSentinel();
}

extension TodoOrmExtension on Todo {
  static const _TodoCopyWithSentinel _copyWithSentinel =
      _TodoCopyWithSentinel();
  Todo copyWith({
    Object? id = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? completed = _copyWithSentinel,
  }) {
    return Todo(
      id: identical(id, _copyWithSentinel) ? this.id : id as int?,
      title: identical(title, _copyWithSentinel) ? this.title : title as String,
      completed: identical(completed, _copyWithSentinel)
          ? this.completed
          : completed as bool,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$TodoDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static Todo fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$TodoDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $Todo;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $Todo toTracked() {
    return $Todo.fromModel(this);
  }
}

extension TodoPredicateFields on PredicateBuilder<Todo> {
  PredicateField<Todo, int?> get id => PredicateField<Todo, int?>(this, 'id');
  PredicateField<Todo, String> get title =>
      PredicateField<Todo, String>(this, 'title');
  PredicateField<Todo, bool> get completed =>
      PredicateField<Todo, bool>(this, 'completed');
}

void registerTodoEventHandlers(EventBus bus) {
  // No event handlers registered for Todo.
}
