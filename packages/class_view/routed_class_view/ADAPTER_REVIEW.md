# Routed Class View Adapter - Review & Modernization

**Review Date:** 2025-10-18  
**Package:** routed_class_view  
**Context:** Routed now has much more flexible response handling

---

## Executive Summary

The `routed_class_view` adapter is currently **functional but underutilizing** routed's enhanced response capabilities.
Routed now offers a rich render system with 10+ response types, advanced content negotiation, and flexible response
handling that the adapter doesn't expose to class-based views.

### Current State: **Basic** ⭐⭐⭐ (3/5)

- ✅ Basic adapter implementation works
- ✅ Handles standard request/response operations
- ✅ Exposes `EngineContext` to unlock advanced routed capabilities
- ⚠️ Uses only 5 of 20+ available response methods
- ⚠️ Doesn't expose routed's render system helpers out of the box

### Opportunity: **HIGH** 🚀

Routed's response system has evolved significantly and offers much more than the adapter currently exposes.

---

## 1. Routed's Enhanced Response Capabilities

### 1.1 Response Methods Available (Not Used by Adapter)

**Currently Used (5 methods):**

```dart
✅ _context.status(code)         // Set status code
✅ _context.setHeader(name, value) // Set header
✅ _context.write(body)          // Write string
✅ _context.json(data)           // JSON response
✅ _context.redirect(url)        // Redirect
```

**Available But NOT Exposed (15+ methods):**

```dart
❌ _context.xml(data)             // XML response
❌ _context.yaml(data)            // YAML response  
❌ _context.html(content, data)   // HTML with templating
❌ _context.template(...)         // Template rendering
❌ _context.file(path)            // Serve file
❌ _context.fileAttachment(...)   // Download file
❌ _context.string(content)       // Plain text
❌ _context.data(type, bytes)     // Custom content type
❌ _context.indentedJson(data)    // Pretty JSON
❌ _context.asciiJson(data)       // ASCII-safe JSON
❌ _context.secureJson(data)      // XSS-safe JSON
❌ _context.jsonp(data)           // JSONP response
❌ _context.dataFromReader(...)   // Stream response
❌ _context.render(renderer)      // Custom renderer
```

### 1.2 Routed's Render System

**Architecture:**

```dart
// Base interface
abstract class Render {
  FutureOr<void> render(Response response);
  void writeContentType(Response response);
}

// Implementations (10+ renderers)
- JsonRender, IndentedJsonRender, SecureJsonRender, AsciiJsonRender, JsonpRender
- XMLRender
- YamlRender
- HTMLRender (with template engine support)
- StringRender
- DataRender
- ReaderRender (streaming)
- RedirectRender
```

**Benefits:**

- Content-Type handling automatic
- Consistent error handling
- Streaming support built-in
- Easy to add custom renderers
- Content negotiation support

### 1.3 Content Negotiation

Routed has built-in content negotiation:

```dart
extension ContextNegotiation on EngineContext {
  String? negotiateContentType(List<String> offers);
  bool shouldYield(String contentType, List<String> offers);
  // ... more negotiation methods
}
```

**Use case:** Same view can return JSON, XML, or HTML based on Accept header.

---

## 2. Current Adapter Limitations

### 2.1 ViewAdapter Interface Constraints

The `ViewAdapter` interface in class_view is too basic:

```dart
abstract class ViewAdapter {
  // Only these response operations:
  Future<void> setStatusCode(int code);
  Future<void> setHeader(String name, String value);
  Future<void> write(String body);
  Future<void> writeJson(Map<String, dynamic> data, {int statusCode = 200});
  Future<void> redirect(String url, {int statusCode = 302});
}
```

**Problems:**

1. No support for other content types (XML, YAML, etc.)
2. No streaming support
3. No file serving
4. No template rendering (beyond what class_view itself provides)
5. No content negotiation
6. Forces async even when not needed

### 2.2 RoutedAdapter Implementation

**File:** `routed_class_view/lib/src/routed_adapter.dart`

**Current implementation:**

```dart
@override
Future<void> writeJson(Map<String, dynamic> data, {int statusCode = 200}) async {
  _context.json(data, statusCode: statusCode);
}

@override
Future<void> write(String body) async {
  _context.write(body);
}
```

