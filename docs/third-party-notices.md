# Сторонние компоненты Linux bundle

Полные уведомления Flutter, Dart и пакетов лежат в
`data/flutter_assets/NOTICES.Z`. Файл распаковывается командой
`gzip -dc data/flutter_assets/NOTICES.Z`. В них входят лицензии Flutter,
Material UI, Material Icons, media_kit и его плагинов, SQLite Dart bindings,
file_selector, JNI и остальных включённых пакетов.

| Компонент | Условия и исходники |
| --- | --- |
| flutter_taglib bridge 1.6.0 | Apache-2.0. Собран из [исходников bridge](https://github.com/axel10/flutter_taglib/tree/d2b7674b386583f5ef80188c3497709137dddae2). |
| TagLib 2.3 внутри bridge | Статически включена в `lib/libflutter_taglib_native.so` по LGPL 2.1, §6(a). Использованы неизменённые [исходники TagLib v2.3](https://github.com/taglib/taglib/tree/v2.3). Исходники, объект bridge и скрипт перелинковки предоставляются с релизом. |
| utfcpp 4.0.9 | Лицензия Boost Software License 1.0. [Исходники utfcpp v4.0.9](https://github.com/nemtrif/utfcpp/tree/v4.0.9). |
| mimalloc 2.1.2 | MIT. Статически включён через media_kit. [Исходники mimalloc v2.1.2](https://github.com/microsoft/mimalloc/tree/v2.1.2). |
| hls.js 1.4.10 | Apache-2.0. Поставляется как ресурс пакета media_kit. [Исходники hls.js v1.4.10](https://github.com/video-dev/hls.js/tree/v1.4.10). |

Тексты этих лицензий, авторы TagLib и отдельные уведомления Flutter Engine
и Material Icons приложены в `licenses/`. SQLite, libmpv и
libcurl загружаются из дистрибутива. Условия системного libmpv зависят от
того, как его собрал поставщик. Сторонние лицензии относятся к перечисленным
компонентам. [Лицензирование mpv](https://github.com/mpv-player/mpv/blob/v0.41.0/Copyright).

Пользователи вправе изменять библиотеку для собственного использования
и применять обратную разработку для отладки этих изменений. Инструкция
и информация о комплекте исходников находятся в `SOURCE-CODE.md`.

## Графика musAni

Фон Atmosphere создан ImageGen по текстовому запросу для прототипа musAni.
SHA-256 перенесённого в приложение `assets/atmosphere/aurora.webp`
совпадает с файлом прототипа.

```text
0f0e6b9d0568611b5b12255e0429f599ca81da5be7f19c83f082ed3ae69b9920
```

[Условия OpenAI о правах на результат генерации](https://openai.com/policies/terms-of-use/#content).
Демонстрационные обложки на снимках README также созданы для прототипа.
Библиотека, аудио для съёмки и демонстрационные обложки в архив не входят.
