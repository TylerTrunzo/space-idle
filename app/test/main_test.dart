import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/main.dart' as app;
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/shell.dart';

void main() {
  testWidgets('main boots the themed app on the device save slot', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    app.main();
    await tester.pump();

    expect(find.byType(SpaceIdleApp), findsOneWidget);
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.title, 'Space Idle');
    expect(material.theme?.scaffoldBackgroundColor, Palette.background);

    // The in-memory prefs answer asynchronously; let start() finish.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Shell), findsOneWidget);
  });
}
