"""20 repetitions of backend and packaging tests; not iOS device tests."""
import datetime
import json
from pathlib import Path
import subprocess
import sys
import time
root = Path(__file__).resolve().parents[1]
results = []
for i in range(20):
    start = time.monotonic()
    outputs = []
    returncode = 0
    for suite in ["server/tests", "scripts/tests"]:
        p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", suite], cwd=root, capture_output=True, text=True)
        outputs.append(p.stderr)
        returncode = max(returncode, p.returncode)
    results.append({"run": i + 1, "returncode": returncode, "elapsedSeconds": round(time.monotonic() - start, 3)})
    if returncode:
        print("\n".join(outputs), file=sys.stderr)
        break
report = {"timestampUTC": datetime.datetime.now(datetime.UTC).isoformat(), "suite": "Python backend + IPA packaging, synthetic fixtures, no iPhone, no actual iOS build or live API", "testsPerRun": 84, "runs": results, "allPassed": len(results) == 20 and all(r["returncode"] == 0 for r in results)}
(root / "docs/backend-repeat-summary.json").write_text(json.dumps(report, indent=2) + "\n")
print(f'{len(results)} runs, {len(results) * 84} test executions; allPassed={report["allPassed"]}')
sys.exit(0 if report["allPassed"] else 1)
