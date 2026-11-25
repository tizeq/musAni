import 'dart:io';

Future<void> main(List<String> arguments) async {
  // Keep the generated plugin entry point, using the compiler's multi-root
  // scheme so the AOT snapshot carries no build-machine path.
  final registrant = Uri.file(
    '${Directory.current.path}/.dart_tool/flutter_build/dart_plugin_registrant.dart',
  ).toString();
  const portable =
      'org-dartlang-root:///.dart_tool/flutter_build/dart_plugin_registrant.dart';
  final sdkBin = File(Platform.resolvedExecutable).parent.path;
  final server = await Process.start('$sdkBin/dartaotruntime', [
    '$sdkBin/snapshots/frontend_server_aot.dart.snapshot',
    for (final arg in arguments) arg.replaceAll(registrant, portable),
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await server.exitCode;
}
