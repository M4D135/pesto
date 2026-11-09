"""Release tooling behaviour with isolated synthetic payloads; no GUI, AD or signing."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import release_assurance as release
import managed_install as managed
import update_channels as rings
import qualification
import check_toolchain
import scan_evidence
import rebind_signed_engine as rebind
from refresh_manifest import validate_runtime_relative
from refresh_manifest import write_manifest, file_hash


def fixture(root):
    (root/'wad/support').mkdir(parents=True)
    (root/'tools/launcher').mkdir(parents=True)
    paths=['Pesto.exe','wad/Pesto-Integrity.ps1','wad/Pesto-Fixture.ps1','wad/common.lock.json']
    (root/'wad/Pesto-Integrity.ps1').write_text("# BEGIN Pesto_RUNTIME_FILES\n@(\n"+','.join("'"+p+"'" for p in paths)+"\n)\n# END Pesto_RUNTIME_FILES\n")
    (root/'wad/Pesto-Fixture.ps1').write_text('# non executable fixture')
    (root/'wad/common.lock.json').write_text('{}')
    (root/'wad/cfg.json').write_text('{"Configured":false}')
    (root/'tools/cfg.template.json').write_bytes((root/'wad/cfg.json').read_bytes())
    (root/'wad/support/DEBLOQUER_TOUT.cmd').write_text('@exit /b 0')
    binding='PESTO_BINDING_V1\n'+''.join(p+'|'+file_hash(root/p)+'\n' for p in paths[1:])+'PESTO_BINDING_END'
    (root/'Pesto.exe').write_bytes(binding.encode())
    write_manifest(root)
    return root


class Release120Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.source=fixture(self.root/'source')
    def make_catalogue(self):
        identity={'version':'1.0','exeSHA256':file_hash(self.source/'Pesto.exe'),'manifestSHA256':file_hash(self.source/'wad/package.json')}
        path=self.root/'rings.json';path.write_text(json.dumps({'schema':1,'rings':{'pilot':identity,'general':identity}}));return path
    def test_sbom_contains_exact_runtime_hashes_not_configuration(self):
        output=self.root/'report';release.generate(self.source,output)
        data=json.loads((output/'sbom.cdx.json').read_text())
        self.assertEqual(data['specVersion'],'1.6');self.assertEqual(data['bomFormat'],'CycloneDX')
        self.assertEqual(len(data['components']),4);self.assertNotIn('wad/cfg.json',[c['name'] for c in data['components']])
    def test_provenance_never_claims_signature_or_windows(self):
        result=release.generate(self.source,self.root/'report')
        self.assertEqual(result['signature'],'NOT_VERIFIED');self.assertEqual(result['attestation'],'UNSIGNED_STATEMENT')
        self.assertEqual(result['qualifications']['AD'],'NOT_INFERRED')
    def test_release_output_existing_preserved(self):
        output=self.root/'report';output.mkdir();(output/'canary').write_text('keep')
        with self.assertRaises(FileExistsError):release.generate(self.source,output)
        self.assertEqual((output/'canary').read_text(),'keep')
    def test_output_inside_source_refused(self):
        with self.assertRaises(ValueError):release.generate(self.source,self.source/'out')
    def test_stale_build_record_refused(self):
        (self.source/'tools/launcher/last-build.json').write_text('{"SHA256":"bad"}')
        with self.assertRaises(ValueError):release.generate(self.source,self.root/'report')
        self.assertFalse((self.root/'report').exists())
    def test_metadata_deterministic_for_same_input(self):
        with mock.patch.object(release,'source_identity',return_value={'commit':None,'dirty':None}):
            release.generate(self.source,self.root/'a');release.generate(self.source,self.root/'b')
        for path in (self.root/'a').iterdir():self.assertEqual(path.read_bytes(),(self.root/'b'/path.name).read_bytes())
    def test_compare_identical_supplied_builds(self):self.assertTrue(release.compare_builds(self.source,self.source)['identical'])
    def test_raw_evidence_stays_raw(self):
        report=self.root/'failed.json';report.write_text('{"Failed":1}')
        data=release.evidence_envelope(report,'portable-doubles','a'*64,True)
        self.assertEqual(data['scope'],'portable-doubles');self.assertNotIn('PASS',data.values());self.assertEqual(report.read_text(),'{"Failed":1}')
    def test_evidence_requires_exact_build(self):
        with self.assertRaises(ValueError):release.evidence_envelope(self.root/'x','portable-doubles','latest',False)
    def test_invalid_scope_refused(self):
        with self.assertRaises(ValueError):release.evidence_envelope(self.root/'x','all-validated','a'*64,True)
    def test_managed_install_detect_uninstall_preserves_configuration_and_unknown_files(self):
        target=self.root/'installed';managed.install(self.source,target)
        self.assertTrue(managed.detect(target)['healthy'])
        (target/'wad/cfg.json').write_text('private configuration')
        (target/'wad/private-note.txt').write_text('keep')
        self.assertFalse(managed.uninstall(target)['executed']);self.assertTrue((target/'Pesto.exe').exists())
        with mock.patch.object(managed,'check_local_states'),mock.patch.object(managed,'mutation_guard',contextlib.nullcontext):
            self.assertTrue(managed.uninstall(target,True)['executed'])
        self.assertEqual((target/'wad/cfg.json').read_text(),'private configuration');self.assertEqual((target/'wad/private-note.txt').read_text(),'keep')
        self.assertFalse(managed.detect(target)['installed'])
    def test_managed_modified_code_never_removed(self):
        target=self.root/'installed';managed.install(self.source,target);(target/'wad/Pesto-Fixture.ps1').write_text('local edit')
        with self.assertRaises(ValueError):managed.uninstall(target,True)
        self.assertTrue((target/'Pesto.exe').exists())
    def test_managed_existing_destination_preserved(self):
        with self.assertRaises(ValueError):managed.install(self.source,self.source)
    def test_managed_mutation_guard_prevents_deletion(self):
        target=self.root/'installed';managed.install(self.source,target)
        with mock.patch.object(managed,'mutation_guard',side_effect=ValueError('active')):
            with self.assertRaises(ValueError):managed.uninstall(target,True)
        self.assertTrue((target/'Pesto.exe').exists())
    def test_uninstall_conflicting_update_fence_preserved(self):
        target=self.root/'installed';managed.install(self.source,target);(target/'.pesto-update.lock').write_text('owner')
        with mock.patch.object(managed,'check_local_states'),mock.patch.object(managed,'mutation_guard',contextlib.nullcontext):
            with self.assertRaises(FileExistsError):managed.uninstall(target,True)
        self.assertEqual((target/'.pesto-update.lock').read_text(),'owner');self.assertTrue((target/'Pesto.exe').exists())
    def test_ring_requires_exact_supplied_artifact(self):self.assertEqual(rings.select(self.make_catalogue(),'pilot',self.source)['ring'],'pilot')
    def test_ring_invalid_hash_refused(self):
        path=self.make_catalogue();data=json.loads(path.read_text());data['rings']['pilot']['exeSHA256']='b'*64;path.write_text(json.dumps(data))
        with self.assertRaises(ValueError):rings.select(path,'pilot',self.source)
    def test_unknown_ring_refused(self):
        with self.assertRaises(ValueError):rings.select(self.make_catalogue(),'automatic',self.source)
    def test_qualification_all_starts_not_run(self):
        data=qualification.plan('a'*64);self.assertGreater(len(data['cases']),25);self.assertEqual({c['status'] for c in data['cases']},{'NOT_RUN'})
    def test_qualification_cannot_pass_without_evidence(self):
        path=self.root/'plan.json';path.write_text(json.dumps(qualification.plan('a'*64)))
        with self.assertRaises(ValueError):qualification.record(path,'gui/first-run-import','PASS','looks good',[])
    def test_qualification_preserves_original_and_prevents_overwriting_case(self):
        path=self.root/'plan.json';path.write_text(json.dumps(qualification.plan('a'*64)));before=path.read_bytes()
        image=self.root/'capture.png';image.write_bytes(b'fixture')
        result=qualification.record(path,'gui/first-run-import','PASS','observed fixture',[image]);self.assertEqual(path.read_bytes(),before)
        path.write_text(json.dumps(result))
        with self.assertRaises(ValueError):qualification.record(path,'gui/first-run-import','FAIL','changed',[image])
    def test_secret_canary_report_does_not_repeat_value(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'error.log').write_text('password=CANARY_PRIVATE_123')
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['status'],'FAIL');self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_cli_accepts_bom_on_first_canary(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'error.log').write_text('CANARY_PRIVATE_123')
        canaries=self.root/'canaries.txt';canaries.write_text('CANARY_PRIVATE_123\n',encoding='utf-8-sig')
        output=io.StringIO()
        with contextlib.redirect_stdout(output):code=scan_evidence.main([str(evidence),'--canary-file',str(canaries)])
        self.assertEqual(code,1);self.assertEqual(json.loads(output.getvalue())['status'],'FAIL')
        self.assertNotIn('CANARY_PRIVATE_123',output.getvalue())
    def test_secret_scan_read_error_is_unexamined_without_raw_exception(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'CANARY_PRIVATE_123.log').write_text('fixture')
        with mock.patch.object(Path,'read_bytes',side_effect=OSError('secret path CANARY_PRIVATE_123')):
            report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['status'],'INCOMPLETE');self.assertEqual(report['ioErrors'],1)
        self.assertEqual(report['textFilesExamined'],0);self.assertEqual(report['unexamined'],['[***].log'])
        self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_stat_error_is_unexamined_without_raw_exception(self):
        evidence=self.root/'evidence';evidence.mkdir();target=evidence/'CANARY_PRIVATE_123.log';target.write_text('fixture')
        target=target.resolve()
        original=Path.lstat
        def failing_stat(path,*args,**kwargs):
            if path==target:raise OSError('secret path CANARY_PRIVATE_123')
            return original(path,*args,**kwargs)
        with mock.patch.object(Path,'lstat',failing_stat):report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['unexamined'],['[***].log']);self.assertEqual(report['ioErrors'],1)
        self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_directory_error_callback_is_reported(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'normal.log').write_text('ordinary')
        def failed_walk(root,onerror,followlinks):
            onerror(PermissionError(13,'secret CANARY_PRIVATE_123',str(root/'CANARY_PRIVATE_123')))
            return iter([(str(root),[],['normal.log'])])
        with mock.patch.object(scan_evidence.os,'walk',side_effect=failed_walk):report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['unexamined'],['[***]']);self.assertEqual(report['textFilesExamined'],1)
        self.assertEqual(report['status'],'INCOMPLETE');self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_enumeration_exception_is_reported(self):
        evidence=self.root/'evidence';evidence.mkdir()
        with mock.patch.object(scan_evidence.os,'walk',side_effect=OSError('secret CANARY_PRIVATE_123')):
            report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['unexamined'],['.']);self.assertEqual(report['ioErrors'],1)
        self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_root_io_error_is_reported(self):
        with mock.patch.object(Path,'lstat',side_effect=OSError('secret CANARY_PRIVATE_123')):
            report=scan_evidence.scan(self.root/'CANARY_PRIVATE_123',['CANARY_PRIVATE_123'])
        self.assertEqual(report['status'],'INCOMPLETE');self.assertEqual(report['unexamined'],['.'])
        self.assertNotIn('CANARY_PRIVATE_123',json.dumps(report))
    def test_secret_scan_cli_input_error_has_no_trace_or_sensitive_path(self):
        evidence=self.root/'evidence';evidence.mkdir();output=io.StringIO();errors=io.StringIO()
        with mock.patch.object(Path,'read_text',side_effect=OSError('secret CANARY_PRIVATE_123')):
            with contextlib.redirect_stdout(output),contextlib.redirect_stderr(errors):
                code=scan_evidence.main([str(evidence),'--canary-file',str(self.root/'CANARY_PRIVATE_123.txt')])
        self.assertEqual(code,2);self.assertEqual(json.loads(output.getvalue())['unexamined'],['.'])
        self.assertEqual(errors.getvalue(),'');self.assertNotIn('CANARY_PRIVATE_123',output.getvalue())
    def test_secret_scan_masks_hit_and_unexamined_paths_stably(self):
        evidence=self.root/'evidence';folder=evidence/'CANARY_PRIVATE_123';folder.mkdir(parents=True)
        (folder/'CANARY_SECOND_456.log').write_text('CANARY_PRIVATE_123')
        (folder/'CANARY_SECOND_456.png').write_bytes(b'fixture')
        canaries=['CANARY_PRIVATE_123','CANARY_SECOND_456']
        report=scan_evidence.scan(evidence,canaries)
        self.assertEqual(report,scan_evidence.scan(evidence,canaries))
        self.assertEqual(report['hits'],[{'path':'[***]/[***].log','matches':1}])
        self.assertEqual(report['unexamined'],['[***]/[***].png'])
        for canary in canaries:self.assertNotIn(canary,json.dumps(report))
    def test_secret_scan_masking_does_not_reintroduce_another_canary(self):
        canaries=['zone/[***]/file.log','CANARY_PRIVATE_123']
        masked=scan_evidence._masked_path('zone/CANARY_PRIVATE_123/file.log',canaries)
        self.assertEqual(masked,'[***]')
        for canary in canaries:self.assertNotIn(canary,masked)
    def test_secret_scan_decodes_windows_utf16(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'windows.log').write_text('CANARY_PRIVATE_123',encoding='utf-16')
        self.assertEqual(len(scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])['hits']),1)
    def test_secret_scan_decodes_utf16_big_endian_with_bom(self):
        evidence=self.root/'evidence';evidence.mkdir()
        (evidence/'windows.log').write_bytes(b'\xfe\xff'+'CANARY_PRIVATE_123'.encode('utf-16-be'))
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['textFilesExamined'],1);self.assertEqual(len(report['hits']),1)
    def test_secret_scan_bomless_utf16_is_unexamined(self):
        evidence=self.root/'evidence';evidence.mkdir()
        for encoding in ('utf-16-le','utf-16-be'):
            (evidence/(encoding+'.log')).write_bytes('CANARY_PRIVATE_123'.encode(encoding))
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['textFilesExamined'],0);self.assertEqual(report['hits'],[])
        self.assertEqual(report['unexamined'],['utf-16-be.log','utf-16-le.log'])
        self.assertNotEqual(report['status'],'PASS')
    def test_secret_scan_utf8_with_nul_is_unexamined(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'binary.log').write_bytes(b'ordinary\x00text')
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['textFilesExamined'],0);self.assertEqual(report['unexamined'],['binary.log'])
    def test_secret_scan_invalid_utf8_is_unexamined(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'invalid.log').write_bytes(b'\xffCANARY_PRIVATE_123')
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
        self.assertEqual(report['textFilesExamined'],0);self.assertEqual(report['unexamined'],['invalid.log'])
    def test_secret_scan_refuses_file_root(self):
        evidence=self.root/'error.log';evidence.write_text('CANARY_PRIVATE_123')
        with self.assertRaisesRegex(ValueError,'directory'):scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
    def test_secret_scan_refuses_link_root(self):
        evidence=self.root/'evidence';evidence.mkdir();link=self.root/'linked';link.symlink_to(evidence,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'Linked evidence root'):scan_evidence.scan(link,['CANARY_PRIVATE_123'])
    def test_secret_scan_refuses_linked_child(self):
        evidence=self.root/'evidence';evidence.mkdir();outside=self.root/'outside.log';outside.write_text('CANARY_PRIVATE_123')
        (evidence/'linked.log').symlink_to(outside)
        with self.assertRaisesRegex(ValueError,'Linked evidence'):scan_evidence.scan(evidence,['CANARY_PRIVATE_123'])
    def test_secret_scan_does_not_claim_images_examined(self):
        evidence=self.root/'evidence';evidence.mkdir();(evidence/'capture.png').write_bytes(b'fixture')
        report=scan_evidence.scan(evidence,['CANARY_PRIVATE_123']);self.assertEqual(report['unexamined'],['capture.png']);self.assertNotEqual(report['status'],'PASS')
    def test_only_engine_build_json_is_runtime_exception(self):
        validate_runtime_relative('wad/Pesto.Engine.build.json')
        for name in ('wad/Pesto.Engine.exports.json','wad/cfg.json','wad/other.json'):
            with self.assertRaises(ValueError):validate_runtime_relative(name)
    def test_signed_engine_rebind_preserves_runtime_bytes(self):
        wad=self.source/'wad';runtime=wad/'Pesto.Engine.Runtime.ps1';runtime.write_bytes(b'fixture signed runtime')
        module=wad/'Pesto.Engine.psm1';module.write_bytes(b"\xef\xbb\xbfif($x.Hash -ine '"+b'a'*64+b"'){throw 'bad'}\r\n")
        metadata=wad/'Pesto.Engine.build.json';metadata.write_text(json.dumps({'Schema':1,'RuntimeSHA256':'a'*64}))
        digest=rebind.rebind(self.source)
        self.assertEqual(runtime.read_bytes(),b'fixture signed runtime');self.assertIn(digest,module.read_text(encoding='utf-8-sig'));self.assertEqual(json.loads(metadata.read_text(encoding='utf-8-sig'))['RuntimeSHA256'],digest)
    def test_rebind_refuses_already_signed_module(self):
        wad=self.source/'wad';(wad/'Pesto.Engine.Runtime.ps1').write_text('fixture');(wad/'Pesto.Engine.psm1').write_text('# SIG # Begin signature block');(wad/'Pesto.Engine.build.json').write_text('{}')
        with self.assertRaises(ValueError):rebind.rebind(self.source)
    def test_development_includes_adapter_formats(self):
        from package_distribution import DEV_SUFFIXES,DEV_TREES
        self.assertIn('integrations',DEV_TREES)
        self.assertTrue({'.psm1','.psd1','.admx','.adml'}.issubset(DEV_SUFFIXES))
    def test_pack_identity_in_release_dossier(self):
        pack=self.root/'Pesto_PROD.zip';pack.write_bytes(b'fixture archive')
        data=release.generate(self.source,self.root/'report',packs=[pack])
        self.assertEqual(data['packs'][0]['sha256'],file_hash(pack))
    def test_workflow_placed_at_repository_root_and_runs_on_push(self):
        repo=ROOT.parent if (ROOT.parent/'.github/workflows/validate.yml').is_file() else ROOT
        text=(repo/'.github/workflows/validate.yml').read_text();self.assertIn('branches: [master]',text);self.assertIn('tests/Run-AllTests.ps1',text);self.assertNotIn("@('Zoom','ToolsTabs','Ux')",text)
        # The standalone DEV pack must carry the same jobs, with its root paths adapted.
        if repo != ROOT:
            standalone = text.replace('DEV/', '').replace('-Root DEV', '-Root .').replace('--root DEV', '--root .').replace('--source DEV', '--source .').replace('working-directory: DEV', 'working-directory: .')
            self.assertEqual((ROOT / '.github/workflows/validate.yml').read_text(), standalone)
    def test_attestation_targets_generated_reports_not_supplied_executable(self):
        repo=ROOT.parent if (ROOT.parent/'.github/workflows/release-evidence.yml').is_file() else ROOT
        text=(repo/'.github/workflows/release-evidence.yml').read_text()
        self.assertIn('subject-path: out/release/*.json',text);self.assertIn("github.ref == 'refs/heads/master'",text)
        self.assertNotIn('subject-path: DEV/Pesto.exe',text);self.assertIn('workflow_dispatch:',text)
    def test_signing_requires_existing_certificate_timestamp_and_copy(self):
        text=(ROOT/'tools/Sign-PestoRelease.ps1').read_text(encoding='utf-8-sig')
        for required in ('Cert:\\CurrentUser\\My\\','TimeStamperCertificate','--channel DEV','Get-AuthenticodeSignature','M4D.Admin.Common.*.dll'):self.assertIn(required,text)
        self.assertNotIn('New-SelfSignedCertificate',text);self.assertNotIn('Import-Certificate',text)
    def test_toolchain_mismatch_refused(self):
        lock=self.root/'lock.json';lock.write_text(json.dumps({'profiles':{'fixture':{'clang':'wanted','lld':'wanted'}}}))
        completed=mock.Mock(stdout='different\n',stderr='')
        with mock.patch.object(check_toolchain.shutil,'which',return_value='/tool'),mock.patch.object(check_toolchain.subprocess,'run',return_value=completed):
            with self.assertRaises(ValueError):check_toolchain.check('fixture',lock)
    def test_ring_cli_delegates_existing_safe_updater(self):
        text=(ROOT/'tools/update_channels.py').read_text();self.assertIn("'--source'",text);self.assertIn("'--destination'",text);self.assertIn("cmd.append('--apply')",text)

if __name__=='__main__':unittest.main(verbosity=2)
