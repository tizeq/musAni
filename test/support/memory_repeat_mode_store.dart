import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/repeat_mode_store.dart';

class MemoryRepeatModeStore implements RepeatModeStore {
  MemoryRepeatModeStore([this.value = RepeatMode.off]);

  RepeatMode value;
  Object? loadError;
  Object? saveError;
  final savedModes = <RepeatMode>[];

  @override
  Future<RepeatMode> load() async {
    if (loadError case final error?) throw error;
    return value;
  }

  @override
  Future<void> save(RepeatMode mode) async {
    if (saveError case final error?) throw error;
    value = mode;
    savedModes.add(mode);
  }
}
