"""Packaging tests use tiny synthetic headers, NOT a working iOS executable."""
import importlib.util
from pathlib import Path
import os
import plistlib
import struct
import tempfile
import unittest
import zipfile
spec = importlib.util.spec_from_file_location("package_ipa", Path(__file__).resolve().parents[1] / "package_ipa.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.app = self.root / "Svitanok.app"; self.app.mkdir()
        self.output = self.root / "dist/Svitanok-unsigned.ipa"
        self.info = {"CFBundleExecutable": "Svitanok", "CFBundleIdentifier": "ua.test.svitanok",
                     "CFBundleSupportedPlatforms": ["iPhoneOS"], "MinimumOSVersion": "26.0",
                     "NSAlarmKitUsageDescription": "Test description"}
        self.write_info()
        self.binary = self.app / "Svitanok"
        self.binary.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + b'fixture-not-real-app')
        self.binary.chmod(0o755)
    def tearDown(self): self.tmp.cleanup()
    def write_info(self):
        with (self.app / "Info.plist").open("wb") as f: plistlib.dump(self.info, f)
    def fails(self):
        with self.assertRaises((ValueError, FileNotFoundError)): m.package(self.app, self.output)
        self.assertFalse(self.output.exists())
    def test_structure_and_digest(self):
        digest = m.package(self.app, self.output)
        with zipfile.ZipFile(self.output) as z:
            self.assertIsNone(z.testzip()); self.assertIn("Payload/Svitanok.app/Info.plist", z.namelist())
        self.assertIn(digest, (self.output.parent / "SHA256SUMS.txt").read_text())
    def test_preserves_permissions(self):
        m.package(self.app, self.output)
        with zipfile.ZipFile(self.output) as z: self.assertTrue((z.getinfo("Payload/Svitanok.app/Svitanok").external_attr >> 16) & 0o100)
    def test_rejects_source_as_executable(self): self.binary.write_text('print("hello")'); self.fails()
    def test_rejects_wrong_architecture(self): self.binary.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x01000007)); self.fails()
    def test_rejects_empty_binary(self): self.binary.write_bytes(b''); self.fails()
    def test_rejects_missing_binary(self): self.binary.unlink(); self.fails()
    def test_rejects_missing_exec_bit(self): self.binary.chmod(0o644); self.fails()
    def test_rejects_simulator(self): self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]; self.write_info(); self.fails()
    def test_rejects_missing_platform(self): del self.info["CFBundleSupportedPlatforms"]; self.write_info(); self.fails()
    def test_rejects_old_os(self): self.info["MinimumOSVersion"] = "18.0"; self.write_info(); self.fails()
    def test_rejects_missing_minimum(self): del self.info["MinimumOSVersion"]; self.write_info(); self.fails()
    def test_rejects_bad_minimum(self): self.info["MinimumOSVersion"] = "bad"; self.write_info(); self.fails()
    def test_rejects_nan_minimum(self): self.info["MinimumOSVersion"] = "NaN"; self.write_info(); self.fails()
    def test_rejects_infinite_minimum(self): self.info["MinimumOSVersion"] = "inf"; self.write_info(); self.fails()
    def test_rejects_missing_alarm_description(self): del self.info["NSAlarmKitUsageDescription"]; self.write_info(); self.fails()
    def test_rejects_empty_alarm_description(self): self.info["NSAlarmKitUsageDescription"] = " "; self.write_info(); self.fails()
    def test_rejects_missing_bundle_id(self): del self.info["CFBundleIdentifier"]; self.write_info(); self.fails()
    def test_rejects_path_traversal(self): self.info["CFBundleExecutable"] = "../other"; self.write_info(); self.fails()
    def test_rejects_symlink(self): (self.app / "escape").symlink_to(self.binary); self.fails()
    def test_resources_included(self):
        (self.app / "dawn.wav").write_bytes(b'fixture-audio')
        m.package(self.app, self.output)
        with zipfile.ZipFile(self.output) as z: self.assertIn("Payload/Svitanok.app/dawn.wav", z.namelist())

if __name__ == "__main__": unittest.main(verbosity=2)
