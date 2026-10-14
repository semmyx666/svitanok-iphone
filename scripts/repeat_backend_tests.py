"""20 repetitions of backend and packaging tests; not iOS device tests."""
import datetime
import json
import re
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
    tests_count = 0
    for suite in ["server/tests", "scripts/tests"]:
        p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", suite], cwd=root, capture_output=True, text=True)
        outputs.append(p.stderr)
        match = re.search(r"Ran (\d+) tests?", p.stderr)
        if match: tests_count += int(match.group(1))
        returncode = max(returncode, p.returncode)
    results.append({"run": i + 1, "returncode": returncode, "elapsedSeconds": round(time.monotonic() - start, 3), "testExecutions": tests_count})
    if returncode:
        print("\n".join(outputs), file=sys.stderr)
        break
report = {"timestampUTC": datetime.datetime.now(datetime.UTC).isoformat(), "suite": "Python backend + IPA packaging, synthetic fixtures, no iPhone, no actual iOS build or live API", "testsPerRun": results[0]["testExecutions"] if results else 0, "runs": results, "allPassed": len(results) == 20 and all(r["returncode"] == 0 for r in results)}
(root / "docs/backend-repeat-summary.json").write_text(json.dumps(report, indent=2) + "\n")
print(f'{len(results)} runs, {sum(r["testExecutions"] for r in results)} test executions; allPassed={report["allPassed"]}')
sys.exit(0 if report["allPassed"] else 1)
