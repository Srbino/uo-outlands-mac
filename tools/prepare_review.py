#!/usr/bin/env python3
"""Snapshot reviewable source, including untracked files, without private game data."""
import hashlib
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = {".github", "Sources", "Tests", "docs", "tools", "helpers"}
ROOT_FILES = {".gitignore", "README.md", "LICENSE", "Package.swift", "Package.resolved"}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main():
    candidates = set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0"))
    files = {}
    for name in sorted(candidates):
        if not name:
            continue
        relative = Path(name)
        if name not in ROOT_FILES and relative.parts[0] not in DIRECTORIES:
            continue
        source = ROOT / relative
        if source.is_symlink():
            raise SystemExit(f"Refusing to package a source symlink: {name}")
        if source.is_file():
            # Read once so manifest and ZIP contain the same bytes even if a file changes.
            files[name] = source.read_bytes()
    if "docs/REVIEW.md" not in files:
        raise SystemExit("Review entry point is missing.")
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "base_commit": git("rev-parse", "HEAD").decode().strip(),
        "working_tree": "Local snapshot including untracked source; not a reviewed commit",
        "excluded": [".git", ".qa", ".build", ".build-management", "dist", "game data", "private backups", "raw session logs"],
        "files": [{"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()} for name, data in files.items()],
    }
    metadata = {
        "manifest.json": json.dumps(manifest, indent=2).encode() + b"\n",
        "git-status.txt": git("status", "--short"),
        "tracked-changes.patch": git("diff", "--binary", "HEAD", "--", "."),
        "START-HERE.txt": b"Read source/docs/REVIEW.md first. The source snapshot is authoritative.\nThe tracked diff omits untracked additions; inspect source/ in full.\nThe manifest hashes source files; no private game data or app binary is included.\nThis is a review handoff, not an independent approval or stable release.\n",
    }
    output = ROOT / "dist/review"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "Outlands-for-Mac-review.zip"
    temporary = output / "Outlands-for-Mac-review.zip.tmp"
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in files.items():
            package.writestr("source/" + name, data)
        for name, data in metadata.items():
            package.writestr(name, data)
    with zipfile.ZipFile(temporary) as package:
        if package.testzip() is not None:
            raise SystemExit("Review ZIP integrity check failed.")
        for item in manifest["files"]:
            content = package.read("source/" + item["path"])
            if hashlib.sha256(content).hexdigest() != item["sha256"]:
                raise SystemExit("Review source manifest verification failed.")
    temporary.replace(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
    print(f"Verified {len(files)} source files. Review archive: {archive}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
