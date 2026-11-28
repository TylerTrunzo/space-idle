import 'package:shared_preferences/shared_preferences.dart';

/// The app's own settings, kept apart from the game save: the guide's
/// place, whether the goal strip is folded. A new game keeps them; a save
/// moved to another device does not carry them.
abstract interface class SettingsStore {
  /// The text stored under [key], or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);
}

/// Settings in the device's shared preferences (local storage on web).
final class PrefsSettingsStore implements SettingsStore {
  /// Creates a store over the platform's shared preferences.
  PrefsSettingsStore() : _prefs = SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString('settings_$key');

  @override
  Future<void> write(String key, String value) =>
      _prefs.setString('settings_$key', value);
}

/// Settings in memory, for tests; [values] may be seeded and read back.
final class MemorySettingsStore implements SettingsStore {
  /// Creates a store, empty or holding [values].
  MemorySettingsStore([Map<String, String>? values]) : values = values ?? {};

  /// What is stored.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
