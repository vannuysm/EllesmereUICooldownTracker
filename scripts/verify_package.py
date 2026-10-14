"""Verify the packaged addon layout and ZIP contents."""

import argparse
from pathlib import Path
from zipfile import ZipFile

from deploy import ADDON, ROOT, validate_package


def verify_package(release_directory: Path) -> None:
    package = release_directory / ADDON
    validate_package(package)
    source_directory = ROOT / "src"
    for source in source_directory.rglob("*"):
        if source.is_file():
            relative = source.relative_to(source_directory)
            assert (package / relative).is_file(), f"Missing packaged source: {relative}"
    assert (package / "LICENSE").is_file()
    allowed = {source.name for source in source_directory.iterdir()}
    allowed.update({"LICENSE", "CHANGELOG.md", "CHANGELOG.txt"})
    unexpected = {entry.name for entry in package.iterdir()} - allowed
    assert not unexpected, f"Unexpected packaged entries: {unexpected}"
    expected = {
        f"{ADDON}/{file.relative_to(package).as_posix()}"
        for file in package.rglob("*") if file.is_file()
    }
    archives = list(release_directory.glob("*.zip"))
    assert archives, "Packager did not create a ZIP"
    for archive in archives:
        with ZipFile(archive) as zipped:
            actual = {name for name in zipped.namelist() if not name.endswith("/")}
            assert actual == expected, f"Unexpected ZIP layout: {archive}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--release-dir", type=Path, default=ROOT / ".release",
        help="Directory containing the packaged addon and ZIP files (default: .release)",
    )
    args = parser.parse_args()
    verify_package(args.release_dir)
    print("Packaged addon layout and ZIP contents verified.")


if __name__ == "__main__":
    main()
