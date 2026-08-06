library;

// Facade for view/translation presentation.
// Re-exports will be added as EngineContext extensions and view engines
// are moved from `routed` to this package (Phase 6 per refactor.md).
// For now this is a skeleton establishing the package boundary and
// owning the view-heavy dependencies (liquify, mustache_template, image).

export 'src/view_ext.dart';
