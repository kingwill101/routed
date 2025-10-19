/// Driver registries for extending Routed integrations.
///
/// Import this when providing custom cache/storage/session drivers or when
/// inspecting driver metadata.
library;

export 'src/cache/cache_manager.dart'
    show CacheDriverRegistry, CacheDriverDocBuilder, CacheDriverDocContext;
export 'src/storage/storage_drivers.dart'
    show
        StorageDriverRegistry,
        StorageDriverContext,
        StorageDriverDocContext,
        StorageDriverDocBuilder,
        LocalStorageDisk,
        StorageDiskBuilder;
export 'src/engine/providers/sessions.dart'
    show
        SessionDriverRegistry,
        SessionDriverDocBuilder,
        SessionDriverDocContext,
        SessionDriverBuilder;
