"""Exercise the release allowlist, runtime baseline and clean rebuild."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from zipfile import ZipFile, ZipInfo

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fhr_package", ROOT / "tools/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


@pytest.fixture
def work(tmp_path):
    root = tmp_path / "source checkout"
    for name in package.names_from((ROOT / package.LIST).read_bytes()):
        destination = root / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, destination)
    return root


def test_release_excludes_unreviewed_files_and_rebuilds_identically(work):
    target = package.create(work)
    expected = target.read_bytes()
    marker = hashlib.sha256(b"unlisted release fixture").digest()
    for name in (".env", ".git/config", "local/maintainer.md", ".agents/skills/example/SKILL.md", "export.rsc", "backup.backup",
                 "docs/session.txt", "routeros/FHR-private.rsc", "dist/old.zip"):
        p = work / name
        p.parent.mkdir(exist_ok=True, parents=True)
        p.write_bytes(marker)
    (work / "README.md").touch()
    assert package.create(work).read_bytes() == expected
    with ZipFile(target) as z:
        entries = set(z.namelist())
        ordered = package.names_from((work / package.LIST).read_bytes())
        assert entries == {f"{package.PREFIX}/{n}" for n in [*ordered, package.SUMS]}
        assert not any(marker in z.read(n) for n in entries)
        assert z.read(f"{package.PREFIX}/{package.SUMS}") == (work / package.SUMS).read_bytes()
    package.verify_archive(target, (work / package.LIST).read_bytes())


@pytest.mark.parametrize("change", ["missing-source", "changed-script", "changed-installer"])
def test_failed_pack_preserves_previous_zip_and_manifest(work, change):
    target = package.create(work)
    before = target.read_bytes()
    first_manifest = (work / package.SUMS).read_bytes()
    if change == "missing-source":
        (work / "README.md").unlink()
    else:
        name = "routeros/FHR-core.rsc" if change == "changed-script" else package.INSTALLER
        with (work / name).open("ab") as stream:
            stream.write(b"# local change\n")
    with pytest.raises(ValueError):
        package.create(work)
    assert target.read_bytes() == before
    assert (work / package.SUMS).read_bytes() == first_manifest


@pytest.mark.parametrize("name", ["README.md", "docs", "dist"])
def test_rejects_file_and_directory_links(work, name, tmp_path):
    p = work / name
    outside = tmp_path / "external"
    if name == "dist":
        outside.mkdir()
    else:
        p.rename(outside)
    try:
        p.symlink_to(outside, target_is_directory=outside.is_dir())
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")
    with pytest.raises(ValueError, match="link"):
        package.create(work)


@pytest.mark.parametrize("bad", ["../leak", "/absolute", "docs//file.md", "docs\\file",
                                  ".git/config", "docs/CON.txt", "sha256sums", "Readme.md",
                                  "local/notes.md", ".AGENTS/skills/example/SKILL.md"])
def test_rejects_nonportable_or_duplicate_allowlist_names(bad):
    approved = (ROOT / package.LIST).read_bytes()
    with pytest.raises(ValueError):
        package.names_from(approved + bad.encode() + b"\n")


@pytest.mark.parametrize("change", ["extra", "missing", "tamper", "checksum", "rehashed", "symlink", "duplicate"])
def test_zip_verifier_rejects_modified_archives(work, tmp_path, change):
    original = package.create(work)
    altered = tmp_path / "altered.zip"
    prefix = package.PREFIX + "/"
    member = prefix + "README.md"
    with ZipFile(original) as src, ZipFile(altered, "w") as dst:
        readme = src.read(member)
        for info in src.infolist():
            data = src.read(info)
            if info.filename == member:
                if change == "missing":
                    continue
                if change in {"tamper", "rehashed"}:
                    data += b"unreviewed"
                if change == "symlink":
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
            if info.filename == prefix + package.SUMS and change == "checksum":
                data = data.replace(b"  LICENSE\n", b"  license\n")
            if info.filename == prefix + package.SUMS and change == "rehashed":
                data = data.replace(package.digest(readme).encode("ascii"),
                                    package.digest(readme + b"unreviewed").encode("ascii"))
            dst.writestr(info, data)
        if change == "extra":
            dst.writestr(prefix + "../private", b"fixture")
        if change == "duplicate":
            with pytest.warns(UserWarning, match="Duplicate"):
                dst.writestr(ZipInfo(member), b"duplicate")
    with pytest.raises(ValueError):
        package.verify_archive(altered, (work / package.LIST).read_bytes(), (work / package.SUMS).read_bytes())


def test_clean_build_recreates_packaged_sources_and_installer(work):
    editable = {"config", "core", "storage", "network", "benchmarks", "discovery",
                "dns", "engine", "commands", "selftest"}
    modules = list((work / "routeros").glob("FHR-*.rsc"))
    generated = [p for p in modules if p.stem.removeprefix("FHR-") not in editable]
    assert len(generated) == 14
    generated.extend([work / package.INSTALLER, work / "manifests/embedded-sources.json"])
    expected = {path: path.read_bytes() for path in generated}
    for path in generated:
        path.unlink()
    subprocess.run([sys.executable, str(work / "tools/build.py")], cwd=work, check=True)
    for path, data in expected.items():
        assert path.read_bytes() == data, path.name
    package.collect(work)


def test_rewritten_index_cannot_hide_changed_runtime(work):
    script = work / "routeros/FHR-doctor.rsc"
    original = script.read_bytes()
    altered = original + b"# edited after validation\n"
    script.write_bytes(altered)
    baseline = work / package.PIN
    baseline.write_bytes(baseline.read_bytes().replace(
        package.digest(original).encode("ascii"), package.digest(altered).encode("ascii")))
    with pytest.raises(ValueError, match="pinned"):
        package.create(work)


def test_check_tree_cli_reports_changed_reviewed_file(work):
    package.create(work)
    cmd = [sys.executable, str(work / "tools/package.py"), "--check-tree"]
    subprocess.run(cmd, cwd=work, check=True, capture_output=True)
    with (work / "README.md").open("ab") as stream:
        stream.write(b"new information")
    changed = subprocess.run(cmd, cwd=work, capture_output=True, text=True)
    assert changed.returncode != 0 and "differs from SHA256SUMS" in changed.stderr


def test_installer_and_license_provenance():
    assert package.digest((ROOT / package.INSTALLER).read_bytes()) == package.INSTALLER_SHA
    upstream = (ROOT / "licenses/fastly-hosts-adjust-MIT.txt").read_bytes()
    assert package.digest(upstream) == "b356ccb67633c60386f988c1072d494df295653811fbc3d843c87be2e629b046"
    port_credit = b"Copyright (c) 2026 Fastly Hosts RouterOS contributors\n"
    assert (ROOT / "LICENSE").read_bytes().replace(port_credit, b"", 1) == upstream


def test_archive_and_installer_declare_the_same_release():
    config = (ROOT / "routeros/FHR-config.rsc").read_text(encoding="utf-8")
    assert f'"version"="{package.VERSION}";' in config
    assert package.ARCHIVE == f"fastly-hosts-routeros-{package.VERSION}.zip"
