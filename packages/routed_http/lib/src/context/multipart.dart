import 'package:routed_core/routed_core.dart';
import 'package:routed_http/src/binding/multipart.dart';
import 'package:routed_http/src/context/form_cache.dart';

/// Adds multipart form convenience methods to an [EngineContext].
extension MultipartFormMethods on EngineContext {
  /// Retrieves a file named [name] from the multipart form.
  Future<MultipartFile?> formFile(String name) async {
    final form = await multipartForm;
    return form.files.where((f) => f.name == name).firstOrNull;
  }

  /// Saves an uploaded [file] to [destination].
  Future<void> saveUploadedFile(MultipartFile file, String destination) async {
    final sourceFile = engine?.config.fileSystem.file(file.path);
    final destFile = engine?.config.fileSystem.file(destination);
    destFile?.parent.existsSync() ?? destFile?.parent.create(recursive: true);
    await sourceFile?.copy(destFile?.path ?? '');
  }

  /// Returns the first value of a form field, or [defaultValue] when empty.
  Future<String> defaultPostForm(String key, String defaultValue) async {
    final value = await postForm(key);
    return value.isEmpty ? defaultValue : value;
  }

  /// Returns the string value of a form field named [key].
  Future<String> postForm(String key) async {
    await initFormCache();
    final form = get<Map<String, dynamic>>(formCacheKey) ?? {};
    final value = form[key];
    return value == null ? '' : value.toString();
  }

  /// Returns all values of a form field named [key].
  Future<List<String>> postFormArray(String key) async {
    await initFormCache();
    final form = get<Map<String, dynamic>>(formCacheKey) ?? {};
    final value = form[key];
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [value.toString()];
  }

  /// Returns the cached form fields associated with [key].
  Future<Map<String, dynamic>> postFormMap(String key) async {
    await initFormCache();
    return get<Map<String, dynamic>>(formCacheKey) ?? {};
  }

  /// Returns all cached form fields asynchronously.
  Future<Map<String, dynamic>> form() async {
    return formCache;
  }
}
