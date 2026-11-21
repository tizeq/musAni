import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Linux statx has a stable kernel ABI, unlike the architecture-specific stat.
class LinuxFileIdentity {
  const LinuxFileIdentity(this.inode, this.owner, this.group, this.links);
  final int inode;
  final int owner;
  final int group;
  final int links;
}

final _libc = DynamicLibrary.process();
final _statx = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
    >('statx');
final _uid = _libc.lookupFunction<Uint32 Function(), int Function()>('geteuid');
final _chmod = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('chmod');
final _chown = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32, Uint32),
      int Function(Pointer<Utf8>, int, int)
    >('chown');
final _listxattr = _libc
    .lookupFunction<
      IntPtr Function(Pointer<Utf8>, Pointer<Void>, IntPtr),
      int Function(Pointer<Utf8>, Pointer<Void>, int)
    >('listxattr');
final _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)
    >('open');
final _fsync = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'fsync',
);
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);

final _flock = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'flock',
    );

int lockMetadataFile(String path) {
  final name = path.toNativeUtf8();
  try {
    final descriptor = _open(
      name,
      2 | 0x20000 | 0x80000,
    ); // RDWR, NOFOLLOW, CLOEXEC; no create/truncate
    if (descriptor < 0)
      throw FileSystemException('Нет доступа для записи в файл', path);
    if (_flock(descriptor, 2 | 4) != 0) {
      _close(descriptor);
      throw FileSystemException('Файл занят другим редактором', path);
    }
    return descriptor;
  } finally {
    calloc.free(name);
  }
}

void unlockMetadataFile(int descriptor) {
  _flock(descriptor, 8);
  _close(descriptor);
}

LinuxFileIdentity identity(String path) {
  final name = path.toNativeUtf8();
  final memory = calloc<Uint8>(256);
  try {
    if (_statx(-100, name, 0x100, 0x7ff, memory) != 0)
      throw FileSystemException('Не удалось проверить файл', path);
    final data = ByteData.sublistView(memory.asTypedList(256));
    return LinuxFileIdentity(
      data.getUint64(32, Endian.host),
      data.getUint32(20, Endian.host),
      data.getUint32(24, Endian.host),
      data.getUint32(16, Endian.host),
    );
  } finally {
    calloc.free(name);
    calloc.free(memory);
  }
}

void requireEditable(String path) {
  if (!Platform.isLinux)
    throw UnsupportedError('Редактор пока поддерживает только Linux');
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException(
      'Редактирование ссылок и специальных файлов не поддерживается',
      path,
    );
  }
  final info = identity(path);
  if (info.owner != _uid() || info.links != 1) {
    throw FileSystemException(
      'Нужен принадлежащий вам файл без жёстких ссылок',
      path,
    );
  }
  final mode = File(path).statSync().mode;
  if (mode & 0x80 == 0 || mode & 0xe00 != 0) {
    throw FileSystemException(
      'Файл недоступен для записи или имеет специальные права',
      path,
    );
  }
  final name = path.toNativeUtf8();
  try {
    // Refuse rather than silently discard ACLs, capabilities or user xattrs.
    if (_listxattr(name, nullptr, 0) != 0) {
      throw FileSystemException(
        'Файлы с ACL/расширенными атрибутами пока не редактируются',
        path,
      );
    }
  } finally {
    calloc.free(name);
  }
}

void setPermissions(String path, int mode, {LinuxFileIdentity? original}) {
  final name = path.toNativeUtf8();
  try {
    if (original != null && _chown(name, original.owner, original.group) != 0) {
      throw FileSystemException('Не удалось сохранить владельца файла', path);
    }
    if (_chmod(name, mode & 0x1ff) != 0)
      throw FileSystemException('Не удалось установить права файла', path);
  } finally {
    calloc.free(name);
  }
}

void syncDirectory(String path) {
  final name = path.toNativeUtf8();
  try {
    final descriptor = _open(name, 0x10000); // O_RDONLY | O_DIRECTORY
    if (descriptor < 0)
      throw FileSystemException('Не удалось открыть каталог для fsync', path);
    try {
      if (_fsync(descriptor) != 0)
        throw FileSystemException('Не удалось синхронизировать каталог', path);
    } finally {
      _close(descriptor);
    }
  } finally {
    calloc.free(name);
  }
}
