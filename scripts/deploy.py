"""Package the addon and deploy it to a local World of Warcraft client."""

import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.error import URLError
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
ADDON = "EllesmereUICooldownTracker"


def configured_path(command_line: str | None, root: Path) -> str:
    """Read only WOW_PATH; never execute or interpolate dotenv contents."""
    if command_line is not None:
        if not command_line.strip():
            raise ValueError("The command-line WoW path cannot be empty.")
        return command_line

    env_file = root / ".env"
    if env_file.is_file():
        value = None
        for line in env_file.read_text(encoding="utf-8-sig").splitlines():
            match = re.match(r"^\s*(?:export\s+)?WOW_PATH\s*=\s*(.*)$", line)
            if not match:
                continue
            raw = match[1].strip()
            if raw.startswith(("'", '"')):
                end = raw.find(raw[0], 1)
                if end < 0 or (raw[end + 1:].strip() and not raw[end + 1:].lstrip().startswith("#")):
                    raise ValueError("Invalid quoted WOW_PATH in .env.")
                value = raw[1:end]
            else:
                value = re.split(r"\s+#", raw, maxsplit=1)[0].strip()
        if value and value.strip():
            return value
    raise ValueError('Provide a WoW path on the command line or set WOW_PATH in the repository .env file.')


def client_directory(value: str, client: str, root: Path) -> Path:
    if not re.fullmatch(r"_[A-Za-z0-9_]+_", client):
        raise ValueError("--client must be a client folder name such as _retail_ or _classic_.")
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    path = path.resolve(strict=True)
    if not path.is_dir():
        raise ValueError(f"WoW path is not a directory: {path}")
    # A supplied client directory takes priority over the root's client selector.
    if (path / "Interface").is_dir() or any(path.glob("Wow*.exe")) or (path / "World of Warcraft.app").is_dir():
        return path
    selected = path / client
    if selected.is_dir():
        return selected.resolve()
    raise ValueError(f"Cannot find a WoW client at {path}. Pass a client folder with Interface, or a WoW root containing {client}.")


def packager_configuration(root: Path) -> tuple[str, list[str]]:
    """Use the release workflow as the source of the Packager pin and arguments."""
    workflow = (root / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    match = re.search(r"(?m)^\s+uses:\s+BigWigsMods/packager@([0-9a-f]{40})\b[^\n]*\n", workflow)
    if not match:
        raise ValueError("release.yml must pin BigWigsMods/packager to a full commit SHA.")
    # Read the literal, single-line args field in this action's step only.
    step = re.split(r"(?m)^\s+- (?:name|uses):", workflow[match.end():], maxsplit=1)[0]
    args = re.search(r"(?m)^\s+args:\s*(.*?)\s*$", step)
    if not args:
        return match[1], []
    value = args[1]
    if value.startswith(("'", '"')) and value.endswith(value[0]):
        value = value[1:-1]
    if "${{" in value or value in {"|", ">"}:
        raise ValueError("Packager args in release.yml must be a literal single-line value.")
    return match[1], shlex.split(value, comments=True)


def find_bash(explicit: str | None = None) -> str:
    if explicit:
        executable = shutil.which(explicit)
        if executable:
            return executable
        raise ValueError(f"Cannot find Bash: {explicit}")
    if os.name == "nt":
        # Prefer Git Bash over Windows' legacy bash.exe launcher for WSL.
        git = shutil.which("git")
        if git:
            candidate = Path(git).resolve().parents[1] / "bin" / "bash.exe"
            if candidate.is_file():
                return str(candidate)
    executable = shutil.which("bash")
    if not executable:
        raise ValueError("Bash 4.3+ is required. Install Git for Windows or pass --bash PATH.")
    return executable


def build_package(root: Path, bash: str | None = None) -> Path:
    revision, arguments = packager_configuration(root)
    executable = find_bash(bash)
    release = root / ".release"
    script = release / "tools" / revision / "release.sh"
    if not script.is_file():
        script.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://raw.githubusercontent.com/BigWigsMods/packager/{revision}/release.sh"
        print(f"Downloading BigWigsMods Packager at {revision}...", flush=True)
        with urlopen(url, timeout=30) as response:
            contents = response.read()
        script.write_bytes(contents)
    output = release / "local"
    if not output.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Unsafe package output directory: {output}")
    output.mkdir(exist_ok=True)
    command = [
        executable, script.relative_to(root).as_posix(), *arguments,
        "-d", "-z", "-t", ".", "-r", "./.release/local",
    ]
    # -d disables every upload; -z deploys Packager's directory without needing zip.
    print(f"Packaging with BigWigsMods Packager at {revision}...", flush=True)
    environment = os.environ.copy()
    # Signature text in `git show` breaks Packager's metadata substitutions.
    # Scope this setting to the subprocess, preserving the user's Git config.
    config_count = int(environment.get("GIT_CONFIG_COUNT", "0"))
    environment[f"GIT_CONFIG_KEY_{config_count}"] = "log.showSignature"
    environment[f"GIT_CONFIG_VALUE_{config_count}"] = "false"
    environment["GIT_CONFIG_COUNT"] = str(config_count + 1)
    subprocess.run(command, cwd=root, check=True, env=environment)
    package = output / ADDON
    if not (package / f"{ADDON}.toc").is_file():
        raise ValueError(f"Packager did not produce the expected addon: {package}")
    return package


def deploy_package(package: Path, client: Path, root: Path) -> Path:
    addons = client / "Interface" / "AddOns"
    target = addons / ADDON
    # Resolve before any replacement/deletion so a junction cannot redirect cleanup.
    if not target.resolve().is_relative_to(client.resolve()) or target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Unsafe deployment destination: {target}")
    if target.is_symlink() or target.is_junction() or (target.exists() and not target.is_dir()):
        raise ValueError(f"Deployment destination must be an ordinary directory: {target}")
    addons.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{ADDON}-", dir=addons))
    backup = staging / "previous"
    preserve_backup = False
    try:
        prepared = staging / ADDON
        shutil.copytree(package, prepared)
        if target.exists():
            target.rename(backup)
        try:
            prepared.rename(target)
        except OSError as install_error:
            if backup.exists():
                try:
                    backup.rename(target)
                except OSError as restore_error:
                    preserve_backup = True
                    raise OSError(f"Install failed ({install_error}); restore failed ({restore_error}). Previous addon preserved at {backup}") from restore_error
            raise
    finally:
        if not preserve_backup:
            # The staging directory was created within the validated AddOns path.
            if not staging.resolve().is_relative_to(addons.resolve()):
                raise ValueError(f"Unsafe cleanup destination: {staging}")
            shutil.rmtree(staging)
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wow_path", nargs="?", help="WoW root or client folder; overrides WOW_PATH in .env")
    parser.add_argument("--client", default="_retail_", help="Client folder when passing the WoW root (default: _retail_)")
    parser.add_argument("--bash", help="Bash executable (defaults to Git Bash on Windows, or bash on PATH)")
    args = parser.parse_args(argv)
    try:
        client = client_directory(configured_path(args.wow_path, ROOT), args.client, ROOT)
        package = build_package(ROOT, args.bash)
        destination = deploy_package(package, client, ROOT)
    except (OSError, ValueError, URLError, subprocess.CalledProcessError) as error:
        print(f"Deployment failed: {error}", file=sys.stderr)
        return 1
    print(f"Packaged: {package}")
    print(f"Deployed: {destination}")
    print("Run /reload in WoW, or enable the addon and restart the client if newly installed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
