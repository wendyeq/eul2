#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
grep -q "QuotaCountdown.displayTick" eul/Views/Menu/QuotaMenuBlockView.swift
grep -q "context.date" eul/Views/Menu/QuotaMenuBlockView.swift
WORK=$(mktemp -d)
FAKE=$(mktemp -d)
trap 'rm -rf "$WORK" "$FAKE"' EXIT
python3 - "$WORK/QuotaSnapshot.swift" <<'PY'
from pathlib import Path
import sys
source = Path("eul/Schema/QuotaSnapshot.swift").read_text().replace("import Localize_Swift\n", "")
stub = '''
extension String {
    func localized() -> String {
        self == "quota.reset_in" ? "剩 %@" : self
    }
}
'''
Path(sys.argv[1]).write_text(stub + source)
PY
cat > "$FAKE/codex" <<'PY'
#!/usr/bin/env python3
import os
import sys
import time
mode = os.environ.get("CODEX_FAKE_MODE", "silent")
if mode == "burst":
    sys.stdout.write('{"id":1,"result":{}}\n')
    sys.stdout.write('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1700000000}}}}\n')
    sys.stdout.flush()
time.sleep(30)
PY
chmod +x "$FAKE/codex"
printf '%s\n' '{"tokens":{"access_token":"fixture"}}' > "$FAKE/auth.json"
swiftc "$WORK/QuotaSnapshot.swift" eul/Utilities/CodexQuotaClient.swift tests/CodexQuotaRefreshTests.swift -o "$WORK/tests"
PATH="$FAKE:/usr/bin:/bin" CODEX_HOME="$FAKE" "$WORK/tests"
