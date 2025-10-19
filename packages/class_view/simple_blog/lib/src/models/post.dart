import 'package:uuid/uuid.dart';

/// Simple blog post model
class Post {
  final String id;
  final String title;
  final String content;
  final String author;
  final String slug;
  final bool isPublished;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.slug,
    this.isPublished = false,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a new post with generated ID and timestamps
  factory Post.create({
    required String title,
    required String content,
    required String author,
    String? slug,
    bool isPublished = false,
    List<String> tags = const [],
  }) {
    final now = DateTime.now();
    final uuid = const Uuid();

    return Post(
      id: uuid.v4(),
      title: title,
      content: content,
      author: author,
      slug: slug ?? _generateSlug(title),
      isPublished: isPublished,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create post from form data
  factory Post.fromFormData(Map<String, dynamic> data) {
    final tags = data['tags'] is String
        ? (data['tags'] as String)
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : data['tags'] as List<String>? ?? [];

    return Post.create(
      title: data['title'] as String,
      content: data['content'] as String,
      author: data['author'] as String,
      slug: data['slug'] as String?,
      isPublished: data['isPublished'] as bool? ?? false,
      tags: tags,
    );
  }

  /// Copy post with updated fields
  Post copyWith({
    String? title,
    String? content,
    String? author,
    String? slug,
    bool? isPublished,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return Post(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      author: author ?? this.author,
      slug: slug ?? this.slug,
      isPublished: isPublished ?? this.isPublished,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'author': author,
      'slug': slug,
      'isPublished': isPublished,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Generate slug from title
  static String _generateSlug(String title) {
    final baseSlug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    // Add UUID suffix to ensure uniqueness
    final uuid = const Uuid().v4().substring(0, 8);
    return '$baseSlug-$uuid';
  }

  @override
  String toString() => 'Post(id: $id, title: $title, slug: $slug)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Post && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
