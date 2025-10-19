import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:simple_blog/simple_blog.dart';

void main() {
  group('SimpleBlog Integration Tests', () {
    late TestClient client;

    setUpAll(() async {
      // Set test environment to use in-memory databases
      DatabaseService.setTestEnvironment(true);

      // Create the real handler from our server
      final handler = createHandler();

      // Create test client with the real handler using server_testing_shelf
      client = TestClient.inMemory(ShelfRequestHandler(handler));
    });

    tearDownAll(() async {
      await client.close();
      // Reset database instance and test environment
      DatabaseService.reset();
      DatabaseService.setTestEnvironment(false);
    });

    group('Home View Tests', () {
      test('GET / should return home page with features', () async {
        final response = await client.get('/');

        response.assertStatus(200).assertJson((json) {
          json
              .has('page_title')
              .where('page_title', contains('SimpleBlog'))
              .has('page_description')
              .has('features')
              .where('features', isA<List>())
              .has('total_posts')
              .has('published_posts')
              .has('recent_posts')
              .where('recent_posts', isA<List>());
        });
      });
    });

    group('Post List View Tests', () {
      test('GET /api/posts should return paginated posts list', () async {
        final response = await client.get('/api/posts');

        response.assertStatus(200).assertJson((json) {
          json
              .has('object_list')
              .where('object_list', isA<List>())
              .has('paginator')
              .has('page_title')
              .has('search_query')
              .where('search_query', '')
              .has('show_search')
              .where('show_search', true);
        });
      });

      test('GET /api/posts with search should filter results', () async {
        // First create a post to search for
        await client.postJson('/api/posts', {
          'title': 'Searchable Test Post',
          'content': 'This post contains unique searchable content',
          'author': 'Test Author',
          'isPublished': true,
        });

        final response = await client.get('/api/posts?search=searchable');

        response.assertStatus(200).assertJson((json) {
          json
              .has('search_query')
              .where('search_query', 'searchable')
              .has('object_list')
              .where('object_list', isA<List>())
              .has('page_title')
              .where('page_title', contains('Search Results'));
        });
      });

      test('GET /api/posts with pagination should work correctly', () async {
        final response = await client.get('/api/posts?page=1&page_size=2');

        response.assertStatus(200).assertJson((json) {
          json
              .has('paginator')
              .where('paginator.page_size', 2)
              .where('paginator.current_page', 1)
              .has('object_list')
              .where('object_list', isA<List>());
        });
      });
    });

    group('Post Create View Tests', () {
      test('GET /posts/new should return create form info', () async {
        final response = await client.get('/posts/new');

        response.assertStatus(200).assertJson((json) {
          json
              .has('message')
              .where('message', contains('Create'))
              .has('required_fields')
              .where('required_fields', isA<List>())
              .has('form_method')
              .where('form_method', 'POST')
              .has('validation')
              .has('example');
        });
      });

      test('POST /api/posts should create new post successfully', () async {
        final response = await client.postJson('/api/posts', {
          'title': 'Integration Test Post',
          'content': 'This is test content for integration testing',
          'author': 'Integration Tester',
          'isPublished': true,
          'tags': 'test,integration,automation',
        });

        response.assertStatus(201).assertJson((json) {
          json
              .has('success')
              .where('success', true)
              .has('post')
              .has('message')
              .where('message', contains('successfully'))
              .has('redirect_url')
              .has('post.id')
              .has('post.title')
              .where('post.title', 'Integration Test Post')
              .has('post.author')
              .where('post.author', 'Integration Tester')
              .has('post.content')
              .has('post.slug')
              .has('post.isPublished')
              .where('post.isPublished', true)
              .has('post.tags')
              .where('post.tags', isA<List>())
              .has('post.createdAt')
              .has('post.updatedAt');
        });
      });

      test(
        'POST /api/posts with invalid data should return validation errors',
        () async {
          final response = await client.postJson('/api/posts', {
            'title': '', // Empty title should fail
            'content': '',
            'author': '',
          });

          response.assertStatus(400).assertJson((json) {
            json
                .has('success')
                .where('success', false)
                .has('error')
                .where('error', contains('required'));
          });
        },
      );

      test(
        'POST /api/posts with long title should return validation error',
        () async {
          final longTitle = 'A' * 250; // Over 200 character limit

          final response = await client.postJson('/api/posts', {
            'title': longTitle,
            'content': 'Valid content',
            'author': 'Valid Author',
          });

          response.assertStatus(400).assertJson((json) {
            json
                .has('success')
                .where('success', false)
                .has('error')
                .where('error', contains('200 characters'));
          });
        },
      );
    });

    group('Post Detail View Tests', () {
      test('GET /api/posts/{slug} should return post details', () async {
        // Create a post first
        final createResponse = await client.postJson('/api/posts', {
          'title': 'Detail View Test Post',
          'content': '# Test Content\n\nThis is for testing the detail view.',
          'author': 'Detail Tester',
          'isPublished': true,
        });

        createResponse.assertStatus(201);
        final createdPost = createResponse.json()['post'];
        final slug = createdPost['slug'];

        final response = await client.get('/api/posts/$slug');

        response.assertStatus(200).assertJson((json) {
          json
              .has('post')
              .has('page_title')
              .where('page_title', createdPost['title'])
              .has('page_description')
              .has('author')
              .has('published_date');
        });
      });

      test('GET /api/posts/nonexistent-slug should return 404', () async {
        final response = await client.get('/api/posts/nonexistent-post-slug');

        response.assertStatus(404).assertJson((json) {
          json.has('error').where('error', contains('not found'));
        });
      });
    });

    group('Post Update View Tests', () {
      test('PUT /api/posts/{id} should update post successfully', () async {
        // Create a post first
        final createResponse = await client.postJson('/api/posts', {
          'title': 'Original Title',
          'content': 'Original content',
          'author': 'Original Author',
          'isPublished': false,
        });

        createResponse.assertStatus(201);
        final createdPost = createResponse.json()['post'];
        final postId = createdPost['id'];

        final updateResponse = await client.putJson('/api/posts/$postId', {
          'title': 'Updated Title',
          'content': 'Updated content with new information',
          'author': 'Updated Author',
          'isPublished': true,
        });

        updateResponse.assertStatus(200).assertJson((json) {
          json
              .has('success')
              .where('success', true)
              .has('post')
              .has('message')
              .where('message', contains('updated'))
              .has('post.title')
              .where('post.title', 'Updated Title')
              .has('post.content')
              .where('post.content', 'Updated content with new information')
              .has('post.isPublished')
              .where('post.isPublished', true);
        });
      });

      test('PUT /api/posts/invalid-id should return 404', () async {
        final response = await client.putJson('/api/posts/invalid-id', {
          'title': 'Updated Title',
          'content': 'Updated content',
          'author': 'Author',
        });

        response
            .assertStatus(404) // Invalid ID returns 404 (not found)
            .assertJson((json) {
              json.has('error').where('error', contains('not found'));
            });
      });
    });

    group('Post Delete View Tests', () {
      test('DELETE /api/posts/{id} should delete post successfully', () async {
        // Create a post first
        final createResponse = await client.postJson('/api/posts', {
          'title': 'Post to Delete',
          'content': 'This post will be deleted',
          'author': 'Delete Tester',
        });

        createResponse.assertStatus(201);
        final createdPost = createResponse.json()['post'];
        final postId = createdPost['id'];

        final deleteResponse = await client.delete('/api/posts/$postId');

        deleteResponse.assertStatus(200).assertJson((json) {
          json
              .has('success')
              .where('success', true)
              .has('message')
              .where('message', contains('deleted'))
              .has('redirect_url');
        });

        // Verify post is actually deleted
        final getResponse = await client.get('/api/posts');
        getResponse.assertStatus(200);

        final posts = getResponse.json()['object_list'] as List;
        final deletedPostExists = posts.any((p) => p['id'] == postId);
        expect(deletedPostExists, isFalse, reason: 'Post should be deleted');
      });

      test('DELETE /api/posts/invalid-id should return 404', () async {
        final response = await client.delete('/api/posts/invalid-id');

        response
            .assertStatus(404) // Invalid ID returns 404 (not found)
            .assertJson((json) {
              json.has('error').where('error', contains('not found'));
            });
      });
    });

    group('Health Check Tests', () {
      test('GET /health should return health status', () async {
        final response = await client.get('/health');

        response.assertStatus(200).assertBody('SimpleBlog is running!');
      });
    });

    group('Newsletter API Tests', () {
      test('GET /api/newsletter should return API information', () async {
        final response = await client.get('/api/newsletter');

        response.assertStatus(200).assertJson((json) {
          json
              .has('message')
              .where('message', contains('Newsletter subscription API'))
              .has('required_fields')
              .where('required_fields', contains('email'))
              .has('endpoints')
              .has('stats');
        });
      });

      test(
        'POST /api/newsletter should create new subscription successfully',
        () async {
          final response = await client.postJson('/api/newsletter', {
            'email': 'test@example.com',
            'name': 'Test User',
          });

          response.assertStatus(201).assertJson((json) {
            json
                .has('success')
                .where('success', true)
                .has('subscription')
                .has('message')
                .where('message', contains('Successfully subscribed'))
                .has('subscription.email')
                .where('subscription.email', 'test@example.com')
                .has('subscription.name')
                .where('subscription.name', 'Test User')
                .has('subscription.is_active')
                .where('subscription.is_active', true);
          });
        },
      );

      test('POST /api/newsletter should validate required email', () async {
        final response = await client.postJson('/api/newsletter', {
          'name': 'Test User',
        });

        response.assertStatus(400).assertJson((json) {
          json
              .has('success')
              .where('success', false)
              .has('error')
              .where('error', contains('Email is required'));
        });
      });

      test('POST /api/newsletter should validate email format', () async {
        final response = await client.postJson('/api/newsletter', {
          'email': 'invalid-email',
          'name': 'Test User',
        });

        response.assertStatus(400).assertJson((json) {
          json
              .has('success')
              .where('success', false)
              .has('error')
              .where('error', contains('valid email address'));
        });
      });

      test(
        'POST /api/newsletter should handle duplicate email subscription',
        () async {
          final subscriptionData = {
            'email': 'duplicate@example.com',
            'name': 'First User',
          };

          // First subscription
          final response1 = await client.postJson(
            '/api/newsletter',
            subscriptionData,
          );
          response1.assertStatus(201);

          // Second subscription with same email
          final response2 = await client.postJson(
            '/api/newsletter',
            subscriptionData,
          );
          response2
              .assertStatus(409) // Conflict
              .assertJson((json) {
                json
                    .has('success')
                    .where('success', false)
                    .has('error')
                    .where('error', contains('already subscribed'));
              });
        },
      );

      test(
        'POST /api/newsletter should allow subscription without name',
        () async {
          final response = await client.postJson('/api/newsletter', {
            'email': 'noname@example.com',
          });

          response.assertStatus(201).assertJson((json) {
            json
                .has('success')
                .where('success', true)
                .has('subscription.email')
                .where('subscription.email', 'noname@example.com')
                .has('subscription.name')
                .where('subscription.name', isNull);
          });
        },
      );

      test(
        'GET /api/newsletter/stats should return subscription statistics',
        () async {
          final response = await client.get('/api/newsletter/stats');

          response.assertStatus(200).assertJson((json) {
            json
                .has('stats')
                .has('stats.total')
                .has('stats.active')
                .has('stats.inactive')
                .has('recent_subscriptions')
                .where('recent_subscriptions', isA<List>());
          });
        },
      );

      test(
        'DELETE /api/newsletter/<email> should unsubscribe existing user',
        () async {
          // First, create a subscription
          final createResponse = await client.postJson('/api/newsletter', {
            'email': 'tounsubscribe@example.com',
            'name': 'Unsubscribe Test',
          });
          createResponse.assertStatus(201);

          // Then unsubscribe
          final response = await client.delete(
            '/api/newsletter/tounsubscribe@example.com',
          );

          response.assertStatus(200).assertJson((json) {
            json
                .has('success')
                .where('success', true)
                .has('message')
                .where('message', contains('Successfully unsubscribed'))
                .has('email')
                .where('email', 'tounsubscribe@example.com');
          });
        },
      );

      test(
        'DELETE /api/newsletter/<email> should handle non-existent email',
        () async {
          final response = await client.delete(
            '/api/newsletter/nonexistent@example.com',
          );

          response.assertStatus(404).assertJson((json) {
            json
                .has('success')
                .where('success', false)
                .has('error')
                .where('error', contains('not found'));
          });
        },
      );

      test(
        'POST /api/newsletter should reactivate inactive subscription',
        () async {
          final subscriptionData = {
            'email': 'reactivate@example.com',
            'name': 'Reactivate Test',
          };

          // Create subscription
          final createResponse = await client.postJson(
            '/api/newsletter',
            subscriptionData,
          );
          createResponse.assertStatus(201);

          // Unsubscribe
          final unsubscribeResponse = await client.delete(
            '/api/newsletter/reactivate@example.com',
          );
          unsubscribeResponse.assertStatus(200);

          // Try to subscribe again (should reactivate)
          final reactivateResponse = await client.postJson(
            '/api/newsletter',
            subscriptionData,
          );
          reactivateResponse.assertStatus(201).assertJson((json) {
            json
                .has('success')
                .where('success', true)
                .has('subscription.email')
                .where('subscription.email', 'reactivate@example.com')
                .has('subscription.is_active')
                .where('subscription.is_active', true);
          });
        },
      );

      test(
        'POST /api/newsletter should normalize email to lowercase',
        () async {
          final response = await client.postJson('/api/newsletter', {
            'email': 'UPPERCASE@EXAMPLE.COM',
            'name': 'Case Test',
          });

          response.assertStatus(201).assertJson((json) {
            json
                .has('success')
                .where('success', true)
                .has('subscription.email')
                .where('subscription.email', 'uppercase@example.com');
          });
        },
      );
    });
  });
}
