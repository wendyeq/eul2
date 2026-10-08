#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Compile the actual sampler, replacing only app localization/logging helpers.
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
source = Path('eul/Utilities/AppleSiliconIOReport.swift').read_text()
(work / 'AppleSiliconIOReport.swift').write_text(source.replace('import Localize_Swift\n', ''))
(work / 'IOHelper.swift').write_text('import IOKit\n' + Path('eul/Utilities/IOHelper.swift').read_text())
PY
swiftc -module-cache-path "$WORK/cache" \
    "$WORK/AppleSiliconIOReport.swift" "$WORK/IOHelper.swift" \
    tests/AppleSiliconIOReportMemoryTests.swift -o "$WORK/tests"
"$WORK/tests"
