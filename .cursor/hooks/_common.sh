#!/usr/bin/env bash
# .cursor/hooks/_common.sh
#
# Cursor adapter bootstrap (Phase C). Delegates to shared scripts/cek_runtime.sh
# so Cursor / Codex / Grok all set CLAUDE_PROJECT_DIR the same way.

export CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="cursor"
