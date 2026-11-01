"""Synthetic malformed payload tests; these are NOT installable App artifacts."""
import importlib.util
import pathlib
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'verify_ipa', pathlib.Path(__file__).resolve().parents[1] / 'scripts' / 'verify-ipa.py'
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PayloadValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='ChainProbeValidator-')
        self.addCleanup(self.temporary.cleanup)
        self.path = pathlib.Path(self.temporary.name) / 'synthetic.ipa'

    def payload(self, variant='A', platform=2, cpu=0x0100000C, signed=False, extra=None):
        info = {
            'CFBundleIdentifier': 'com.dailyhabit.chainprobe',
            'CFBundleExecutable': 'ChainProbe', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1.1.1', 'ProbeVariant': variant,
            'MinimumOSVersion': '17.0', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
        }
        commands = struct.pack('<6I', 0x32, 24, platform, 0x00110000, 0x001A0200, 0)
        if signed:
            commands += struct.pack('<4I', 0x1D, 16, 0, 0)
        header = struct.pack('<8I', 0xFEEDFACF, cpu, 0, 2, 2 if signed else 1, len(commands), 0, 0)
        with zipfile.ZipFile(self.path, 'w') as archive:
            archive.writestr('Payload/ChainProbe.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/ChainProbe.app/ChainProbe', header + commands)
            if extra:
                archive.writestr(extra, b'test')

    def check(self):
        return module.verify(self.path, 'A', '1.1.1')

    def test_structurally_valid_fixture_reports_device_test_not_run(self):
        self.payload()
        result = self.check()
        self.assertTrue(result['unsigned'])
        self.assertEqual(result['deviceInstallation'], 'not tested')
        self.assertEqual(len(result['sha256']), 64)

    def test_rejects_wrong_build_variant(self):
        self.payload(variant='B')
        with self.assertRaisesRegex(ValueError, 'ProbeVariant'):
            self.check()

    def test_rejects_arm64_simulator_despite_matching_plist(self):
        self.payload(platform=7)
        with self.assertRaisesRegex(ValueError, 'iOS device'):
            self.check()

    def test_rejects_wrong_architecture(self):
        self.payload(cpu=0x01000007)
        with self.assertRaisesRegex(ValueError, 'arm64'):
            self.check()

    def test_rejects_embedded_signature(self):
        self.payload(signed=True)
        with self.assertRaisesRegex(ValueError, 'signature'):
            self.check()

    def test_rejects_provisioning_profile(self):
        self.payload(extra='Payload/ChainProbe.app/embedded.mobileprovision')
        with self.assertRaisesRegex(ValueError, 'provisioning'):
            self.check()

    def test_rejects_path_traversal(self):
        self.payload(extra='Payload/../escape')
        with self.assertRaisesRegex(ValueError, 'Unsafe ZIP path'):
            self.check()

    def test_rejects_truncated_archive(self):
        self.path.write_bytes(b'PK\x03\x04broken')
        with self.assertRaises(zipfile.BadZipFile):
            self.check()


if __name__ == '__main__':
    unittest.main()
