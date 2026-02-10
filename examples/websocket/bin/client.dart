// WebSocket Client
//
// Exercises the echo, chat, and room endpoints to demonstrate client-side
// interaction with WebSocket handlers.
//
// Start the server first:
//   dart run bin/server.dart
//
// Then run this client:
//   dart run bin/client.dart
import 'dart:async';
import 'dart:io';

const _base = 'ws://localhost:3000';

/// ANSI colour helpers for readable output.
String _bold(String s) => '\x1B[1m$s\x1B[0m';
String _dim(String s) => '\x1B[2m$s\x1B[0m';
String _cyan(String s) => '\x1B[36m$s\x1B[0m';
String _green(String s) => '\x1B[32m$s\x1B[0m';

void _printHeader(String title) {
  print('');
  print(_bold('=' * 60));
  print(_bold('  $title'));
  print(_bold('=' * 60));
}

// ---------------------------------------------------------------------------
// 1. Echo test
// ---------------------------------------------------------------------------

Future<void> _testEcho() async {
  _printHeader('1. Echo Handler (ws://localhost:3000/echo)');
  print(_dim('  Sends messages and expects them echoed back'));

  final ws = await WebSocket.connect('$_base/echo');
  final messages = <String>[];
  final completer = Completer<void>();

  ws.listen(
    (data) {
      messages.add(data.toString());
      print('  ${_cyan("recv:")} $data');
      if (messages.length == 4) completer.complete();
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
  );

  // Wait for welcome message
  await Future.delayed(Duration(milliseconds: 200));

  // Send three messages
  for (final msg in ['Hello', 'World', '42']) {
    print('  ${_green("send:")} $msg');
    ws.add(msg);
    await Future.delayed(Duration(milliseconds: 100));
  }

  await completer.future.timeout(Duration(seconds: 3), onTimeout: () {});
  await ws.close();
  print('  ${_dim("Received ${messages.length} messages total")}');
}

// ---------------------------------------------------------------------------
// 2. Chat test — two clients in the same room
// ---------------------------------------------------------------------------

Future<void> _testChat() async {
  _printHeader('2. Chat Handler (ws://localhost:3000/chat)');
  print(_dim('  Two clients exchanging messages'));

  final alice = await WebSocket.connect('$_base/chat');
  final bob = await WebSocket.connect('$_base/chat');

  final aliceMessages = <String>[];
  final bobMessages = <String>[];

  alice.listen((data) {
    aliceMessages.add(data.toString());
    print('  ${_cyan("Alice recv:")} $data');
  });

  bob.listen((data) {
    bobMessages.add(data.toString());
    print('  ${_cyan("Bob   recv:")} $data');
  });

  // Wait for welcome messages
  await Future.delayed(Duration(milliseconds: 300));

  // Alice sets nickname
  print('  ${_green("Alice send:")} /nick Alice');
  alice.add('/nick Alice');
  await Future.delayed(Duration(milliseconds: 200));

  // Bob sets nickname
  print('  ${_green("Bob   send:")} /nick Bob');
  bob.add('/nick Bob');
  await Future.delayed(Duration(milliseconds: 200));

  // Alice sends a message — Bob should receive it
  print('  ${_green("Alice send:")} Hi everyone!');
  alice.add('Hi everyone!');
  await Future.delayed(Duration(milliseconds: 200));

  // Bob replies — Alice should receive it
  print('  ${_green("Bob   send:")} Hey Alice!');
  bob.add('Hey Alice!');
  await Future.delayed(Duration(milliseconds: 200));

  await alice.close();
  await Future.delayed(Duration(milliseconds: 100));
  await bob.close();

  print('  ${_dim("Alice received ${aliceMessages.length} messages")}');
  print('  ${_dim("Bob   received ${bobMessages.length} messages")}');
}

// ---------------------------------------------------------------------------
// 3. Named rooms — two clients in different rooms
// ---------------------------------------------------------------------------

Future<void> _testRooms() async {
  _printHeader('3. Room Handler (ws://localhost:3000/rooms/{room})');
  print(_dim('  Two clients in "dart" room, one in "rust" room'));

  final dart1 = await WebSocket.connect('$_base/rooms/dart');
  final dart2 = await WebSocket.connect('$_base/rooms/dart');
  final rust1 = await WebSocket.connect('$_base/rooms/rust');

  final dart1Messages = <String>[];
  final dart2Messages = <String>[];
  final rustMessages = <String>[];

  dart1.listen((data) {
    dart1Messages.add(data.toString());
    print('  ${_cyan("dart-1 recv:")} $data');
  });

  dart2.listen((data) {
    dart2Messages.add(data.toString());
    print('  ${_cyan("dart-2 recv:")} $data');
  });

  rust1.listen((data) {
    rustMessages.add(data.toString());
    print('  ${_cyan("rust-1 recv:")} $data');
  });

  // Wait for join messages
  await Future.delayed(Duration(milliseconds: 300));

  // dart-1 sends — dart-2 should receive, rust-1 should NOT
  print('  ${_green("dart-1 send:")} Dart is great!');
  dart1.add('Dart is great!');
  await Future.delayed(Duration(milliseconds: 200));

  // rust-1 sends — no one else in rust room, so no one receives
  print('  ${_green("rust-1 send:")} Rust is fast!');
  rust1.add('Rust is fast!');
  await Future.delayed(Duration(milliseconds: 200));

  await dart1.close();
  await dart2.close();
  await rust1.close();

  print('  ${_dim("dart-1 received ${dart1Messages.length} messages")}');
  print('  ${_dim("dart-2 received ${dart2Messages.length} messages")}');
  print(
    '  ${_dim("rust-1 received ${rustMessages.length} messages (expected: 1 join only)")}',
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main() async {
  try {
    await _testEcho();
    await _testChat();
    await _testRooms();

    print('');
    print(_green('Done! All WebSocket scenarios demonstrated.'));
    print('');
  } catch (e) {
    print('Error: $e');
    print('Make sure the server is running: dart run bin/server.dart');
    exit(1);
  }
}
