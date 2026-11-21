import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';
import 'package:test/test.dart';

void main() {
  test('Linux constructor rejects other platforms', () {
    if (Platform.isLinux) return;
    expect(() => RemVibeTerminal.linux(), throwsUnsupportedError);
  });

  test('Linux manual shared library path fails explicitly', () {
    if (!Platform.isLinux) return;
    expect(
      () => RemVibeTerminal.linux(
        libraryPath: '/definitely/no/remvibe_terminal_linux.so',
      ),
      throwsA(isA<TerminalLinuxLibraryLoadException>()),
    );
  });

  test('Linux native PTY starts actual shell, emits output and exits', () async {
    if (!Platform.isLinux) return;
    final engine = RemVibeTerminal.currentPlatform(
      pollInterval: const Duration(milliseconds: 10),
    );
    try {
      final session = engine.create(
        commandLine: 'exec /bin/sh -i',
        columns: 80,
        rows: 24,
      );
      final output = StringBuffer();
      final sub = session.output.listen((bytes) {
        output.write(latin1.decode(bytes));
      });
      try {
        session.write(utf8.encode('echo RVTERM_LINUX_TEST_SUCCESS\r'));
        final until = DateTime.now().add(const Duration(seconds: 8));
        // Require an executed result line, not the terminal's echoed command.
        // Linux PTYs may use LF or CRLF and prepend a shell prompt.
        while (!_hasPrintedLine(
          output.toString(),
          'RVTERM_LINUX_TEST_SUCCESS',
        )) {
          if (DateTime.now().isAfter(until)) {
            fail('No real Linux shell output: $output');
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        session.write(utf8.encode('exit 9\r'));
        expect(
          await session.exitCode.timeout(const Duration(seconds: 8)),
          9,
        );
      } finally {
        await sub.cancel();
        await session.close();
      }
    } finally {
      await engine.close();
    }
  }, skip: !Platform.isLinux);
}

bool _hasPrintedLine(String output, String expected) {
  final lines = output.replaceAll('\r', '').split('\n');
  return lines.any((line) {
    final result = line.trimRight();
    return result == expected ||
        result.endsWith(r'$ ' + expected) ||
        result.endsWith('# ' + expected);
  });
}

