#!/usr/bin/env python3
"""CI-only Developer ID signing setup. Secrets are read from the environment, never printed."""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['APPLE_CERTIFICATE_P12_BASE64', 'APPLE_CERTIFICATE_PASSWORD', 'APPLE_SIGNING_IDENTITY',
            'APPLE_ID', 'APPLE_APP_PASSWORD', 'APPLE_TEAM_ID']

def run(*args):
    subprocess.run(args, check=True, cwd=ROOT)

def main():
    missing = [key for key in REQUIRED if not os.environ.get(key)]
    if missing:
        raise SystemExit('Release signing is not configured: ' + ', '.join(missing))
    if os.environ.get('CI') != 'true':
        raise SystemExit('This keychain setup is intended for a disposable CI runner. Use tools/build.py locally.')
    with tempfile.TemporaryDirectory(prefix='outlands-signing-') as temp:
        folder = Path(temp)
        certificate = folder / 'certificate.p12'
        certificate.write_bytes(base64.b64decode(os.environ['APPLE_CERTIFICATE_P12_BASE64'], validate=True))
        certificate.chmod(0o600)
        keychain = str(folder / 'release.keychain-db')
        password = secrets.token_urlsafe(32)
        try:
            run('security', 'create-keychain', '-p', password, keychain)
            run('security', 'set-keychain-settings', '-lut', '21600', keychain)
            run('security', 'unlock-keychain', '-p', password, keychain)
            run('security', 'import', str(certificate), '-P', os.environ['APPLE_CERTIFICATE_PASSWORD'], '-k', keychain, '-T', '/usr/bin/codesign')
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
            run('security', 'list-keychains', '-d', 'user', '-s', keychain)
            run('xcrun', 'notarytool', 'store-credentials', 'outlands-release', '--apple-id', os.environ['APPLE_ID'],
                '--password', os.environ['APPLE_APP_PASSWORD'], '--team-id', os.environ['APPLE_TEAM_ID'], '--keychain', keychain)
            run('python3', 'tools/build.py', '--identity', os.environ['APPLE_SIGNING_IDENTITY'], '--notary-profile', 'outlands-release', '--notary-keychain', keychain)
        finally:
            subprocess.run(['security', 'delete-keychain', keychain], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == '__main__':
    main()
