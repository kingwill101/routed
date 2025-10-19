/// Simple Todo model for testing class views
class Todo {
  final String id;
  final String title;
  final String description;
  final bool completed;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Todo({
    required this.id,
    required this.title,
    required this.description,
    this.completed = false,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create a new Todo with generated ID and timestamp
  factory Todo.create({
    required String title,
    required String description,
    bool completed = false,
  }) {
    final now = DateTime.now();
    return Todo(
      id: _generateId(),
      title: title,
      description: description,
      completed: completed,
      createdAt: now,
    );
  }

  /// Create Todo from JSON
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert Todo to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'completed': completed,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  Todo copyWith({
    String? title,
    String? description,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return Todo(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Simple ID generation for testing (in real apps, use UUID or database ID)
  static String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          completed == other.completed &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      description.hashCode ^
      completed.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Todo(id: $id, title: $title, description: $description, completed: $completed, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}
