#!/usr/bin/env python3
"""Inspect an IPA without extracting it. Python standard library only."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import struct
import zipfile


def verify(path, variant, build):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP CRC verification failed')
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP members')
        for name in names:
            parts = pathlib.PurePosixPath(name).parts
            if name.startswith('/') or '..' in parts or '\\' in name:
                raise ValueError('Unsafe ZIP path')
            if not name.startswith('Payload/'):
                raise ValueError('Unexpected file outside Payload')
        prefix = 'Payload/ChainProbe.app/'
        if any(name != 'Payload/' and not name.startswith(prefix) for name in names):
            raise ValueError('Unexpected additional app or payload')
        if any('_CodeSignature' in name.split('/') or name.endswith('.mobileprovision') for name in names):
            raise ValueError('Expected an unsigned payload without provisioning')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        expected = {
            'CFBundleIdentifier': 'com.dailyhabit.chainprobe',
            'CFBundleExecutable': 'ChainProbe',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': build,
            'ProbeVariant': variant,
            'MinimumOSVersion': '17.0',
        }
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f'{key}: expected {value!r}, got {info.get(key)!r}')
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('This is not an iPhoneOS device build')
        executable = archive.read(prefix + 'ChainProbe')
        # The iPhone-only target builds a thin 64-bit arm64 Mach-O executable.
        if len(executable) < 32:
            raise ValueError('Truncated Mach-O header')
        magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', executable)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or filetype != 2:
            raise ValueError('Expected a thin arm64 Mach-O executable')
        end = 32 + sizeofcmds
        if end > len(executable):
            raise ValueError('Truncated Mach-O load commands')
        offset = 32
        ios_platform = False
        for _ in range(ncmds):
            if offset + 8 > end:
                raise ValueError('Invalid load command count')
            cmd, size = struct.unpack_from('<II', executable, offset)
            if size < 8 or offset + size > end:
                raise ValueError('Invalid Mach-O load command')
            if cmd == 0x1D:  # LC_CODE_SIGNATURE
                raise ValueError('Mach-O contains a code signature')
            if cmd == 0x32:  # LC_BUILD_VERSION: distinguish arm64 simulator binaries.
                if size < 24:
                    raise ValueError('Truncated platform build command')
                platform, minos = struct.unpack_from('<II', executable, offset + 8)
                if platform != 2 or minos != 0x00110000:
                    raise ValueError('Expected an iOS device executable with minimum iOS 17.0')
                ios_platform = True
            offset += size
        if offset != end:
            raise ValueError('Inconsistent Mach-O load command size')
        if not ios_platform:
            raise ValueError('Missing iOS device platform command')
        return {
            'file': pathlib.Path(path).name,
            'sha256': hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest(),
            'variant': variant,
            'build': build,
            'bundleID': info['CFBundleIdentifier'],
            'minimumOS': info['MinimumOSVersion'],
            'architecture': 'arm64',
            'platform': 'iPhoneOS',
            'unsigned': True,
            'zipCRC': 'passed',
            'deviceInstallation': 'not tested',
        }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--variant', choices=['A', 'B'], required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--report')
    args = parser.parse_args()
    result = verify(args.ipa, args.variant, args.build)
    output = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.report:
        pathlib.Path(args.report).write_text(output, encoding='utf-8')
    print(output, end='')
