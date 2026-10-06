import 'dart:io';

import 'package:test/test.dart';
import 'package:android_libcpp_shared/src/process.dart';

void main() {
  test('runProcess returns correct output', () async {
    final result = await runProcess(
      executable: Uri.file(Platform.isWindows ? 'cmd' : 'echo'),
      arguments: Platform.isWindows
          // Separate arguments: one containing a space would be quoted, and
          // cmd's echo prints the quotes.
          ? ['/c', 'echo', 'Hello,', 'World!']
          : ['Hello, World!'],
    );
    expect(result.exitCode, 0);
    expect(result.stdout.trim(), 'Hello, World!');
    expect(result.stderr, '');
  });

  test('runProcess returns non-zero exit code for failing command', () async {
    final result = await runProcess(
      executable: Uri.file(Platform.isWindows ? 'cmd' : 'ls'),
      arguments: Platform.isWindows
          // Unlike `dir`, `type` prints nothing to stdout when it fails.
          ? ['/c', 'type', 'non_existent_file']
          : ['non_existent_directory'],
    );
    expect(result.exitCode, isNonZero);
    expect(result.stdout, '');
    expect(result.stderr, isNotEmpty);
  });

  test('which finds existing executable', () async {
    final whichResult = await which(Platform.isWindows ? 'cmd' : 'echo');
    expect(whichResult, isNotNull);
  });

  test('which returns null for non-existent executable', () async {
    final whichResult = await which('some_non_existent_executable');
    expect(whichResult, isNull);
  });
}
