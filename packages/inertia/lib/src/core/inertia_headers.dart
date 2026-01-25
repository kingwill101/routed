/// Defines canonical HTTP header names used by the Inertia protocol.
///
/// These constants centralize header strings for requests, responses, partial
/// reloads, and Inertia-specific metadata.
///
/// ```dart
/// final headers = {
///   InertiaHeaders.inertia: 'true',
///   InertiaHeaders.inertiaVersion: '1.0.0',
/// };
/// ```
class InertiaHeaders {
  /// Header that marks a request or response as an Inertia exchange.
  static const String inertia = 'X-Inertia';

  /// Header that communicates the current asset version.
  static const String inertiaVersion = 'X-Inertia-Version';

  /// Header listing requested props for a partial reload.
  static const String inertiaPartialData = 'X-Inertia-Partial-Data';

  /// Header naming the component for a partial reload.
  static const String inertiaPartialComponent = 'X-Inertia-Partial-Component';

  /// Header listing props to exclude during a partial reload.
  static const String inertiaPartialExcept = 'X-Inertia-Partial-Except';

  /// Header naming the error bag for validation errors.
  static const String inertiaErrorBag = 'X-Inertia-Error-Bag';

  /// Header used for location visits on version mismatches.
  static const String inertiaLocation = 'X-Inertia-Location';

  /// Header listing merge props to reset.
  static const String inertiaReset = 'X-Inertia-Reset';

  /// Header carrying infinite-scroll merge intent.
  static const String inertiaInfiniteScrollMergeIntent =
      'X-Inertia-Infinite-Scroll-Merge-Intent';

  /// Header listing once props to exclude from a response.
  static const String inertiaExceptOnceProps = 'X-Inertia-Except-Once-Props';

  /// Header used for HTTP cache variance.
  static const String inertiaVary = 'Vary';
}
