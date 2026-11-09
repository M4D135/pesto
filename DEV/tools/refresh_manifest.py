#!/usr/bin/env python3
"""Explicit development-time regeneration of the Runtime-only manifest.

Never called by Pesto at startup. Uses the same closed file list as the PowerShell
checker. Does not include configuration, state, CMD files, tests or demos.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile

from release_version import VERSION, FILE_VERSION
SCHEMA = 2
SCOPE = "Runtime"
_RESERVED_WIN32 = re.compile(r"(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", re.I)
_REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x00000400)


def _is_link_or_junction(path: Path) -> bool:
    try:
        if path.is_symlink():
            return True
    except OSError:
        pass
    is_junction = getattr(path, "is_junction", None)
    if callable(is_junction):
        try:
            return bool(is_junction())
        except OSError:
            pass
    if os.name == "nt":
        try:
            st = os.lstat(path)
            return bool(getattr(st, "st_file_attributes", 0) & _REPARSE)
        except OSError:
            pass
    return False


def runtime_files(root: Path) -> tuple[str, ...]:
    """Read literals from the marked list without executing any PowerShell code."""
    text = safe_file(root, "wad/Pesto-Integrity.ps1").read_text(encoding="utf-8-sig")
    block = re.search(r"# BEGIN Pesto_RUNTIME_FILES\s+@\((.*?)\)\s+# END Pesto_RUNTIME_FILES", text, re.S)
    if block is None:
        raise ValueError("Closed runtime list not found in Pesto-Integrity.ps1")
    paths = tuple(re.findall(r"'([^']+)'", block.group(1)))
    residue = re.sub(r"'[^']+'|[\s,]", "", block.group(1))
    if residue or len(paths) != len({p.casefold() for p in paths}) or not paths:
        raise ValueError("Invalid closed runtime list")
    for relative in paths:
        validate_runtime_relative(relative)
    return paths


def validate_relative(relative: str) -> None:
    if not isinstance(relative, str) or ":" in relative:
        raise ValueError(f"Invalid relative path: {relative!r}")
    if not re.fullmatch(r"(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+", relative):
        raise ValueError(f"Invalid relative path: {relative!r}")
    for part in relative.split("/"):
        if part.endswith((".", " ")):
            raise ValueError(f"Trailing dot/space is forbidden: {relative!r}")
        if _RESERVED_WIN32.fullmatch(part):
            raise ValueError(f"Reserved Windows name: {relative!r}")
    if any(part in (".", "..") for part in relative.split("/")):
        raise ValueError(f"Traversal is forbidden: {relative!r}")



def validate_runtime_relative(relative: str) -> None:
    """Shared closed-runtime path policy for current builds and older update manifests."""
    validate_relative(relative)
    lowered = relative.lower()
    if lowered.endswith((".json", ".log")) and relative not in ("wad/common.lock.json", "wad/Pesto.Engine.build.json"):
        raise ValueError(f"Mutable/runtime manifest component in required list: {relative}")
    if not (relative == "Pesto.exe" or
            (relative.startswith("wad/") and not lowered.startswith(("wad/docs/", "wad/maintenance/")))):
        raise ValueError(f"Non-runtime component in required list: {relative}")
    if lowered.endswith((".cmd", ".bat")) or "/cfg" in lowered:
        raise ValueError(f"Mutable/development component in required list: {relative}")


def safe_file(root: Path, relative: str) -> Path:
    validate_relative(relative)
    root = root.resolve(strict=True)
    path = root.joinpath(*relative.split("/"))
    for item in (path, *path.parents):
        if item == root:
            break
        if _is_link_or_junction(item):
            raise ValueError(f"Linked component is forbidden: {relative}")
    if not path.is_file() or root not in path.resolve(strict=True).parents:
        raise ValueError(f"Missing or invalid file: {relative}")
    return path


def file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_native_binding(root: Path) -> dict[str, str]:
    """Detect a stale EXE after source edits; this is not publisher authentication."""
    data = safe_file(root, "Pesto.exe").read_bytes()
    start, end = b"PESTO_BINDING_V1\n", b"PESTO_BINDING_END"
    if data.count(start) != 1:
        raise ValueError("Missing/duplicate compiled runtime binding; rebuild Pesto.exe")
    block = data.split(start, 1)[1].split(end, 1)[0]
    if len(block) > 65536:
        raise ValueError("Oversized compiled binding")
    bindings = {}
    for line in block.decode("ascii").splitlines():
        path, digest = line.split("|", 1)
        validate_relative(path)
        if path in bindings or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError("Invalid compiled binding")
        bindings[path] = digest
    expected = set(runtime_files(root)) - {"Pesto.exe"}
    if set(bindings) != expected:
        raise ValueError("The EXE and runtime component list differ; rebuild")
    # Nommer seulement la premiere divergence faisait croire qu'un composant était périmé alors qu'un
    # seul commit en wad/ en désaligne souvent plusieurs : la borne doit énoncer toute l'étendue.
    diverged = [path for path, digest in sorted(bindings.items())
                if file_hash(safe_file(root, path)) != digest]
    if diverged:
        raise ValueError("EXE was built for different bytes: %d of %d components (%s); rebuild Pesto.exe"
                         % (len(diverged), len(bindings), ", ".join(diverged)))
    return bindings


def verify_runtime(root: Path) -> dict:
    path = safe_file(root, "wad/package.json")
    if path.stat().st_size > 262144:
        raise ValueError("Oversized runtime manifest")
    manifest = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(manifest, dict):
        raise ValueError("Invalid runtime manifest: expected an object")
    expected = runtime_files(root)
    entries = manifest.get("Files")
    if (manifest.get("Schema") != SCHEMA or manifest.get("Version") != VERSION or
            manifest.get("Scope") != SCOPE or not isinstance(entries, list) or len(entries) != len(expected)):
        raise ValueError("Incompatible runtime manifest")
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("Invalid runtime entry: expected an object")
        relative = entry.get("Path")
        if not isinstance(relative, str) or relative not in expected or relative.casefold() in seen:
            raise ValueError(f"Unexpected/duplicate runtime entry: {relative!r}")
        seen.add(relative.casefold())
        digest = entry.get("SHA256")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            raise ValueError(f"Invalid runtime hash: {relative}")
        if file_hash(safe_file(root, relative)) != digest.lower():
            raise ValueError(f"Changed runtime component: {relative}")
    if seen != {p.casefold() for p in expected}:
        raise ValueError("Missing required runtime entries")
    verify_native_binding(root)
    return manifest


def write_manifest(root: Path) -> dict:
    entries = [{"Path": p, "SHA256": file_hash(safe_file(root, p))} for p in runtime_files(root)]
    data = {"Schema": SCHEMA, "Version": VERSION, "Scope": SCOPE, "FileVersion": FILE_VERSION, "Files": entries}
    target = root / "wad/package.json"
    if _is_link_or_junction(target):
        raise ValueError("Manifest must not be a link/junction")
    fd, temp = tempfile.mkstemp(prefix=".package-", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    verify_runtime(root)
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Read-only verification; do not regenerate hashes")
    args = parser.parse_args()
    try:
        result = verify_runtime(args.root.resolve()) if args.check else write_manifest(args.root.resolve())
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.exit(1, f"Package error: {exc}\n")
    print(f"{'Checked' if args.check else 'Regenerated'}: {len(result['Files'])} runtime components; "
          "no demos/tests/CMD/configuration. Not an author signature.")


if __name__ == "__main__":
    main()
