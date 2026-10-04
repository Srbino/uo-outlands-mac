#!/usr/bin/env python3
"""Bounded checksum memory regression; optional read-only QA archive verification."""
import argparse
import json
import os
import platform
import shutil
from pathlib import Path
import subprocess
import tempfile
import resource_guard

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--qa-root', type=Path, required=True)
    parser.add_argument('--backup', type=Path, help='Optional existing disposable QA backup to verify')
    args = parser.parse_args()
    qa = args.qa_root.resolve()
    if '/.qa/' not in str(qa):
        raise SystemExit('Choose a directory beneath .qa, never a production folder.')
    ci = os.environ.get('GITHUB_ACTIONS') == 'true'
    if not ci and not str(qa).startswith('/Volumes/'):
        raise SystemExit('Local resource QA must be on an external volume under /Volumes.')
    qa.mkdir(parents=True, exist_ok=True)
    if not ci and qa.stat().st_dev == Path.home().stat().st_dev:
        raise SystemExit('The QA root is on the home volume; select an external disk.')
    bindir = Path(subprocess.check_output(
        ['swift', 'build', '--show-bin-path'], cwd=ROOT, text=True).strip())
    with tempfile.TemporaryDirectory(prefix='bounded-memory-', dir=qa) as directory:
        work = Path(directory)
        probe = work / 'probe'
        objects = sorted((bindir / 'OutlandsCore.build').glob('*.o'))
        if not objects:
            raise SystemExit('Run swift test --jobs 2 first to build the core.')
        compile_command = ['swiftc', '-parse-as-library', '-warnings-as-errors',
                           '-target', f'{platform.machine()}-apple-macosx14.6',
                           '-I', str(bindir / 'Modules'), '-I', str(bindir),
                           '-I', str(ROOT / 'Sources/CArchive'),
                           str(ROOT / 'tools/backup_memory_probe.swift'),
                           *map(str, objects), '-larchive.2', '-o', str(probe)]
        compiler_log = work / 'compiler.txt'
        try:
            resource_guard.run(compile_command, cwd=ROOT, output=compiler_log)
        except RuntimeError:
            if compiler_log.exists():
                shutil.copy2(compiler_log, qa / 'last-compiler-failure.txt')
                if ci:
                    with compiler_log.open('rb') as log:
                        print(log.read(8192).decode('utf-8', errors='replace'), flush=True)
            raise
        fixture = work / 'hash-fixture.bin'
        with fixture.open('wb') as file:
            for _ in range(16):
                file.write(bytes(1024 * 1024))
        report = {'hash': resource_guard.run(
            [str(probe), 'hash', str(fixture), str(work / 'logs')],
            cwd=ROOT, output=work / 'hash.txt')}
        if args.backup:
            backup = args.backup.resolve()
            if not backup.is_relative_to(qa):
                raise SystemExit('The optional backup must be inside the selected disposable QA root.')
            report['archive'] = resource_guard.run(
                [str(probe), 'verify', str(backup), str(work / 'archive-logs')],
                cwd=ROOT, output=work / 'verify.txt')
        (qa / 'resource-results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))


if __name__ == '__main__':
    main()
