import 'dart:async';

abstract class SessionStorage {
  FutureOr<String?> getSessionStorageItem(String key);

  FutureOr<void> setSessionStorageItem(String key, String value);

  FutureOr<void> removeSessionStorageItem(String key);

  FutureOr<void> clearSessionStorage();

  FutureOr<Map<String, String>> getAllSessionStorageItems();
}
