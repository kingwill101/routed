/// Request binding utilities for Routed.
///
/// Import this when you need to bind request payloads (JSON, forms, query
/// parameters) to data classes.
library;

export 'src/binding/binding.dart'
    show
        Binding,
        MimeType,
        defaultBinding,
        formBinding,
        jsonBinding,
        multipartBinding,
        queryBinding,
        uriBinding;
export 'src/binding/json.dart' show JsonBinding;
export 'src/binding/form.dart' show FormBinding;
export 'src/binding/query.dart' show QueryBinding;
export 'src/binding/uri.dart' show UriBinding;
export 'src/binding/multipart.dart' show MultipartBinding;
