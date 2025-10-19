import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

class TestPost {
  final int id;
  final String title;
  final String content;

  TestPost({required this.id, required this.title, required this.content});
}

class TestPostTemplateDetailView extends TemplateDetailView<TestPost> {
  @override
  Future<TestPost?> getObject() async {
    final id = await request().get('id');
    if (id == null || id.isEmpty) return null;
    if (id == '999') return null;
    return TestPost(
      id: int.parse(id),
      title: 'Test Post',
      content: 'Test Content',
    );
  }

  @override
  String get templateName => 'post_detail';
}

void main() {
  late MockViewAdapter adapter;
  late TestPostTemplateDetailView view;

  setUp(() {
    adapter = MockViewAdapter();
    view = TestPostTemplateDetailView();
    view.setAdapter(adapter);
    // Configure TemplateManager for testing
    TemplateManager.configureMemoryOnly();
  });

  tearDown(() {
    // Reset TemplateManager after each test
    TemplateManager.reset();
  });

  group('TemplateDetailView', () {
    test('renders template with object data', () async {
      // Setup
      when(adapter.getMethod()).thenAnswer((_) async => 'GET');
      when(adapter.getUri()).thenAnswer((_) async => Uri.parse('/posts/1'));
      when(adapter.getRouteParams()).thenAnswer((_) async => {'id': '1'});
      when(adapter.getParam('id')).thenAnswer((_) async => '1');

      // Mock template rendering
      when(adapter.write(any)).thenAnswer((_) async {});

      // Execute
      await view.dispatch();

      // Verify
      verify(adapter.write(any)).called(1);
      verify(adapter.setStatusCode(200)).called(1);
    });

    test('handles object not found', () async {
      // Setup
      when(adapter.getMethod()).thenAnswer((_) async => 'GET');
      when(adapter.getUri()).thenAnswer((_) async => Uri.parse('/posts/999'));
      when(adapter.getRouteParams()).thenAnswer((_) async => {'id': '999'});
      when(adapter.getParam('id')).thenAnswer((_) async => '999');

      // Execute
      await view.dispatch();

      // Verify
      verify(adapter.writeJson(any, statusCode: 404)).called(1);
    });

    test('handles errors gracefully', () async {
      // Setup
      when(adapter.getMethod()).thenAnswer((_) async => 'GET');
      when(adapter.getUri()).thenAnswer((_) async => Uri.parse('/posts/1'));
      when(adapter.getRouteParams()).thenAnswer((_) async => {'id': '1'});
      when(adapter.getParam('id')).thenAnswer((_) async => '1');

      // Mock template rendering to throw error
      when(adapter.write(any)).thenThrow(Exception('Template error'));

      // Execute
      await view.dispatch();

      // Verify
      verify(adapter.writeJson(any, statusCode: 500)).called(1);
    });
  });
}
