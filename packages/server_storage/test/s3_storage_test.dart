import 'package:file_cloud/drivers.dart' show MinioCloudDriver;
import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

void main() {
  group('S3StorageDisk', () {
    test('configures an S3-compatible endpoint without contacting it', () {
      final disk = S3StorageDisk(
        endpoint: 'http://127.0.0.1:9000',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
        region: 'us-east-1',
        pathStyle: true,
        prefix: '/tenant-1/assets/',
        publicUrl: Uri.parse('https://cdn.example.test'),
        autoCreateBucket: true,
        allowInsecureHttp: true,
        throwOnError: true,
        diskName: 'assets',
      );

      expect(disk.endpoint, Uri.parse('http://127.0.0.1:9000'));
      expect(disk.useSsl, isFalse);
      expect(disk.bucket, 'uploads');
      expect(disk.region, 'us-east-1');
      expect(disk.prefix, 'tenant-1/assets');
      expect(disk.publicUrl, Uri.parse('https://cdn.example.test'));
      expect(disk.pathStyle, isTrue);
      expect(disk.autoCreateBucket, isTrue);
      expect(disk.allowInsecureHttp, isTrue);
      expect(disk.diskName, 'assets');
      expect(disk.fileSystem, same(disk.adapter.fileSystem));
      expect(disk.storage, same(disk.adapter));
      expect(disk.adapter.config.throw_, isTrue);
      expect(disk.adapter.config.options, isNot(contains('secret')));
      expect(disk.adapter.config.options, isNot(contains('key')));

      final driver = disk.adapter.driver as MinioCloudDriver;
      expect(driver.client.endPoint, '127.0.0.1');
      expect(driver.client.port, 9000);
      expect(driver.client.useSSL, isFalse);
      expect(driver.client.region, 'us-east-1');
      expect(driver.rootPrefix, 'tenant-1/assets');
      expect(driver.enforcePathStyle, isTrue);
      expect(driver.autoCreateBucket, isTrue);
      expect(
        disk.adapter.url('logo.png'),
        'https://cdn.example.test/tenant-1/assets/logo.png',
      );

      final manager = StorageManager()
        ..registerDisk('assets', disk)
        ..setDefault('assets');
      expect(manager.storage(), same(disk.adapter));
      expect(manager.drive('assets'), same(disk.adapter));
      expect(manager.disk(), same(disk));
    });

    test('defaults a host-only endpoint to HTTPS', () {
      final disk = S3StorageDisk(
        endpoint: 's3.amazonaws.com',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );

      expect(disk.endpoint, Uri.parse('https://s3.amazonaws.com'));
      expect(disk.useSsl, isTrue);
      final driver = disk.adapter.driver as MinioCloudDriver;
      expect(driver.client.port, 443);
    });

    test('rejects HTTP unless local development explicitly opts in', () {
      expect(
        () => S3StorageDisk(
          endpoint: 'http://127.0.0.1:9000',
          accessKey: 'test-access-key',
          secretKey: 'test-secret-key',
          bucket: 'uploads',
        ),
        throwsArgumentError,
      );
      const endpointCredential = 'sensitive-endpoint-credential';
      expect(
        () => S3StorageDisk(
          endpoint: 'https://user:$endpointCredential@objects.example.test',
          accessKey: 'key',
          secretKey: 'secret',
          bucket: 'uploads',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(endpointCredential)),
          ),
        ),
      );
      expect(
        () => S3StorageDisk(
          endpoint: 'objects.example.test',
          accessKey: 'test-access-key',
          secretKey: 'test-secret-key',
          bucket: 'uploads',
          useSsl: false,
        ),
        throwsArgumentError,
      );
    });

    test('is immediately ready when bucket creation is disabled', () async {
      final disk = S3StorageDisk(
        endpoint: 'objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );

      await expectLater(disk.ensureReady(), completes);
    });

    test('keeps objects private and rejects public visibility', () async {
      final disk = S3StorageDisk(
        endpoint: 'objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );

      expect(await disk.storage.getVisibility('private.txt'), 'private');
      expect(
        await disk.storage.setVisibility('private.txt', 'private'),
        isTrue,
      );
      expect(
        await disk.storage.setVisibility('private.txt', 'public'),
        isFalse,
      );
      expect(
        await disk.storage.put(
          'public.txt',
          'blocked',
          options: const {'visibility': 'public'},
        ),
        isFalse,
      );
    });

    test('generates a signed temporary download URL', () async {
      final disk = S3StorageDisk(
        endpoint: 'https://objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
        region: 'us-east-1',
        pathStyle: true,
        prefix: 'tenant/private',
      );

      final manager = StorageManager()
        ..registerDisk('uploads', disk)
        ..setDefault('uploads');
      final result = await manager.temporaryUrl(
        'report.txt',
        DateTime.now().add(const Duration(minutes: 5)),
      );
      final url = Uri.parse(result);

      expect(url.path, '/uploads/tenant/private/report.txt');
      expect(url.queryParameters, contains('X-Amz-Signature'));
      expect(
        url.queryParameters,
        containsPair('X-Amz-Algorithm', 'AWS4-HMAC-SHA256'),
      );
    });

    test('generates signed temporary upload data', () async {
      final disk = S3StorageDisk(
        endpoint: 'https://objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
        region: 'us-east-1',
        pathStyle: true,
        prefix: 'tenant/private',
      );
      final manager = StorageManager()..registerDisk('uploads', disk);

      final result = await manager.temporaryUploadUrl(
        'report.txt',
        DateTime.now().add(const Duration(minutes: 5)),
        disk: 'uploads',
      );
      final url = Uri.parse(result['url']! as String);

      expect(url.path, '/uploads/tenant/private/report.txt');
      expect(url.queryParameters, contains('X-Amz-Signature'));
      expect(result['headers'], isEmpty);
    });

    test('temporary URLs reject keys outside the disk boundary', () async {
      final disk = S3StorageDisk(
        endpoint: 'https://objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );
      final manager = StorageManager()
        ..registerDisk('uploads', disk)
        ..setDefault('uploads');

      await expectLater(
        manager.temporaryUrl(
          '../outside.txt',
          DateTime.now().add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('supports temporary session credentials', () {
      final disk = S3StorageDisk(
        endpoint: 'https://objects.example.test',
        accessKey: 'temporary-access-key',
        secretKey: 'temporary-secret-key',
        sessionToken: 'session-token',
        bucket: 'uploads',
      );

      final driver = disk.adapter.driver as MinioCloudDriver;
      expect(driver.client.sessionToken, 'session-token');
    });

    test('normalizes safe relative object keys', () {
      final disk = S3StorageDisk(
        endpoint: 'objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );

      expect(disk.resolve('images/../avatars/user.png'), 'avatars/user.png');
      expect(disk.resolve(''), '');
    });

    test('rejects object keys that escape the disk boundary', () {
      final disk = S3StorageDisk(
        endpoint: 'objects.example.test',
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
        bucket: 'uploads',
      );

      expect(() => disk.resolve('/absolute.txt'), throwsArgumentError);
      expect(() => disk.resolve('../outside.txt'), throwsArgumentError);
      expect(
        () => disk.resolve('images/../../outside.txt'),
        throwsArgumentError,
      );
    });

    test('rejects invalid endpoint and credential configuration', () {
      expect(
        () => S3StorageDisk(
          endpoint: 'ftp://objects.example.test',
          accessKey: 'key',
          secretKey: 'secret',
          bucket: 'uploads',
        ),
        throwsArgumentError,
      );
      expect(
        () => S3StorageDisk(
          endpoint: 'https://objects.example.test/path',
          accessKey: 'key',
          secretKey: 'secret',
          bucket: 'uploads',
        ),
        throwsArgumentError,
      );
      expect(
        () => S3StorageDisk(
          endpoint: 'https://objects.example.test',
          accessKey: 'key',
          secretKey: 'secret',
          bucket: 'uploads',
          useSsl: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => S3StorageDisk(
          endpoint: 'objects.example.test',
          accessKey: '',
          secretKey: 'secret',
          bucket: 'uploads',
        ),
        throwsArgumentError,
      );
      expect(
        () => S3StorageDisk(
          endpoint: 'objects.example.test',
          accessKey: 'key',
          secretKey: 'secret',
          bucket: 'uploads',
          prefix: 'tenant/../other',
        ),
        throwsArgumentError,
      );
    });
  });
}
