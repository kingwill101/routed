import 'dart:io';

import 'package:mockito/annotations.dart';

@GenerateNiceMocks([
  MockSpec<HttpRequest>(),
  MockSpec<HttpResponse>(),
  MockSpec<HttpHeaders>(),
  MockSpec<Uri>(),
  MockSpec<HttpConnectionInfo>()
])
// ignore: unused_import
import 'mock.mocks.dart'; // Replace with the actual path to your mocks file
