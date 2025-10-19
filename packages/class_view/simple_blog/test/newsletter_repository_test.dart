import 'package:simple_blog/src/database/database.dart';
import 'package:simple_blog/src/repositories/newsletter_repository.dart';
import 'package:test/test.dart';

void main() {
  group('NewsletterRepository Tests', () {
    late NewsletterRepository repository;
    late BlogDatabase database;

    setUp(() async {
      // Create in-memory database for testing
      database = BlogDatabase(inMemory: true);
      repository = NewsletterRepository(database);

      // Wait for database to initialize
      await database.customStatement('SELECT 1');

      // Clear any existing data
      await database.delete(database.newsletterSubscriptions).go();
    });

    tearDown(() async {
      await database.close();
    });

    test('should create a new newsletter subscription', () async {
      final subscription = await repository.create(
        'test@example.com',
        name: 'Test User',
      );

      expect(subscription.email, equals('test@example.com'));
      expect(subscription.name, equals('Test User'));
      expect(subscription.isActive, isTrue);
      expect(subscription.id, isNotEmpty);
      expect(subscription.unsubscribeToken, isNotEmpty);
      expect(subscription.subscribedAt, isNotNull);
    });

    test('should create subscription without name', () async {
      final subscription = await repository.create('noname@example.com');

      expect(subscription.email, equals('noname@example.com'));
      expect(subscription.name, isNull);
      expect(subscription.isActive, isTrue);
    });

    test('should throw error for duplicate email subscription', () async {
      // Create first subscription
      await repository.create('duplicate@example.com');

      // Try to create duplicate
      expect(
        () => repository.create('duplicate@example.com'),
        throwsA(isA<Exception>()),
      );
    });

    test('should reactivate inactive subscription for same email', () async {
      // Create subscription
      final original = await repository.create('reactivate@example.com');

      // Unsubscribe
      await repository.unsubscribeByEmail('reactivate@example.com');

      // Verify it's inactive
      final inactive = await repository.findByEmail('reactivate@example.com');
      expect(inactive!.isActive, isFalse);

      // Create "new" subscription with same email should reactivate
      final reactivated = await repository.create('reactivate@example.com');
      expect(reactivated.isActive, isTrue);
      expect(reactivated.id, equals(original.id)); // Same subscription
    });

    test('should find subscription by email', () async {
      await repository.create('findme@example.com', name: 'Find Me');

      final found = await repository.findByEmail('findme@example.com');
      expect(found, isNotNull);
      expect(found!.email, equals('findme@example.com'));
      expect(found.name, equals('Find Me'));
    });

    test('should return null for non-existent email', () async {
      final notFound = await repository.findByEmail('notfound@example.com');
      expect(notFound, isNull);
    });

    test('should find subscription by ID', () async {
      final subscription = await repository.create('byid@example.com');

      final found = await repository.findById(subscription.id);
      expect(found, isNotNull);
      expect(found!.id, equals(subscription.id));
      expect(found.email, equals('byid@example.com'));
    });

    test('should get all active subscriptions', () async {
      // Create multiple subscriptions
      await repository.create('active1@example.com');
      await repository.create('active2@example.com');
      await repository.create('will-be-inactive@example.com');

      // Deactivate one
      await repository.unsubscribeByEmail('will-be-inactive@example.com');

      // Get active subscriptions
      final activeSubscriptions = await repository.findAll();
      expect(activeSubscriptions.length, equals(2));
      expect(activeSubscriptions.every((s) => s.isActive), isTrue);
    });

    test('should get all subscriptions including inactive', () async {
      // Create subscriptions
      await repository.create('all1@example.com');
      await repository.create('all2@example.com');
      await repository.create('all3@example.com');

      // Deactivate one
      await repository.unsubscribeByEmail('all2@example.com');

      // Get all subscriptions
      final allSubscriptions = await repository.findAll(activeOnly: false);
      expect(allSubscriptions.length, equals(3));

      // Get only active
      final activeSubscriptions = await repository.findAll(activeOnly: true);
      expect(activeSubscriptions.length, equals(2));
    });

    test('should unsubscribe by email', () async {
      await repository.create('unsubscribe@example.com');

      final success = await repository.unsubscribeByEmail(
        'unsubscribe@example.com',
      );
      expect(success, isTrue);

      final subscription = await repository.findByEmail(
        'unsubscribe@example.com',
      );
      expect(subscription!.isActive, isFalse);
    });

    test('should unsubscribe by token', () async {
      final subscription = await repository.create(
        'tokenunsubscribe@example.com',
      );

      final success = await repository.unsubscribeByToken(
        subscription.unsubscribeToken!,
      );
      expect(success, isTrue);

      final updated = await repository.findByEmail(
        'tokenunsubscribe@example.com',
      );
      expect(updated!.isActive, isFalse);
    });

    test('should handle invalid unsubscribe token', () async {
      final success = await repository.unsubscribeByToken('invalid-token');
      expect(success, isFalse);
    });

    test('should get active subscription count', () async {
      // Create subscriptions
      await repository.create('count1@example.com');
      await repository.create('count2@example.com');
      await repository.create('count3@example.com');

      // Deactivate one
      await repository.unsubscribeByEmail('count2@example.com');

      final activeCount = await repository.getActiveCount();
      expect(activeCount, equals(2));
    });

    test('should get subscription statistics', () async {
      // Create subscriptions
      await repository.create('stats1@example.com');
      await repository.create('stats2@example.com');
      await repository.create('stats3@example.com');
      await repository.create('stats4@example.com');

      // Deactivate some
      await repository.unsubscribeByEmail('stats3@example.com');
      await repository.unsubscribeByEmail('stats4@example.com');

      final stats = await repository.getStats();
      expect(stats['total'], equals(4));
      expect(stats['active'], equals(2));
      expect(stats['inactive'], equals(2));
    });

    test('should delete subscription permanently', () async {
      final subscription = await repository.create('delete@example.com');

      final success = await repository.delete(subscription.id);
      expect(success, isTrue);

      final notFound = await repository.findById(subscription.id);
      expect(notFound, isNull);
    });

    test('should handle deleting non-existent subscription', () async {
      final success = await repository.delete('non-existent-id');
      expect(success, isFalse);
    });

    test('should reactivate subscription', () async {
      // Create and deactivate subscription
      await repository.create('reactivate2@example.com');
      await repository.unsubscribeByEmail('reactivate2@example.com');

      // Verify it's inactive
      final inactive = await repository.findByEmail('reactivate2@example.com');
      expect(inactive!.isActive, isFalse);

      // Reactivate
      final reactivated = await repository.reactivate(
        'reactivate2@example.com',
      );
      expect(reactivated.isActive, isTrue);

      // Verify in database
      final verified = await repository.findByEmail('reactivate2@example.com');
      expect(verified!.isActive, isTrue);
    });

    test(
      'should throw error when reactivating non-existent subscription',
      () async {
        expect(
          () => repository.reactivate('nonexistent@example.com'),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('should handle empty email validation in find operations', () async {
      final notFound = await repository.findByEmail('');
      expect(notFound, isNull);
    });

    test('should maintain subscription order by date', () async {
      // Create subscriptions with slight delay to ensure different timestamps
      await repository.create('first@example.com');
      await Future.delayed(Duration(milliseconds: 10));
      await repository.create('second@example.com');
      await Future.delayed(Duration(milliseconds: 10));
      await repository.create('third@example.com');

      final subscriptions = await repository.findAll();

      // Should be ordered by subscribedAt desc (newest first)
      expect(subscriptions.length, equals(3));
      expect(
        subscriptions[0].email,
        equals('first@example.com'),
      ); // Actually first in results
      expect(
        subscriptions[1].email,
        equals('second@example.com'),
      ); // Second in results
      expect(
        subscriptions[2].email,
        equals('third@example.com'),
      ); // Third in results
    });
  });
}
