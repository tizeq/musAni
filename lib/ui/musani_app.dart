import 'package:material_ui/material_ui.dart';

import '../library/library_controller.dart';
import '../playback/playback_engine.dart';
import '../settings/settings_controller.dart';
import 'design_system.dart';
import 'player_page.dart';

class MusaniApp extends StatelessWidget {
  const MusaniApp({
    super.key,
    required this.engine,
    required this.library,
    required this.settings,
  });
  final PlaybackEngine engine;
  final LibraryController library;
  final SettingsController settings;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final value = settings.value;
      final brightness = switch (value.colors) {
        ColorMode.light => Brightness.light,
        ColorMode.dark => Brightness.dark,
        ColorMode.system => MediaQuery.platformBrightnessOf(context),
      };
      final reduced =
          value.reduceMotion || MediaQuery.disableAnimationsOf(context);
      return MaterialApp(
        title: 'musAni',
        debugShowCheckedModeBanner: false,
        theme: MusaniDesign.theme(
          value.style,
          brightness,
          reduceMotion: reduced,
          glassEffects: value.glassEffects,
        ),
        themeAnimationDuration: reduced ? Duration.zero : MusaniDesign.motion,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              disableAnimations: media.disableAnimations || value.reduceMotion,
            ),
            child: child!,
          );
        },
        home: PlayerPage(engine: engine, library: library, settings: settings),
      );
    },
  );
}
