# Журнал изменений

## v0.1.1

- Faster incremental library rescans and artist filtering, with optimized SQLite
  queries and batched metadata loading for the playback queue.
- More responsive scrolling and navigation in Atmosphere, with fewer widget
  rebuilds and shared artwork caching.
- User albums now own shared artwork and metadata, support multiple discs,
  and automatically renumber tracks when their order or disc changes.
- Batch writing for MP3 and FLAC album tags, with per-file backups and results
  for unsupported formats or failed writes.
- Existing libraries migrate to SQLite schema v6. See the
  [Linux upgrade guide](docs/linux-release.md) for rollback instructions.

## v0.1.0-alpha.1

Первый публичный тестовый выпуск для Linux x86-64.

- Локальная музыкальная библиотека SQLite с поиском, сортировкой, обложками,
  страницами исполнителей и альбомов.
- Контекстные очереди с предыдущим и следующим треком, перемешиванием и
  режимами повтора. Повторяющиеся позиции плейлиста сохраняются.
- Локальные плейлисты с обложками, перетаскиванием треков и типом «Альбом».
- Редактор тегов MP3 и FLAC с многозначными исполнителями и резервной копией.
- Minimal и Atmosphere с независимой цветовой схемой, Reduced Motion,
  настройками клавиатуры, внутренними вкладками и гибкой панелью коллекции.
- Снижена задержка открытия плейлистов и нагрузка Atmosphere при обновлении
  прогресса. Для Linux используется runtime-имя `libsqlite3.so.0`.
- Архив Flutter bundle с контрольной суммой и инструкцией для Linux.

[Инструкция по запуску и обновлению](docs/linux-release.md).
