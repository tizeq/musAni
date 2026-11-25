import 'dart:async';

import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/models.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/design_system.dart';
import 'package:musani/ui/library_navigation.dart';
import 'package:musani/ui/library_widgets.dart';

import 'support/library_fakes.dart';

import 'package:musani/playback/playback_engine.dart';
import 'package:musani/ui/player_page.dart';

class FakeEngine implements PlaybackEngine {
  FakeEngine({this.repeatMode = RepeatMode.off, this.queue = const []});

  final controller = StreamController<PlaybackState>.broadcast();
  int opens = 0;
  RepeatMode repeatMode;
  List<LocalTrack> queue;
  int index = 0;
  bool playing = true;
  bool shuffle = false;
  double volume = 80;
  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 10);
  final selectedModes = <RepeatMode>[];
  final jumps = <int>[];
  final seeks = <Duration>[];
  Object? repeatError;
  Completer<void>? repeatGate;
  @override
  PlaybackState get state => PlaybackState(
    queue: queue,
    index: index,
    playing: playing,
    position: position,
    duration: duration,
    volume: volume,
    repeatMode: repeatMode,
    shuffle: shuffle,
  );
  @override
  Stream<PlaybackState> get changes => controller.stream;
  @override
  Future<void> open(List<LocalTrack> tracks, {int index = 0}) async {
    opens++;
    queue = tracks;
    this.index = index;
    controller.add(state);
  }

  @override
  Future<void> toggle() async {
    playing = !playing;
    controller.add(state);
  }

  @override
  Future<void> jump(int index) async {
    this.index = index;
    jumps.add(index);
    controller.add(state);
  }

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
    seeks.add(position);
    controller.add(state);
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    controller.add(state);
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    await repeatGate?.future;
    if (repeatError case final error?) throw error;
    repeatMode = mode;
    selectedModes.add(mode);
    controller.add(state);
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    shuffle = enabled;
    controller.add(state);
  }

  @override
  Future<void> dispose() => controller.close();
}

