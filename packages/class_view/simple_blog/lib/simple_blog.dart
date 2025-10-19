/// SimpleBlog - A demonstration of class_view features
///
/// This library demonstrates how to build a complete blog application
/// using the class_view framework with Dart and Shelf.
library;

// Export database
export 'src/database/database.dart' hide NewsletterSubscription;

// Forms
export 'src/forms/post_form.dart';
export 'src/models/comment.dart';
export 'src/models/newsletter_subscription.dart';

// Export models
export 'src/models/post.dart';
export 'src/repositories/newsletter_repository.dart';

// Export repositories
export 'src/repositories/post_repository.dart';

// Export server
export 'src/server.dart';
export 'src/views/api/newsletter_view.dart';
export 'src/views/api/post_create_view.dart';
export 'src/views/api/post_delete_view.dart';
export 'src/views/api/post_detail_view.dart';

// Export API views (JSON responses)
export 'src/views/api/post_list_view.dart';
export 'src/views/api/post_update_view.dart';

// Export Web views (HTML template responses)
export 'src/views/web/home_view.dart';
export 'src/views/web/post_detail_view.dart';
export 'src/views/web/post_form_view.dart';
export 'src/views/web/post_list_view.dart';
