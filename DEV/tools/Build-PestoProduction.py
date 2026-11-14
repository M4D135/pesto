#!/usr/bin/env python3
"""Rebuild PROD/Pesto.exe + the normal wad folder from a complete edited wad directory.

Offline; sources and previous distributions are never overwritten. Windows needs
Python 3.10+ and either LLVM (clang/lld-link) or Visual Studio C++ x64 + Windows SDK.
Validation uses Windows PowerShell 5.1, or PowerShell 7.4 on Mac/Linux.
The application is never launched by this script.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from refresh_manifest import runtime_files, safe_file, verify_runtime, _is_link_or_junction

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    completed = subprocess.run([str(p) for p in command], capture_output=True, text=True)
    if completed.returncode:
        raise RuntimeError((completed.stderr or completed.stdout).strip())
    return completed


def prepare_payload(wad_directory: Path, staging: Path, source: Path = ROOT):
    """Copy the closed runtime without executing the application's PowerShell."""
    wad_directory = Path(wad_directory).absolute()
    if _is_link_or_junction(wad_directory) or not wad_directory.is_dir():
        raise ValueError('Le dossier wad doit être un dossier complet, sans lien.')
    tools = Path(source) / 'tools'
    if _is_link_or_junction(tools):
        raise ValueError('Le dossier tools ne doit pas être un lien.')
    resolved_tools = tools.resolve(strict=True)
    resolved_staging = Path(staging).resolve(strict=False)
    if resolved_staging == resolved_tools or resolved_tools in resolved_staging.parents:
        raise ValueError('Le dossier temporaire doit être situé hors du dossier tools pour éviter une copie récursive.')
    # copytree follows links by default: reject every included tool component
    # before creating staging, including Windows junctions on Python 3.10/3.11.
    excluded = {'__pycache__', '.build', 'dist', 'logs', 'results'}
    for path in resolved_tools.rglob('*'):
        if any(part in excluded for part in path.relative_to(resolved_tools).parts):
            continue
        if _is_link_or_junction(path):
            raise ValueError('Composant tools lié : ' + str(path.relative_to(resolved_tools)))
    # runtime_files expects a parent containing wad. An external folder may have
    # any name, so parse its list in a tiny private staging root first.
    target_wad = staging / 'wad'
    target_wad.mkdir(parents=True)
    integrity = safe_file(wad_directory, 'Pesto-Integrity.ps1')
    shutil.copy2(integrity, target_wad / integrity.name)
    required = runtime_files(staging)
    for relative in (*required, 'wad/cfg.json', 'wad/support/DEBLOQUER_TOUT.cmd'):
        if relative == 'Pesto.exe':
            continue
        if not relative.startswith('wad/'):
            raise ValueError('Composant hors du dossier wad : ' + relative)
        origin = safe_file(wad_directory, relative[4:])
        destination = staging / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, destination)
    # This build-only declaration preserves CLI exports when regenerating the module.
    if (wad_directory / "Pesto.Engine.exports.json").exists():
        shutil.copy2(safe_file(wad_directory, "Pesto.Engine.exports.json"), target_wad / "Pesto.Engine.exports.json")
    # Only development tools are copied here; they never enter the PROD payload.
    shutil.copytree(tools, staging / 'tools', ignore=shutil.ignore_patterns('__pycache__', '.build', 'dist', 'logs', 'results'))
    return required


