import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as database;
import '../models/newsletter_subscription.dart' as models;

/// Repository for managing newsletter subscriptions
class NewsletterRepository {
  final database.BlogDatabase _database;
  final Uuid _uuid = const Uuid();

  NewsletterRepository(this._database);

  /// Get all newsletter subscriptions
  Future<List<models.NewsletterSubscription>> findAll({
    bool activeOnly = true,
  }) async {
    final dbSubscriptions = await _database.getAllSubscriptions(
      activeOnly: activeOnly,
    );
    return dbSubscriptions.map(_fromDatabaseModel).toList();
  }

  /// Get subscription by email address
  Future<models.NewsletterSubscription?> findByEmail(String email) async {
    final dbSubscription = await _database.getSubscriptionByEmail(email);
    return dbSubscription != null ? _fromDatabaseModel(dbSubscription) : null;
  }

  /// Get subscription by ID
  Future<models.NewsletterSubscription?> findById(String id) async {
    final dbSubscription = await _database.getSubscriptionById(id);
    return dbSubscription != null ? _fromDatabaseModel(dbSubscription) : null;
  }

  /// Create a new newsletter subscription
  Future<models.NewsletterSubscription> create(
    String email, {
    String? name,
  }) async {
    // Check if email already exists
    final existing = await findByEmail(email);
    if (existing != null) {
      if (existing.isActive) {
        throw Exception('Email address is already subscribed');
      } else {
        // Reactivate existing subscription
        return await reactivate(existing.email);
      }
    }

    // Create new subscription
    final id = _uuid.v4();
    final unsubscribeToken = _uuid.v4();
    final now = DateTime.now();

    final companion = database.NewsletterSubscriptionsCompanion.insert(
      id: id,
      email: email,
      name: Value(name),
      isActive: const Value(true),
      unsubscribeToken: Value(unsubscribeToken),
      subscribedAt: Value(now),
    );

    await _database.createSubscription(companion);

    return models.NewsletterSubscription(
      id: id,
      email: email,
      name: name,
      isActive: true,
      unsubscribeToken: unsubscribeToken,
      subscribedAt: now,
    );
  }

  /// Unsubscribe by email
  Future<bool> unsubscribeByEmail(String email) async {
    return await _database.unsubscribeByEmail(email);
  }

  /// Unsubscribe by token
  Future<bool> unsubscribeByToken(String token) async {
    return await _database.unsubscribeByToken(token);
  }

  /// Reactivate a subscription
  Future<models.NewsletterSubscription> reactivate(String email) async {
    final existing = await findByEmail(email);
    if (existing == null) {
      throw Exception('No subscription found for this email');
    }

    final companion = database.NewsletterSubscriptionsCompanion(
      isActive: const Value(true),
      subscribedAt: Value(DateTime.now()), // Update subscription date
    );

    await _database.updateSubscription(existing.id, companion);

    return existing.copyWith(isActive: true, subscribedAt: DateTime.now());
  }

  /// Delete a subscription permanently
  Future<bool> delete(String id) async {
    final affected = await _database.deleteSubscription(id);
    return affected > 0;
  }

  /// Get total active subscription count
  Future<int> getActiveCount() async {
    return await _database.getActiveSubscriptionCount();
  }

  /// Get subscription statistics
  Future<Map<String, int>> getStats() async {
    final total = (await _database.getAllSubscriptions(
      activeOnly: false,
    )).length;
    final active = await getActiveCount();

    return {'total': total, 'active': active, 'inactive': total - active};
  }

  /// Convert database model to our custom model
  models.NewsletterSubscription _fromDatabaseModel(
    database.NewsletterSubscription dbModel,
  ) {
    return models.NewsletterSubscription(
      id: dbModel.id,
      email: dbModel.email,
      name: dbModel.name,
      isActive: dbModel.isActive,
      unsubscribeToken: dbModel.unsubscribeToken,
      subscribedAt: dbModel.subscribedAt,
    );
  }
}
