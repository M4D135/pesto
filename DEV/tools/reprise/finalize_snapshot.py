from pathlib import Path
import hashlib,json,zipfile,shutil,datetime
base=Path('/mnt/data');root=base/'Pesto_REPRISE/DEV';b=base/'Pesto_REPRISE_BILAN.json'
if not root.is_dir():raise RuntimeError('Aucune source recuperee: pas de faux paquet produit.')
r=json.loads(b.read_text('utf-8')) if b.is_file() else {}
checks=r.get('validation',[])+r.get('finalChecks',[])
if r.get('supportDistributionTests'):checks.append(r['supportDistributionTests']|{'name':'support-distribution'})
failed=[x for x in checks if x.get('status')=='FAIL']
notrun=[x for x in checks if x.get('status') in ('NOT_RUN','SKIP')]
# A successful pack builder is not allowed to override a failed engine validation.
prod=base/'Pesto_REPRISE_PROD.zip'
if failed and prod.exists():
    staging=base/'Pesto_REPRISE/production_NON_VALIDEE';staging.mkdir(exist_ok=True)
    shutil.move(str(prod),str(staging/'NE_PAS_DISTRIBUER.zip'))
    r['productionPackCreated']=False
r['releaseStatus']='BLOQUE_PAR_LES_TESTS' if failed else 'RECETTE_WINDOWS_NON_EFFECTUEE'
r['all44AuditItemsCompleted']=False
r['validationScope']='Ce bilan ne transforme pas des controles de distribution en validation du moteur AD.'
rows=[]
for x in checks:
    rows.append('| '+str(x.get('name','controle'))+' | '+str(x.get('status','INCONNU'))+' | '+str(x.get('reason','')).replace('|','/').replace('\n',' ')+' |')
md='''# Pesto : point de reprise et fichiers conservés

## Statut

**Travail de développement, pas une version certifiée pour le domaine de production.**

Les 44 modifications de l’audit ne sont pas annoncées comme toutes terminées. Les fichiers du chantier déjà présent ont été conservés. Le tableau ci-dessous est issu des retours réels des commandes exécutées par le script de reprise, pas d’un ancien compte rendu recopié.

## Modifications apportées par cette reprise

- `DEBLOQUER_TOUT.cmd` est dans `wad\\support`, avec une résolution de la racine deux niveaux au-dessus et un contrôle de présence de Pesto.exe et des points d’entrée. Il ne part pas du dossier de travail courant.
- Le déblocage demande confirmation, ignore les liens repérés, contrôle le retrait des marques de téléchargement et produit un bilan dans `wad\\logs`. Il ne change ni antivirus, ni stratégie de sécurité, ni verrou métier.
- Un générateur autonome `tools/Build-PestoPacks.py` fabrique des dossiers PROD et DEV, conserve seulement Pesto.exe et wad à la racine de PROD, refuse les composants incohérents et n’impose pas le support au démarrage.
- `FABRIQUER_PACKS.cmd` appelle ce générateur. La fabrication utilise un dossier de sortie nouveau, sans écraser une installation existante.
- Des tests isolés du générateur couvrent fichiers manquants ou modifiés, chemins traversants, code non couvert, exclusion des journaux et préférences, support facultatif et noms des dossiers des archives.

## Base récupérée

'''
md+=f"Version détectée dans la source : RC{r.get('sourceVersionRC','inconnue')}.\n\n"
md+=f"Fichiers applicatifs conservés qui diffèrent de la RC18 : {len(r.get('retainedRuntimeDiffFromRC18',[]))}. Leurs empreintes sont dans le JSON. Ce nombre ne mesure ni la couverture de tests ni l’achèvement de l’audit.\n\n"
md+='## Résultats des commandes\n\n| Contrôle | Résultat | Précision |\n|---|---|---|\n'+'\n'.join(rows)+'\n\n'
md+='''## Vérifications non réalisées ici

Windows PowerShell 5.1 natif, lancement de l’EXE sous Windows, rendu WPF, UAC interactive, droits réels du poste, Planificateur Windows, authentification AD, jonction, renommage, déplacement et redémarrage réels. Une signature officielle demande le certificat autorisé de l’organisation. Ces étapes ne sont pas rendues « réussies » par une compilation ou une vérification de ZIP.

Les tests en échec restent des blocages à traiter. Le snapshot DEV est fourni pour conserver et poursuivre les sources, pas pour contourner ces blocages. Aucun ancien verrou, reçu ou fichier de configuration opérationnel ne doit être effacé pour lancer un essai.

## Continuer depuis ce dossier

Consulter `docs/bilan-reprise.json` et les fichiers de `verification` ; corriger les premiers tests réellement en échec avant une nouvelle mutation. Les tests historiques gardent leur statut historique. Examiner les différences avec la RC18 avant toute diffusion. Ne pas installer ce chantier à la place d’une installation utilisée sur des postes de production.
'''
(base/'Pesto_REPRISE_BILAN.md').write_text(md,encoding='utf-8')
(root/'docs/REPRISE_ET_LIMITES.md').write_text(md,encoding='utf-8')
(root/'docs/bilan-reprise.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
b.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
# Include the continuation scripts so no recovery/build work is lost.
folder=root/'tools/reprise';folder.mkdir(exist_ok=True)
for p in (base/'pesto_continuation_tools').glob('*.py'):shutil.copy2(p,folder/p.name)
archive=base/'Pesto_REPRISE_DEV.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file() and not p.is_symlink() and '__pycache__' not in p.parts and p.suffix!='.pyc':z.write(p,p.relative_to(root.parent).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert 'DEV/wad/support/DEBLOQUER_TOUT.cmd' in z.namelist()
 assert 'DEV/tools/Build-PestoPacks.py' in z.namelist()
 assert 'DEV/Pesto.exe' in z.namelist()
 assert 'DEV/DEBLOQUER_TOUT.cmd' not in z.namelist()
proof={'snapshot':str(archive),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
       'bilan':str(base/'Pesto_REPRISE_BILAN.md'),'releaseStatus':r['releaseStatus'],
       'failedChecks':len(failed),'unexecutedChecks':len(notrun),
       'zipIntegrity':'PASS','supportPlacement':'PASS','all44Completed':False}
(base/'Pesto_REPRISE_EXISTENCE.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(proof,ensure_ascii=False,indent=2))
