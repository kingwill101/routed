import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

// Posts table definition
@DataClassName('BlogPost')
class Posts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 200)();

  TextColumn get content => text()();

  TextColumn get author => text().withLength(min: 1, max: 100)();

  TextColumn get slug => text().unique()();

  BoolColumn get isPublished => boolean().withDefault(const Constant(false))();

  TextColumn get tags => text().nullable()(); // JSON array of tags as string
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// Comments table definition
@DataClassName('BlogComment')
class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get content => text().withLength(min: 1, max: 1000)();

  TextColumn get author => text().withLength(min: 1, max: 100)();

  IntColumn get postId => integer().references(Posts, #id)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Newsletter subscriptions table definition
@DataClassName('NewsletterSubscription')
class NewsletterSubscriptions extends Table {
  TextColumn get id => text()(); // UUID primary key
  TextColumn get email => text().unique()(); // Unique email addresses
  TextColumn get name => text().nullable()(); // Optional name
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  TextColumn get unsubscribeToken =>
      text().nullable()(); // For unsubscribe links
  DateTimeColumn get subscribedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// Database class
@DriftDatabase(tables: [Posts, Comments, NewsletterSubscriptions])
class BlogDatabase extends _$BlogDatabase {
  final bool _skipSeedData;

  BlogDatabase({bool inMemory = false, bool skipSeedData = false})
    : _skipSeedData = skipSeedData || inMemory,
      // Skip seeding for tests
      super(_openConnection(inMemory: inMemory));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();

      // Only seed data for production databases
      if (!_skipSeedData) {
        await _seedInitialData();
      }
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from == 1 && to == 2) {
        await m.createTable(newsletterSubscriptions);
      }
    },
  );

  // Seed initial blog data
  Future<void> _seedInitialData() async {
    await batch((b) {
      b.insertAll(posts, [
        PostsCompanion.insert(
          title: 'Welcome to SimpleBlog',
          content: '''
# Welcome to SimpleBlog!

This is your first blog post created with **class_view** and **Drift**.

## Features

- ✅ Full CRUD operations
- ✅ Reactive database with Drift
- ✅ Beautiful Liquid templates
- ✅ Form validation
- ✅ Search functionality
- ✅ Comments system

Enjoy exploring the features!
          ''',
          author: 'Admin',
          slug: 'welcome-to-simpleblog',
          isPublished: const Value(true),
          tags: const Value('welcome,demo,blog'),
        ),
        PostsCompanion.insert(
          title: 'Getting Started with Class View',
          content: '''
# Getting Started

This blog demonstrates the power of combining Django-style class-based views with modern Dart web development.

## Key Features

1. **Clean CRUD Views**: ListView, DetailView, CreateView, UpdateView, DeleteView
2. **Powerful Mixins**: Composable functionality
3. **Type-safe Forms**: BaseForm with field validation
4. **Template System**: Liquid templating with inheritance

Happy coding!
          ''',
          author: 'Developer',
          slug: 'getting-started-with-class-view',
          isPublished: const Value(true),
          tags: const Value('tutorial,class-view,dart'),
        ),
      ]);
    });
  }

  // Post queries
  Future<List<BlogPost>> getAllPosts({bool publishedOnly = false}) {
    final query = select(posts);
    if (publishedOnly) {
      query.where((p) => p.isPublished.equals(true));
    }
    query.orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    return query.get();
  }

  Stream<List<BlogPost>> watchAllPosts({bool publishedOnly = false}) {
    final query = select(posts);
    if (publishedOnly) {
      query.where((p) => p.isPublished.equals(true));
    }
    query.orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    return query.watch();
  }

  Future<BlogPost?> getPostById(int id) {
    return (select(posts)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  Future<BlogPost?> getPostBySlug(String slug) {
    return (select(posts)..where((p) => p.slug.equals(slug))).getSingleOrNull();
  }

  Future<int> createPost(PostsCompanion post) {
    return into(posts).insert(post);
  }

  Future<bool> updatePost(int id, PostsCompanion post) async {
    final affectedRows = await (update(
      posts,
    )..where((p) => p.id.equals(id))).write(post);
    return affectedRows > 0;
  }

  Future<int> deletePost(int id) {
    return (delete(posts)..where((p) => p.id.equals(id))).go();
  }

  // Comment queries
  Future<List<BlogComment>> getCommentsForPost(int postId) {
    return (select(comments)
          ..where((c) => c.postId.equals(postId))
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .get();
  }

  Stream<List<BlogComment>> watchCommentsForPost(int postId) {
    return (select(comments)
          ..where((c) => c.postId.equals(postId))
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .watch();
  }

  Future<int> createComment(CommentsCompanion comment) {
    return into(comments).insert(comment);
  }

  Future<int> deleteComment(int id) {
    return (delete(comments)..where((c) => c.id.equals(id))).go();
  }

  // Search functionality
  Future<List<BlogPost>> searchPosts(
    String query, {
    bool publishedOnly = false,
  }) {
    final searchQuery = select(posts);
    searchQuery.where(
      (p) =>
          p.title.contains(query) |
          p.content.contains(query) |
          p.tags.contains(query),
    );

    if (publishedOnly) {
      searchQuery.where((p) => p.isPublished.equals(true));
    }

    searchQuery.orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    return searchQuery.get();
  }

  // Pagination support
  Future<({List<BlogPost> items, int total})> getPaginatedPosts({
    int page = 1,
    int pageSize = 10,
    bool publishedOnly = false,
    String? search,
  }) async {
    final query = select(posts);

    if (publishedOnly) {
      query.where((p) => p.isPublished.equals(true));
    }

    if (search != null && search.isNotEmpty) {
      query.where(
        (p) =>
            p.title.contains(search) |
            p.content.contains(search) |
            p.tags.contains(search),
      );
    }

    query.orderBy([(p) => OrderingTerm.desc(p.createdAt)]);

    // Get total count
    final totalQuery = selectOnly(posts)..addColumns([posts.id.count()]);
    if (publishedOnly) {
      totalQuery.where(posts.isPublished.equals(true));
    }
    if (search != null && search.isNotEmpty) {
      totalQuery.where(
        posts.title.contains(search) |
            posts.content.contains(search) |
            posts.tags.contains(search),
      );
    }

    final total = await totalQuery.getSingle().then(
      (row) => row.read(posts.id.count()) ?? 0,
    );

    // Get paginated results
    query.limit(pageSize, offset: (page - 1) * pageSize);
    final items = await query.get();

    return (items: items, total: total);
  }

  // Newsletter subscription queries
  Future<List<NewsletterSubscription>> getAllSubscriptions({
    bool activeOnly = true,
  }) {
    final query = select(newsletterSubscriptions);
    if (activeOnly) {
      query.where((s) => s.isActive.equals(true));
    }
    query.orderBy([(s) => OrderingTerm.desc(s.subscribedAt)]);
    return query.get();
  }

  Future<NewsletterSubscription?> getSubscriptionByEmail(String email) {
    return (select(
      newsletterSubscriptions,
    )..where((s) => s.email.equals(email))).getSingleOrNull();
  }

  Future<NewsletterSubscription?> getSubscriptionById(String id) {
    return (select(
      newsletterSubscriptions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<int> createSubscription(
    NewsletterSubscriptionsCompanion subscription,
  ) {
    return into(
      newsletterSubscriptions,
    ).insert(subscription, mode: InsertMode.insertOrReplace);
  }

  Future<bool> updateSubscription(
    String id,
    NewsletterSubscriptionsCompanion subscription,
  ) async {
    final affectedRows = await (update(
      newsletterSubscriptions,
    )..where((s) => s.id.equals(id))).write(subscription);
    return affectedRows > 0;
  }

  Future<int> deleteSubscription(String id) {
    return (delete(
      newsletterSubscriptions,
    )..where((s) => s.id.equals(id))).go();
  }

  Future<bool> unsubscribeByEmail(String email) async {
    final affectedRows =
        await (update(
          newsletterSubscriptions,
        )..where((s) => s.email.equals(email))).write(
          const NewsletterSubscriptionsCompanion(isActive: Value(false)),
        );
    return affectedRows > 0;
  }

  Future<bool> unsubscribeByToken(String token) async {
    final affectedRows =
        await (update(
          newsletterSubscriptions,
        )..where((s) => s.unsubscribeToken.equals(token))).write(
          const NewsletterSubscriptionsCompanion(isActive: Value(false)),
        );
    return affectedRows > 0;
  }

  // Get active subscription count
  Future<int> getActiveSubscriptionCount() async {
    final query = selectOnly(newsletterSubscriptions)
      ..addColumns([newsletterSubscriptions.id.count()])
      ..where(newsletterSubscriptions.isActive.equals(true));
    return await query.getSingle().then(
      (row) => row.read(newsletterSubscriptions.id.count()) ?? 0,
    );
  }
}

// Database connection
LazyDatabase _openConnection({bool inMemory = false}) {
  return LazyDatabase(() async {
    if (inMemory) {
      // Use in-memory database for testing
      return NativeDatabase.memory();
    } else {
      // For server applications, we'll use a local SQLite file
      final file = File('blog.db');
      return NativeDatabase(file);
    }
  });
}

// Database Service with singleton pattern
class DatabaseService {
  static BlogDatabase? _instance;
  static bool _isTestEnvironment = false;

  // Set test environment flag
  static void setTestEnvironment(bool isTest) {
    _isTestEnvironment = isTest;
  }

  // Get singleton database instance
  static BlogDatabase get instance {
    _instance ??= BlogDatabase(
      inMemory: _isTestEnvironment,
      skipSeedData: _isTestEnvironment,
    );
    return _instance!;
  }

  // Reset instance (useful for tests)
  static void reset() {
    _instance?.close();
    _instance = null;
  }

  // Get a fresh database instance for tests
  static BlogDatabase createTestDatabase() {
    return BlogDatabase(inMemory: true, skipSeedData: true);
  }
}
