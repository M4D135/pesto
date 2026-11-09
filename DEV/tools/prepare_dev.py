#!/usr/bin/env python3
"""Prepare a fresh DEV clone: create wad/cfg.json from tools/cfg.template.json when it is absent.

wad/cfg.json is excluded from Git so that a real configuration is never published. The template is the
non-configured model shipped since RC23 ("Configured": false). An existing wad/cfg.json is never read,
replaced or renamed. No compilation, download, UAC or AD call.
"""
from pathlib import Path
import sys

from refresh_manifest import safe_file, _is_link_or_junction

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = "tools/cfg.template.json"


def ensure_config(root: Path = ROOT) -> str:
    """Return 'present' or 'created'. Exclusive creation: an existing file, even a link, is left untouched."""
    root = Path(root)
    target = root / "wad" / "cfg.json"
    if target.is_symlink() or target.exists():
        return "present"
    if _is_link_or_junction(root / "wad"):
        raise ValueError("Linked wad directory: configuration was not created")
    template = root / TEMPLATE
    if template.is_symlink() or not template.is_file():
        raise FileNotFoundError(f"Template missing or linked: {TEMPLATE}")
    data = safe_file(root, TEMPLATE).read_bytes()
    try:
        with open(target, "xb") as handle:
            handle.write(data)
    except FileExistsError:
        return "present"
    return "created"


def check_pack_config(root: Path = ROOT, allow_config: bool = False) -> str:
    """Packs copy wad/cfg.json from the source. Refuse anything but the unconfigured template unless explicitly allowed."""
    root = Path(root)
    target = safe_file(root, "wad/cfg.json")
    # The source tree's own template, else this tool's (fixtures and older trees may not carry one).
    template_root = root if (root / TEMPLATE).is_file() or (root / TEMPLATE).is_symlink() else ROOT
    template = safe_file(template_root, TEMPLATE)
    if target.read_bytes() == template.read_bytes():
        return "template"
    if not allow_config:
        raise ValueError("wad/cfg.json differs from the unconfigured template: a real configuration would be published. "
                         "Use a clean DEV, or pass --allow-config deliberately.")
    return "custom"


if __name__ == "__main__":
    state = ensure_config(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT)
    print("wad/cfg.json " + ("created from " + TEMPLATE if state == "created" else "already present, left untouched"))
