#!/usr/bin/env bash
# scripts/find_python.sh
#
# Source this file to get a $PYTHON variable pointing to a working Python 3.
# Usage:  source "$(dirname "$0")/../../scripts/find_python.sh"
#         "$PYTHON" my_script.py
#
# Resolution order:
#   1. python3  — standard on macOS/Linux
#   2. python   — Windows (python.org installer), conda, some Linux
#   3. py       — Windows Python Launcher (py.exe, installed to C:\Windows\)
#
# Each candidate is verified to be Python 3 before being accepted.
# If none found, PYTHON is set to "python3" so the caller gets a clear
# "command not found" error rather than silently running Python 2.

_find_python3() {
  local cmd
  for cmd in python3 python py; do
    if command -v "$cmd" &>/dev/null 2>&1; then
      if "$cmd" -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
        # On Windows, bare `python` may resolve to the Microsoft Store stub
        # (which prints "Python was not found" and exits non-zero on -c). The
        # version check above catches that. `py` is the canonical Windows path.
        echo "$cmd"
        return 0
      fi
    fi
  done
  # No Python 3 found — emit a loud message to stderr so failed hooks have
  # a discoverable cause rather than silently exit-127ing.
  echo "[find_python] ERROR: no Python 3 interpreter found on PATH (tried: python3, python, py)" >&2
  echo "python3"
}

PYTHON=$(_find_python3)
