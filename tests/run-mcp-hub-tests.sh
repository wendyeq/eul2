#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MCP_HUB_TEST_DIR="$WORK"
# Production Hub source is copied verbatim, then same-file test accessors are
# appended. No production logic/visibility is rewritten. Dependencies cannot
# open sockets, launch processes, or resolve the user's Application Support.
python3 - "$WORK/McpHub.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(Path('eul/Utilities/MCP/McpHub.swift').read_text() + '\n' + Path('tests/McpHubTestAccess.swift').read_text())
PY
swiftc eul/Utilities/MCP/McpCatalog.swift "$WORK/McpHub.swift" \
  tests/McpHubStubs.swift tests/McpHubTests.swift -o "$WORK/tests"
"$WORK/tests"
