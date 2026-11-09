"""RC21 portable checks on shipped files and build contracts.

These execute Python, validate XML/lexical structure and inspect the built PE.
They do not execute PowerShell, WPF, the CLR, UAC or any Active Directory action.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
sys.path.insert(0,str(ROOT/'tests'))
from refresh_manifest import runtime_files, verify_native_binding, verify_runtime
from package_distribution import distribution_files
from ps_lexical import functions, tokens

class RC21(unittest.TestCase):
    def text(self, name):
        return (ROOT/name).read_text('utf-8-sig')

    def body(self, file, function):
        value=self.text('wad/'+file)
        return value[slice(*functions(value)[function])]

    def test_all_new_modules_are_pinned_in_the_actual_executable(self):
        pinned=verify_native_binding(ROOT)
        for name in ('Contracts.ps1','Policy.ps1','Names.ps1','Workspace.ps1','Recovery.ps1','LogWriter.cs'):
            path='wad/Pesto-'+name
            self.assertIn(path,pinned)
        self.assertEqual(set(pinned),set(runtime_files(ROOT))-{'Pesto.exe'})

    def test_actual_pack_still_passes_integrity(self):
        verify_runtime(ROOT)

    def test_prod_root_and_optional_support(self):
        prod=distribution_files(ROOT,'PROD')
        self.assertEqual({p.split('/')[0] for p in prod},{'Pesto.exe','wad'})
        self.assertIn('wad/support/DEBLOQUER_TOUT.cmd',prod)
        self.assertNotIn('wad/support/DEBLOQUER_TOUT.cmd',runtime_files(ROOT))
        self.assertFalse(any(p.startswith(('tests/','tools/','wad/maintenance/')) for p in prod))

    def test_dev_includes_the_release_gate_test_targets(self):
        dev=set(distribution_files(ROOT,'DEV'))
        for target in ('tests/Pesto.RC21.Tests.ps1','tests/Run-Pesto21Tests.ps1','tests/Run-NamesLoadingTests.ps1','tools/Sign-PestoRelease.ps1','tools/Initialize-Coordination.ps1'):
            self.assertIn(target,dev)
        gate=self.text('tools/Verify-Release.ps1')
        self.assertIn('Pesto.RC21.Tests.ps1',gate)
        self.assertIn('SkippedCount',gate)
        self.assertIn('PublicReleaseAuthorized=$false',gate)

    def test_new_powershell_files_lexically_balanced(self):
        for path in ('tests/Pesto.RC21.Tests.ps1','tests/Run-Pesto21Tests.ps1','tools/Sign-PestoRelease.ps1','tools/Initialize-Coordination.ps1'):
            tokens(self.text(path))

    def test_current_shell_has_unique_names_and_expected_help(self):
        tree=ET.fromstring(self.text('wad/Pesto-Shell.xaml'))
        names={}
        def visual_elements(node):
            # Templates own a separate namescope; repeated PART names there are valid WPF.
            if node.tag.rsplit('}',1)[-1] in ('Window.Resources','ControlTemplate','DataTemplate','ItemsPanelTemplate'):
                return
            yield node
            for child in node:
                yield from visual_elements(child)
        for element in visual_elements(tree):
            name=element.attrib.get('{http://schemas.microsoft.com/winfx/2006/xaml}Name')
            if name:
                self.assertNotIn(name,names)
                names[name]=element
        for name in ('NmPrevPage','NmNextPage','NmStrategy','NmSuggestions','NmVerifyCandidate','NmUseCandidate','PrepList','PrepName','HomeInterventions'):
            self.assertIn(name,names)
            self.assertTrue(names[name].attrib.get('ToolTip'),name)

    def test_names_calculation_reuses_index_and_materializes_only_page(self):
        body=self.body('Pesto-Core.ps1','Invoke-PestoBuildNamesView')
        self.assertIn('$index=$Request.CachedIndex',body)
        self.assertIn('if($null -eq $index)',body)
        self.assertIn('$matched -ge $offset -and $rows.Count -lt $size',body)
        self.assertIn('$Request.Cancellation.Cancelled',body)
        self.assertIn("'Occupé dans AD'",body)
        self.assertIn("'Préparé dans la file'",body)
        self.assertIn("'AfterLast'",body)

    def test_received_receipts_are_closed_and_recheck_plan_fingerprint(self):
        body=self.body('Pesto-Safety.ps1','Read-PestoIntervention')
        self.assertIn('Assert-PestoClosedObject $r ',body)
        self.assertIn('Assert-PestoClosedObject $r.Plan ',body)
        self.assertIn('(Get-PestoPlanFingerprint $r.Plan) -cne $r.PlanFingerprint',body)
        self.assertIn("'Owner','ResumeFrom'",body)
        self.assertIn('$r.ResultCode -isnot [int]',body)

    def test_shared_locks_use_exclusive_create_and_no_timeout_unlock(self):
        enter=self.body('Pesto-Policy.ps1','Enter-PestoCoordination')
        leave=self.body('Pesto-Policy.ps1','Exit-PestoCoordination')
        self.assertIn('[IO.FileMode]::CreateNew',enter)
        self.assertIn('Aucune expiration automatique',enter)
        self.assertIn("$Receipt.Phase -notin @('Failed','Verified')",leave)
        self.assertIn('$entry.OperationId -ne $Receipt.OperationId',leave)

    def test_log_writer_is_bounded_and_receipts_do_not_use_it(self):
        writer=self.text('wad/Pesto-LogWriter.cs')
        self.assertIn('new BlockingCollection<Entry>',writer)
        self.assertIn('queue.TryAdd',writer)
        self.assertIn('TaskCompletionSource<bool>',writer)
        for file,fn in (('Pesto-Safety.ps1','Write-PestoIntervention'),('Pesto-Join.ps1','Write-PestoJoinReceipt')):
            body=self.body(file,fn)
            self.assertNotIn('AsyncAuditWriter',body)
            self.assertNotIn('TryWrite(',body)

    def test_frozen_plans_are_rechecked_in_each_mutation_worker(self):
        for path in ('wad/Pesto-Direct.ps1','wad/Pesto-Core.ps1','wad/Pesto-Join.ps1'):
            self.assertIn('Confirmed',self.text(path))
        body=self.body('Pesto-Contracts.ps1','Assert-PestoConfirmedPlan')
        self.assertIn('Get-PestoPlanFingerprint',body)
        self.assertIn('$Plan.ConfigStamp -cne $ConfigurationStamp',body)

    def test_executable_contains_new_command_paths(self):
        binary=(ROOT/'Pesto.exe').read_bytes()
        for option in ('--consult','--validate-plan','--check-json'):
            self.assertIn(option.encode('utf-16le'),binary)
        self.assertIn('Consult'.encode('utf-16le'),binary)

    def test_live_observation_is_read_only_and_local_health_is_not_ssodata(self):
        body=self.body('Pesto-Inspection.ps1','Get-PestoLocalHealth')
        self.assertIn('/status',body)
        self.assertNotIn('/leave',body)
        self.assertNotRegex(body,r'Test-ComputerSecureChannel[^\n]*-Repair')
        self.assertIn('SSO',body)

    def test_signing_never_installs_trust_and_requires_explicit_certificate(self):
        body=self.text('tools/Sign-PestoRelease.ps1')
        self.assertIn('Thumbprint',body)
        self.assertIn('Set-AuthenticodeSignature',body)
        self.assertNotIn('Import-Certificate',body)
        self.assertNotIn('New-SelfSignedCertificate',body)
        self.assertNotIn('Install-Module',body)

    def test_developer_gate_never_fetches_dependencies_during_app_start(self):
        for path in (ROOT/'wad').glob('Pesto-*.ps1'):
            self.assertNotRegex(path.read_text('utf-8-sig'),r'\b(?:Install-Module|Install-Package|Invoke-WebRequest)\b',path.name)
        gate=self.text('tools/Verify-Release.ps1')
        self.assertIn('-RequiredVersion 5.7.1',gate)
        self.assertIn('-RequiredVersion 1.24.0',gate)

    def test_cli_and_native_fixture_counts_match(self):
        runner=self.text('tools/checks/run_native_portable.py')
        count=int(re.search(r'for i in range\((\d+)\):',runner).group(1))
        self.assertGreaterEqual(count,46)
        self.assertIn('PASS: '+str(count)+' C entry scenarios',runner)
        c=self.text('tools/launcher/test_entry.c')
        for n in range(count):
            self.assertRegex(c,rf'case\s+{n}\s*:')
        self.assertNotRegex(c,rf'case\s+{count}\s*:')

    def test_current_version_file_drives_native_build(self):
        version=json.loads(self.text('tools/version.json'))
        self.assertEqual((version['major'],version['minor'],version['channel']),(1,0,'Final'))
        from release_version import VERSION,FILE_VERSION
        self.assertEqual(VERSION,'1.0')
        self.assertEqual(FILE_VERSION,'1.0.0.0')
        self.assertIn('release_version',self.text('tools/launcher/build_native.py'))

if __name__=='__main__':unittest.main(verbosity=2)