def build(wad_directory, output_directory, source=ROOT, powershell=None):
    source = Path(source).resolve(strict=True)
    wad_directory = Path(wad_directory).absolute()
    output_directory = Path(output_directory).absolute()
    if output_directory.exists() or output_directory.is_symlink():
        raise FileExistsError('Le dossier de sortie existe. Choisissez une nouvelle destination.')
    output_directory = output_directory.resolve(strict=False)
    resolved_wad = wad_directory.resolve(strict=True)
    if output_directory == resolved_wad or resolved_wad in output_directory.parents:
        raise ValueError('La sortie doit être située hors du dossier wad.')
    # The same-parent staging directory is later populated with a copy of tools.
    # Resolve parent aliases before refusing a destination inside that source.
    resolved_tools = (source / 'tools').resolve(strict=True)
    if output_directory == resolved_tools or resolved_tools in output_directory.parents:
        raise ValueError('La sortie doit être située hors du dossier tools pour éviter une copie récursive.')
    host = powershell or os.environ.get('PESTO_BUILD_PWSH') or shutil.which('powershell' if os.name == 'nt' else 'pwsh')
    if not host:
        raise RuntimeError('PowerShell introuvable. Sur Mac : préciser --powershell ou PESTO_BUILD_PWSH (7.4 minimum).')
    llvm = bool(shutil.which('clang') and shutil.which('lld-link'))
    msvc = os.name == 'nt' and all(shutil.which(tool) for tool in ('cl.exe', 'rc.exe', 'link.exe'))
    if not llvm and not msvc:
        raise RuntimeError('Compilation C : installer clang + lld-link, ou lancer depuis Developer PowerShell for VS x64 (C++ et Windows SDK). Aucun téléchargement automatique.')
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.pesto-rebuild-', dir=output_directory.parent) as temporary:
        stage = Path(temporary) / 'DEV'
        required = prepare_payload(wad_directory, stage, source)
        engine_builder = stage / 'tools/Build-PestoEngineModule.ps1'
        if engine_builder.is_file():
            run([host, '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', engine_builder, '-Root', stage])
        print('1/4 Sources copiées ; contrôle de syntaxe et de configuration.', flush=True)
        run([host, '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', source / 'tools/Validate-PestoBuild.ps1', '-Root', stage])
        print('2/4 Recompilation du lanceur natif et des empreintes.', flush=True)
        if llvm:
            run([sys.executable, stage / 'tools/launcher/build_native.py'])
            run([sys.executable, stage / 'tools/refresh_manifest.py', '--root', stage])
            payload = Path(temporary) / 'payload'
            for relative in (*required, 'wad/package.json', 'wad/cfg.json', 'wad/support/DEBLOQUER_TOUT.cmd'):
                destination = payload / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(safe_file(stage, relative), destination)
        else:
            payload = Path(temporary) / 'payload'
            run([host, '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', stage / 'tools/Build-Pesto.ps1', '-OutputDirectory', payload, '-PythonPath', sys.executable])
        verify_runtime(payload)
        print('3/4 Vérification de la distribution classique.', flush=True)
        if {path.name for path in payload.iterdir()} != {'Pesto.exe', 'wad'}:
            raise ValueError('La racine PROD doit contenir Pesto.exe et le dossier wad.')
        from refresh_manifest import file_hash
        report = {'Version': '1.0', 'RuntimeFiles': len(required), 'ExeSHA256': file_hash(payload / 'Pesto.exe'), 'RuntimeVerification': 'PASS', 'WindowsExecuted': False, 'ADExecuted': False}
        # Reserve the new destination exclusively after all checks have passed,
        # then move its two children and clean up this owned directory on failure.
        output_directory.mkdir()
        try:
            for path in payload.iterdir():
                shutil.move(str(path), output_directory / path.name)
        except BaseException:
            shutil.rmtree(output_directory)
            raise
        print('4/4 PROD généré : Pesto.exe + dossier wad. Sources conservées.', flush=True)
        report['NativeCompiler'] = 'LLVM clang/lld' if llvm else 'MSVC x64/Windows SDK'
        report['SourceWad'] = str(resolved_wad)
        report['OutputDirectory'] = str(output_directory)
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wad', nargs='?', type=Path, default=ROOT / 'wad', help='Dossier wad complet ; son cfg.json sera inclus.')
    parser.add_argument('--output', type=Path, help='Nouveau dossier PROD, jamais écrasé.')
    parser.add_argument('--powershell', help='Chemin du moteur PowerShell de compilation.')
    arguments = parser.parse_args()
    destination = arguments.output or ROOT.parent / ('Pesto_PROD_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
    try:
        report = build(arguments.wad, destination, powershell=arguments.powershell)
    except (OSError, ValueError, RuntimeError, TypeError, KeyError) as error:
        parser.exit(1, 'Fabrication refusée : ' + str(error) + '\n')
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