**Issues:**

1. ⚠️ Unnecessary async wrappers (all operations are synchronous)
2. ❌ Doesn't expose routed's rich response methods
3. ❌ No way to use custom renderers
4. ❌ No streaming support

---

## 3. Routed Response System Deep Dive

### 3.1 Response Class Features

**File:** `routed/lib/src/response.dart` (357 lines)

**Key Features:**

```dart
class Response {
  // Buffering system
  bool get bufferOutput;
  void write(dynamic data);
  void writeBytes(List<int> data);
  void writeHeaderNow();
  void writeNow();
  
  // Streaming
  Future<void> addStream(Stream<List<int>> stream);
  Future<void> flush();
  
  // Convenience methods
  Future<void> string(String content, {int statusCode});
  Future<void> json(Map<String, dynamic> data, {int statusCode});
  void error(String message, {int statusCode});
  
  // File operations
  HttpResponse download(File file, {String? name, Map<String, String>? headers});
  HttpResponse redirect(String location, {int status, Map<String, String>? headers});
  
  // Cookie management
  void setCookie(String name, dynamic value, {...});
  
  // Body filtering
  void setBodyFilter(ResponseBodyFilter? filter);
  
  // State management
  bool get isClosed;
  Future<void> get done;
  Future<Socket> detachSocket({bool writeHeaders});
}
```

### 3.2 Context Render Extension

**File:** `routed/lib/src/context/render.dart` (229 lines)

**All Available Methods:**

```dart
extension ContextRender on EngineContext {
  // Core render
  FutureOr<Response> render(int statusCode, Render renderer);
  
  // JSON variants (5 methods)
  Response json(dynamic data, {int statusCode});
  Response jsonp(dynamic data, {String callback, int statusCode});
  Response indentedJson(dynamic data, {int statusCode});
  Response secureJson(dynamic data, {int statusCode, String prefix});
  Response asciiJson(dynamic data, {int statusCode});
  
  // Other formats
  Response string(String content, {int statusCode});
  Response xml(Map<String, dynamic> data, {int statusCode});
  Response yaml(Map<String, dynamic> data, {int statusCode});
  Response data(String contentType, List<int> data, {int statusCode});
  
  // Templates & HTML
  Future<Response> html(String content, {Map<String, dynamic> data, int statusCode});
  Future<Response> template({String? content, Map<String, dynamic> data, int statusCode, String? templateName});
  Future<String> templateString({String? content, Map<String, dynamic> data, String? templateName});
  
  // Files
  Future<Response> file(String filePath);
  Future<Response> dir(String dirPath);
  Future<Response> fileAttachment(String filePath, String? filename);
  
  // Streaming
  Response dataFromReader({
    required int statusCode,
    int? contentLength,
    required String contentType,
    required Stream<List<int>> reader,
    Map<String, String>? extraHeaders,
  });
  
  // Navigation
  Future<Response> redirect(String url, {int statusCode});
}
```

---

## 4. Proposed Improvements

### 4.1 Option A: Extend ViewAdapter Interface (BREAKING)

**Pros:**

- Exposes all routed capabilities
- Other adapters benefit too
- Type-safe

**Cons:**

- Breaking change for all adapters
- Shelf adapter would need dummy implementations
- Couples class_view to routed features

**Implementation:**

```dart
abstract class ViewAdapter {
  // Existing methods...
  
  // New optional methods (with defaults)
  Future<void> writeXml(Map<String, dynamic> data, {int statusCode = 200}) async {
    throw UnimplementedError('XML not supported by this adapter');
  }
  
  Future<void> writeYaml(Map<String, dynamic> data, {int statusCode = 200}) async {
    throw UnimplementedError('YAML not supported by this adapter');
  }
  
  Future<void> serveFile(String path) async {
    throw UnimplementedError('File serving not supported by this adapter');
  }
  
  Future<void> writeStream(Stream<List<int>> stream, String contentType) async {
    throw UnimplementedError('Streaming not supported by this adapter');
  }
}
```

### 4.2 Option B: Routed-Specific View Extension (NON-BREAKING) ⭐ RECOMMENDED

**Pros:**

- No breaking changes
- Routed views get full power
- Clean separation
- Other adapters unaffected

**Cons:**

