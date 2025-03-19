class Device {
  final String userAgent;
  final Viewport viewport;
  final double deviceScaleFactor;
  final bool isMobile;
  final bool hasTouch;
  final String defaultBrowserType;

  Device({
    required this.userAgent,
    required this.viewport,
    required this.deviceScaleFactor,
    required this.isMobile,
    required this.hasTouch,
    required this.defaultBrowserType,
  });

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

class Viewport {
  final int width;
  final int height;

  Viewport({
    required this.width,
    required this.height,
  });

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
