#!/usr/bin/env python3
"""Check official upstream versions; optionally write a reviewable recipe update.
Never execute downloaded code. No game files or private system data are accessed.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.request
import urllib.error
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'Sources/OutlandsCore/recipe.json'

def api(path):
    headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'OutlandsInstaller-upstream-check'}
    token = os.environ.get('GH_TOKEN')
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request('https://api.github.com/' + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def latest_asset(repo, pattern):
    # Upstream keeps all versions on a single release. Parse JSON, then numeric versions.
    candidates = []
    for release in api(f'repos/{repo}/releases?per_page=100'):
        if release['draft'] or release['prerelease']:
            continue
        for asset in release['assets']:
            if re.fullmatch(pattern, asset['name']):
                candidates.append(asset)
    if not candidates:
        raise RuntimeError(f'No supported release asset found in {repo}')
    item = max(candidates, key=lambda a: tuple(map(int, re.findall(r'\d+', a['name']))))
    digest = item.get('digest') or ''
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise RuntimeError(f'No SHA-256 digest for {item["name"]}; manual review required')
    url = item['browser_download_url']
    if not url.startswith(f'https://github.com/{repo}/releases/download/'):
        raise RuntimeError('Unexpected upstream URL')
    return {'name': item['name'], 'url': url, 'sha256': digest[7:], 'size': item['size']}

def latest_winetricks():
    commit = api('repos/Sikarugir-App/winetricks/commits/sikarugir')['sha']
    if not re.fullmatch(r'[a-f0-9]{40}', commit):
        raise RuntimeError('Invalid upstream commit')
    url = f'https://github.com/Sikarugir-App/winetricks/archive/{commit}.tar.gz'
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read(10 * 1024 * 1024 + 1)
    if len(data) > 10 * 1024 * 1024:
        raise RuntimeError('Unexpectedly large Winetricks source archive')
    return {'name': f'winetricks-{commit}.tar.gz', 'url': url, 'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    old = json.loads(MANIFEST.read_text())
    new = dict(old)
    new['engine'] = latest_asset('Sikarugir-App/Engines', r'WS12WineSikarugir\d+\.\d+(?:_\d+)?\.tar\.xz')
    new['template'] = latest_asset('Sikarugir-App/Template', r'Template-\d+\.\d+(?:\.\d+)?\.tar\.xz')
    new['winetricks'] = latest_winetricks()
    changes = [key for key in ('engine', 'template', 'winetricks') if new[key] != old[key]]
    if not changes:
        print('Pinned components match the current upstream versions and digests.')
        return
    for key in changes:
        print(f'{key}: {old[key]["name"]} -> {new[key]["name"]}')
        if old[key]['name'] == new[key]['name']:
            print('WARNING: Existing asset content changed; manual integrity review required.')
    if args.write:
        new['revision'] += 1
        new['verifiedAt'] = datetime.date.today().isoformat()
        MANIFEST.write_text(json.dumps(new, indent=2) + '\n')
        print('Manifest updated for review. This does not certify game compatibility.')

if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        message = 'GitHub API rate limit or access denied; retry later or set GH_TOKEN.' if error.code in (403, 429) else f'Upstream HTTP error {error.code}; no unverified recipe was accepted.'
        print(message, file=sys.stderr)
        sys.exit(1)
    except (urllib.error.URLError, TimeoutError, ValueError, RuntimeError) as error:
        print(f'Upstream check failed: {error}', file=sys.stderr)
        sys.exit(1)
