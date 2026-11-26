#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  printf '此增補包需要 Python 3；請先安裝 Python 3 再重試。\n' >&2
  exit 1
fi
exec python3 "$ROOT/scripts/manage_unix.py" install
