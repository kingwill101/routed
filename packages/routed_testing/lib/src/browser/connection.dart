import 'dart:async';
import 'dart:io';

class BrowserConnection {
  final String host;
  final int port;
  final Duration timeout;
  
  BrowserConnection({
    this.host = 'localhost',
    required this.port,
    this.timeout = const Duration(seconds: 30),
  });

  Future<void> waitForConnection() async {
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      try {
        final socket = await Socket.connect(
          host, 
          port,
          timeout: Duration(seconds: 1),
        );
        await socket.close();
        return;
      } catch (_) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    
    throw TimeoutException(
      'Failed to connect to browser on $host:$port',
      timeout,
    );
  }

  Future<bool> isConnected() async {
    try {
      final socket = await Socket.connect(host, port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}