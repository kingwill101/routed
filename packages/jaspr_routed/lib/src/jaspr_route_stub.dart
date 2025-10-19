typedef JasprComponentBuilder = Object Function(Object context);

Never jasprRoute(JasprComponentBuilder builder) {
  throw AssertionError('jasprRoute is only available on the server runtime.');
}
