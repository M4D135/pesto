#!/usr/bin/env python3
"""RC4 source guards only. Does NOT execute PowerShell, .NET, WPF or AD."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import sys
from ps_lexical import functions, tokens

# The engine spread its functions across components that the core dot-sources. A checker indexing only
# Pesto-Core.ps1 died on KeyError at the first relocated term: it guarded nothing any more, and its own
# selftest turned that crash into a FileNotFoundError. The corpus is therefore the core plus every
# dot-sourced component, as in ux_static_checks.py; --wad points the guards at a mutated copy.
COMPONENT = re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")


def read_ps(path):
    return path.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source', type=Path)
    ap.add_argument('--wad', type=Path, help='engine components (default: <root>/wad)')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    root = args.root.resolve()
    raw = (args.source or root / 'wad/Pesto-Core.ps1').read_bytes()
    src = raw.decode('utf-8-sig').replace('\r\n', '\n')
    wad = args.wad or root / 'wad'
    texts = {'Pesto-Core.ps1': src}
    missing_components = []
    for name in COMPONENT.findall(src):
        if name in texts:
            continue
        component = wad / name
        if component.is_file():
            texts[name] = read_ps(component)
        else:
            missing_components.append(name)
    spans = {}
    duplicates = {}
    for file_name, text in texts.items():
        for function, span in functions(text).items():
            if function in spans:
                duplicates.setdefault(function, [spans[function][0]]).append(file_name)
            else:
                spans[function] = (file_name, span)
    checks = []

    def block(name):
        # A missing function is a FAIL, never an exception: a checker that crashes guards nothing, and
        # its own breakdown then looks like a broken toolchain instead of a lost guard.
        if name not in spans:
            raise AssertionError('Function absent from the corpus (core and components): ' + name)
        file_name, (a, b) = spans[name]
        return texts[file_name][a:b]

    def require(value, message):
        if not value:
            raise AssertionError(message)

    def check(name, action):
        try:
            detail = action()
            checks.append(dict(name=name, status='PASS', detail=detail))
        except Exception as exc:
            checks.append(dict(name=name, status='FAIL', detail=str(exc)))

    check('Core and its dot-sourced components are all present, each function defined once', lambda: require(
        not missing_components and not duplicates,
        'Missing components: ' + str(missing_components) + '; functions defined in several files: ' + str(duplicates)))

    def blocks(*names):
        # These bodies are bound once for readability. Resolving them eagerly would let one relocated
        # function kill the whole checker again, so an absent one is recorded as a FAIL and reads as an
        # empty body: every guard built on it then fails loudly instead of the checker disappearing.
        out = []
        for name in names:
            try:
                out.append(block(name))
            except AssertionError as exc:
                check('Function available to the guards: ' + name, lambda exc=exc: require(False, str(exc)))
                out.append('')
        return out

    atomic, decision, start, before, go, ui = blocks(
        'Write-PestoAtomicText', 'Get-PestoRenameMoveDecision', 'Start-PestoNextQueueTask',
        'Complete-PestoQueueNotStarted', 'Go', 'Check-SameOU')
    check('True null passed directly to File.Replace', lambda: require(
        '[IO.File]::Replace($tmp,$full,[System.Management.Automation.Language.NullString]::Value)' in atomic,
        'Missing explicit NullString.Value call'))
    check('Backup branch and first creation kept separate', lambda: require(
        "if ($Backup)" in atomic and "[IO.File]::Replace($tmp,$full,($full+'.bak'))" in atomic
        and '} else { [IO.File]::Move($tmp,$full) }' in atomic,
        'Backup/create branch changed'))
    check('Destination never deleted as a replacement fallback', lambda: require(
        '[IO.File]::Delete($full)' not in atomic and '[IO.File]::Delete($tmp)' in atomic
        and '$fs.Flush($true)' in atomic,
        'Destination deletion or durable temporary write changed'))
    check('Atomic write failures expose target and inner error', lambda: require(
        '[IO.IOException]::new(' in atomic and "pour '$full'" in atomic and ',$_.Exception)' in atomic,
        'Loss of actionable atomic-write error'))
    check('Site extracted from full conventional computer name', lambda: require(
        # The site is no longer read by a local regex: Get-PestoNameSiteCode delegates to the single
        # name parser, which is the only place the convention is written. Both halves are required, so
        # a reintroduced local extraction without the anchor cannot pass.
        'ConvertTo-PestoNameParts -Name $Name -CurrentName' in block('Get-PestoNameSiteCode')
        and 'return $parts.Site' in block('Get-PestoNameSiteCode')
        and "'^(?<Type>['+$types+'])(?<Prefix>[0-9]{6})(?<Site>[A-Z]{2})" in block('ConvertTo-PestoNameParts')
        and '$Name.Trim().ToUpperInvariant()' in block('ConvertTo-PestoNameParts'),
        'Site no longer read from the anchored single name parser'))
    check('Rename move flag derived from unequal site codes', lambda: require(
        '$r.Automatic=$true;$r.Move=$false' in decision and '$r.SiteChanged=($old -ine $new)' in decision
        and 'if($r.SiteChanged)' in decision and 'else {$r.Move=$true}' in decision,
        'Rename can move independently of a site change'))
    check('Already-target and invalid-target safeguards retained', lambda: require(
        'if($sameOU)' in decision and 'elseif(-not(Test-PestoOUPath $TargetOU))' in decision
        and "$r.Valid=$false;$r.Error='Changement de site" in decision,
        'Missing target validation'))
    check('Explicit move-only and local join are separate operations', lambda: require(
        # A standalone move stays distinct from a rename. The join is no longer dispatched by Go: out
        # of the domain Go returns 96 and sends the operator to the join page (the contract the RC4
        # suite is aligned on). GoJoinDomain must stay absent, otherwise the join could be coupled
        # back into the queue path.
        "if(-not $InDomain){$r.Move=$true;" in decision and 'if(-not $Rename)' in decision
        and 'return New-ActionResult 96' in go[:go.index('if($Renommer)')]
        and 'Ajouter au domaine' in go[:go.index('if($Renommer)')]
        and 'GoJoinDomain' not in go,
        'Standalone move or join was coupled to rename'))
    check('Nonconventional names use configured AD site containers', lambda: require(
        'Get-PestoSiteContainerDN $CurrentOU' in decision and 'Get-PestoSiteContainerDN $TargetOU' in decision
        and "$r.Valid=$false;$r.Error='Site actuel indeterminable" in decision
        and "Test-PestoDNWithinScope" in block('Get-PestoSiteContainerDN'),
        'Ambiguous site silently accepted'))
    check('UI computes and locks automatic move flag', lambda: require(
        '$ChkMove.IsChecked=[bool]$decision.Move' in ui and '$ChkMove.IsEnabled=$false' in ui
        and '$script:AutoMoveError=$decision.Error' in ui and 'finally {$script:Suspend=$prev}' in ui,
        'UI auto-plan or recursion guard changed'))
    check('Selecting a site does not force a standalone move', lambda: require(
        'if($script:INDOMAIN){$ChkMove.IsChecked=$false}' in block('Apply-SiteSelection')
        and 'if($script:INDOMAIN){$ChkMove.IsEnabled=$true;$ChkMove.IsChecked=$false;' in block('Apply-SiteSelection'),
        'Implicit standalone move selected'))
    for name, call in [('Add-Or-UpdateRow', 'Get-PestoRenameMoveDecision'),
                       ('Show-PestoQueuePreview', 'Update-PestoQueueRenamePlan'),
                       ('Run-Queue', 'Update-PestoQueueRenamePlan'),
                       ('Import-Queue', 'Get-PestoRenameMoveDecision'),
                       ('Go', 'Get-PestoRenameMoveDecision')]:
        check('Single decision integrated into ' + name,
              lambda name=name, call=call: require(call in block(name), 'Decision missing from ' + name))
    # The protected status list grows when the product gains a terminal state (VÉRIFIÉ was added after
    # this guard was written, which made it red on a legitimate strengthening). It now requires every
    # historical flag to still be protected: a status may be added, none may be dropped.
    HISTORICAL_FLAGS = ('OK', 'SIMULÉ', 'PARTIEL', 'PROTECTION', 'INCERTAIN', 'TECHNIQUE', 'EN COURS')

    def protected_flags(expression, body):
        found = re.search(re.escape(expression) + r'\s*@\(([^)]*)\)', body)
        require(found, 'Protected status list not found: ' + expression)
        listed = set(re.findall(r"'([^']*)'", found[1]))
        dropped = [flag for flag in HISTORICAL_FLAGS if flag not in listed]
        require(not dropped, 'Historical flags no longer protected: ' + str(dropped))
        return sorted(listed)

    check('Historical row flags are not silently rewritten', lambda: {
        'plan': protected_flags('$Row.Statut -notin', block('Update-PestoQueueRenamePlan')),
        'import': protected_flags('$oldStatus -notin', block('Import-Queue'))})
    check('Confirmation contains normalized rename and move counts', lambda: require(
        'Renommages : $renames | Déplacements : $moves' in block('Run-Queue')
        and block('Run-Queue').index('Update-PestoQueueRenamePlan') < block('Run-Queue').index('Confirm-YesNo'),
        'Plan normalized only after confirmation'))
    check('Worker never adds an unreviewed move', lambda: require(
        'if($decision.Move -and -not $Deplacer)' in go and 'return New-ActionResult 21' in go,
        'Extra mutation allowed without a confirmed plan'))
    sequence, = blocks('GoRenameAndMove')
    check('Move follows successful rename and absent result stops flow', lambda: require(
        sequence.index('$renameResult = RenameComputer') < sequence.index('$moveResult = MoveComputer')
        and 'if(-not $renameResult){return New-ActionResult 97' in sequence
        and '$renameResult.ExitCode -ne 20' in sequence,
        'Rename failure can reach move'))
    check('Partial and protection/uncertainty results retained', lambda: require(
        'return New-ActionResult 89' in sequence and 'return New-ActionResult 32' in sequence
        and 'return New-ActionResult 97' in sequence,
        'Partial outcome or safety result removed'))
    check('Local save failure classified before the async worker exists', lambda: require(
        "Save-PestoQueueCheckpoint -Phase 'Active'" in start
        and start.index('Complete-PestoQueueNotStarted -Failure $_') < start.index('Start-PestoAsyncOperation -Name')
        and start.count('Complete-PestoQueueNotStarted -Failure $_') == 1,
        'Pre-start boundary changed'))
    check('Not-started handler counts all pending rows without inventing a lock', lambda: require(
        before.count('$st.CancelCount++') == 2 and '-Code 96' in before
        and '$st.KoCount++' not in before and '$script:MutationUncertain=' not in before,
        'Local failure counted as mutation or lock reset'))
    check('Actual worker errors still activate existing safety stop', lambda: require(
        "-OnError {param($e) Complete-PestoQueueItem -Failure $e}" in start
        and 'if($code -in @(32,97,98))' in block('Complete-PestoQueueItem')
        and 'Stop-PestoQueueRemainingForSafety' in block('Complete-PestoQueueItem'),
        'Real worker safety path lost'))
    suite = (root / 'tests/Run-RC4Tests.ps1').read_text(encoding='utf-8-sig')
    def whitelist_check():
        m = re.search(r'\$load=@\((.*?)\)\s*foreach', suite, re.S)
        require(m, 'Native test whitelist not found')
        names = re.findall(r"'([^']+)'", m[1])
        require(all(n in spans for n in names), 'Whitelisted function missing from engine')
        require("Parser]::ParseFile" in suite and '. ([scriptblock]::Create($defs[$name]))' in suite,
                'Tests must load only the whitelisted function definitions')
        # PowerShell keywords are case-insensitive; detect unguarded source invocation separately.
        require(not re.search(r'(?m)^\s*[.&]\s+\$SourcePath\s*$', suite), 'Entire engine invoked by tests')
        for name in ['RenameComputer', 'MoveComputer', 'Get-ComputerOU', 'Start-PestoAsyncOperation', 'GoJoinDomain']:
            require('function ' + name + ' ' in suite, 'Mutation-capable function not mocked: ' + name)
        return dict(whitelisted_functions=len(names), native_cases=len(re.findall(r"(?m)^\s*Case '", suite)), executed=False)
    check('Native regression suite extracts functions and mocks external actions', whitelist_check)
    check('Native suite covers existing-file writes and pre-start integration', lambda: require(
        "[IO.File]::Replace($tmp,$old,$null)" in suite and 'for($i=0;$i -lt 100;$i++)' in suite
        and "Save-PestoQueueCheckpoint -Phase 'Idle'" in suite and 'Assert-Equal $script:WorkerStarts 0' in suite,
        'Targeted native regression cases removed'))
    cmd = (root / 'TEST_CORRECTIF.cmd').read_bytes()
    check('Test CMD is ASCII and chooses x64 STA with process-local policy', lambda: require(
        all(c < 128 for c in cmd) and b'Sysnative' in cmd and b'-STA -ExecutionPolicy RemoteSigned' in cmd
        and b'Run-RC4Tests.ps1' in cmd and b'%ERRORLEVEL%' in cmd,
        'Runner encoding or invocation changed'))
    build = (root / 'tools/Build-Pesto.ps1').read_text(encoding='utf-8-sig')
    check('Build aborts on every failing native step', lambda: require(
        build.count('if($LASTEXITCODE -ne 0){throw') >= 5
        and "throw 'EXE et composants non concordants.'" in build,
        'A failing native step can be ignored before build'))
    # Build-Pesto.ps1 runs no native suite any more: it compiles and checks the components against the
    # launcher manifest. The suites are invoked by TEST_CORRECTIF.cmd and Run-AllTests.ps1, so the
    # exit-code guarantee is guarded where it actually lives. It is no longer a property of the build.
    alltests = (root / 'tests/Run-AllTests.ps1').read_text(encoding='utf-8-sig')
    check('Native suites run outside the build and a failing one stops the run', lambda: require(
        'Run-RC4Tests.ps1' in alltests and 'if($LASTEXITCODE -ne 0){$failures.Add($suite)}' in alltests
        and "throw ('Suites en échec : '" in alltests,
        'A failing native suite no longer stops anything'))
    failed = sum(c['status'] == 'FAIL' for c in checks)
    report = dict(version='17.0-RC4', utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                  source_sha256=hashlib.sha256(raw).hexdigest(), files=sorted(texts),
                  scope='SOURCE GUARDS ONLY. No native parser, PowerShell binding, .NET file operations, WPF or AD execution.',
                  totals=dict(checks=len(checks), passed=len(checks)-failed, failed=failed), checks=checks)
    path = args.report or root / 'tests/rc4-static-report.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for c in checks:
        print(c['status']+' '+c['name']+(' : '+str(c['detail']) if c['status']=='FAIL' else ''))
    print(json.dumps(report['totals']))
    return int(failed > 0)


if __name__ == '__main__':
    sys.exit(main())
