#!/usr/bin/env python3
"""Build a standalone arm64 .app and distribution ZIP. Python is for maintainers only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--identity', default='-', help='Developer ID Application identity; default is local ad-hoc signing')
    parser.add_argument('--notary-profile', help='Existing notarytool keychain profile')
    parser.add_argument('--notary-keychain', help='Optional keychain containing the notarytool profile')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        raise SystemExit('Build this macOS application on macOS.')
    if args.notary_profile and args.identity == '-':
        raise SystemExit('Notarization requires a Developer ID identity.')
    version = re.search(r'let version = "([^"]+)"', (ROOT / 'Sources/OutlandsCore/Support.swift').read_text()).group(1)
    run('swift', 'build', '-c', 'release', '--arch', 'arm64', '-Xswiftc', '-warnings-as-errors')
    bindir = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--arch', 'arm64', '--show-bin-path'], cwd=ROOT, text=True).strip())
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    app = dist / 'Outlands Installer.app'
    if app.exists():
        shutil.rmtree(app)
    macos = app / 'Contents/MacOS'
    resources = app / 'Contents/Resources'
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(bindir / 'OutlandsInstaller', macos)
    shutil.copy2(ROOT / 'Sources/OutlandsCore/recipe.json', resources / 'recipe.json')
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE.txt')
    shutil.copytree(ROOT / 'Sources/OutlandsInstaller/Resources/GameIcons', resources / 'GameIcons')
    info = {
        'CFBundleName': 'Outlands Installer', 'CFBundleDisplayName': 'Outlands Installer',
        'CFBundleExecutable': 'OutlandsInstaller', 'CFBundleIdentifier': 'com.srbino.outlands.installer',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': version,
        'LSMinimumSystemVersion': '14.6', 'NSHighResolutionCapable': True,
        'NSPrincipalClass': 'NSApplication', 'CFBundleIconFile': 'AppIcon',
        'LSApplicationCategoryType': 'public.app-category.utilities',
    }
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('swift', str(ROOT / 'tools/icon.swift'), str(resources / 'AppIcon.iconset'), str(resources / 'GameIcons/AppEmblem.svg'))
    run('/usr/bin/iconutil', '-c', 'icns', str(resources / 'AppIcon.iconset'), '-o', str(resources / 'AppIcon.icns'))
    shutil.rmtree(resources / 'AppIcon.iconset')
    signargs = ['--force', '--sign', args.identity]
    if args.identity != '-':
        signargs += ['--options', 'runtime', '--timestamp']
    run('/usr/bin/codesign', *signargs, str(app))
    run('/usr/bin/codesign', '--verify', '--strict', '--verbose=2', str(app))
    run(str(macos / 'OutlandsInstaller'), '--self-check')
    archive = dist / f'Outlands-Installer-{version}-arm64.zip'
    archive.unlink(missing_ok=True)
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
    if args.notary_profile:
        notaryargs = ['--keychain', args.notary_keychain] if args.notary_keychain else []
        run('xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', args.notary_profile, *notaryargs, '--wait', '--timeout', '30m')
        run('xcrun', 'stapler', 'staple', str(app))
        run('xcrun', 'stapler', 'validate', str(app))
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose', str(app))
        archive.unlink()
        run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
    digest = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() if sys.version_info >= (3, 11) else hashlib.sha256(archive.read_bytes()).hexdigest()
    (dist / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')
    (dist / 'build-info.json').write_text(json.dumps({'version': version, 'architecture': 'arm64', 'notarized': bool(args.notary_profile), 'signing': 'ad-hoc' if args.identity == '-' else 'Developer ID'}, indent=2) + '\n')
    print(f'Built {archive}\n' + ('Notarized distribution.' if args.notary_profile else 'Local/development build. Not notarized; see docs/RELEASING.md.'))

if __name__ == '__main__':
    main()
