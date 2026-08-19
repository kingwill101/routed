import 'package:routed_analyzer/src/inspection/metadata.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderMetadata', () {
    test('fromJson/toJson round-trip preserves all fields', () {
      final json = <String, Object?>{
        'id': 'core',
        'description': 'Core provider',
        'providerType': 'CoreServiceProvider',
        'configurationType': 'EngineConfig',
      };
      final meta = ProviderMetadata.fromJson(json);
      expect(meta.id, 'core');
      expect(meta.description, 'Core provider');
      expect(meta.providerType, 'CoreServiceProvider');
      expect(meta.configurationType, 'EngineConfig');

      final serialized = meta.toJson();
      expect(serialized['id'], 'core');
      expect(serialized['description'], 'Core provider');
      expect(serialized['configurationType'], 'EngineConfig');
    });

    test('fromJson handles missing fields gracefully', () {
      final meta = ProviderMetadata.fromJson(<String, Object?>{});
      expect(meta.id, '');
      expect(meta.description, '');
      expect(meta.providerType, '');
      expect(meta.configurationType, isNull);
    });
  });
}
