"""O8 : files de lots du profil courant listées dans l'aperçu de mise à jour (lecture seule, non bloquant).

La liste est ajoutée par la ligne de commande, hors de plan_update/apply_update : le plan comparé et update-plan.json
n'en dépendent pas, et l'examen ne peut ni refuser ni interrompre une mise à jour.

Exécuté sur le Mac avec un LOCALAPPDATA simulé : rien ici ne prouve le comportement sous Windows PowerShell 5.1.
Les règles de classement sont reproduites du code PowerShell ; SourceRulesTests relit ce code pour que ces règles
ne soient pas de simples hypothèses répétées par les tests (lecture du texte source, pas exécution).
"""
import contextlib,io,json,os,re,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest import mock
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from refresh_manifest import runtime_files,file_hash
import update_installation as ui


def tree(root):
    return {p.relative_to(root).as_posix():(file_hash(p) if p.is_file() and not p.is_symlink() else 'dir' if p.is_dir() else 'other')
            for p in root.rglob('*')}


def symlink_or_skip(test,link,target,directory=False):
    try:link.symlink_to(target,target_is_directory=directory)
    except (OSError,NotImplementedError) as exc:test.skipTest('symbolic links unavailable here: '+type(exc).__name__)


class UserQueueTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='pesto-o8-');self.base=Path(self.tmp.name).resolve()
        self.dest=self.base/'installed';self.dest.mkdir()
        for rel in (*runtime_files(ROOT),'wad/package.json'):
            p=self.dest/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
        (self.dest/'wad/cfg.json').write_text('{"PRIVATE-CONFIG":"preserve"}')
        self.local=self.base/'Local';self.local.mkdir()
        self.mine=ui.queue_state_id(str(self.dest/'wad'/'cfg.json'))

    def tearDown(self):self.tmp.cleanup()

    def queue(self,state_id,value,*,raw=None,name='queue.json'):
        d=self.local/'GP'/'State'/state_id;d.mkdir(parents=True,exist_ok=True)
        p=d/name
        if raw is not None:p.write_bytes(raw)
        else:p.write_text(json.dumps(value),encoding='utf-8')
        return p

    def reset(self):shutil.rmtree(self.local/'GP',ignore_errors=True)

    @staticmethod
    def data(phase='Idle',statuses=('OK',)):
        return {'Schema':1,'Version':'1.0','Domain':'lab.local','Host':'PC1','MachineId':'m','Mode':'REEL','Phase':phase,
                'Utc':'2026-10-04T10:00:00Z','OperationIds':[],'Rows':[{'Nom_du_PC':'PC'+str(i),'Statut':s} for i,s in enumerate(statuses)]}

    def scan(self):return ui.list_user_queues([str(self.dest/'wad'/'cfg.json')],self.local)

    def test_state_id_matches_powershell_formula(self):
        # 16 premiers hex MAJUSCULES du SHA-256 UTF-8 du chemin complet en minuscules (Get-PestoStateDirectory).
        # Vecteur calculé hors Python (shasum -a 256) ; parité .NET non rejouée sous Windows.
        self.assertEqual(ui.queue_state_id('C:\\Outils\\Pesto\\wad\\cfg.json'),'236463DE81AFC03A')
        self.assertEqual(ui.queue_state_id('C:\\OUTILS\\Pesto\\wad\\CFG.json'),'236463DE81AFC03A')
        # One code unit in, one out (.NET simple mapping): no final-sigma rule, no expansion.
        self.assertEqual(ui._lower_invariant('ΣΑΣ É'),'σασ é')
        self.assertEqual(len(ui._lower_invariant('C:\\İ\\Ω')),len('C:\\İ\\Ω'))

    def test_no_profile_is_reported_not_blocking(self):
        with mock.patch.dict(os.environ,{},clear=False):
            os.environ.pop('LOCALAPPDATA',None)
            q=ui.installation_queues(self.dest)
        self.assertEqual(q['Status'],'NotExamined');self.assertIn('LOCALAPPDATA',q['Warning'])
        self.assertTrue(ui.queue_warning_lines(q))

    def test_no_state_directory_still_names_the_profile_and_its_limit(self):
        q=self.scan();self.assertEqual(q['Status'],'NoQueue');self.assertIsNone(q['Warning']);self.assertEqual(q['Queues'],[])
        lines=ui.queue_warning_lines(q);self.assertEqual(len(lines),1)
        self.assertIn('aucune file',lines[0]);self.assertIn(str(self.local),lines[0]);self.assertIn('relais UAC',lines[0])

    def test_concluded_queues_are_listed_without_warning(self):
        self.queue(self.mine,self.data('Idle',('OK','VÉRIFIÉ','KO','ANNULÉ','NON LANCÉ','')))
        verified=self.data('Reviewed',('VÉRIFIÉ',));verified['Rows'][0]['Code']='89'  # Verified rows keep their old code.
        self.queue('0123456789ABCDEF',verified)
        (self.local/'GP'/'State'/'FEDCBA9876543210').mkdir()  # history-only directory: no queue
        q=self.scan();self.assertEqual(q['Status'],'Clear');self.assertIsNone(q['Warning'])
        self.assertEqual(len(q['Queues']),2);self.assertTrue(all(x['State']=='Concluded' for x in q['Queues']))
        self.assertTrue(all(x['SafetyLockExpected'] is False for x in q['Queues']))
        mine=[x for x in q['Queues'] if x['ThisInstallation']];self.assertEqual([x['StateId'] for x in mine],[self.mine])
        self.assertEqual(mine[0]['Rows'],6);self.assertEqual(mine[0]['Domain'],'lab.local')
        self.assertIn('toutes conclues',ui.queue_warning_lines(q)[0])

    def test_lock_and_verify_cases(self):
        cases={'Uncertain':('Uncertain',('OK',),True),'Active':('Active',('OK',),True),'phase en minuscules':('uncertain',('OK',),True),
               'EN COURS':('Idle',('OK','EN COURS'),True),'en cours':('Idle',('en cours',),True),
               'INCERTAIN':('Idle',('INCERTAIN',),False),'TECHNIQUE':('Idle',('technique',),False),'PROTECTION':('Reviewed',('PROTECTION',),False)}
        for label,(phase,statuses,lock) in cases.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,self.data(phase,statuses))
                q=self.scan();self.assertEqual(q['Status'],'Attention');entry=q['Queues'][0]
                self.assertEqual(entry['State'],'Uncertain');self.assertIs(entry['SafetyLockExpected'],lock)
                self.assertIn('ATTENTION',q['Warning']);self.assertIn('cette installation',q['Warning'])
                self.assertIn("n'est pas bloquée",q['Warning']);self.assertEqual('Verrou de sécurité attendu' in q['Warning'],lock)

    def test_exact_values_like_powershell(self):
        # PowerShell -eq/-in compare case-insensitively but never trim: these values do not match.
        for label,(phase,statuses) in {'statut avec espace':('Idle',('EN COURS ',)),'phase avec espace':('Idle ',('OK',))}.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,self.data(phase,statuses));entry=self.scan()['Queues'][0]
                self.assertFalse(entry['SafetyLockExpected'])
                self.assertEqual(entry['State'],'Concluded' if label=='statut avec espace' else 'NotConcluded')

    def test_not_concluded_cases(self):
        cases={'BetweenActions':self.data('BetweenActions',('OK',)),'PARTIEL':self.data('Idle',('PARTIEL',)),
               'phase inconnue':self.data('Mystery',('OK',)),'phase absente':{k:v for k,v in self.data().items() if k!='Phase'},
               'ligne':dict(self.data(),Rows=['x']),'rows':dict(self.data(),Rows='x')}
        for label,value in cases.items():
            with self.subTest(label=label):
                self.reset();self.queue('0123456789ABCDEF',value)
                q=self.scan();self.assertEqual(q['Status'],'Attention');entry=q['Queues'][0]
                self.assertEqual(entry['State'],'NotConcluded',entry['Reasons']);self.assertFalse(entry['ThisInstallation'])
                self.assertFalse(entry['SafetyLockExpected']);self.assertNotIn('cette installation',q['Warning'])
                self.assertNotIn('Verrou de sécurité attendu',q['Warning'])

    def test_restore_format_rules(self):
        accepted={'Schema texte':dict(self.data(),Schema='1'),'Schema réel':dict(self.data(),Schema=1.0),
                  'Mode minuscules':dict(self.data(),Mode='reel'),
                  'clés en minuscules':{k.lower():v for k,v in self.data().items()}}
        refused={'Schema 2':dict(self.data(),Schema=2),'Schema absent':{k:v for k,v in self.data().items() if k!='Schema'},
                 'Mode SIM':dict(self.data(),Mode='SIM'),'Mode accentué':dict(self.data(),Mode='RÉEL'),
                 'Schema booléen (forme non modélisée)':dict(self.data(),Schema=True)}
        for label,value in accepted.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,value);entry=self.scan()['Queues'][0]
                self.assertEqual(entry['State'],'Concluded',entry['Reasons'])
        for label,value in refused.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,value);entry=self.scan()['Queues'][0]
                self.assertEqual((entry['State'],entry['SafetyLockExpected']),('Uncertain',True),entry['Reasons'])
                self.assertIn('Schema/Mode',entry['Reasons'][0])
        self.reset();self.queue(self.mine,self.data('Idle',('OK','OK','OK')))
        with mock.patch.object(ui,'QUEUE_ROW_LIMIT',2):entry=self.scan()['Queues'][0]
        self.assertEqual((entry['State'],entry['SafetyLockExpected']),('Uncertain',True))

    def test_encodings_read_like_get_content_utf8(self):
        text=json.dumps(self.data('Idle'),ensure_ascii=False)
        cases={'UTF-8 BOM':b'\xef\xbb\xbf'+text.encode('utf-8'),'UTF-16LE BOM':b'\xff\xfe'+text.encode('utf-16-le'),
               'UTF-16BE BOM':b'\xfe\xff'+text.encode('utf-16-be'),'UTF-32LE BOM':b'\xff\xfe\x00\x00'+text.encode('utf-32-le'),
               'octet UTF-8 invalide':text.replace('lab.local','lab\x00local').encode('utf-8').replace(b'\x00',b'\xff')}
        for label,raw in cases.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,None,raw=raw);entry=self.scan()['Queues'][0]
                self.assertEqual(entry['State'],'Concluded',entry['Reasons'])
        self.reset();self.queue(self.mine,None,raw=text.encode('utf-16-le'))  # No BOM: read as UTF-8, as Pesto would.
        self.assertEqual(self.scan()['Queues'][0]['State'],'Unreadable')

    def test_powershell_shapes_tolerated(self):
        single=self.data('Idle');single['Rows']={'Nom_du_PC':'PC1','Statut':'INCERTAIN'}
        self.queue(self.mine,None,raw=b'\xef\xbb\xbf'+json.dumps(single).encode('utf-8'))
        entry=self.scan()['Queues'][0];self.assertEqual(entry['State'],'Uncertain');self.assertEqual(entry['Rows'],1)
        self.assertEqual(entry['Statuses'],{'INCERTAIN':1})
        empty=self.data('Idle');empty['Rows']=None
        self.queue(self.mine,empty);entry=self.scan()['Queues'][0];self.assertEqual((entry['State'],entry['Rows']),('Concluded',0))

    def test_unreadable_queues_are_reported_never_raised(self):
        cases={'json':b'{not json','binaire':b'\xff\xfe\x00','liste':b'[1,2]','vide':b''}
        for label,raw in cases.items():
            with self.subTest(label=label):
                self.reset();self.queue(self.mine,None,raw=raw)
                q=self.scan();self.assertEqual(q['Status'],'Attention');entry=q['Queues'][0]
                self.assertEqual((entry['State'],entry['SafetyLockExpected']),('Unreadable',True))
        p=self.queue(self.mine,self.data('Idle'))
        with mock.patch.object(ui,'QUEUE_LIMIT',16):
            q=self.scan();self.assertEqual(q['Queues'][0]['State'],'Unreadable');self.assertIn('16 Mio',q['Queues'][0]['Reasons'][0])
        os.chmod(p,0)
        try:
            if os.access(p,os.R_OK):self.skipTest('running with privileges that bypass file modes')
            q=self.scan();self.assertEqual(q['Queues'][0]['State'],'Unreadable');self.assertIn('PermissionError',q['Queues'][0]['Reasons'][0])
        finally:os.chmod(p,0o600)

    def test_directory_listing_failure_is_reported(self):
        self.queue(self.mine,self.data('Uncertain'))
        with mock.patch.object(Path,'iterdir',side_effect=PermissionError('denied')):
            q=self.scan()
        self.assertEqual(q['Status'],'NotExamined');self.assertIn('PermissionError',q['Warning'])

    def test_own_queue_is_read_first_whatever_the_limits(self):
        state=self.local/'GP'/'State';state.mkdir(parents=True)
        for i in range(300):(state/('!pad-%03d'%i)).mkdir();(state/('!file-%03d'%i)).write_text('x')
        for i in range(6):self.queue('!q-%d'%i,self.data('Idle'))
        self.queue(self.mine,self.data('Uncertain',('INCERTAIN',)))
        with mock.patch.object(ui,'QUEUE_DIR_LIMIT',4):q=self.scan()
        read=[x['StateId'] for x in q['Queues']];self.assertEqual(read[0],self.mine);self.assertEqual(len(read),4)
        self.assertEqual(q['Status'],'Attention');self.assertIn('cette installation',q['Warning'])
        self.assertIn('3 file(s) de lots non examinée(s)',q['Warning'])
        self.assertTrue(any('[cette installation]' in line for line in ui.queue_warning_lines(q)))
        with mock.patch.object(ui,'QUEUE_ENTRY_LIMIT',10):q=self.scan()
        self.assertEqual(q['Queues'][0]['StateId'],self.mine);self.assertIn('liste tronquée',q['Warning'])
        self.assertIn('cette installation',q['Warning'])

    def test_links_are_refused_and_not_followed(self):
        outside=self.base/'outside';outside.mkdir();target=outside/'queue.json';target.write_text(json.dumps(self.data('Idle')))
        d=self.local/'GP'/'State'/self.mine;d.mkdir(parents=True);symlink_or_skip(self,d/'queue.json',target)
        symlink_or_skip(self,self.local/'GP'/'State'/'0123456789ABCDEF',outside,True)
        q=self.scan();self.assertEqual(q['Status'],'Attention')
        self.assertEqual({x['StateId']:x['State'] for x in q['Queues']},{self.mine:'Unreadable','0123456789ABCDEF':'Unreadable'})
        self.assertTrue(all('lien' in x['Reasons'][0] and x['SafetyLockExpected'] is None for x in q['Queues']))
        shutil.rmtree(self.local/'GP');symlink_or_skip(self,self.local/'GP',outside,True)
        q=self.scan();self.assertEqual(q['Status'],'NotExamined');self.assertIn('Lien ou jonction',q['Warning'])

    def run_main(self,args):
        """update_installation.main() in this process, with the simulated profile; returns (code, JSON or None, stderr)."""
        out=io.StringIO();err=io.StringIO()
        with mock.patch.object(sys,'argv',['update_installation.py','--source',str(ROOT),*args]),\
             mock.patch.dict(os.environ,{'LOCALAPPDATA':str(self.local)}),\
             contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
            try:ui.main();code=0
            except SystemExit as exc:code=exc.code
        return code,(json.loads(out.getvalue()) if code==0 else None),err.getvalue()

    def test_typed_path_under_linked_parent_is_recognised(self):
        alias=self.base/'alias';symlink_or_skip(self,alias,self.base,True)
        typed=alias/'installed';typed_id=ui.queue_state_id(os.path.abspath(typed/'wad'/'cfg.json'))
        self.assertNotEqual(typed_id,self.mine)
        self.queue(typed_id,self.data('Uncertain',('EN COURS',)));self.queue(self.mine,self.data('Idle'))
        q=ui.installation_queues(typed,self.local)
        self.assertEqual({(x['StateId'],x['ThisInstallation']) for x in q['Queues']},{(typed_id,True),(self.mine,True)})
        code,result,err=self.run_main(['--destination',str(typed),'--apply'])
        self.assertEqual(code,0,err);self.assertTrue(result['Updated'])
        self.assertTrue(all(x['ThisInstallation'] for x in result['UserQueues']['Queues']))

    def test_queues_stay_out_of_the_plan_and_never_block_the_update(self):
        self.queue(self.mine,self.data('Uncertain',('EN COURS',)));self.queue('0123456789ABCDEF',self.data('Idle'))
        before=tree(self.local)
        code,preview,err=self.run_main(['--destination',str(self.dest)])
        self.assertEqual(code,0,err);self.assertEqual(preview['UserQueues']['Status'],'Attention');self.assertIn('ATTENTION',err)
        self.assertEqual(tree(self.local),before);self.assertFalse((self.dest/'.pesto-update.lock').exists())
        shown={k:v for k,v in preview.items() if k!='UserQueues'}
        plan=ui.plan_update(ROOT,self.dest);self.assertNotIn('UserQueues',plan);self.assertEqual(shown,plan)
        # A running Pesto rewrites its queue between the preview and --apply: neither the update nor its plan depend on it.
        self.queue(self.mine,self.data('Active',('EN COURS','INCERTAIN')));changed=tree(self.local)
        calls=[];real=ui.list_user_queues
        def counted(*args,**kwargs):calls.append(os.path.exists(self.dest/'.pesto-update.lock'));return real(*args,**kwargs)
        with mock.patch.object(ui,'list_user_queues',counted):code,result,err=self.run_main(['--destination',str(self.dest),'--apply'])
        self.assertEqual(code,0,err);self.assertTrue(result['Updated'])
        self.assertEqual(calls,[False])  # One scan, once the update is over and its lock released.
        self.assertEqual(result['UserQueues']['Status'],'Attention');self.assertEqual(result['UserQueues']['Queues'][0]['Phase'],'Active')
        self.assertEqual(tree(self.local),changed)
        saved=json.loads((Path(result['Backup'])/'update-plan.json').read_text(encoding='utf-8'))
        self.assertEqual(saved,shown)  # update-plan.json is the plan shown by the preview, queues excluded.

    def test_library_plan_and_update_never_scan(self):
        self.queue(self.mine,self.data('Uncertain',('EN COURS',)))
        with mock.patch.dict(os.environ,{'LOCALAPPDATA':str(self.local)}),\
             mock.patch.object(ui,'list_user_queues',side_effect=AssertionError('scan inside the plan or the update')):
            plan=ui.plan_update(ROOT,self.dest);result=ui.apply_update(ROOT,self.dest)
        self.assertNotIn('UserQueues',plan);self.assertNotIn('UserQueues',result);self.assertTrue(result['Updated'])

    def test_failing_scan_never_turns_an_update_into_a_failure(self):
        with mock.patch.object(ui,'list_user_queues',side_effect=RuntimeError('boom')):
            code,result,err=self.run_main(['--destination',str(self.dest),'--apply'])
        self.assertEqual(code,0,err);self.assertTrue(result['Updated'])
        self.assertEqual(result['UserQueues']['Status'],'NotExamined');self.assertIn('RuntimeError',err)
        with mock.patch.object(ui,'list_user_queues',side_effect=AssertionError('no scan after a refusal')):
            code,result,err=self.run_main(['--destination',str(self.base/'absent')])
        self.assertEqual(code,1);self.assertIn('Update refused',err)

    def test_console_lines_never_raise(self):
        info={'LocalAppData':'C:\\Users\\Иван\\AppData\\Local','Warning':'ATTENTION é','Status':'Attention',
              'Queues':[{'State':'Uncertain','ThisInstallation':True,'Path':'C:\\Users\\Иван\\q','Reasons':['phase Active']}]}
        raw=io.BytesIO();stream=io.TextIOWrapper(raw,encoding='cp1252',errors='strict')
        with mock.patch.object(sys,'stdout',io.StringIO()):ui.print_queue_lines(info,stream)
        text=raw.getvalue().decode('cp1252');self.assertIn('ATTENTION é',text);self.assertIn('C:\\Users\\????\\q',text)
        class Broken(io.StringIO):
            def write(self,s):raise OSError('console gone')
        ui.print_queue_lines(info,Broken())
        self.assertEqual(ui.queue_warning_lines(None),[])

    def run_cli(self,local,encoding='utf-8'):
        env=dict(os.environ,LOCALAPPDATA=str(local),PYTHONIOENCODING=encoding)
        r=subprocess.run([sys.executable,str(ROOT/'tools'/'update_installation.py'),'--source',str(ROOT),'--destination',str(self.dest)],
                         capture_output=True,env=env,timeout=60)
        return r.returncode,r.stdout.decode(encoding),r.stderr.decode(encoding,'replace')

    def test_command_line_preview_prints_clear_warning(self):
        self.queue(self.mine,self.data('Uncertain',('INCERTAIN',)))
        code,out,err=self.run_cli(self.local)
        self.assertEqual(code,0,err)
        self.assertEqual(json.loads(out)['UserQueues']['Status'],'Attention')
        self.assertIn('ATTENTION',err);self.assertIn('[cette installation]',err);self.assertIn(str(self.local),err)
        self.assertIn('relais UAC',err);self.assertFalse((self.dest/'.pesto-update.lock').exists())

    def test_command_line_with_ansi_code_page_and_foreign_profile_path(self):
        local=self.base/'Иван'/'Local';local.mkdir(parents=True)
        code,out,err=self.run_cli(local,'cp1252')
        self.assertEqual(code,0,err);result=json.loads(out)  # Valid JSON even when the console cannot show the path.
        self.assertEqual((result['UserQueues']['LocalAppData'],result['UserQueues']['Status']),(str(local),'NoQueue'))
        self.assertIn('aucune file',err);self.assertNotIn('Traceback',err)


