/// Recognize an executed PTY output line, not the shell's echoed input.
/// Bash may surround output with ANSI cursor/bracketed-paste sequences.
/// Linux PTY lines may use LF or CRLF, with a prompt at the start of a line.
bool hasExecutedPtyOutputLine(String output, String expected) {
  final plain = output
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)'), '')
      .replaceAll('\r', '');
  return plain.split('\n').any((line) {
    final printable = line
        .replaceAll(RegExp(r'[\x00-\x08\x0B-\x1F\x7F]'), '')
        .trimRight();
    return printable == expected ||
        printable.endsWith(r'$ ' + expected) ||
        printable.endsWith('# ' + expected);
  });
}

/// Keep the non-rendering codes visible if an actual PTY output test fails.
String describePtyOutputTail(String output) {
  final tail = output.length > 450
      ? output.substring(output.length - 450)
      : output;
  final escaped = tail
      .replaceAll('\x1b', r'\x1b')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n' + '\n')
      .replaceAll('\x00', r'\x00');
  final bytes = tail.codeUnits;
  final lastUnits = bytes.length > 100
      ? bytes.sublist(bytes.length - 100)
      : bytes;
  return 'text=$escaped codeUnits=$lastUnits';
}
