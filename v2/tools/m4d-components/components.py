#!/usr/bin/env python3
"""Offline checks for declared M4D component bytes; never a UI or engine certification."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

VERSION = "0.1.0"
CANONICAL = "M4D135/domenia-d120"
PRODUCTS = ("domenia", "pesto", "filpro", "glpi-pilot", "dex-platform", "m4d-admin-common")
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_FILE_BYTES = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_FILES = 1024
HEX40 = re.compile(r"[a-f0-9]{40}")
HEX64 = re.compile(r"[a-f0-9]{64}")


class InvalidInput(ValueError):
    def __init__(self, code, message, path=None):
        super().__init__(message)
        self.code, self.path = code, path


def fail(code, message, path=None):
    raise InvalidInput(code, message, path)


def exact_keys(value, required, optional=()):
    if not isinstance(value, dict) or set(value) - set(required) - set(optional) or set(required) - set(value):
        fail("schema.keys", "Missing or unexpected JSON properties.")


def text(value, maximum, name):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum or any(ord(c) < 32 for c in value):
        fail("schema.text", "Invalid bounded text: " + name)
    return value


def digest_text(value, expression, name):
    if not isinstance(value, str) or not expression.fullmatch(value):
        fail("schema.hash", "Invalid lowercase hexadecimal " + name)
    return value


def relative_path(value):
    text(value, 400, "path")
    if "\\" in value or value.startswith("/") or re.search(r'[<>:"|?*]', value):
        fail("path.invalid", "Only portable relative paths are accepted.", value)
    parts = value.split("/")
    if any(p in ("", ".", "..") or p.endswith((".", " ")) or
           re.fullmatch(r"(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", p) for p in parts):
        fail("path.invalid", "Ambiguous or traversing path refused.", value)
    return value


def no_links(path):
    # Check the supplied spelling, including every parent: resolve() first would hide links.
    path = Path(path).absolute()
    for current in reversed((path, *path.parents)):
        try:
            info = current.lstat()
        except FileNotFoundError:
            fail("path.missing", "Path does not exist.", str(current))
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            fail("path.link", "Links and reparse points are refused.", str(current))
    return path


def root_path(path):
    path = no_links(path)
    if not path.is_dir():
        fail("path.root", "A directory root is required.", str(path))
    return path


def bounded_read(path, limit):
    path = no_links(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode):
        fail("path.file", "A regular file is required.", str(path))
    if before.st_size > limit:
        fail("bounds.file", "File exceeds the byte limit.", str(path))
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            fail("path.changed", "File changed while opening.", str(path))
        data = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    if len(data) > limit:
        fail("bounds.file", "File exceeds the byte limit.", str(path))
    no_links(path)
    current = path.stat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns
    ) or (opened.st_size, opened.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        fail("path.changed", "File changed during verification.", str(path))
    return data


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            fail("json.duplicate", "Duplicate JSON property: " + key)
        result[key] = value
    return result


def load_json(path):
    raw = bounded_read(path, MAX_MANIFEST_BYTES)
    try:
        value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=pairs,
                           parse_constant=lambda value: fail("json.constant", "Non-finite JSON number refused."))
        pending = [(value, 0)]
        nodes = 0
        while pending:
            item, depth = pending.pop()
            nodes += 1
            if depth > 16 or nodes > 20000:
                fail("json.depth", "JSON nesting or node limit exceeded.")
            children = item.values() if isinstance(item, dict) else item if isinstance(item, list) else ()
            pending.extend((child, depth + 1) for child in children)
        return value
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        fail("json.invalid", "Invalid UTF-8 JSON: " + type(error).__name__)


def manifest(path, kind):
    value = load_json(path)
    common = ("schema", "kind", "product", "files")
    exact_keys(value, common + (("repository", "commit") if kind == "canonical" else ("canonical", "adoption")))
    if type(value["schema"]) is not int or value["schema"] != 1 or value["kind"] != kind:
        fail("schema.version", "Unsupported manifest kind or schema.")
    if value["product"] not in PRODUCTS or kind == "canonical" and value["product"] != "domenia":
        fail("scope.product", "This product is outside the six-tool registry.")
    if kind == "canonical":
        canonical = value
    else:
        if value["adoption"] not in ("partial", "full"):
            fail("schema.adoption", "Adoption must be an explicit declaration: partial or full.")
        canonical = value["canonical"]
        exact_keys(canonical, ("repository", "commit"))
    if canonical["repository"] != CANONICAL:
        fail("scope.canonical", "Domenia V2 is the canonical UI source.")
    digest_text(canonical["commit"], HEX40, "commit")
    files = value["files"]
    if not isinstance(files, list) or not 1 <= len(files) <= MAX_FILES:
        fail("bounds.entries", "Manifest must declare 1 to 1024 files.")
    seen, upstream_seen = set(), {}
    for entry in files:
        required = ("path", "sha256") + (() if kind == "canonical" else ("upstreamPath", "upstreamSha256"))
        exact_keys(entry, required, () if kind == "canonical" else ("adaptation",))
        local = relative_path(entry["path"])
        if local.casefold() in seen:
            fail("path.duplicate", "Duplicate or case-colliding local paths.", local)
        seen.add(local.casefold())
        digest_text(entry["sha256"], HEX64, "sha256")
        if kind == "consumer":
            upstream = relative_path(entry["upstreamPath"])
            digest_text(entry["upstreamSha256"], HEX64, "upstreamSha256")
            previous = upstream_seen.get(upstream.casefold())
            if previous is not None and previous != (upstream, entry["upstreamSha256"]):
                fail("path.upstream_conflict", "Upstream casing or pinned hash is inconsistent.", upstream)
            # One canonical file can feed multiple explicitly declared product adapters.
            upstream_seen[upstream.casefold()] = (upstream, entry["upstreamSha256"])
            if "adaptation" in entry:
                text(entry["adaptation"], 2000, "adaptation")
            elif entry["sha256"] != entry["upstreamSha256"]:
                fail("schema.adaptation", "Different bytes require an explicit adaptation.", local)
    return value


def finding(code, path, expected=None, actual=None):
    value = {"code": code, "path": path}
    if expected is not None:
        value["expected"] = expected
    if actual is not None:
        value["actual"] = actual
    return value


def verify_files(root, files, budget):
    result = []
    for entry in files:
        path = root / entry["path"]
        try:
            data = bounded_read(path, min(MAX_FILE_BYTES, budget[0]))
        except InvalidInput as error:
            if error.code != "path.missing":
                raise
            result.append(finding("file.missing", entry["path"]))
            continue
        budget[0] -= len(data)
        actual = hashlib.sha256(data).hexdigest()
        if actual != entry["sha256"]:
            result.append(finding("file.changed", entry["path"], entry["sha256"], actual))
    return result


def check(root, manifest_path, canonical_root=None, canonical_manifest=None):
    root = root_path(root)
    value = manifest(manifest_path, "consumer")
    compared = canonical_root is not None and canonical_manifest is not None
    if (canonical_root is None) != (canonical_manifest is None):
        fail("arguments.canonical", "Both canonical root and manifest are required.")
    report = {
        "schema": 1, "tool": {"name": "m4d-components", "version": VERSION,
                             "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
        "product": value["product"], "adoption": {"declared": value["adoption"], "verified": False},
        "scope": "declared-files-only", "certification": False,
        "sourceCommit": {"value": value["canonical"]["commit"], "verification": "declared-not-git-proven"},
        "upstream": "checked" if compared else "not_checked",
        "filesChecked": len(value["files"]), "adaptations": sum("adaptation" in e for e in value["files"]),
        "findings": [], "notices": [],
    }
    budget = [MAX_TOTAL_BYTES]
    report["findings"] = verify_files(root, value["files"], budget)
    if compared:
        canonical_root = root_path(canonical_root)
        upstream = manifest(canonical_manifest, "canonical")
        report["findings"] += [dict(x, origin="canonical") for x in verify_files(canonical_root, upstream["files"], budget)]
        by_path = {e["path"]: e for e in upstream["files"]}
        report["comparedCommit"] = {"value": upstream["commit"], "verification": "declared-not-git-proven"}
        if value["canonical"]["commit"] != upstream["commit"]:
            report["notices"].append({"code": "upstream.revision_differs", "expected": value["canonical"]["commit"],
                                      "actual": upstream["commit"]})
        for entry in value["files"]:
            current = by_path.get(entry["upstreamPath"])
            if current is None:
                report["findings"].append(finding("upstream.missing", entry["upstreamPath"]))
            elif current["sha256"] != entry["upstreamSha256"]:
                report["findings"].append(finding("upstream.changed", entry["upstreamPath"],
                                                  entry["upstreamSha256"], current["sha256"]))
    report["status"] = "drift" if report["findings"] else "consistent"
    return report


def git(root, *arguments, raw=False):
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment.update(GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0", GIT_NO_LAZY_FETCH="1")
    completed = subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=not raw, timeout=30,
                               env=environment)
    return completed.stdout if raw else completed.stdout.strip()


def bundle_tool(output):
    """Bundle only the comparator and schema, never the private project registry or product data."""
    root = root_path(Path(__file__).parent.parent)
    selected = ("tools/components.py", "schemas/components.schema.json")
    if root_path(git(root, "rev-parse", "--show-toplevel")) != root:
        fail("bundle.repository", "The comparator must own its source repository root.")
    commit = git(root, "rev-parse", "HEAD")
    digest_text(commit, HEX40, "source commit")
    if git(root, "status", "--porcelain", "--", *selected):
        fail("bundle.dirty", "Commit comparator and schema before exporting.")
    if set(git(root, "ls-files", "--", *selected).splitlines()) != set(selected):
        fail("bundle.untracked", "Comparator and schema must be committed.")
    output = Path(output).absolute()
    root_path(output.parent)
    if output.exists() or output.is_symlink():
        fail("bundle.exists", "A new output directory is required.")
    entries = []
    payloads = []
    for relative in selected:
        data = bounded_read(root / relative, MAX_FILE_BYTES)
        if data != git(root, "show", "HEAD:" + relative, raw=True):
            fail("bundle.source_changed", "Source bytes differ from HEAD, regardless of index flags.", relative)
        name = Path(relative).name
        entries.append({"path": name, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
        payloads.append((name, data))
    if git(root, "rev-parse", "HEAD") != commit:
        fail("bundle.revision_changed", "Source commit changed during export preparation.")
    # mkdir is exclusive; on failure preserve the partial owned directory for diagnosis.
    output.mkdir()
    for name, data in payloads:
        with (output / name).open("xb") as stream:
            stream.write(data)
    lock = {"schema": 1, "tool": "m4d-components", "version": VERSION,
            "sourceRepository": "M4D135/m4d-admin-common", "sourceCommit": commit, "files": entries}
    with (output / "m4d-components.lock.json").open("x", encoding="utf-8") as stream:
        json.dump(lock, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    return {"schema": 1, "status": "exported", "toolLock": lock}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "compare"):
        command = commands.add_parser(name)
        command.add_argument("--root", required=True, type=Path)
        command.add_argument("--manifest", required=True, type=Path)
        if name == "compare":
            command.add_argument("--canonical-root", required=True, type=Path)
            command.add_argument("--canonical-manifest", required=True, type=Path)
    commands.add_parser("bundle-tool").add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "bundle-tool":
            report = bundle_tool(args.output)
        else:
            report = check(args.root, args.manifest, getattr(args, "canonical_root", None), getattr(args, "canonical_manifest", None))
        code = 1 if report["status"] == "drift" else 0
    except InvalidInput as error:
        report = {"schema": 1, "status": "invalid", "certification": False,
                  "findings": [{"code": error.code, "message": str(error), "path": error.path}]}
        code = 2
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report = {"schema": 1, "status": "invalid", "certification": False,
                  "findings": [{"code": "input.io", "message": type(error).__name__}]}
        code = 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())

