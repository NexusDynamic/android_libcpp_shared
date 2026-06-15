import 'dart:convert';
import 'dart:io';
import 'dart:async';

final class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  ProcessResult(this.exitCode, this.stdout, this.stderr);
}

Future<ProcessResult> runProcess({
  required Uri executable,
  required List<String> arguments,
  Uri? workingDirectory,
  Map<String, String>? environment,
}) async {
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final process = await Process.start(
    executable.toFilePath(),
    arguments,
    workingDirectory: workingDirectory?.toFilePath(),
    environment: environment,
    runInShell: Platform.isWindows && workingDirectory != null,
  );

  // Windows uses system encoding (e.g., GBK for Chinese), while
  // Linux/macOS use UTF-8 for process output.
  final encoding = Platform.isWindows ? systemEncoding : utf8;
  final stdoutFuture = process.stdout
      .transform(encoding.decoder)
      .transform(const LineSplitter())
      .forEach(stdout.writeln);
  final stderrFuture = process.stderr
      .transform(encoding.decoder)
      .transform(const LineSplitter())
      .forEach(stderr.writeln);
  await Future.wait([stdoutFuture, stderrFuture]);
  final exitCode = await process.exitCode;
  return ProcessResult(exitCode, stdout.toString(), stderr.toString());
}

Future<Uri?> which(String executableName) async {
  final whichBin = Uri.file(Platform.isWindows ? 'where' : 'which');
  final process = await runProcess(
    executable: whichBin,
    arguments: [executableName],
  );
  if (process.exitCode == 0) {
    final file = File(LineSplitter.split(process.stdout).first);
    final uri = File(await file.resolveSymbolicLinks()).uri;
    if (uri.pathSegments.last case 'llvm' || 'lld') {
      return file.uri;
    }
    return uri;
  }
  // The exit code for executable not being on the `PATH`.
  assert(process.exitCode == 1);
  return null;
}
