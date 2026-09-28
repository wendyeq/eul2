#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Compile the production geometry helper without app-only SwiftUI dependencies.
python3 - "$WORK/OrderListDragLayout.swift" <<'PY'
from pathlib import Path
import sys
source = Path('eul/Views/Preference/PreferenceMenuViewView.swift').read_text()
start = source.index('enum OrderListDragLayout {')
end = source.index('private struct OrderListFramePreferenceKey:', start)
Path(sys.argv[1]).write_text('import Foundation\n' + source[start:end])
PY
swiftc "$WORK/OrderListDragLayout.swift" tests/OrderListDragLayoutTests.swift -o "$WORK/tests"
"$WORK/tests"
