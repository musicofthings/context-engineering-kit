#!/usr/bin/env bash
# scripts/find_jq.sh
#
# Source this to ensure `jq` is callable. On WSL, the Windows winget package
# installs jq.exe but does not put it on the Linux PATH — we detect that.
#
# Sets: JQ (path/command). Defines a shell function jq() only when the
# system has no `jq` on PATH but we found a usable binary.

_find_jq_bin() {
  local c cand
  for c in jq jq.exe; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  # WSL → Windows WinGet package layout
  if [ -d /mnt/c/Users ]; then
    # Prefer the current Windows user if we can map it
    for cand in \
      /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe \
      /mnt/c/ProgramData/chocolatey/bin/jq.exe \
      /mnt/c/tools/jq/jq.exe
    do
      if [ -f "$cand" ] && [ -x "$cand" ] || [ -f "$cand" ]; then
        echo "$cand"
        return 0
      fi
    done
  fi
  # Git-Bash style paths when running under MSYS
  for cand in \
    /usr/bin/jq \
    /mingw64/bin/jq.exe \
    "$LOCALAPPDATA/Microsoft/WinGet/Packages"/jqlang.jq_*/jq.exe
  do
    # shellcheck disable=SC2086
    for f in $cand; do
      if [ -f "$f" ]; then
        echo "$f"
        return 0
      fi
    done
  done
  return 1
}

JQ="${JQ:-}"
if [ -z "$JQ" ]; then
  JQ=$(_find_jq_bin) || JQ=""
fi

if [ -n "$JQ" ]; then
  # Always wrap so jq.exe CR characters cannot poison bash $(( )) / test(1).
  # Preserve exit status of the real binary.
  _CEK_JQ_BIN="$JQ"
  jq() {
    local ec
    "$_CEK_JQ_BIN" "$@" | tr -d '\r'
    ec=${PIPESTATUS[0]}
    return "$ec"
  }
  export _CEK_JQ_BIN
  export -f jq 2>/dev/null || true
  export JQ
else
  # Loud once — almost every hook silently degrades without jq
  if [ -z "${CEK_JQ_WARNED:-}" ]; then
    echo "[find_jq] ERROR: jq not found on PATH (tried: jq, jq.exe, WinGet/Chocolatey locations)." >&2
    echo "[find_jq] Install: https://jqlang.github.io/jq/  or  winget install jqlang.jq" >&2
    export CEK_JQ_WARNED=1
  fi
fi
