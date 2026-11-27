import 'package:shared_preferences/shared_preferences.dart';

/// Where the one save slot lives: the text of the save envelope.
abstract interface class SaveStore {
  /// The stored text, or null when nothing was ever saved.
  Future<String?> read();

  /// Replaces the stored text with [text].
  Future<void> write(String text);
}

/// The device's save slot, in shared preferences (local storage on web).
final class PrefsSaveStore implements SaveStore {
  /// Creates a store over the platform's shared preferences.
  PrefsSaveStore() : _prefs = SharedPreferencesAsync();

  /// Preferences key of the save envelope. A new key, not a migration, is
  /// how an incompatible envelope format would be introduced.
  static const key = 'save_v1';

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read() => _prefs.getString(key);

  @override
  Future<void> write(String text) => _prefs.setString(key, text);
}

/// An in-memory save slot for tests, counting [writes].
final class MemorySaveStore implements SaveStore {
  /// Creates a store holding [text]; seeding it does not count as a write.
  MemorySaveStore([this.text]);

  /// The stored text, which tests may set directly.
  String? text;

  /// Number of [write] calls so far.
  int writes = 0;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String text) async {
    writes++;
    this.text = text;
  }
}
