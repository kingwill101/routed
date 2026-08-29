import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

void main() {
  group('SftpStorageDisk', () {
    test('configures password authentication without connecting', () {
      final disk = SftpStorageDisk(
        config: const SftpConfig(
          host: ' sftp.example.test ',
          port: 2222,
          username: ' deploy ',
          password: 'secret',
          root: '/srv/app/../uploads/',
          readOnly: true,
          connectTimeout: Duration(seconds: 5),
        ),
        diskName: 'backups',
      );

      expect(disk.config.host, 'sftp.example.test');
      expect(disk.config.port, 2222);
      expect(disk.config.username, 'deploy');
      expect(disk.config.root, '/srv/uploads');
      expect(disk.config.readOnly, isTrue);
      expect(disk.diskName, 'backups');
      expect(disk.fileSystem.path.separator, '/');

      final manager = StorageManager()
        ..registerDisk('backups', disk)
        ..setDefault('backups');
      expect(manager.storage(), same(disk.storage));
      expect(manager.drive('backups'), same(disk.storage));
    });

    test('supports private-key authentication', () {
      final disk = SftpStorageDisk(
        config: const SftpConfig(
          host: 'sftp.example.test',
          username: 'deploy',
          privateKeyPems: ['private-key-pem'],
        ),
      );

      expect(disk.config.privateKeyPems, ['private-key-pem']);
    });

    test('normalizes safe relative paths and rejects escapes', () {
      final disk = SftpStorageDisk(
        config: const SftpConfig(
          host: 'sftp.example.test',
          username: 'deploy',
          password: 'secret',
        ),
      );

      expect(disk.resolve('reports/../daily.json'), 'daily.json');
      expect(disk.resolve(''), '');
      expect(() => disk.resolve('/etc/passwd'), throwsArgumentError);
      expect(() => disk.resolve('../outside'), throwsArgumentError);
      expect(() => disk.resolve('a/../../outside'), throwsArgumentError);
      expect(
        () => disk.storage.put('../outside', 'blocked'),
        throwsArgumentError,
      );
    });

    test('rejects invalid connection configuration', () {
      expect(
        () => SftpStorageDisk(
          config: const SftpConfig(
            host: '',
            username: 'deploy',
            password: 'secret',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => SftpStorageDisk(
          config: const SftpConfig(
            host: 'sftp.example.test',
            username: 'deploy',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => SftpStorageDisk(
          config: const SftpConfig(
            host: 'sftp.example.test',
            port: 0,
            username: 'deploy',
            password: 'secret',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => SftpStorageDisk(
          config: const SftpConfig(
            host: 'sftp.example.test',
            username: 'deploy',
            password: 'secret',
            root: 'relative/path',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('close is safe before the first connection', () async {
      final disk = SftpStorageDisk(
        config: const SftpConfig(
          host: 'sftp.example.test',
          username: 'deploy',
          password: 'secret',
        ),
      );

      await expectLater(disk.close(), completes);
    });
  });
}
