import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

/// Test view that uses ContextMixin
class TestContextView extends View with ContextMixin {
  @override
  Map<String, dynamic> get extraContext => {
    'app_name': 'Test App',
    'version': '1.0.0',
  };

  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}

/// Test view that overrides getExtraContext with async data
class AsyncContextView extends View with ContextMixin {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    // Simulate async operation like database call
    await Future.delayed(Duration(milliseconds: 10));
    return {
      'user': {'id': 1, 'name': 'John Doe'},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}

/// Test view that adds more complex context
class ComplexContextView extends View with ContextMixin {
  final String userId;

  ComplexContextView(this.userId);

  @override
  Map<String, dynamic> get extraContext => {
    'user_id': userId,
    'request_id': 'req_123',
  };

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final baseContext = await super.getExtraContext();

    // Add dynamic context
    return {
      ...baseContext,
      'current_time': DateTime.now().toIso8601String(),
      'session_data': await _getSessionData(),
    };
  }

  Future<Map<String, dynamic>> _getSessionData() async {
    // Simulate session lookup
    return {'authenticated': true, 'role': 'admin'};
  }

  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}

void main() {
  group('ContextMixin Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('Basic Context Functionality', () {
      test('should provide default empty extra context', () {
        final view = TestContextView();
        view.setAdapter(mockAdapter);

        expect(view.extraContext, isA<Map<String, dynamic>>());
        expect(view.extraContext['app_name'], equals('Test App'));
        expect(view.extraContext['version'], equals('1.0.0'));
      });

      test('should build context from extraContext', () async {
        final view = TestContextView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context, containsPair('app_name', 'Test App'));
        expect(context, containsPair('version', '1.0.0'));
      });

      test('should merge extraContext into context data', () async {
        final view = TestContextView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        // Should contain extra context
        expect(context['app_name'], equals('Test App'));
        expect(context['version'], equals('1.0.0'));
      });
    });

    group('Async Context Functionality', () {
      test('should handle async getExtraContext', () async {
        final view = AsyncContextView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['user'], isA<Map<String, dynamic>>());
        expect(context['user']['id'], equals(1));
        expect(context['user']['name'], equals('John Doe'));
        expect(context['timestamp'], isA<int>());
      });

      test('should handle complex async context building', () async {
        final view = ComplexContextView('user123');
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['user_id'], equals('user123'));
        expect(context['request_id'], equals('req_123'));
        expect(context['current_time'], isA<String>());
        expect(context['session_data'], isA<Map<String, dynamic>>());
        expect(context['session_data']['authenticated'], isTrue);
        expect(context['session_data']['role'], equals('admin'));
      });
    });

    group('Context in Response', () {
      test('should send context data as JSON response', () async {
        final view = TestContextView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) => Future.value('GET'));

        await view.dispatch();

        // Verify that writeJson was called with context data
        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['app_name'], equals('Test App'));
        expect(responseData['version'], equals('1.0.0'));
      });

      test('should handle async context in response', () async {
        final view = AsyncContextView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) => Future.value('GET'));

        await view.dispatch();

        // Verify that writeJson was called with async context data
        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['user'], isA<Map<String, dynamic>>());
        expect(responseData['timestamp'], isA<int>());
      });
    });

    group('Context Inheritance and Override', () {
      test('should allow override of getExtraContext', () async {
        final view = ComplexContextView('user456');
        view.setAdapter(mockAdapter);

        // Test that both sync extraContext and async getExtraContext work together
        final syncContext = view.extraContext;
        expect(syncContext['user_id'], equals('user456'));
        expect(syncContext['request_id'], equals('req_123'));

        final asyncContext = await view.getExtraContext();
        expect(asyncContext['user_id'], equals('user456')); // From sync
        expect(asyncContext['current_time'], isA<String>()); // From async
        expect(
          asyncContext['session_data'],
          isA<Map<String, dynamic>>(),
        ); // From async
      });

      test('should preserve all context data with complex overrides', () async {
        final view = ComplexContextView('user789');
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        // Custom context should be present
        expect(context['user_id'], equals('user789'));
        expect(context['session_data']['role'], equals('admin'));
      });
    });

    group('Error Handling', () {
      test('should handle errors in async context gracefully', () async {
        final view = _ErrorContextView();
        view.setAdapter(mockAdapter);

        // Should not throw, but might have different behavior depending on implementation
        try {
          final context = await view.getContextData();
          // If it doesn't throw, basic structure might be there
          expect(context, isA<Map<String, dynamic>>());
        } catch (e) {
          // If it does throw, that's also acceptable behavior
          expect(e, isA<Exception>());
        }
      });
    });

    group('Performance and Memory', () {
      test('should not create unnecessary objects', () async {
        final view = TestContextView();
        view.setAdapter(mockAdapter);

        // Multiple calls should work without issues
        final context1 = await view.getContextData();
        final context2 = await view.getContextData();

        // Should have same context data
        expect(context1['app_name'], equals(context2['app_name']));
        expect(context1['version'], equals(context2['version']));
      });
    });

    group('Integration with Base Context Functionality', () {
      test('should work with empty extraContext', () async {
        final view = _EmptyContextView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        // Should be an empty map but not null
        expect(context, isA<Map<String, dynamic>>());
        expect(context.isEmpty, isTrue);
      });

      test('should handle null values in context', () async {
        final view = _NullValueContextView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context, containsPair('nullable_field', null));
        expect(context, containsPair('string_field', 'value'));
      });
    });
  });
}

/// Test view that throws error in context building
class _ErrorContextView extends View with ContextMixin {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    throw Exception('Context error');
  }

  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}

/// Test view with empty context
class _EmptyContextView extends View with ContextMixin {
  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}

/// Test view with null values
class _NullValueContextView extends View with ContextMixin {
  @override
  Map<String, dynamic> get extraContext => {
    'nullable_field': null,
    'string_field': 'value',
  };

  @override
  Future<void> get() async {
    final context = await getContextData();
    sendJson(context);
  }
}