- Views need to check adapter type
- Not portable across frameworks

**Implementation:**

```dart
// In routed_class_view package

/// Extension on View when using RoutedAdapter
extension RoutedViewExtensions on View {
  /// Get the routed context if available
  EngineContext? get routedContext {
    if (adapter is RoutedAdapter) {
      return (adapter as RoutedAdapter).context;
    }
    return null;
  }
  
  /// Check if this view is running on routed
  bool get isRoutedView => adapter is RoutedAdapter;
  
  /// Send XML response (routed only)
  Future<void> sendXml(Map<String, dynamic> data, {int statusCode = 200}) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    ctx.status(statusCode);
    ctx.xml(data);
  }
  
  /// Send YAML response (routed only)
  Future<void> sendYaml(Map<String, dynamic> data, {int statusCode = 200}) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    ctx.status(statusCode);
    ctx.yaml(data);
  }
  
  /// Render using routed's template engine
  Future<void> sendTemplate(String templateName, {
    Map<String, dynamic> data = const {},
    int statusCode = 200,
  }) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    await ctx.template(
      templateName: templateName,
      data: data,
      statusCode: statusCode,
    );
  }
  
  /// Serve a file (routed only)
  Future<void> serveFile(String path) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    await ctx.file(path);
  }
  
  /// Serve file as download
  Future<void> downloadFile(String path, {String? filename}) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    await ctx.fileAttachment(path, filename);
  }
  
  /// Stream response (routed only)
  Future<void> streamResponse(
    Stream<List<int>> stream,
    String contentType, {
    int? contentLength,
    int statusCode = 200,
  }) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    ctx.dataFromReader(
      statusCode: statusCode,
      contentType: contentType,
      contentLength: contentLength,
      reader: stream,
    );
  }
  
  /// Use custom renderer (routed only)
  Future<void> renderWith(Render renderer, {int statusCode = 200}) async {
    final ctx = routedContext;
    if (ctx == null) throw StateError('Not a routed view');
    await ctx.render(statusCode, renderer);
  }
}
```

**Usage Example:**

```dart
import 'package:routed_class_view/routed_class_view.dart';

class DataExportView extends View {
  @override
  Future<void> get() async {
    final format = getParam('format') ?? 'json';
    final data = await fetchData();
    
    // Use routed-specific features when available
    if (isRoutedView) {
      switch (format) {
        case 'xml':
          await sendXml(data);
        case 'yaml':
          await sendYaml(data);
        case 'csv':
          await streamResponse(
            generateCSV(data),
            'text/csv',
          );
        default:
          await sendJson(data);
      }
    } else {
      // Fallback for other adapters
      await sendJson(data);
    }
  }
}
```

### 4.3 Option C: Enhanced Adapter Interface (HYBRID)

**Pros:**

- Framework-agnostic capability detection
- No breaking changes
- Clean API

**Cons:**

- More complex implementation
- Requires capability flags

**Implementation:**

```dart
// In class_view package

enum AdapterCapability {
  json,
  xml,
  yaml,
  html,
  templating,
  fileServing,
  streaming,
  contentNegotiation,
}

abstract class ViewAdapter {
  // Existing methods...
  
  /// Check if adapter supports a capability
  bool supports(AdapterCapability capability) => false;
  
  /// Get adapter-specific extension
  T? getExtension<T>() => null;
}

// In routed_class_view package

class RoutedAdapter implements ViewAdapter {
  @override
  bool supports(AdapterCapability capability) {
    return const {
      AdapterCapability.json,
      AdapterCapability.xml,
      AdapterCapability.yaml,
      AdapterCapability.html,
      AdapterCapability.templating,
      AdapterCapability.fileServing,
      AdapterCapability.streaming,
      AdapterCapability.contentNegotiation,
    }.contains(capability);
  }
  
  @override
  T? getExtension<T>() {
    if (T == RoutedAdapterExtension) {
      return RoutedAdapterExtension(this) as T;
    }
    return null;
  }
}

class RoutedAdapterExtension {
  final RoutedAdapter adapter;
  RoutedAdapterExtension(this.adapter);
  
  EngineContext get context => adapter._context;
  
  Future<void> xml(Map<String, dynamic> data, {int statusCode = 200}) async {
    context.status(statusCode);
    context.xml(data);
  }
  
  // ... all other methods
}

// Usage
class MyView extends View {
  @override
  Future<void> get() async {
    if (adapter.supports(AdapterCapability.xml)) {
      final ext = adapter.getExtension<RoutedAdapterExtension>();
      await ext?.xml(data);
    }
  }
}
```

