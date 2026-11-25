import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library/library_controller.dart';
import 'library/library_repository.dart';
import 'playback/media_kit_engine.dart';
import 'settings/repeat_mode_store.dart';
import 'settings/settings_controller.dart';
import 'ui/musani_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
    final engine = MediaKitEngine(
      Player(configuration: const PlayerConfiguration(title: 'musAni')),
      repeatModeStore: PreferencesRepeatModeStore(),
    );
    final settings = SettingsController(PreferencesSettingsStore());
    final (directory, _, _) = await (
      getApplicationSupportDirectory(),
      settings.restore(),
      engine.restoreRepeatMode(),
    ).wait;
    final library = LibraryController(
      LibraryRepository(p.join(directory.path, 'library')),
    );
    runApp(MusaniApp(engine: engine, library: library, settings: settings));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'Не удалось запустить аудиодвижок.\nПроверьте установку libmpv.\n$error',
            ),
          ),
        ),
      ),
    );
  }
}
