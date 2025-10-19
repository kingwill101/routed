import 'package:simple_blog/src/server.dart';

Future<void> main(List<String> arguments) async {
  // Parse command line arguments for port
  int port = 8080;

  if (arguments.isNotEmpty) {
    final portArg = int.tryParse(arguments[0]);
    if (portArg != null && portArg > 0 && portArg < 65536) {
      port = portArg;
    } else {
      print('Invalid port number: ${arguments[0]}');
      print('Usage: dart run bin/simple_blog.dart [port]');
      return;
    }
  }

  // Start the server
  await startServer(port: port);
}