---

## 5. Immediate Improvements (No Breaking Changes)

### 5.1 Embrace Context Access Safely

- ✅ Adapter now exposes the underlying `EngineContext`, unlocking routed features (cache, config, middleware hooks)
- 🔄 Provide helper docs/examples so developers know how to leverage the context **without breaking adapter-agnostic
  guarantees** (e.g., type-check before casting, prefer capability helpers when they land)

### 5.2 Remove Unnecessary Async Wrappers

All operations are synchronous, no need for async:

```dart
// BEFORE
@override
Future<void> setStatusCode(int code) async {
  _context.status(code);
}

@override
Future<void> write(String body) async {
  _context.write(body);
}

// AFTER (but keep Future for interface compatibility)
@override
Future<void> setStatusCode(int code) async {
  _context.status(code);
}

@override
Future<void> write(String body) async {
  _context.write(body);
}
```

**Note:** Keep `Future<void>` return type for interface compatibility, but no need for internal async operations.

### 5.3 Expose Context (Non-Breaking Addition)

```dart
class RoutedAdapter implements ViewAdapter {
  final routed.EngineContext _context;
  final Map<String, String> _routeParams;
  
  // Add public getter
  /// Get the underlying routed context for advanced usage
  routed.EngineContext get context => _context;
  
  // ... rest of implementation
}
```

**Benefits:**

- Views can access context directly for advanced features
- Non-breaking (just adds a getter)
- Enables extension methods

---

## 6. Content Negotiation Support

### 6.1 Add Content Negotiation Helper

```dart
// In routed_class_view/lib/src/content_negotiation.dart

import 'package:routed/routed.dart';

/// Helper for content negotiation in class-based views
class ContentNegotiator {
  final EngineContext context;
  
  ContentNegotiator(this.context);
  
  /// Negotiate response format based on Accept header
  Future<void> respondWith(
    Map<String, dynamic> data, {
    List<String> supportedFormats = const ['json', 'xml', 'yaml'],
  }) async {
    final accept = context.headers['accept']?.first ?? 'application/json';
    
    // Try to negotiate
    if (accept.contains('application/json') || 
        accept.contains('*/*')) {
      context.json(data);
    } else if (accept.contains('application/xml') && 
               supportedFormats.contains('xml')) {
      context.xml(data);
    } else if (accept.contains('application/yaml') && 
               supportedFormats.contains('yaml')) {
      context.yaml(data);
    } else {
      // Default to JSON
      context.json(data);
    }
  }
}

// Usage in views
extension RoutedViewNegotiation on View {
  Future<void> negotiateResponse(
    Map<String, dynamic> data, {
    List<String> supportedFormats = const ['json', 'xml', 'yaml'],
  }) async {
    if (adapter is RoutedAdapter) {
      final ctx = (adapter as RoutedAdapter).context;
      await ContentNegotiator(ctx).respondWith(
        data,
        supportedFormats: supportedFormats,
      );
    } else {
      await sendJson(data);
    }
  }
}
```

**Usage:**

```dart
class APIView extends ListView<Post> {
  @override
  Future<void> get() async {
    final posts = await getObjectList();
    
    // Automatically return JSON, XML, or YAML based on Accept header
    await negotiateResponse({
      'posts': posts.items.map((p) => p.toJson()).toList(),
      'total': posts.total,
    });
  }
}
```

---

## 7. Example: Full-Featured View

### 7.1 Using Enhanced Adapter

