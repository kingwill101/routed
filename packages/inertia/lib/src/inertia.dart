/// Main Inertia library export

// Core
export 'core/headers.dart';
export 'core/page_data.dart';
export 'core/inertia_request.dart';
export 'core/inertia_response.dart';
export 'core/response_factory.dart';

// Properties
export 'properties/inertia_prop.dart';
export 'properties/lazy_prop.dart';
export 'properties/optional_prop.dart';
export 'properties/deferred_prop.dart';
export 'properties/always_prop.dart';
export 'properties/merge_prop.dart';
export 'properties/once_prop.dart';
export 'properties/scroll_prop.dart';
export 'properties/property_resolver.dart';

// Utilities
export 'property_context.dart';
export 'inertia_serializable.dart';
export 'shared_props.dart';

// Middleware
export 'middleware/inertia_middleware.dart';
export 'middleware/version_middleware.dart';
export 'middleware/redirect_middleware.dart';
export 'middleware/shared_data_middleware.dart';
export 'middleware/error_handling_middleware.dart';

// SSR
export 'ssr/ssr_gateway.dart';
export 'ssr/http_gateway.dart';
export 'ssr/ssr_response.dart';

// Config
export 'config/inertia_settings.dart';

// Testing
export 'testing/assertable_inertia.dart';
export 'testing/inertia_test_extensions.dart';
