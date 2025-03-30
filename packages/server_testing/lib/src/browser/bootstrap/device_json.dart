/// Represents device emulation parameters, typically used for simulating
/// mobile devices during testing. Includes properties like user agent,
/// viewport size, device scale factor, touch support, and default browser type.
class Device {
  /// The user agent string to emulate.
  final String userAgent;
  /// The viewport dimensions ([Viewport.width] and [Viewport.height]) to emulate.
  final Viewport viewport;
  /// The device scale factor (pixel density) to emulate.
  final double deviceScaleFactor;
  /// Whether the device should be treated as a mobile device.
  final bool isMobile;
  /// Whether the device emulation should include touch event support.
  final bool hasTouch;
  /// The default browser engine associated with this device (e.g., 'webkit', 'chromium').
  final String defaultBrowserType;

  /// Creates a [Device] instance with the specified emulation parameters.
  Device({
    required this.userAgent,
    required this.viewport,
    required this.deviceScaleFactor,
    required this.isMobile,
    required this.hasTouch,
    required this.defaultBrowserType,
  });

  /// Creates a [Device] instance from a JSON map.
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      userAgent: json['userAgent'] as String,
      viewport: Viewport.fromJson(json['viewport'] as Map<String, dynamic>),
      deviceScaleFactor: json['deviceScaleFactor'] as double,
      isMobile: json['isMobile'] as bool,
      hasTouch: json['hasTouch'] as bool,
      defaultBrowserType: json['defaultBrowserType'] as String,
    );
  }

  /// Converts this [Viewport] instance to a JSON map.

  /// Converts this [Device] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'userAgent': userAgent,
      'viewport': viewport.toJson(),
      'deviceScaleFactor': deviceScaleFactor,
      'isMobile': isMobile,
      'hasTouch': hasTouch,
      'defaultBrowserType': defaultBrowserType,
    };
  }
}

/// Represents the dimensions (width and height) of a device viewport.
class Viewport {
  /// The viewport width in pixels.
  final int width;
  /// The viewport height in pixels.
  final int height;

  /// Creates a [Viewport] instance.
  Viewport({
    required this.width,
    required this.height,
  });

  /// Creates a [Viewport] instance from a JSON map.
  factory Viewport.fromJson(Map<String, dynamic> json) {
    return Viewport(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
    };
  }
}