```dart
import 'package:routed_class_view/routed_class_view.dart';

class DocumentView extends DetailView<Document> {
  @override
  Future<Document?> getObject() async {
    final id = getParam('id');
    return await DocumentRepository.findById(id);
  }
  
  @override
  Future<void> get() async {
    final doc = await getObject();
    if (doc == null) {
      throw HttpException.notFound();
    }
    
    // Use routed's enhanced capabilities
    if (isRoutedView) {
      final format = getParam('format');
      final download = getParam('download') == 'true';
      
      switch (format) {
        case 'xml':
          await sendXml(doc.toJson());
          
        case 'yaml':
          await sendYaml(doc.toJson());
          
        case 'pdf':
          if (download) {
            await downloadFile(doc.pdfPath, filename: '${doc.title}.pdf');
          } else {
            await serveFile(doc.pdfPath);
          }
          
        case 'html':
          await sendTemplate('documents/detail.html', data: {
            'document': doc,
            'user': getCurrentUser(),
          });
          
        default:
          // Content negotiation
          await negotiateResponse(doc.toJson());
      }
    } else {
      // Fallback for non-routed adapters
      await sendJson(doc.toJson());
    }
  }
}

class ReportView extends View {
  @override
  Future<void> get() async {
    final reportType = getParam('type');
    
    if (!isRoutedView) {
      await sendJson({'error': 'This view requires routed adapter'});
      return;
    }
    
    // Generate report stream
    final reportStream = generateReport(reportType);
    
    // Stream response efficiently
    await streamResponse(
      reportStream,
      'application/pdf',
      statusCode: 200,
    );
  }
}
```

---

## 8. Testing Enhanced Features

### 8.1 Test Content Negotiation

```dart
test('view responds with XML when requested', () async {
  final view = DocumentView();
  final adapter = RoutedAdapter(
    mockContext(headers: {'accept': 'application/xml'}),
  );
  
  view.setAdapter(adapter);
  await view.dispatch();
  
  expect(adapter.context.response.contentType, contains('xml'));
});

test('view falls back to JSON for unknown formats', () async {
  final view = DocumentView();
  final adapter = RoutedAdapter(
    mockContext(headers: {'accept': 'application/unknown'}),
  );
  
  view.setAdapter(adapter);
  await view.dispatch();
  
  expect(adapter.context.response.contentType, contains('json'));
});
```

### 8.2 Test File Serving

```dart
test('view serves file correctly', () async {
  final view = DocumentView();
  final adapter = RoutedAdapter(mockContext());
  
  view.setAdapter(adapter);
  await view.get(); // Triggers file serving
  
  expect(adapter.context.response.statusCode, 200);
  // Verify file was served
});
```

---

## 9. Documentation Needs

### 9.1 New Documentation Files

**Create:** `routed_class_view/ADVANCED_FEATURES.md`

- Content negotiation
- File serving
- Streaming responses
- Template rendering with routed
- Custom renderers

**Create:** `routed_class_view/MIGRATION.md`

- How to use new features
- Backwards compatibility notes
- Examples

**Update:** `routed_class_view/README.md`

- Add section on advanced features
- Add examples
- Link to new docs

### 9.2 API Documentation

Add comprehensive dartdoc comments:

```dart
/// Extension providing routed-specific features for class-based views.
///
/// When using the RoutedAdapter, views can access advanced routed features
/// like content negotiation, file serving, and streaming responses.
///
/// Example:
/// ```dart
/// class MyView extends View {
///   @override
///   Future<void> get() async {
///     if (isRoutedView) {
///       await sendXml(data); // Use routed feature
///     } else {
///       await sendJson(data); // Fallback
///     }
///   }
/// }
/// ```
extension RoutedViewExtensions on View {
  // ...
}
```

---

## 10. Recommendations Summary

### 10.1 Immediate Actions (This Week) 🔴

1. ✅ **Remove debug prints** (already complete)
2. ✅ **Expose context getter** (available via `adapter.context`)
3. 🔄 **Update documentation/examples**
    - Add note about direct context access
    - Demonstrate config/cache integrations
4. 🔄 **Trim unnecessary async wrappers** to reduce overhead

### 10.2 Short Term (This Month) 🟡

4. **Implement Option B: Routed-Specific Extensions**
    - Create `RoutedViewExtensions`
    - Add `sendXml`, `sendYaml`, `sendTemplate`
    - Add `serveFile`, `downloadFile`
    - Add `streamResponse`

5. **Add content negotiation helper**
    - Create `ContentNegotiator` class
    - Add `negotiateResponse` extension

6. **Write comprehensive tests**
    - Test all new extensions
    - Test content negotiation
    - Test file serving
    - Test streaming

7. **Document new features**
    - Create ADVANCED_FEATURES.md
    - Update README with examples
    - Add dartdoc comments

### 10.3 Medium Term (Next Quarter) 🟢

8. **Consider Option C: Capability System**
    - Design capability detection API
    - Implement for routed and shelf
    - Provide migration guide

9. **Performance optimization**
    - Benchmark response methods
    - Optimize common paths
    - Add caching where appropriate

10. **Integration examples**
    - API with content negotiation
    - File download service
    - Streaming video/audio
    - Multi-format export

---

## 11. Comparison: Current vs Potential

### 11.1 Current Capabilities

```dart
class MyView extends ListView<Post> {
  @override
  Future<void> get() async {
    final posts = await getObjectList();
    
    // Only JSON response possible
    await sendJson({
      'posts': posts.items.map((p) => p.toJson()).toList(),
      'total': posts.total,
    });
  }
}
```

**Limitations:**

- Only JSON output
- No file serving
- No streaming
- No content negotiation
- Manual HTML rendering

### 11.2 With Enhanced Adapter

```dart
class MyView extends ListView<Post> with RoutedViewMixin {
  @override
  Future<void> get() async {
    final posts = await getObjectList();
    final data = {
      'posts': posts.items.map((p) => p.toJson()).toList(),
      'total': posts.total,
    };
    
    // Automatic content negotiation
    await negotiateResponse(data, supportedFormats: ['json', 'xml', 'yaml']);
  }
}

