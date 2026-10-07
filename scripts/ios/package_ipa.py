#!/usr/bin/env python3
"""Validate a release device build and wrap it as an unsigned, resignable IPA."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    app = Path('build/ios/iphoneos/Runner.app').resolve()
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.lxyveex.zaix':
        raise RuntimeError('Unexpected bundle identifier')
    if tuple(map(int, info['MinimumOSVersion'].split('.'))) > (16, 7):
        raise RuntimeError('The build no longer supports iPadOS 16.7')
    if 2 not in info.get('UIDeviceFamily', []):
        raise RuntimeError('iPad support is missing')

    binaries = [app / info['CFBundleExecutable'],
                app / 'Frameworks/App.framework/App',
                app / 'Frameworks/Flutter.framework/Flutter']
    binary_details = []
    for binary in binaries:
        architectures = command('xcrun', 'lipo', '-archs', str(binary))
        platform = command('xcrun', 'vtool', '-show-build', str(binary))
        if 'arm64' not in architectures.split() or 'IOSSIMULATOR' in platform:
            raise RuntimeError(f'Not an arm64 device binary: {binary}')
        binary_details.append({'path': str(binary.relative_to(app)),
                               'architectures': architectures,
                               'build_version': platform})

    out = Path('dist/ios').resolve()
    out.mkdir(parents=True, exist_ok=True)
    ipa = out / f"ZAI-X-iOS-{info['CFBundleShortVersionString']}-unsigned.ipa"
    with tempfile.TemporaryDirectory(prefix='zaix-ipa-') as temp:
        payload = Path(temp) / 'Payload'
        payload.mkdir()
        shutil.copytree(app, payload / 'Runner.app', symlinks=True)
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                        str(payload), str(ipa)], check=True)
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('IPA ZIP integrity check failed')
        if 'Payload/Runner.app/Info.plist' not in archive.namelist():
            raise RuntimeError('IPA payload is missing')
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (out / 'SHA256SUMS.txt').write_text(f'{digest}  {ipa.name}\n')
    report = {'source_commit': command('git', 'rev-parse', 'HEAD'),
              'repository': os.environ.get('GITHUB_REPOSITORY', ''),
              'version': info['CFBundleShortVersionString'],
              'build': info['CFBundleVersion'],
              'bundle_identifier': info['CFBundleIdentifier'],
              'minimum_ios': info['MinimumOSVersion'],
              'device_families': info['UIDeviceFamily'],
              'signed': False, 'sha256': digest, 'binaries': binary_details}
    (out / 'build-info.json').write_text(json.dumps(report, indent=2))
    shutil.copyfile('docs/IOS.md', out / 'INSTALL.md')
    print(f'Packaged {ipa.name} ({ipa.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
