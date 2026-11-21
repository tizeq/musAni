import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../library/library_controller.dart';
import '../library/models.dart';
import '../metadata/track_editor.dart';
import 'motion.dart';

typedef CoverPicker = Future<String?> Function();

Future<String?> pickMetadataCover() async => (await openFile(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'Обложка JPEG/PNG', extensions: ['jpg', 'jpeg', 'png']),
  ],
))?.path;

class MetadataSaveOutcome {
  const MetadataSaveOutcome(this.result, this.catalogWarning);
  final EditResult result;
  final String? catalogWarning;
}

Future<bool> editTrackMetadata(
  BuildContext context,
  LibraryTrack track,
  LibraryController controller,
) => editTrackMetadataPath(context, track.path, controller);

Future<bool> editTrackMetadataPath(
  BuildContext context,
  String path,
  LibraryController controller,
) async {
  if (controller.mutating) {
    showAppSnackBar(
      context,
      const SnackBar(
        content: Text('Дождитесь завершения обновления библиотеки'),
      ),
    );
    return false;
  }
  final outcome = await showAppDialog<MetadataSaveOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MetadataEditorDialog(
      path: path,
      controller: controller,
      editor: TagLibTrackEditor(
        p.join(controller.repository.directory, '.musani-edit-backups'),
      ),
    ),
  );
  if (outcome == null) return false;
  if (context.mounted)
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(
          outcome.catalogWarning ??
              outcome.result.warning ??
              'Метаданные сохранены',
        ),
      ),
    );
  return true;
}

class MetadataEditorDialog extends StatefulWidget {
  const MetadataEditorDialog({
    super.key,
    required this.path,
    required this.editor,
    required this.controller,
    this.coverPicker = pickMetadataCover,
  });
  final String path;
  final TrackEditor editor;
  final LibraryController controller;
  final CoverPicker coverPicker;
  @override
  State<MetadataEditorDialog> createState() => _MetadataEditorDialogState();
}

class _MetadataEditorDialogState extends State<MetadataEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _artists = <TextEditingController>[];
  EditSnapshot? _snapshot;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _coverPath;
  static const _labels = {
    'TITLE': 'Название трека',
    'ALBUMARTIST': 'Исполнитель альбома',
    'ALBUM': 'Название альбома',
    'DATE': 'Год',
    'GENRE': 'Жанр',
    'TRACKNUMBER': 'Номер трека',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await widget.editor.read(widget.path);
      if (!mounted) return;
      for (final controller in _fields.values) {
        controller.dispose();
      }
      _fields.clear();
      for (final controller in _artists) {
        controller.dispose();
      }
      _artists.clear();
      _artists.addAll(
        snapshot.artists.map((name) => TextEditingController(text: name)),
      );
      for (final key in editableFields) {
        _fields[key] = TextEditingController(text: snapshot.fields[key] ?? '');
      }
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  MetadataPatch get _patch => MetadataPatch(
    {
      for (final entry in _fields.entries)
        if (entry.value.text != _snapshot!.fields[entry.key])
          entry.key: entry.value.text.trim(),
    },
    artists:
        listEquals(
          _artists.map((value) => value.text).toList(),
          _snapshot!.artists,
        )
        ? null
        : _artists.map((value) => value.text.trim()).toList(),
    coverPath: _coverPath,
  );

  Future<void> _pickCover() async {
    try {
      final path = await widget.coverPicker();
      if (mounted && path != null)
        setState(() {
          _coverPath = path;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await widget.controller.writeMetadata(() async {
        final saved = await widget.editor.save(_snapshot!, _patch);
        String? warning;
        try {
          await widget.controller.metadataChanged(widget.path);
        } catch (error) {
          warning =
              'Файл сохранён, но библиотека не обновилась: $error. Нажмите «Обновить библиотеку».';
        }
        return MetadataSaveOutcome(saved, warning);
      });
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop(outcome);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final controller in _artists) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final changed =
        snapshot != null &&
        (_patch.fields.isNotEmpty ||
            _patch.artists != null ||
            _coverPath != null);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Редактировать метаданные'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: BusyIndicator()),
                    ),
                  if (!_loading && snapshot != null) ...[
                    const SizedBox(height: 16),
                    for (final entry in _labels.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          key: Key('metadata-${entry.key}'),
                          controller: _fields[entry.key],
                          enabled: !_saving,
                          maxLength: 8192,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                          decoration: InputDecoration(
                            labelText: entry.value,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType:
                              ['DATE', 'TRACKNUMBER'].contains(entry.key)
                              ? TextInputType.number
                              : TextInputType.text,
                          validator: (value) {
                            if (['DATE', 'TRACKNUMBER'].contains(entry.key) &&
                                value!.trim().isNotEmpty) {
                              final number = int.tryParse(value.trim());
                              if (number == null || number < 1 || number > 9999)
                                return 'От 1 до 9999 либо пустое поле';
                            }
                            if (value?.contains('\u0000') ?? false)
                              return 'Недопустимый символ';
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (entry.key == 'TITLE') ...[
                        Text(
                          'Исполнители трека',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _artists.length; i++)
                          Padding(
                            key: ObjectKey(_artists[i]),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    key: Key('metadata-artist-$i'),
                                    controller: _artists[i],
                                    enabled: !_saving,
                                    maxLength: 8192,
                                    buildCounter: (
                                      _, {
                                      required currentLength,
                                      required isFocused,
                                      maxLength,
                                    }) => null,
                                    decoration: InputDecoration(
                                      labelText: 'Исполнитель ${i + 1}',
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? 'Введите имя или удалите исполнителя'
                                        : value.contains('\u0000')
                                        ? 'Недопустимый символ'
                                        : null,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Удалить исполнителя ${i + 1}',
                                  onPressed: _saving
                                      ? null
                                      : () {
                                          final removed = _artists[i];
                                          setState(
                                            () => _artists.remove(removed),
                                          );
                                          // The old TextFormField detaches on the next frame.
                                          WidgetsBinding.instance
                                              .addPostFrameCallback(
                                                (_) => removed.dispose(),
                                              );
                                        },
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                          ),
                        TextButton.icon(
                          key: const Key('metadata-add-artist'),
                          onPressed: _saving || _artists.length >= 100
                              ? null
                              : () => setState(
                                  () => _artists.add(TextEditingController()),
                                ),
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить исполнителя'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 84,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _coverPath != null
                                ? Image.file(
                                    File(_coverPath!),
                                    fit: BoxFit.cover,
                                    cacheWidth: 256,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  )
                                : snapshot.cover != null
                                ? Image.memory(
                                    snapshot.cover!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 256,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  )
                                : const Icon(Icons.album_outlined, size: 52),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _pickCover,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Выбрать обложку'),
                          ),
                        ),
                      ],
                    ),
                    if (_coverPath != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _coverPath = null),
                        child: const Text('Оставить прежнюю обложку'),
                      ),
                  ],
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: BusyIndicator.bar(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (!_loading && snapshot == null)
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить чтение'),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: _loading || _saving || !changed ? null : _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