void main() {
  final repeatButton = find.byKey(const Key('repeat-mode'));
  final tracks = [
    LocalTrack(Uri.file('/tmp/a.wav'), 'a.wav'),
    LocalTrack(Uri.file('/tmp/b.wav'), 'b.wav'),
  ];

  testWidgets(
    'position ticks update progress without rebuilding the player shell',
    (tester) async {
      final engine = FakeEngine(queue: tracks);
      await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
      final shell = tester.widget<Scaffold>(find.byType(Scaffold));
      for (var second = 1; second <= 5; second++) {
        engine.position = Duration(seconds: second);
        engine.controller.add(engine.state);
        await tester.pump();
        await tester.pump();
        expect(
          identical(shell, tester.widget<Scaffold>(find.byType(Scaffold))),
          isTrue,
        );
        expect(
          tester.widget<Slider>(find.byType(Slider).first).value,
          second * 1000,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Atmosphere progress skips subpixel updates and keeps time and seeking',
    (tester) async {
      final engine = FakeEngine(queue: tracks)
        ..duration = const Duration(minutes: 4);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusaniDesign.theme(MusaniTheme.atmosphere, Brightness.dark),
          home: PlayerPage(engine: engine),
        ),
      );
      final progress = find
          .descendant(
            of: find.byKey(const Key('playback-dock')),
            matching: find.byType(Slider),
          )
          .first;

      Future<void> tick(Duration position) async {
        engine.position = position;
        engine.controller.add(engine.state);
        await tester.pump();
        await tester.pump();
      }

      await tick(const Duration(milliseconds: 1100));
      final slider = tester.widget<Slider>(progress);
      await tick(const Duration(milliseconds: 1101));
      expect(tester.widget<Slider>(progress), same(slider));

      await tick(const Duration(seconds: 2));
      expect(find.text('0:02 / 4:00'), findsOneWidget);
      expect(tester.widget<Slider>(progress).value, 2000);

      final bounds = tester.getRect(progress);
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
      expect(engine.seeks.last.inSeconds, inInclusiveRange(118, 122));
      expect(
        tester.widget<Slider>(progress).value,
        engine.position.inMilliseconds,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'bottom player shows the current track artists beneath its title in queue view',
    (tester) async {
      final engine = FakeEngine(
        queue: [
          LocalTrack(
            Uri.file('/tmp/a.flac'),
            'First song',
            artists: const ['Tyler, The Creator', 'Guest'],
          ),
          LocalTrack(
            Uri.file('/tmp/b.flac'),
            'Second song',
            artists: const ['AC/DC'],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-artists'))).data,
        'Tyler, The Creator / Guest',
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('now-playing-artists'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('now-playing-title'))).dy,
        ),
      );
      await tester.tap(find.byTooltip('Следующий'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-title'))).data,
        'Second song',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-artists'))).data,
        'AC/DC',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final theme in MusaniTheme.values) {
    testWidgets('player and track lists hide album metadata in ${theme.name}', (
      tester,
    ) async {
      const track = LibraryTrack(
        id: 1,
        path: '/tmp/album-track.flac',
        albumId: 'playlist:example',
        metadata: TrackMetadata(
          title: 'Композиция',
          artists: ['Исполнитель трека'],
          album: 'Концертный альбом',
          albumArtist: 'Ансамбль',
          trackNumber: 1,
          discNumber: 2,
        ),
        size: 0,
        modifiedUs: 0,
        changedUs: 0,
      );
      final repo = FakeLibraryRepository([track]);
      final engine = FakeEngine(queue: [track.playable]);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusaniDesign.theme(theme, Brightness.dark),
          home: PlayerPage(
            engine: engine,
            library: LibraryController(repo)
              ..query = const LibraryQuery(view: LibraryView.tracks),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.labelReads, greaterThan(0));
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-title'))).data,
        track.metadata.title,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-artists'))).data,
        track.metadata.artists.single,
      );
      void expectNoAlbumMetadata() {
        expect(find.textContaining(track.metadata.album), findsNothing);
        expect(find.textContaining('Диск 2'), findsNothing);
        expect(find.textContaining('№ 1'), findsNothing);
      }

      expect(find.byType(LibraryTrackTile), findsOneWidget);
      expectNoAlbumMetadata();

      await tester.tap(
        find.byTooltip(
          theme == MusaniTheme.atmosphere
              ? 'Открыть очередь'
              : 'Очередь воспроизведения',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('queue-current-track-0')), findsOneWidget);
      expectNoAlbumMetadata();

      if (theme == MusaniTheme.atmosphere) {
        await tester.tap(find.byKey(const Key('collection-mode-currentTrack')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('panel-track-title')), findsOneWidget);
        expectNoAlbumMetadata();
      }
    });
  }

  testWidgets(
    'catalog edits refresh current labels without reopening audio or querying on position ticks',
    (tester) async {
      final tracks = sampleLibraryTracks('/tmp');
      final repo = FakeLibraryRepository(tracks);
      final library = LibraryController(repo)
        ..query = const LibraryQuery(view: LibraryView.tracks);
      final queue = tracks.map((track) => track.playable).toList();
      final engine = FakeEngine(queue: queue, repeatMode: RepeatMode.one);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(engine: engine, library: library),
        ),
      );
      await tester.pumpAndSettle();
      final reads = repo.labelReads;
      final navigation = tester.widget<LibraryNavigation>(
        find.byType(LibraryNavigation),
      );
      final trackRow = find.byType(LibraryTrackTile).first;
      final row = tester.widget<LibraryTrackTile>(trackRow);
      final marker = find.byKey(
        Key('library-current-track-${tracks.first.id}'),
      );
      final indicator = tester.widget(marker);
      final slider = find.byType(Slider).first;
      for (var second = 1; second < 5; second++) {
        engine.position = Duration(seconds: second);
        engine.controller.add(engine.state);
        await tester.pump();
        await tester.pump();
        expect(
          tester.widget(slider),
          isA<Slider>().having((s) => s.value, 'value', second * 1000),
        );
        expect(tester.widget(find.byType(LibraryNavigation)), same(navigation));
        expect(tester.widget(trackRow), same(row));
        expect(tester.widget(marker), same(indicator));
        final currentSlider = tester.widget(slider);
        engine.controller.add(engine.state);
        await tester.pump();
        await tester.pump();
        expect(tester.widget(slider), same(currentSlider));
      }
      expect(repo.labelReads, reads);
      final old = tracks.first;
      tracks[0] = LibraryTrack(
        id: old.id,
        path: old.path,
        albumId: old.albumId,
        metadata: const TrackMetadata(
          title: 'Changed title',
          artists: ['Tyler, The Creator', 'Guest'],
          album: 'Север',
          albumArtist: 'Группа',
        ),
        size: old.size,
        modifiedUs: old.modifiedUs,
        changedUs: old.changedUs,
      );
      await library.metadataChanged(old.path);
      await tester.pumpAndSettle();
      expect(repo.labelReads, reads + 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-artists'))).data,
        'Tyler, The Creator / Guest',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-title'))).data,
        'Changed title',
      );
      await tester.tap(find.byTooltip('Очередь воспроизведения'));
      await tester.pumpAndSettle();
      expect(find.text('Changed title'), findsNWidgets(2));
      expect(find.text('Tyler, The Creator / Guest'), findsNWidgets(2));
      expect(identical(engine.queue, queue), isTrue);
      expect(engine.opens, 0);
      expect(engine.repeatMode, RepeatMode.one);
      expect(engine.position, const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in RepeatMode.values) {
    testWidgets('$mode has the correct icon, highlight and accessible label', (
      tester,
    ) async {
      final engine = FakeEngine(repeatMode: mode);
      await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
      final button = tester.widget<IconButton>(repeatButton);
      final theme = Theme.of(tester.element(repeatButton));
      expect(
        (button.icon as Icon).icon,
        mode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
      );
      expect(button.isSelected, mode != RepeatMode.off);
      expect(
        button.color,
        mode == RepeatMode.off
            ? theme.disabledColor
            : theme.colorScheme.primary,
      );
      final icon = find.descendant(
        of: repeatButton,
        matching: find.byType(Icon),
      );
      expect(
        IconTheme.of(tester.element(icon)).color,
        mode == RepeatMode.off
            ? theme.disabledColor
            : theme.colorScheme.primary,
      );
      expect(
        button.tooltip,
        contains(switch (mode) {
          RepeatMode.off => 'Repeat Off',
          RepeatMode.all => 'Repeat All',
          RepeatMode.one => 'Repeat One',
        }),
      );
      // Mode can be selected even before files are opened.
      expect(button.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode: manual navigation, pause and seeking keep the mode', (
      tester,
    ) async {
      final engine = FakeEngine(repeatMode: mode, queue: tracks);
      await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
      expect(
        tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.skip_previous),
                )
                .onPressed !=
            null,
        mode == RepeatMode.all,
      );
      await tester.tap(find.byTooltip('Следующий'));
      await tester.pumpAndSettle();
      expect(engine.jumps, [1]);
      expect(
        tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.skip_next),
                )
                .onPressed !=
            null,
        mode == RepeatMode.all,
      );
      if (mode == RepeatMode.all) {
        await tester.tap(find.byTooltip('Следующий'));
        await tester.pumpAndSettle();
        expect(engine.index, 0);
        await tester.tap(find.byTooltip('Предыдущий'));
        await tester.pumpAndSettle();
        expect(engine.index, 1);
      }
      await tester.tap(find.byTooltip('Пауза'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(engine.seeks, isNotEmpty);
      expect(engine.playing, isFalse);
      expect(engine.repeatMode, mode);
      expect(engine.selectedModes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('repeat button cycles Off -> All -> One -> Off', (tester) async {
    final engine = FakeEngine();
    await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
    for (final mode in [RepeatMode.all, RepeatMode.one, RepeatMode.off]) {
      await tester.tap(repeatButton);
      await tester.pumpAndSettle();
      expect(engine.repeatMode, mode);
      expect(
        tester.widget<IconButton>(repeatButton).isSelected,
        mode != RepeatMode.off,
      );
    }
    expect(engine.selectedModes, [
      RepeatMode.all,
      RepeatMode.one,
      RepeatMode.off,
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending repeat change prevents duplicate requests', (
    tester,
  ) async {
    final engine = FakeEngine()..repeatGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
    await tester.tap(repeatButton);
    await tester.pump();
    expect(tester.widget<IconButton>(repeatButton).onPressed, isNull);
    await tester.tap(repeatButton);
    engine.repeatGate!.complete();
    await tester.pumpAndSettle();
    expect(engine.selectedModes, [RepeatMode.all]);
    expect(tester.widget<IconButton>(repeatButton).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeat setting errors are visible and the button recovers', (
    tester,
  ) async {
    final engine = FakeEngine()..repeatError = StateError('settings denied');
    await tester.pumpWidget(MaterialApp(home: PlayerPage(engine: engine)));
    await tester.tap(repeatButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('settings denied'), findsOneWidget);
    expect(tester.widget<IconButton>(repeatButton).onPressed, isNotNull);
    expect(engine.repeatMode, RepeatMode.off);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelled picker does not replace the queue', (tester) async {
    final engine = FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(engine: engine, picker: () async => []),
      ),
    );
    await tester.tap(find.text('Выбрать музыку'));
    await tester.pumpAndSettle();
    expect(engine.opens, 0);
    expect(find.textContaining('Ошибка:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('picker errors are visible and controls recover', (tester) async {
    final engine = FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          engine: engine,
          picker: () async => throw StateError('access denied'),
        ),
      ),
    );
    await tester.tap(find.text('Выбрать музыку'));
    await tester.pumpAndSettle();
    expect(find.textContaining('access denied'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
