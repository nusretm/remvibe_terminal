#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
  echo "TERM-02A real PTY gate requires a Linux host." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ "$(git branch --show-current)" != "feature/term-02a-linux-pty" ]]; then
  echo "Expected feature/term-02a-linux-pty branch." >&2
  exit 1
fi

echo "=== TERM-02A: ROOT DART DEPENDENCIES ==="
dart pub get
echo "=== TERM-02A: ROOT DART ANALYZER ==="
dart analyze --fatal-infos
echo "=== TERM-02A: ROOT DART TESTS ==="
dart test
echo "=== TERM-02A: REAL LINUX BASH/PTTY LIVE SMOKE ==="
dart run tool/term_02a_linux_live_smoke.dart
echo "TERM-02A LINUX DART/NATIVE CHECK PASS (GUI still separate)"
