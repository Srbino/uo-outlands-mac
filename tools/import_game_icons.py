#!/usr/bin/env python3
"""Regenerate vendored SVGs from the pinned react-icons/gi package. No JS is executed.
Normal builds are offline and use the committed assets.
"""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools/game-icons.json'
DEST = ROOT / 'Sources/OutlandsInstaller/Resources/GameIcons'

def element(node):
    # SVG keeps viewBox camel-cased; React's other camelCase props map to kebab-case attributes.
    attr = {key if key == 'viewBox' else re.sub(r'[A-Z]', lambda m: '-' + m[0].lower(), key): str(value)
            for key, value in node.get('attr', {}).items()}
    result = ET.Element(node['tag'], attr)
    for child in node.get('child', []):
        result.append(element(child))
    return result

def main():
    manifest = json.loads(MANIFEST.read_text())
    with urllib.request.urlopen(manifest['url'], timeout=60) as response:
        data = response.read(30 * 1024 * 1024 + 1)
    algorithm, expected = manifest['integrity'].split('-', 1)
    if algorithm != 'sha512' or base64.b64encode(hashlib.sha512(data).digest()).decode() != expected:
        raise SystemExit('React Icons package integrity mismatch')
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as package:
        source = package.extractfile('package/gi/index.mjs').read().decode()
        (DEST / 'REACT-ICONS-LICENSE.txt').write_bytes(package.extractfile('package/LICENSE').read())
    for item in manifest['assets']:
        match = re.search(r'export function ' + re.escape(item['export']) + r'\s*\(props\)\s*\{\s*return GenIcon\(', source)
        if not match:
            raise SystemExit('Missing React Icons export: ' + item['export'])
        node, _ = json.JSONDecoder().raw_decode(source[match.end():])
        svg = element(node)
        svg.attrib.update({'xmlns': 'http://www.w3.org/2000/svg', 'width': '512', 'height': '512', 'fill': '#ffffff'})
        text = ET.tostring(svg, encoding='unicode').replace('currentColor', '#ffffff') + '\n'
        (DEST / (item['icon'] + '.svg')).write_text(text)
        item['sha256'] = hashlib.sha256(text.encode()).hexdigest()
    glyph = ET.parse(DEST / 'sword-in-stone.svg').getroot()
    body = ''.join(ET.tostring(child, encoding='unicode') for child in glyph).replace('#ffffff', '#2dd4bf')
    # Strip ElementTree's redundant namespace prefix inside the standalone parent.
    body = body.replace('ns0:', '').replace(' xmlns:ns0="http://www.w3.org/2000/svg"', '')
    (DEST / 'AppEmblem.svg').write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<defs><linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#134e4a"/><stop offset="100%" stop-color="#09090b"/></linearGradient></defs>
<rect x="4" y="4" width="504" height="504" rx="140" fill="url(#tile)" stroke="#3f3f46" stroke-width="8"/>
<g transform="translate(107.52 107.52) scale(0.58)" fill="#2dd4bf">''' + body + '</g></svg>\n')
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f"Imported {len(manifest['assets'])} verified react-icons/gi exports.")

if __name__ == '__main__':
    main()
