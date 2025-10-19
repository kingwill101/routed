part of 'context.dart';

extension MultipartFormMethods on EngineContext {
  /// Retrieve the multipart form asynchronously.
  Future<MultipartForm> multipartForm() async {
    await initFormCache();
    final a = get<MultipartForm>(multipartFormKey) ?? MultipartForm();
    return a;
  }

  /// Retrieve a file from the multipart form.
  Future<MultipartFile?> formFile(String name) async {
    final form = await multipartForm();
    return form.files.where((f) => f.name == name).firstOrNull;
  }

  /// Save an uploaded file to a destination.
  Future<void> saveUploadedFile(MultipartFile file, String destination) async {
    final sourceFile = engine?.config.fileSystem.file(file.path);
    final destFile = engine?.config.fileSystem.file(destination);
    destFile?.parent.existsSync() ?? destFile?.parent.create(recursive: true);
    await sourceFile?.copy(destFile?.path ?? "");
  }

  /// Get the first value of a form field with a default fallback.
  Future<String> defaultPostForm(String key, String defaultValue) async {
    final value = (await postForm(key));
    return value.isEmpty ? defaultValue : value;
  }

  /// Get the value of a form field.
  Future<String> postForm(String key) async {
    await initFormCache();
    final form = get<Map<String, dynamic>>(formCacheKey) ?? {};
    final value = form[key];
    return value == null ? "" : value.toString();
  }

  /// Get all values of a form field.
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

  /// Get a map of form fields with a key prefix.
  Future<Map<String, dynamic>> postFormMap(String key) async {
    await initFormCache();
    return get<Map<String, dynamic>>(formCacheKey) ?? {};
  }

  /// Retrieves the multipart form asynchronously.
  Future<Map<String, dynamic>> form() async {
    return await formCache;
  }
}
