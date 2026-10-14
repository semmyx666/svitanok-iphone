"""Structural audit, deliberately NOT an iOS compiler or hardware test."""
import json
import plistlib
from pathlib import Path
import subprocess
import wave
import yaml
root = Path(__file__).resolve().parents[1]
config = yaml.safe_load((root / "project.yml").read_text())
assert config["options"]["deploymentTarget"]["iOS"] == "26.0"
assert config["targets"]["Svitanok"]["settings"]["base"]["GENERATE_INFOPLIST_FILE"] is False
with (root / "ios/Svitanok/Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSAlarmKitUsageDescription"].strip()
assert config["schemes"]["Svitanok"]["test"]["targets"] == ["SvitanokTests", "SvitanokUITests"]
for path in root.glob("scripts/*.sh"):
    subprocess.run(["bash", "-n", str(path)], check=True)
for path in root.rglob("*.json"):
    json.loads(path.read_text())
for path in (root / "ios/Svitanok/Resources").glob("*.wav"):
    with wave.open(str(path)) as f:
        assert f.getnchannels() == 1 and f.getsampwidth() == 2
        assert 0 < f.getnframes() / f.getframerate() < 30
assert not (root / "server/.env").exists()
assert len(list((root / "ios/Svitanok").glob("*.swift"))) == 5
assert (root / "ios/Svitanok/Assets.xcassets/AppIcon.appiconset/AppIcon.png").exists()
workflow = yaml.safe_load((root / ".github/workflows/build-ios.yml").read_text())
assert workflow["on"] == {"workflow_dispatch": None}
assert workflow["jobs"]["build"]["runs-on"] == "macos-26"
assert workflow["permissions"] == {"contents": "read"}
assert "secrets." not in (root / ".github/workflows/build-ios.yml").read_text()
assert (root / "START_HERE_RU.md").exists()
assert (root / "docs/WINDOWS_FEDORA_FREE_RU.md").exists()
assert (root / "docs/FREE_DATA_PROXY_RU.md").exists()
print("Structural audit passed: YAML, JSON, Bash syntax, sound resources, icon and no real .env. Swift compilation NOT tested.")

locations = json.loads((root / "ios/Svitanok/Resources/locations.json").read_text())
assert len(locations) == len({x["id"] for x in locations}) == 1622
assert locations == json.loads((root / "server/locations.json").read_text())
print("Location catalog and UI-test target verified.")
