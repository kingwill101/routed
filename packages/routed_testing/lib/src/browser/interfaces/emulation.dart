import 'dart:async';

abstract class Emulation {
  FutureOr<void> setUserAgent(String userAgent);

  FutureOr<void> setViewportSize(int width, int height);

  FutureOr<void> setGeolocation(double latitude, double longitude,
      {double? accuracy});

  FutureOr<void> clearGeolocation();

  FutureOr<void> setOffline(bool offline);
}
