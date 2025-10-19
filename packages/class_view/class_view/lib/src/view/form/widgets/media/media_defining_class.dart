import 'media.dart';

/// Base class for media-defining widgets
abstract class MediaDefiningClass {
  /// Get the media files needed by this widget
  List<Media> getMedia();
}