class ExportView extends ListView<Post> {
  @override
  Future<void> get() async {
    final posts = await getObjectList();
    
    final format = getParam('format');
    switch (format) {
      case 'csv':
        // Stream CSV efficiently
        await streamResponse(
          generateCSV(posts.items),
          'text/csv',
        );
        
      case 'excel':
        // Serve generated file
        final file = await generateExcel(posts.items);
        await downloadFile(file.path, filename: 'export.xlsx');
        
      case 'pdf':
        // Serve PDF
        final pdf = await generatePDF(posts.items);
        await downloadFile(pdf.path, filename: 'export.pdf');
        
      default:
        await negotiateResponse({
          'posts': posts.items.map((p) => p.toJson()).toList(),
        });
    }
  }
}
```

**Benefits:**

- ✅ Multiple output formats
- ✅ Automatic content negotiation
- ✅ Efficient streaming
- ✅ File serving built-in
- ✅ Clean, readable code

---

## 12. Performance Considerations

### 12.1 Current Implementation

```dart
@override
Future<void> writeJson(Map<String, dynamic> data, {int statusCode = 200}) async {
  _context.json(data, statusCode: statusCode);
}
```

**Analysis:**

- ✅ Direct passthrough (good)
- ✅ No extra overhead
- ❌ Unnecessary async wrapper

### 12.2 Proposed Extensions

```dart
Future<void> sendXml(Map<String, dynamic> data, {int statusCode = 200}) async {
  final ctx = routedContext;
  if (ctx == null) throw StateError('Not a routed view');
  ctx.status(statusCode);
  ctx.xml(data);
}
```

**Analysis:**

- ✅ Type check cached in getter
- ✅ Direct context access (no overhead)
- ⚠️ StateError for non-routed views (acceptable)

**Optimization:**

```dart
Future<void> sendXml(Map<String, dynamic> data, {int statusCode = 200}) async {
  final ctx = routedContext ?? 
    (throw StateError('sendXml requires RoutedAdapter'));
  ctx.xml(data, statusCode: statusCode);
}
```

---

## 13. Breaking Change Analysis

### 13.1 Proposed Changes Impact

**Option A: Extend Interface**

- ❌ BREAKING for all adapters
- ❌ Forces shelf adapter changes
- ❌ Migration effort required

**Option B: Routed Extensions** ⭐ RECOMMENDED

- ✅ NON-BREAKING
- ✅ No impact on existing code
- ✅ Additive only
- ✅ Optional features

**Option C: Capability System**

- ✅ NON-BREAKING
- ✅ More complex but flexible
- ⚠️ More code to maintain

### 13.2 Backwards Compatibility

All proposed changes maintain backwards compatibility:

```dart
// Existing code continues to work
class OldView extends View {
  @override
  Future<void> get() async {
    await sendJson(data); // ✅ Still works
  }
}

