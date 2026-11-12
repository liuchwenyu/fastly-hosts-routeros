#!/usr/bin/env python3
"""Create or verify the reviewed source ZIP. Requires Python 3.12 or later."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tempfile
from zipfile import BadZipFile, ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "fastly-hosts-routeros"
VERSION = "1.0.0"
ARCHIVE = f"{PREFIX}-{VERSION}.zip"
LIST = "tools/package-files.txt"
SUMS = "SHA256SUMS"
PIN = "manifests/runtime.sha256"
PIN_SHA = "09d6ea245e3592deab3dafc15d1b40bccf3b1125650203400f002faef79f94ca"
INSTALLER = "FHR-install-all.rsc"
INSTALLER_SHA = "b956bf1bb73d842a09fb37d7964cd883eaec2b5c50ec4a1a88a098bff0a60ec4"
MAX_FILE_BYTES = 4 * 1024 * 1024


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sums(files: dict[str, bytes]) -> bytes:
    return "".join(f"{digest(files[name])}  {name}\n" for name in sorted(files)).encode("ascii")


def plain_path(root: Path, name: str) -> Path:
    """The caller supplies a validated project-relative name."""
    path = root
    for part in PurePosixPath(name).parts:
        path = path / part
        if path.is_symlink() or path.is_junction():
            raise ValueError(f"link or junction is outside the packaging policy: {name}")
    return path


def read_file(root: Path, name: str) -> bytes:
    path = plain_path(root, name)
    if not path.is_file() or path.stat().st_size > MAX_FILE_BYTES:
        raise ValueError(f"missing, non-regular or oversized file: {name}")
    return path.read_bytes()


def names_from(data: bytes) -> list[str]:
    names = data.decode("ascii").splitlines()
    seen = set()
    for name in names:
        parts = name.split("/")
        if parts[0].casefold() in {"local", "private", ".agents", ".agent-kit", ".codex"}:
            raise ValueError(f"local-only path in package allowlist: {name}")
        if not all(re.fullmatch(r"[A-Za-z0-9_.-]+", part) for part in parts):
            raise ValueError(f"unsafe allowlist path: {name!r}")
        if any(part in {".", ".."} or part.lower() == ".git" or part.endswith(".")
               or re.fullmatch(r"(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\..*)?", part, re.I)
               for part in parts):
            raise ValueError(f"non-portable allowlist path: {name}")
        if name.casefold() in seen or name.casefold() == SUMS.casefold():
            raise ValueError(f"duplicate or reserved allowlist path: {name}")
        seen.add(name.casefold())
    required = {LIST, PIN, INSTALLER, "manifests/embedded-sources.json",
                "README.md", "AGENTS.md", "CHANGELOG.md", "LICENSE", "NOTICE", "UPSTREAM.md",
                "licenses/fastly-hosts-adjust-MIT.txt"}
    if not required.issubset(names):
        raise ValueError(f"allowlist lacks required files: {sorted(required - set(names))}")
    return sorted(names)


def verify_runtime(files: dict[str, bytes]) -> None:
    runtime = {name: data for name, data in files.items()
               if name == INSTALLER or name.startswith("routeros/") and name.endswith(".rsc")}
    if (digest(files[PIN]) != PIN_SHA or len(runtime) != 25 or sums(runtime) != files[PIN]
            or digest(files[INSTALLER]) != INSTALLER_SHA):
        raise ValueError(f"runtime differs from the pinned {VERSION} files")


def collect(root: Path) -> dict[str, bytes]:
    approved = read_file(root, LIST)
    files = {name: read_file(root, name) for name in names_from(approved) if name != LIST}
    files[LIST] = approved
    verify_runtime(files)
    return files


def verify_archive(path: Path, approved: bytes, expected_sums: bytes | None = None) -> None:
    names = names_from(approved)
    expected = {f"{PREFIX}/{name}" for name in [*names, SUMS]}
    with ZipFile(path) as archive:
        members = archive.infolist()
        if len(members) != len(expected) or set(archive.namelist()) != expected:
            raise ValueError("ZIP has unexpected, missing or duplicate entries")
        for entry in members:
            if not stat.S_ISREG(entry.external_attr >> 16) or entry.file_size > MAX_FILE_BYTES:
                raise ValueError(f"non-regular or oversized ZIP entry: {entry.filename}")
        files = {name: archive.read(f"{PREFIX}/{name}") for name in names}
        archived_sums = archive.read(f"{PREFIX}/{SUMS}")
        if (files[LIST] != approved or sums(files) != archived_sums
                or (expected_sums is not None and archived_sums != expected_sums)):
            raise ValueError("ZIP checksum or allowlist mismatch")
        verify_runtime(files)


def create(root: Path) -> Path:
    files = collect(root)
    manifest = sums(files)
    output_dir = plain_path(root, "dist")
    output_dir.mkdir(exist_ok=True)
    destination = plain_path(root, "dist/" + ARCHIVE)
    sums_path = plain_path(root, SUMS)
    with tempfile.TemporaryDirectory(dir=output_dir) as work:
        temp_zip = Path(work) / ARCHIVE
        with ZipFile(temp_zip, "w") as archive:
            for name, data in sorted((files | {SUMS: manifest}).items()):
                info = ZipInfo(f"{PREFIX}/{name}", (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(info, data, compress_type=ZIP_DEFLATED, compresslevel=9)
        verify_archive(temp_zip, files[LIST], manifest)
        # The checksum list travels inside the ZIP, which is independently complete.
        with tempfile.TemporaryDirectory(dir=root) as stage:
            temp_sums = Path(stage) / SUMS
            temp_sums.write_bytes(manifest)
            os.replace(temp_sums, sums_path)
        os.replace(temp_zip, destination)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-tree", action="store_true", help="check declared files against SHA256SUMS")
    mode.add_argument("--verify", metavar="ZIP", type=Path, help="verify a source ZIP against this file list")
    args = parser.parse_args()
    if args.check_tree:
        files = collect(ROOT)
        if read_file(ROOT, SUMS) != sums(files):
            raise ValueError("working tree differs from SHA256SUMS")
        print(f"Verified {len(files)} declared files and {VERSION} runtime hashes")
    elif args.verify:
        verify_archive(args.verify, read_file(ROOT, LIST), read_file(ROOT, SUMS))
        print(f"Verified {args.verify}")
    else:
        result = create(ROOT)
        print(f"{digest(result.read_bytes())}  {result.name}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, BadZipFile) as error:
        sys.exit(f"Package error: {error}")
