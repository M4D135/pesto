#!/usr/bin/env python3
"""Verify the pinned offline comparator before running the declared UI integrity check."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

PRODUCT = "pesto"
SOURCE_COMMIT = "67ae057d3f46dbb9a72562b3f444a8fd069b10c5"
VERSION = "0.1.0"
FILES = {
    "components.py": ("0cf21d76cf181d3c6b7829218f0c733c7fccb8c96bfb67023a80abccb58ea00e", 15221),
    "components.schema.json": ("b7c321f83392bc25af49b5713bfa857fe7ea0af50c57e881e6d6aa945273afbe", 4451),
}
MAX_BYTES = 1024 * 1024


class Refused(ValueError):
    pass


def no_links(path):
    path = Path(path).absolute()
    for current in reversed((path, *path.parents)):
        info = current.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise Refused("A linked path or reparse point was refused.")
    return path


def read(path):
    path = no_links(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_BYTES:
        raise Refused("A regular, bounded file is required.")
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise Refused("File changed during opening.")
        value = stream.read(MAX_BYTES + 1)
        after = os.fstat(stream.fileno())
    no_links(path)
    current = path.stat()
    if len(value) > MAX_BYTES or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns
    ) or (opened.st_size, opened.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise Refused("File changed or exceeds its bound.")
    return value


def pairs(values):
    result = {}
    for key, value in values:
        if key in result:
            raise Refused("Duplicate JSON property.")
        result[key] = value
    return result


def document(path):
    return json.loads(read(path).decode("utf-8"), object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(Refused("Non-finite JSON number.")))


def verify(folder, manifest):
    no_links(Path(__file__))
    lock = document(folder / "m4d-components.lock.json")
    if not isinstance(lock, dict) or set(lock) != {
        "schema", "tool", "version", "sourceRepository", "sourceCommit", "files"
    } or type(lock["schema"]) is not int or lock["schema"] != 1 or lock["tool"] != "m4d-components" or \
       lock["version"] != VERSION or lock["sourceRepository"] != "M4D135/m4d-admin-common" or \
       lock["sourceCommit"] != SOURCE_COMMIT:
        raise Refused("The comparator lock is not the reviewed version.")
    entries = lock["files"]
    if not isinstance(entries, list) or len(entries) != len(FILES):
        raise Refused("Unexpected comparator file inventory.")
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256", "bytes"}:
            raise Refused("Invalid comparator file record.")
        name = entry["path"]
        if not isinstance(name, str) or name not in FILES or name in seen:
            raise Refused("Unknown or duplicate comparator file.")
        seen.add(name)
        expected_hash, expected_size = FILES[name]
        if entry["sha256"] != expected_hash or type(entry["bytes"]) is not int or entry["bytes"] != expected_size:
            raise Refused("The comparator file pin was changed.")
        data = read(folder / name)
        if len(data) != expected_size or hashlib.sha256(data).hexdigest() != expected_hash:
            raise Refused("Comparator bytes do not match the reviewed pin.")
    consumer = document(manifest)
    if not isinstance(consumer, dict) or consumer.get("product") != PRODUCT:
        raise Refused("The UI manifest belongs to another product.")
    return consumer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-root", type=Path)
    parser.add_argument("--canonical-manifest", type=Path)
    args = parser.parse_args()
    try:
        if (args.canonical_root is None) != (args.canonical_manifest is None):
            raise Refused("Both canonical paths must be provided.")
        here = Path(__file__).absolute().parent
        versioned = here.parent.name == "v2"
        root = here.parent.parent if versioned else here.parent
        manifest = root / ("v2/web/ui-kit.lock.json" if versioned else "web/ui-kit.lock.json")
        folder = here / "m4d-components"
        consumer = verify(folder, manifest)

        def invoke(manifest_path):
            command = [sys.executable, "-I", "-S", str(folder / "components.py"),
                       "compare" if args.canonical_root is not None else "validate",
                       "--root", str(root), "--manifest", str(manifest_path)]
            if args.canonical_root is not None:
                command += ["--canonical-root", str(args.canonical_root),
                            "--canonical-manifest", str(args.canonical_manifest)]
            # Trusted, byte-verified stdlib tool only. No shell, fetch, package manager or product runtime.
            return subprocess.run(command, check=False).returncode

        if versioned:
            return invoke(manifest)
        # DEV ships the v2 source directory as wad/dev. Project only local paths;
        # preserve the original lock bytes, upstream paths, hashes and adaptation declarations.
        entries = consumer.get("files")
        if not isinstance(entries, list) or any(not isinstance(entry, dict)
                or not isinstance(entry.get("path"), str) or not entry["path"].startswith("v2/")
                for entry in entries):
            raise Refused("The DEV source layout requires explicit v2/ local paths.")
        projected = dict(consumer, files=[dict(entry, path=entry["path"][3:]) for entry in entries])
        temporary_parent = Path(tempfile.gettempdir()).resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix="pesto-ui-kit-", dir=temporary_parent) as temporary:
            projected_manifest = Path(temporary) / "ui-kit.lock.json"
            with projected_manifest.open("x", encoding="utf-8") as output:
                json.dump(projected, output, ensure_ascii=False)
            return invoke(projected_manifest)
    except (Refused, OSError, ValueError, RecursionError, subprocess.SubprocessError) as error:
        print(json.dumps({"schema": 1, "status": "invalid", "certification": False,
                          "findings": [{"code": "bootstrap.refused", "message": str(error)}]}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