class SourceRulesTests(unittest.TestCase):
    """The classification rules above must still match the PowerShell code they were taken from."""

    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'wad'/'Pesto-Core.ps1').read_text(encoding='utf-8-sig')
        cls.wad='\n'.join(p.read_text(encoding='utf-8-sig') for p in sorted((ROOT/'wad').glob('*.ps1')))

    def function(self,name):
        m=re.search(r'^function '+re.escape(name)+r' \{\n(.*?)^\}',self.core,re.S|re.M)
        self.assertIsNotNone(m,name);return m.group(1)

    def test_state_directory_formula(self):
        body=self.function('Get-PestoStateDirectory')
        for token in ("GetFolderPath('LocalApplicationData')",'ToLowerInvariant()','Text.Encoding]::UTF8','SHA256',
                      "Replace('-','').Substring(0,16)",'GP\\State\\'):
            self.assertIn(token,body)
        self.assertIn('ToLowerInvariant()',self.wad[self.wad.index('function Get-PestoStartupStateId'):][:600])

    def test_save_writes_what_the_scan_expects(self):
        body=self.function('Save-PestoQueueCheckpoint')
        self.assertIn("Schema=1;",body);self.assertIn("Mode='REEL'",body);self.assertIn("'queue.json'",body)
        self.assertRegex(body,r'if\s*\(\$script:GUI -or \$script:SIM\)\s*\{\s*return\s*\}')
        self.assertIn('-gt 16MB',body);self.assertEqual(ui.QUEUE_LIMIT,16*1024*1024)
        self.assertIn('UTF8Encoding]::new($false)',self.function('Write-PestoAtomicText'))
        calls=re.findall(r"Save-PestoQueueCheckpoint(?:Safe)? -Phase (?:'([A-Za-z]+)'|"
                         r"\$\(if\(\$script:MutationUncertain\)\{'([A-Za-z]+)'\}else\{'([A-Za-z]+)'\}\))",self.wad)
        self.assertGreaterEqual(len(calls),5)
        phases={name.casefold() for call in calls for name in call if name}
        # No other phase form, apart from the pass-through of Save-PestoQueueCheckpointSafe.
        self.assertEqual(len(re.findall(r'Save-PestoQueueCheckpoint(?:Safe)? -Phase (?!\$Phase\b)',self.wad)),len(calls))
        phases|={name.casefold() for name in re.findall(r"\$Phase='([A-Za-z]+)'",body)}  # Default Idle, forced Uncertain.
        known=ui._QUEUE_LOCK_PHASES|ui._QUEUE_OPEN_PHASES|ui._QUEUE_CLOSED_PHASES
        self.assertEqual(phases,set(known))

    def test_restore_rules(self):
        body=self.function('Restore-PestoQueueCheckpoint')
        self.assertIn("Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json",body)
        self.assertIn("$state.Schema -ne 1 -or $state.Mode -ne 'REEL'",body)
        self.assertIn('.Length -gt 16MB',body)
        self.assertEqual(int(re.search(r'\$rows\.Count -gt (\d+)',body).group(1)),ui.QUEUE_ROW_LIMIT)
        lock=re.search(r"\$uncertain=\$state\.Phase -in @\(([^)]*)\) -or @\(\$rows\|Where-Object\{\$_\.Statut -eq '([^']+)'\}\)",body)
        self.assertIsNotNone(lock)
        self.assertEqual({p.casefold() for p in re.findall(r"'([^']+)'",lock.group(1))},set(ui._QUEUE_LOCK_PHASES))
        self.assertEqual({lock.group(2)},set(ui._QUEUE_LOCK_STATUSES))
        self.assertRegex(body,r'\}catch\{\s*\$script:MutationUncertain=\$true')

    def test_row_statuses(self):
        verify=re.search(r"\$uncertain=@\(\$st\.Items\|Where-Object\{\$_\.Row\.Statut -in @\(([^)]*)\)\}\)",self.core)
        self.assertIsNotNone(verify)
        self.assertEqual(set(re.findall(r"'([^']+)'",verify.group(1))),set(ui._QUEUE_VERIFY_STATUSES))
        result=self.function('Set-PestoQueueRowResult')
        self.assertIn("89 {'PARTIEL'}",result);self.assertEqual({'PARTIEL'},set(ui._QUEUE_OPEN_STATUSES))
        self.assertIn("$Row.Statut='VÉRIFIÉ'",self.wad)  # Verified rows: status changes, code 89 may stay.


if __name__=='__main__':unittest.main(verbosity=2)
