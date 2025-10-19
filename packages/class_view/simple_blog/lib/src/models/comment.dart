import 'package:uuid/uuid.dart';

/// Simple blog comment model
class Comment {
  final String id;
  final String content;
  final String author;
  final String postId;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.content,
    required this.author,
    required this.postId,
    required this.createdAt,
  });

  /// Create a new comment with generated ID and timestamp
  factory Comment.create({
    required String content,
    required String author,
    required String postId,
  }) {
    final uuid = const Uuid();

    return Comment(
      id: uuid.v4(),
      content: content,
      author: author,
      postId: postId,
      createdAt: DateTime.now(),
    );
  }

  /// Create comment from form data
  factory Comment.fromFormData(Map<String, dynamic> data) {
    return Comment.create(
      content: data['content'] as String,
      author: data['author'] as String,
      postId: data['postId'] as String,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'author': author,
      'postId': postId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  Comment copyWith({
    String? id,
    String? content,
    String? author,
    String? postId,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      content: content ?? this.content,
      author: author ?? this.author,
      postId: postId ?? this.postId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Comment(id: $id, author: $author, postId: $postId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Comment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
