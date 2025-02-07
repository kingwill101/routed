import 'dart:async';

abstract class LocalStorage {
  FutureOr<String?> getLocalStorageItem(String key);

  FutureOr<void> setLocalStorageItem(String key, String value);

  FutureOr<void> removeLocalStorageItem(String key);

  FutureOr<void> clearLocalStorage();

  FutureOr<Map<String, String>> getAllLocalStorageItems();
}
