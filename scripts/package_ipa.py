"""Package an already compiled ARM64 iPhone .app. Never builds a fake IPA from source."""
from pathlib import Path
import argparse
import hashlib
import os
import re
import plistlib
import stat
import struct
import zipfile


def check_arm64(binary: Path):
    header = binary.read_bytes()[:8]
    if len(header) < 8:
        raise ValueError("Executable is missing a Mach-O header")
    magic, cpu = struct.unpack("<II", header)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError("Expected a thin ARM64 Mach-O executable, not a simulator or source file")


def package(app: Path, output: Path):
    app = app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Input must be a compiled .app directory")
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable or executable in [".", ".."]:
        raise ValueError("Invalid executable name")
    if not info.get("CFBundleIdentifier"):
        raise ValueError("Bundle identifier is missing")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Not a device iPhoneOS build")
    minimum = info.get("MinimumOSVersion")
    if not isinstance(minimum, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum):
        raise ValueError("MinimumOSVersion is missing or malformed")
    if int(minimum.split(".")[0]) < 26:
        raise ValueError("This AlarmKit project requires iOS 26+")
    description = info.get("NSAlarmKitUsageDescription")
    if not isinstance(description, str) or not description.strip():
        raise ValueError("AlarmKit usage description is missing")
    binary = app / executable
    if not binary.is_file():
        raise ValueError("Compiled executable is missing")
    check_arm64(binary)
    if not os.access(binary, os.X_OK):
        raise ValueError("Executable bit is missing")
    files = sorted(p for p in app.rglob("*") if p.is_file() or p.is_symlink())
    # Device SwiftUI apps normally have no symlink resources. Fail explicitly rather than
    # accidentally dereferencing something outside the bundle or corrupting a framework.
    if any(p.is_symlink() for p in files):
        raise ValueError("Symlink in app bundle: packaging needs explicit review")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".ipa.partial")
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, "Payload/" + app.name + "/" + str(path.relative_to(app)))
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("ZIP integrity failed")
            item = archive.getinfo(f"Payload/{app.name}/{executable}")
            if not (item.external_attr >> 16) & stat.S_IXUSR:
                raise ValueError("ZIP lost executable permissions")
        temporary.replace(output)
    finally:
        if temporary.exists(): temporary.unlink()
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (output.parent / "SHA256SUMS.txt").write_text(f"{digest}  {output.name}\n")
    return digest

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path); parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print("Packaged unsigned IPA:", package(args.app, args.output))
