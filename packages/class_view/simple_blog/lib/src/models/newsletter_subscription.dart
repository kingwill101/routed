/// Newsletter subscription model for storing email subscriptions
class NewsletterSubscription {
  final String id;
  final String email;
  final String? name;
  final DateTime subscribedAt;
  final bool isActive;
  final String? unsubscribeToken;

  const NewsletterSubscription({
    required this.id,
    required this.email,
    this.name,
    required this.subscribedAt,
    this.isActive = true,
    this.unsubscribeToken,
  });

  /// Create from JSON data
  factory NewsletterSubscription.fromJson(Map<String, dynamic> json) {
    return NewsletterSubscription(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      subscribedAt: DateTime.parse(json['subscribed_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      unsubscribeToken: json['unsubscribe_token'] as String?,
    );
  }

  /// Convert to JSON data
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'subscribed_at': subscribedAt.toIso8601String(),
      'is_active': isActive,
      'unsubscribe_token': unsubscribeToken,
    };
  }

  /// Create a copy with updated fields
  NewsletterSubscription copyWith({
    String? id,
    String? email,
    String? name,
    DateTime? subscribedAt,
    bool? isActive,
    String? unsubscribeToken,
  }) {
    return NewsletterSubscription(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      subscribedAt: subscribedAt ?? this.subscribedAt,
      isActive: isActive ?? this.isActive,
      unsubscribeToken: unsubscribeToken ?? this.unsubscribeToken,
    );
  }

  @override
  String toString() {
    return 'NewsletterSubscription(id: $id, email: $email, name: $name, '
        'subscribedAt: $subscribedAt, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NewsletterSubscription && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
