#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Compile the production snapshot models without the app-only localization helpers.
python3 - "$WORK/QuotaSnapshot.swift" <<'PY'
from pathlib import Path
import sys
source = Path('eul/Schema/QuotaSnapshot.swift').read_text()
source = source.split('enum QuotaCountdown')[0].replace('import Localize_Swift\n', '')
Path(sys.argv[1]).write_text(source)
PY
swiftc "$WORK/QuotaSnapshot.swift" eul/Utilities/AntigravityQuotaClient.swift tests/AntigravityQuotaTests.swift -o "$WORK/tests"
"$WORK/tests"
