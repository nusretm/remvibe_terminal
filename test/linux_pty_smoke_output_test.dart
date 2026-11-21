import 'package:test/test.dart';

import '../tool/linux_pty_smoke_output.dart';

void main() {
  test('matches real Bash LF output after echoed printf command', () {
    const output = 'bash-5.3$ printf "RVTERM_REAL_LINUX_A\\n"\n'
        'RVTERM_REAL_LINUX_A\nbash-5.3$ ';
    expect(hasExecutedPtyOutputLine(output, 'RVTERM_REAL_LINUX_A'), isTrue);
  });

  test('matches real PTY output containing bracketed-paste ANSI controls', () {
    const output = 'bash-5.3$ echo RVTERM_REAL_LINUX_A\r\n'
        '\x1b[?2004l\rRVTERM_REAL_LINUX_A\r\n'
        '\x1b[?2004hbash-5.3$ ';
    expect(hasExecutedPtyOutputLine(output, 'RVTERM_REAL_LINUX_A'), isTrue);
  });

  test('does not accept only echoed command as executed output', () {
    const output = 'bash-5.3$ echo RVTERM_REAL_LINUX_A\r\n'
        'bash-5.3$ ';
    expect(hasExecutedPtyOutputLine(output, 'RVTERM_REAL_LINUX_A'), isFalse);
  });

  test('accepts prompt-prefixed executed output and rejects partial words', () {
    expect(
      hasExecutedPtyOutputLine(r'$ RVTERM_PID=123', 'RVTERM_PID=123'),
      isTrue,
    );
    expect(
      hasExecutedPtyOutputLine('RVTERM_PID=12345\n', 'RVTERM_PID=123'),
      isFalse,
    );
  });

  test('shows invisible output bytes when diagnosing a failed smoke', () {
    final diagnostic = describePtyOutputTail('\x1b[?2004l\rX\n');
    expect(diagnostic, contains(r'\x1b'));
    expect(diagnostic, contains(r'\r'));
    expect(diagnostic, contains(r'\n'));
    expect(diagnostic, contains('codeUnits='));
  });
}
