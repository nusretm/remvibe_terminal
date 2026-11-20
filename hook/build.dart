// Dart Native Assets: build the same C++ ConPTY source used by CMake.
// The Client's 'dart build cli' automatically bundles the resulting DLL.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final target = input.config.code;
    // The Dart package can still be analyzed and tested on other hosts.
    // No non-Windows PTY backend is implemented yet.
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
