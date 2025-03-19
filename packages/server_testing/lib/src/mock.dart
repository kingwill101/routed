/// Base library for mocking HTTP components.
///
/// This library provides mocks for HTTP requests, responses, headers, and URIs
/// using the Mockito package. These mocks are used throughout the testing
/// utilities to simulate HTTP interactions without requiring actual servers.
///
/// The mock classes are generated using Mockito's code generation facilities.
/// If you modify this file, you'll need to run the build_runner to regenerate
/// the mocks.
library;

import 'dart:io';

import 'package:mockito/annotations.dart';

/// Generate mock classes for HTTP components.
///
/// This annotation generates nicely formatted mock implementations of:
/// - HttpRequest
/// - HttpResponse
/// - HttpHeaders
/// - Uri
/// - HttpConnectionInfo
///
/// These mocks are used in the request and response setup functions to create
/// test doubles that behave like the real components without needing actual
/// HTTP servers or connections.
@GenerateNiceMocks([
  MockSpec<HttpRequest>(),
  MockSpec<HttpResponse>(),
  MockSpec<HttpHeaders>(),
  MockSpec<Uri>(),
  MockSpec<HttpConnectionInfo>()
])
// ignore: unused_import
import 'mock.mocks.dart';