// New code can use enhanced features
class NewView extends View {
  @override
  Future<void> get() async {
    if (isRoutedView) {
      await sendXml(data); // ✅ New feature
    } else {
      await sendJson(data); // ✅ Fallback
    }
  }
}
```

---

## 14. Conclusion

### 14.1 Summary

The routed_class_view adapter is **functional but significantly underutilizing** routed's capabilities. Routed now
provides:

- 10+ response formats (JSON, XML, YAML, HTML, etc.)
- Advanced content negotiation
- File serving and downloads
- Streaming responses
- Custom renderer support
- Template engine integration

**Current adapter exposes only 20% of these features.**

### 14.2 Recommended Path Forward

**Phase 1: Cleanup (1 week)**

1. Update docs & examples to highlight context-based integrations
2. Remove unnecessary async wrappers from adapter methods
3. Add regression tests covering the context getter and existing helpers

**Phase 2: Extensions (2-3 weeks)**

1. Implement `RoutedViewExtensions`
2. Add content negotiation helper
3. Write comprehensive tests
4. Document new features with examples

**Phase 3: Polish (1-2 weeks)**

1. Add advanced examples
2. Performance testing
3. Integration guides
4. Migration documentation

### 14.3 Expected Benefits

**For Developers:**

- ✅ Access to 10+ response formats
- ✅ Automatic content negotiation
- ✅ Efficient file serving
- ✅ Streaming support
- ✅ Cleaner, more expressive code

**For Applications:**

- ✅ Better performance (streaming)
- ✅ More flexible APIs
- ✅ Enhanced user experience
- ✅ Future-proof architecture

**For Ecosystem:**

- ✅ Better alignment with routed
- ✅ Demonstrates routed capabilities
- ✅ Encourages best practices
- ✅ Competitive with other frameworks

---

## Appendix A: Routed Response Methods Reference

```dart
// Status
void status(int code)

// Writing
void write(String s)
void setHeader(String name, String value)

// JSON (5 variants)
Response json(dynamic data, {int statusCode})
Response jsonp(dynamic data, {String callback, int statusCode})
Response indentedJson(dynamic data, {int statusCode})
Response secureJson(dynamic data, {int statusCode, String prefix})
Response asciiJson(dynamic data, {int statusCode})

// Other formats
Response string(String content, {int statusCode})
Response xml(Map<String, dynamic> data, {int statusCode})
Response yaml(Map<String, dynamic> data, {int statusCode})
Response data(String contentType, List<int> data, {int statusCode})

// Templates
Future<Response> html(String content, {Map<String, dynamic> data, int statusCode})
Future<Response> template({String? content, Map<String, dynamic> data, int statusCode, String? templateName})
Future<String> templateString({String? content, Map<String, dynamic> data, String? templateName})

// Files
Future<Response> file(String filePath)
Future<Response> dir(String dirPath)
Future<Response> fileAttachment(String filePath, String? filename)

// Streaming
Response dataFromReader({
  required int statusCode,
  int? contentLength,
  required String contentType,
  required Stream<List<int>> reader,
  Map<String, String>? extraHeaders,
})

// Redirect
Future<Response> redirect(String url, {int statusCode})

// Custom
FutureOr<Response> render(int statusCode, Render renderer)
```

## Appendix B: Implementation Checklist

- [ ] Remove debug print statements
- [ ] Expose context getter
- [ ] Create `RoutedViewExtensions` class
- [ ] Implement `sendXml` method
- [ ] Implement `sendYaml` method
- [ ] Implement `sendTemplate` method
- [ ] Implement `serveFile` method
- [ ] Implement `downloadFile` method
- [ ] Implement `streamResponse` method
- [ ] Implement `renderWith` method
- [ ] Create `ContentNegotiator` helper
- [ ] Add `negotiateResponse` extension
- [ ] Write unit tests for extensions
- [ ] Write integration tests
- [ ] Create ADVANCED_FEATURES.md
- [ ] Update README.md
- [ ] Add dartdoc comments
- [ ] Create usage examples
- [ ] Add performance benchmarks
- [ ] Update CHANGELOG.md

---

**End of Review Document**

*Generated: 2025-10-18*  
*Package: routed_class_view*  
*For: routed_ecosystem*
