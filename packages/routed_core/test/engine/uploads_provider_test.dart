import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'UploadsServiceProvider applies its typed configuration at boot',
    () async {
      final uploads = MultipartConfig(
        maxMemory: 2048,
        maxFileSize: 4096,
        maxDiskUsage: 8192,
        allowedExtensions: {'txt', 'csv'},
        uploadDirectory: 'var/uploads',
        filePermissions: 0x1a4,
      );
      final engine = Engine(
        providers: [
          CoreServiceProvider(),
          RoutingServiceProvider(),
          UploadsServiceProvider(uploads),
        ],
      );
      addTearDown(engine.close);

      await engine.initialize();

      expect(engine.typedConfig<MultipartConfig>(), same(uploads));
      expect(engine.config.multipart.maxMemory, equals(2048));
      expect(engine.config.multipart.maxFileSize, equals(4096));
      expect(engine.config.multipart.maxDiskUsage, equals(8192));
      expect(engine.config.multipart.allowedExtensions, equals({'txt', 'csv'}));
      expect(engine.config.multipart.uploadDirectory, equals('var/uploads'));
    },
  );

  test(
    'UploadsServiceProvider validates unsafe typed configuration before boot',
    () async {
      final engine = Engine(
        providers: [
          CoreServiceProvider(),
          RoutingServiceProvider(),
          UploadsServiceProvider(
            MultipartConfig(
              maxMemory: 0,
              maxFileSize: 0,
              uploadDirectory: '',
              filePermissions: 0x400,
            ),
          ),
        ],
      );
      addTearDown(engine.close);

      await expectLater(
        engine.initialize(),
        throwsA(isA<ConfigValidationException>()),
      );
    },
  );
}
