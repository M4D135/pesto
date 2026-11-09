#!/usr/bin/env python3
"""Create separate PROD and DEV distributions from one verified source tree.

Uses only the Python standard library. No compilation, download, UAC or AD call.
The destination must be new; existing installations are never overwritten.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import tempfile
import zipfile

from refresh_manifest import VERSION, runtime_files, safe_file, verify_runtime, _is_link_or_junction
from prepare_dev import check_pack_config

# Ship the unblock helper in both packs; it is not a runtime dependency.
PROD_HELPERS = ("wad/support/DEBLOQUER_TOUT.cmd",)
DEV_ROOT = (
    "LIRE_MOI.txt", ".gitignore", ".gitattributes", "pytest.ini", "README.md", "CHANGELOG.md", "Pesto.cmd", "Pesto_COMPTE_AD.cmd",
    "DEMO.cmd", "DEMO_DOMAINE.cmd", "APERCU_LOGIN.cmd", "ETAT_RENOMMAGE.cmd",
    "TESTER.cmd", "VERIFIER_PACK.cmd", "TEST_DISTRIBUTION.cmd", "FABRIQUER_PACKS.cmd", "FABRIQUER_PROD.cmd",
)
DEV_TREES = ("vendor", "tools", "tests", "docs", "changes", "integrations", ".github", "wad/maintenance", "wad/docs", "src")
DEV_SUFFIXES = {".cs", ".py", ".ps1", ".psm1", ".psd1", ".admx", ".adml", ".c", ".h", ".manifest", ".md", ".txt", ".json", ".yml", ".yaml", ".patch", ".rc", ".cmd"}
DEV_GUIDES = frozenset('docs/Pesto-1.0-Guide-' + role + '.' + extension
                      for role in ('technicien', 'administrateur') for extension in ('docx', 'pdf'))
DEV_CONFIGS = ("wad/cfg.demo.json", "wad/cfg.example.json")
# Archived fixtures kept in the repository as history, not as green proof (see their README and
# docs/AMELIORATIONS_2026-10-08.md item 158). Shipping them would put red suites inside the pack.
DEV_EXCLUDED_DIRS = ("historique_rc18",)


def distribution_files(source: Path, channel: str) -> tuple[str, ...]:
    if channel not in ("PROD", "DEV"):
        raise ValueError("Channel must be PROD or DEV")
    files = set(runtime_files(source)) | {"wad/package.json", "wad/cfg.json"} | set(PROD_HELPERS)
    if channel == "DEV":
        files.update(DEV_ROOT)
        files.update(DEV_CONFIGS)
        if (source / "wad/Pesto.Engine.exports.json").is_file():
            files.add("wad/Pesto.Engine.exports.json")
        # Legacy launchers remain available only in the developer distribution.
        files.update(p.name for p in source.glob("TEST*.cmd") if p.is_file())
        files.update(p.name for p in source.glob("VERIFIER*.cmd") if p.is_file())
        for folder in DEV_TREES:
            base = source / folder
            if _is_link_or_junction(base):
                raise ValueError(f"Linked developer folder: {folder}")
            if not base.is_dir():
                continue
            for path in base.rglob("*"):
                relative = path.relative_to(source)
                if any(part in ("__pycache__", ".git", ".build", "dist", "logs", "results") for part in relative.parts):
                    continue
                if any(part in DEV_EXCLUDED_DIRS for part in relative.parts):
                    continue
                if _is_link_or_junction(path):
                    raise ValueError(f"Linked developer file: {relative}")
                if path.is_file() and (path.suffix.lower() in DEV_SUFFIXES or relative.as_posix() in DEV_GUIDES):
                    # Existing test reports are historical; never include newly generated Windows/session reports.
                    if path.name.lower().startswith(("windows-", "pesto-etat-", "pesto_etat_", "gp-etat-", "gp_etat_")):
                        continue
                    # Static reports list the domains of the private configuration (.gitignore).
                    if "static-report" in path.name.lower():
                        continue
                    files.add(relative.as_posix())
    if channel == "PROD" and {p.split("/")[0] for p in files} != {"Pesto.exe", "wad"}:
        raise ValueError("PROD must contain exactly Pesto.exe and wad at its root")
    for relative in files:
        safe_file(source, relative)
    return tuple(sorted(files))


def build_directory(source: Path, destination: Path, channel: str, allow_config: bool = False) -> Path:
    source = source.resolve(strict=True)
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Destination already exists; not overwritten: {destination}")
    # Resolve parent aliases too: /tmp/output-link/new may really be <source>/new.
    destination = destination.resolve(strict=False)
    # Prevent accidental recursive copies through the source tree.
    if destination == source or source in destination.parents:
        raise ValueError("Choose a destination outside the source directory")
    verify_runtime(source)
    # Every pack path goes through here: never publish a real configuration by accident.
    check_pack_config(source, allow_config)
    files = distribution_files(source, channel)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".pesto-stage-", dir=destination.parent) as temp:
        stage = Path(temp) / channel
        stage.mkdir()
        for relative in files:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(safe_file(source, relative), target)
        verify_runtime(stage)
        # Own the new destination before copying. A failed publication must not
        # leave a plausible but incomplete distribution at the requested path.
        destination.mkdir()
        try:
            shutil.copytree(stage, destination, dirs_exist_ok=True)
        except BaseException:
            shutil.rmtree(destination)
            raise
    return destination


def write_zip(root: Path, target: Path) -> None:
    if root.name not in ("PROD", "DEV"):
        raise ValueError("Archive root must be named PROD or DEV")
    if _is_link_or_junction(root) or not root.is_dir():
        raise ValueError("Archive source must be a normal directory")
    root = root.resolve(strict=True)
    target = target.absolute()
    if target.exists() or target.is_symlink():
        raise ValueError(f"Archive already exists: {target}")
    target = target.resolve(strict=False)
    if target == root or root in target.parents:
        raise ValueError("Archive must be outside its payload directory")
    files = []
    for path in sorted(root.rglob("*")):
        if _is_link_or_junction(path):
            raise ValueError(f"Linked archive component: {path.relative_to(root)}")
        if path.is_file():
            files.append(path.relative_to(root).as_posix())
    # Exclusive creation also protects a destination created since the check.
    # Only our own incomplete archive is removed when writing or validation fails.
    with target.open("xb") as stream:
        try:
            with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for relative in files:
                    info = zipfile.ZipInfo(root.name + "/" + relative, (2026, 9, 30, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, safe_file(root, relative).read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            stream.flush()
            with zipfile.ZipFile(target) as archive:
                bad = archive.testzip()
                if bad:
                    raise ValueError(f"Damaged archive entry: {bad}")
        except BaseException:
            stream.close()  # Windows cannot unlink an open output file.
            target.unlink()
            raise



def build_archives(source: Path, output: Path, channels=("PROD", "DEV"),
                   allow_config: bool = False, versioned: bool = False) -> tuple[Path, ...]:
    """Publish the requested channels together, only after every archive is verified."""
    source = Path(source).resolve(strict=True)
    output = Path(output).absolute()
    channels = tuple(channels)
    if not channels or len(set(channels)) != len(channels) or any(c not in ("PROD", "DEV") for c in channels):
        raise ValueError("Choose distinct PROD/DEV channels")
    if output.exists() or output.is_symlink():
        raise FileExistsError("Choose a new output directory")
    output = output.resolve(strict=False)
    if output == source or source in output.parents:
        raise ValueError("Output must be outside the source directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    names = []
    with tempfile.TemporaryDirectory(prefix=".pesto-packs-", dir=output.parent) as temporary:
        stage = Path(temporary) / "packs"
        for channel in channels:
            directory = build_directory(source, stage / channel, channel, allow_config)
            name = f"Pesto_{VERSION}_{channel}.zip" if versioned else f"Pesto_{channel}.zip"
            write_zip(directory, stage / name)
            names.append(name)
        output.mkdir()  # Exclusive ownership; a concurrently created output is preserved.
        try:
            for path in stage.iterdir():
                shutil.move(str(path), output / path.name)
        except BaseException:
            shutil.rmtree(output)
            raise
    return tuple(output / name for name in names)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", required=True, type=Path, help="New destination, outside the source")
    parser.add_argument("--channel", choices=("PROD", "DEV", "BOTH"), default="BOTH")
    parser.add_argument("--allow-config", action="store_true", help="Pack a wad/cfg.json that differs from the unconfigured template (deliberate).")
    args = parser.parse_args()
    if args.output.exists():
        parser.exit(1, "Output already exists; choose a new destination.\n")
    try:
        channels = ("PROD", "DEV") if args.channel == "BOTH" else (args.channel,)
        targets = build_archives(args.source, args.output, channels, args.allow_config, versioned=True)
        for channel, target in zip(channels, targets):
            print(f"Built {channel}: {target}")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.exit(1, f"Distribution error: {exc}\n")


if __name__ == "__main__":
    main()
