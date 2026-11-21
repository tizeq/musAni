import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/atmosphere.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('artwork accent survives eviction of the cover file and clears on track changes', () async {
    final dir = await Directory.systemTemp.createTemp('musani-accent-');
    final accent = ArtworkAccent();
    try {
      final file = File('${dir.path}/green.png');
      final picture = img.Image(width: 16, height: 16);
      img.fill(picture, color: img.ColorRgb8(30, 196, 78));
      await file.writeAsBytes(img.encodePng(picture));
      await accent.select(file.path);
      final sampled = accent.value!;
      expect(HSLColor.fromColor(sampled).hue, inInclusiveRange(130, 150));
      await file.delete();
      await accent.select(null);
      expect(accent.value, isNull);
      await accent.select(file.path);
      expect(accent.value, sampled);
      await accent.select('${dir.path}/missing.png');
      expect(accent.value, isNull);
    } finally {
      accent.dispose();
      await dir.delete(recursive: true);
    }
  });

  test(
    'library panels keep label contrast across artwork hues and schemes',
    () {
      for (final dark in [true, false]) {
        for (var hue = 0; hue < 360; hue += 15) {
          final g = GlassColors(
            dark,
            GlassEffects.full,
            HSLColor.fromAHSL(1, hue.toDouble(), .8, .5).toColor(),
          );
          for (final color in [g.ink, g.muted]) {
            for (final surface in [g.paneTint, g.selection, g.menuColor]) {
              final a = color.computeLuminance() + .05;
              final b = surface.computeLuminance() + .05;
              expect(
                a > b ? a / b : b / a,
                greaterThanOrEqualTo(4.5),
                reason: 'hue $hue, dark $dark',
              );
            }
          }
        }
      }
    },
  );
}
