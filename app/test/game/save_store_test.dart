import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:space_idle/game/save_store.dart';

void main() {
  group('MemorySaveStore', () {
    test('reads back what was written and counts reads and writes', () async {
      final store = MemorySaveStore();
      expect(await store.read(), isNull);

      await store.write('a');
      await store.write('b');
      expect(await store.read(), 'b');
      expect(store.writes, 2);
      expect(store.reads, 2);
    });

    test('can start with text, which is not a write', () async {
      final store = MemorySaveStore('seeded');
      expect(await store.read(), 'seeded');
      expect(store.writes, 0);
    });
  });

  group('PrefsSaveStore', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('is empty at first, then reads back what was written', () async {
      final store = PrefsSaveStore();
      expect(await store.read(), isNull);

      await store.write('{"savedAt": 1}');
      expect(await PrefsSaveStore().read(), '{"savedAt": 1}');
    });

    test('stores under the save_v1 key', () async {
      await PrefsSaveStore().write('x');

      final raw = await SharedPreferencesAsyncPlatform.instance!.getString(
        PrefsSaveStore.key,
        const SharedPreferencesOptions(),
      );
      expect(PrefsSaveStore.key, 'save_v1');
      expect(raw, 'x');
    });
  });
}
