// Dart Native Assets: build the same C++ ConPTY source used by CMake.
// The Client's 'dart build cli' automatically bundles the resulting DLL.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final target = input.config.code;
    // Each platform builds its own native PTY library as a Dart Code Asset.
    // Do not compile Windows ConPTY sources or link Win32 libs on Linux.
    if (target.targetOS == OS.linux) {
      if (target.targetArchitecture != Architecture.x64 &&
          target.targetArchitecture != Architecture.arm64) {
        throw UnsupportedError('Linux PTY supports x64/arm64 only.');
      }
      final linuxBuilder = CBuilder.library(
        name: 'remvibe_terminal_linux',
        assetName: 'src/linux/linux_pty.dart',
        sources: ['native/src/platform/linux/remvibe_terminal_linux.cpp'],
        includes: ['native/include'],
        language: Language.cpp,
        std: 'c++17',
        libraries: ['util'],
        linkModePreference: LinkModePreference.dynamic,
      );
      await linuxBuilder.run(input: input, output: output);
      return;
    }
    if (target.targetOS != OS.windows) return;
    if (target.targetArchitecture != Architecture.x64) {
      throw UnsupportedError(
        'remvibe_terminal native ConPTY currently supports Windows x64 only.',
      );
    }

    final builder = CBuilder.library(
      name: 'remvibe_terminal_windows',
      // Identical to the explicit @Native assetId in windows_conpty.dart.
      assetName: 'src/windows/windows_conpty.dart',
      sources: ['native/src/platform/windows/remvibe_terminal_windows.cpp'],
      includes: ['native/include'],
      language: Language.cpp,
      std: 'c++17',
      flags: ['/EHsc'],
      libraries: ['kernel32'],
      defines: {
        'UNICODE': null,
        '_UNICODE': null,
        'WIN32_LEAN_AND_MEAN': null,
        'NOMINMAX': null,
      },
      linkModePreference: LinkModePreference.dynamic,
    );
    await builder.run(input: input, output: output);
  });
}
