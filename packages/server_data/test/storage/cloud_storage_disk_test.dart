import 'package:server_data/server_data.dart';
import 'package:storage_fs/storage_fs.dart';
import 'package:test/test.dart';

void main() {
  group('CloudStorageDisk', () {
    test('resolve strips leading slash and normalizes path', () {
      final adapter = CloudAdapter.fromConfig(
        DiskConfig.fromMap({
          'driver': 's3',
          'options': {
            'endpoint': 'localhost',
            'key': 'key',
            'secret': 'secret',
            'bucket': 'bucket',
          },
        }),
      );
      final disk = CloudStorageDisk(adapter: adapter, diskName: 'cloud');

      expect(disk.resolve('/images/../logo.png'), 'logo.png');
    });

    test('resolve returns empty string for root path', () {
      final adapter = CloudAdapter.fromConfig(
        DiskConfig.fromMap({
          'driver': 's3',
          'options': {
            'endpoint': 'localhost',
            'key': 'key',
            'secret': 'secret',
            'bucket': 'bucket',
          },
        }),
      );
      final disk = CloudStorageDisk(adapter: adapter);

      expect(disk.resolve(''), isEmpty);
      expect(disk.resolve('.'), isEmpty);
    });
  });
}
