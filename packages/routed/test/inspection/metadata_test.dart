import 'package:routed/src/inspection/metadata.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigFieldMetadata', () {
    test('fromJson/toJson round-trip preserves all fields', () {
      final json = <String, Object?>{
        'path': 'app.name',
        'type': 'string',
        'description': 'Application name',
        'default': 'MyApp',
        'deprecated': true,
        'options': ['a', 'b'],
        'metadata': {'custom': 42},
      };
      final meta = ConfigFieldMetadata.fromJson(json);
      expect(meta.path, 'app.name');
      expect(meta.type, 'string');
      expect(meta.description, 'Application name');
      expect(meta.defaultValue, 'MyApp');
      expect(meta.deprecated, isTrue);
      expect(meta.options, ['a', 'b']);
      expect(meta.metadata, {'custom': 42});

      final serialized = meta.toJson();
      expect(serialized['path'], 'app.name');
      expect(serialized['type'], 'string');
      expect(serialized['description'], 'Application name');
      expect(serialized['default'], 'MyApp');
      expect(serialized['deprecated'], isTrue);
      expect(serialized['options'], ['a', 'b']);
      expect(serialized['metadata'], {'custom': 42});
    });

    test('fromJson handles minimal input', () {
      final meta = ConfigFieldMetadata.fromJson(<String, Object?>{});
      expect(meta.path, '');
      expect(meta.type, isNull);
      expect(meta.description, isNull);
      expect(meta.defaultValue, isNull);
      expect(meta.deprecated, isFalse);
      expect(meta.options, isEmpty);
      expect(meta.metadata, isEmpty);
    });

    test('toJson omits null and empty fields', () {
      final meta = ConfigFieldMetadata(path: 'x');
      final json = meta.toJson();
      expect(json.containsKey('type'), isFalse);
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('default'), isFalse);
      expect(json.containsKey('deprecated'), isFalse);
      expect(json.containsKey('options'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });
  });

  group('ProviderMetadata', () {
    test('fromJson/toJson round-trip preserves all fields', () {
      final json = <String, Object?>{
        'id': 'core',
        'description': 'Core provider',
        'providerType': 'CoreServiceProvider',
        'configSource': 'CoreServiceProvider',
        'defaults': <String, Object?>{'app.name': 'Test'},
        'fields': [
          <String, Object?>{
            'path': 'app.name',
            'type': 'string',
            'description': 'App name',
            'default': 'Test',
          },
        ],
      };
      final meta = ProviderMetadata.fromJson(json);
      expect(meta.id, 'core');
      expect(meta.description, 'Core provider');
      expect(meta.providerType, 'CoreServiceProvider');
      expect(meta.configSource, 'CoreServiceProvider');
      expect(meta.defaults, {'app.name': 'Test'});
      expect(meta.fields, hasLength(1));
      expect(meta.fields.first.path, 'app.name');

      final serialized = meta.toJson();
      expect(serialized['id'], 'core');
      expect(serialized['description'], 'Core provider');
      expect(serialized['fields'], hasLength(1));
    });

    test('fromJson handles missing fields gracefully', () {
      final meta = ProviderMetadata.fromJson(<String, Object?>{});
      expect(meta.id, '');
      expect(meta.description, '');
      expect(meta.providerType, '');
      expect(meta.configSource, '');
      expect(meta.defaults, isEmpty);
      expect(meta.fields, isEmpty);
      expect(meta.schemas, isEmpty);
    });
  });
}
