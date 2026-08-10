import 'package:routed/routed.dart';

import '../binding/multipart.dart';
import '../binding/utils.dart';

/// Form and query cache helpers for [EngineContext].
///
/// These used to live on foundation `EngineContext`; they belong with HTTP
/// binding in this package so `package:routed` stays free of multipart/query
/// parsing dependencies.
extension EngineContextFormCache on EngineContext {
  /// Initializes the form cache by parsing form data.
  Future<Map<String, dynamic>> initFormCache() async {
    final cached = get<Map<String, dynamic>>(formCacheKey);
    if (cached != null) return cached;

    final form = <String, dynamic>{};

    if (request.contentType?.subType == 'x-www-form-urlencoded') {
      form.addAll(await parseForm(this));
    }

    if (request.contentType?.subType == 'form-data') {
      final parsed = await parseMultipartForm(this);
      set(multipartFormKey, parsed);
      form.addAll(parsed.fields);
    }

    set(formCacheKey, form);
    return form;
  }

  /// Combined URL-encoded / multipart form fields.
  Future<Map<String, dynamic>> get formCache async {
    await initFormCache();
    return get<Map<String, dynamic>>(formCacheKey) ?? <String, dynamic>{};
  }

  /// Parsed multipart form (empty when not multipart).
  Future<MultipartForm> get multipartForm async {
    await initFormCache();
    return get(multipartFormKey) ?? MultipartForm();
  }

  /// Parsed query string map.
  Map<String, dynamic> get queryCache {
    final cache = get<Map<String, dynamic>>(queryCacheKey);
    if (cache != null) return cache;
    set(queryCacheKey, parseUrlEncoded(uri.query));
    return get(queryCacheKey)!;
  }
}
