import 'dart:io';

import 'package:routed_security/routed_security.dart';

void main() {
  final filter = IpFilter.disabled();
  stdout.writeln(
    'routed_security allows localhost: ${filter.allows('127.0.0.1')}',
  );
}
