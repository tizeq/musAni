import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/metadata/track_editor.dart';
import 'package:musani/ui/library_widgets.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';

import 'support/library_fakes.dart';

class FakeTrackEditor implements TrackEditor {
  Object? readError;
  Object? writeError;
  MetadataPatch? patch;
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<EditSnapshot> read(String path) async {
    if (readError case final error?) throw error;
    return EditSnapshot(
      path: path,
      hash: 'revision',
      size: 1,
      modifiedUs: 1,
      changedUs: 1,
      inode: 1,
      artists: const ['Artist'],
      fields: {
        for (final key in editableFields)
          key: switch (key) {
            'TITLE' => 'Fresh file title',
            'ALBUMARTIST' => 'Album artist',
            'ALBUM' => 'Album',
            'DATE' => '2026',
            'GENRE' => 'Jazz',
            'TRACKNUMBER' => '2',
            _ => '',
          },
      },
    );
  }

  @override
  Future<EditResult> save(EditSnapshot snapshot, MetadataPatch value) async {
    writes++;
    patch = value;
    await gate?.future;
    if (writeError case final error?) throw error;
    return const EditResult('/tmp/backup');
  }
}

class EditorController extends LibraryController {
  EditorController()
    : super(FakeLibraryRepository(sampleLibraryTracks('/tmp')));
  int updates = 0;
  Object? refreshError;
  @override
  Future<void> metadataChanged(String path) async {
    updates++;
    if (refreshError case final error?) throw error;
  }
}

void main() {
  late FakeTrackEditor editor;
  late EditorController controller;
  MetadataSaveOutcome? outcome;
  setUp(() {
    outcome = null;
    editor = FakeTrackEditor();
    controller = EditorController();
  });
  tearDown(() => controller.dispose());

  Future<void> open(WidgetTester tester, {CoverPicker? picker}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<MetadataSaveOutcome>(
                context: context,
                barrierDismissible: false,
                builder: (_) => MetadataEditorDialog(
                  path: '/tmp/track.mp3',
                  editor: editor,
                  controller: controller,
                  coverPicker: picker ?? () async => null,
                ),
              ).then((value) => outcome = value),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows all fields from a fresh file read and cancels without writing',
    (tester) async {
      await open(tester);
      expect(find.text('Fresh file title'), findsOneWidget);
      for (final key in editableFields) {
        expect(find.byKey(Key('metadata-$key')), findsOneWidget);
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(editor.writes, 0);
    },
  );

  testWidgets('writes only changed fields and refreshes the library', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const Key('metadata-TITLE')),
      'Changed title',
    );
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(editor.patch!.fields, {'TITLE': 'Changed title'});
    expect(controller.updates, 1);
    expect(find.byType(MetadataEditorDialog), findsNothing);
  });

  testWidgets(
    'catalog failure after a successful file write returns a distinct warning',
    (tester) async {
      controller.refreshError = StateError('database unavailable');
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('metadata-TITLE')),
        'Saved to file',
      );
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(editor.writes, 1);
      expect(find.byType(MetadataEditorDialog), findsNothing);
      expect(outcome!.catalogWarning, contains('Файл сохранён'));
      expect(outcome!.catalogWarning, contains('database unavailable'));
      expect(controller.editing, isFalse);
    },
  );

  testWidgets(
    'explicit artist rows add/remove individuals without splitting punctuation',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('metadata-artist-0')),
        'Tyler, The Creator',
      );
      await tester.ensureVisible(find.byKey(const Key('metadata-add-artist')));
      await tester.tap(find.byKey(const Key('metadata-add-artist')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('metadata-artist-1')));
      await tester.enterText(
        find.byKey(const Key('metadata-artist-1')),
        'AC/DC',
      );
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(editor.patch!.fields, isEmpty);
      expect(editor.patch!.artists, ['Tyler, The Creator', 'AC/DC']);
      expect(controller.updates, 1);
    },
  );

  testWidgets(
    'removing a focused artist preserves other rows and permits clearing the list',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.byKey(const Key('metadata-add-artist')));
      await tester.tap(find.byKey(const Key('metadata-add-artist')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('metadata-artist-1')));
      await tester.enterText(
        find.byKey(const Key('metadata-artist-1')),
        'Keep me',
      );
      await tester.ensureVisible(find.byTooltip('Удалить исполнителя 1'));
      await tester.tap(find.byTooltip('Удалить исполнителя 1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('metadata-artist-0')))
            .controller!
            .text,
        'Keep me',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Удалить исполнителя 1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('metadata-artist-0')), findsNothing);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(editor.patch!.artists, isEmpty);
      expect(editor.patch!.fields, isEmpty);
    },
  );

  testWidgets('an added blank artist must be filled or explicitly removed', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('metadata-add-artist')));
    await tester.tap(find.byKey(const Key('metadata-add-artist')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(editor.writes, 0);
    expect(find.text('Введите имя или удалите исполнителя'), findsOneWidget);
  });

  testWidgets('invalid year is rejected before writing', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('metadata-DATE')));
    await tester.enterText(
      find.byKey(const Key('metadata-DATE')),
      'not a year',
    );
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(editor.writes, 0);
    expect(find.text('От 1 до 9999 либо пустое поле'), findsOneWidget);
  });

  testWidgets('write errors retain edited text and allow retry', (
    tester,
  ) async {
    editor.writeError = StateError('write denied');
    await open(tester);
    await tester.enterText(
      find.byKey(const Key('metadata-TITLE')),
      'Changed title',
    );
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('write denied'), findsOneWidget);
    expect(find.text('Changed title'), findsOneWidget);
    expect(controller.updates, 0);
    editor.writeError = null;
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(controller.updates, 1);
  });

  testWidgets('read errors show retry and never enable save', (tester) async {
    editor.readError = const FormatException('corrupt file');
    await open(tester);
    expect(find.textContaining('corrupt file'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
          .onPressed,
      isNull,
    );
    editor.readError = null;
    await tester.tap(find.text('Повторить чтение'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh file title'), findsOneWidget);
  });

  testWidgets(
    'saving disables controls and cancellation until operation completes',
    (tester) async {
      editor.gate = Completer<void>();
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('metadata-TITLE')),
        'Changed title',
      );
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed,
        isNull,
      );
      expect(controller.editing, isTrue);
      editor.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.editing, isFalse);
      expect(editor.writes, 1);
    },
  );

  testWidgets('metadata action exists on a track menu', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryTrackTile(
            track: sampleLibraryTracks('/tmp').first,
            onTap: () {},
            onEdit: () => edits++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Действия трека'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать метаданные'));
    await tester.pumpAndSettle();
    expect(edits, 1);
  });
}
