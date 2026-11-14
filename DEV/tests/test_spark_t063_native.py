import hashlib
import json
import re
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
SUITE = DEV / 'tests' / 'Run-CompiledHelpers63Tests.ps1'
HARNESS = DEV / 'tests' / 'Run-CompiledHelpers63MutationTests.ps1'
BENCH = DEV / 'tests' / 'Measure-Engine120.ps1'
BUILD_TOOL = DEV / 'tools' / 'Build-PestoRuntimeTypes.ps1'
RUN_ALL = DEV / 'tests' / 'Run-AllTests.ps1'
SUITES_JSON = DEV / 'tests' / 'suites.json'
LOADER = DEV / 'wad' / 'Pesto-Common.ps1'
MODULE = DEV / 'wad' / 'Pesto.Engine.Runtime.ps1'
DLL = DEV / 'wad' / 'Pesto.Runtime.dll'
WAD = DEV / 'wad'
PROOF = DEV / 'docs' / 'implementation' / 'proofs' / 'COMPILED_HELPERS_63_20261023.json'
DOC = DEV / 'docs' / 'implementation' / 'ENGINE_120.md'

NATIVE_SURFACE = {
    'Pesto.NativeShell|shell32.dll|SetCurrentProcessExplicitAppUserModelID',
    'Pesto.NativeShell|user32.dll|SendMessage',
    'Pesto.NativeShell|user32.dll|DestroyIcon',
    'Pesto.NativePipe17|kernel32.dll|GetNamedPipeClientProcessId',
}

# Les quatre sources que compile tools/Build-PestoRuntimeTypes.ps1 : le banc du point 63 doit les compiler
# a froid du cote Add-Type, exactement les memes, lues de la racine du depot.
HELPER_SOURCES = ['wad/Pesto-LogWriter.cs', 'src/Pesto.Runtime/CompactIndex.cs',
                  'src/Pesto.Runtime/NativePipe.cs', 'src/Pesto.Runtime/NativeShell.cs']

HARNESS_WHITELIST = {'wad/Pesto-Common.ps1', 'wad/Pesto-Operations.ps1', 'wad/Pesto-Core.ps1',
                     'wad/Pesto.Engine.Runtime.ps1', 'wad/Pesto.Runtime.dll', 'wad/Pesto-LogWriter.cs',
                     'src/Pesto.Runtime/CompactIndex.cs', 'src/Pesto.Runtime/NativePipe.cs',
                     'src/Pesto.Runtime/NativeShell.cs', 'tools/Build-PestoRuntimeTypes.ps1',
                     'tests/Measure-Engine120.ps1'}

HARNESS_EXPECTED_FAILURES = (
    'Native surface drifted from the on-target qualification list',
    'Native pipe failure no longer throws in wad/Pesto-Operations.ps1',
    'Pipe gate no longer precedes the secret in wad/Pesto-Operations.ps1',
    'Unguarded native icon call at line ',
    ' in wad/Pesto-Core.ps1',
    'Precompiled helpers and runtime-compiled sources no longer render the same workload',
    'The precompiled side no longer goes through the verified loader',
    'Shipped helper source missing',
    'Pipe gate no longer loads the verified library in wad/Pesto-Operations.ps1',
    'Native pipe call no longer negated in wad/Pesto-Operations.ps1',
    'Native pipe failure no longer throws in module Engine genere',
    'Pipe gate no longer precedes the secret in module Engine genere',
    ' in module Engine genere',
    'Tampered DLL accepted',
    'The Add-Type side no longer compiles the four sources the build tool compiles',
    'The delivered path is no longer cheaper than cold Add-Type compilation',
    'The evaluation result no longer holds: the verified loader is not at least twice as cheap as cold Add-Type',
    'The published block no longer reports the six played samples',
)

# Ce que la suite doit relire dans le bloc publie par le banc (mode evaluation seule) : sans ces aiguilles,
# la suite ne consommerait plus le rapport et les chiffres publies au catalogue n'auraient plus de garde.
SUITE_PUBLISHED_NEEDLES = (
    '-CompiledHelpersOnly',
    'CompiledHelpersSamples',
    'The compiled-helpers report is not the evaluation section',
    'The published block no longer reports the six played samples',
    'The published block no longer compares the two delivery modes',
    'The published block no longer counts one delivered assembly against four compiled ones',
    'The published block no longer reports one identical workload digest',
    'The published percentiles are incoherent',
    'The delivered path is no longer cheaper than cold Add-Type compilation',
    'The evaluation result no longer holds: the verified loader is not at least twice as cheap as cold Add-Type',
)

BENCH_PUBLISHED_NEEDLES = (
    'function Measure-PestoCompiledHelpers',
    'if($CompiledHelpersOnly)',
    "Section='CompiledHelpers'",
    'CompiledHelpers=$compiledPair.Summary',
    'CompiledHelpersSamples=$compiledPair.Samples',
    'WindowsADExecuted=$false',
)

PUBLISHED_MUTATION_LABELS = (
    'Delivered path recompiles at runtime',
    'Published precompiled cost inflated',
    'Published block loses its samples',
)

BENCH_REFUSED_MEASURES = (
    'Les deux modes de livraison ne rendent pas le meme ouvrage',
    'La surface native des helpers precompiles derive de la liste a qualifier sur cible',
    'Le cote precompile ne charge pas l assembly livree Pesto.Runtime',
    'Le cote precompile ne charge pas la DLL livree wad/Pesto.Runtime.dll',
    'Le cote precompile ne passe plus par Initialize-PestoRuntimeTypes',
    'Le cote Add-Type ne compile pas quatre assemblies distinctes',
    'Le cote Add-Type ne compile plus les quatre sources livrees',
    'L ouvrage des helpers precompiles ne rend plus 2 000 lignes indexees',
)

SUITE_CONSUMER_NEEDLES = (
    'Precompiled helpers and runtime-compiled sources no longer render the same workload',
    'The precompiled side no longer goes through the verified loader',
    'The Add-Type side no longer compiles the four sources the build tool compiles',
    'The precompiled side no longer loads the delivered DLL',
    'Runtime-compiled sources no longer expose the pinned native surface',
)


def read(path):
    assert path.is_file(), 'Fichier source introuvable : ' + str(path)
    return path.read_text(encoding='utf-8-sig')


class TestCompiledHelpers63(unittest.TestCase):
    """Contrôles statiques ; l'exécution est jouée par tests/Run-CompiledHelpers63Tests.ps1."""

    def test_suite_epingle_la_surface_native(self):
        suite = read(SUITE)
        m = re.search(r"\$expectedNative=@\(([^)]*)\)", suite)
        self.assertIsNotNone(m, 'Liste native épinglée absente de la suite')
        pinned = set(re.findall(r"'([^']+)'", m.group(1)))
        self.assertEqual(pinned, NATIVE_SURFACE,
                         'La surface native épinglée a divergé de la liste qualifiée sur cible')

    def test_dll_livree_correspond_a_lempreinte_epinglee(self):
        digest = hashlib.sha256(DLL.read_bytes()).hexdigest()
        for path in (LOADER, MODULE):
            text = read(path)
            m = re.search(r"\$expected='([0-9a-f]{64})' # PESTO_COMPILED_SHA256", text)
            self.assertIsNotNone(m, 'Marqueur d\'empreinte absent de ' + str(path))
            self.assertEqual(m.group(1), digest,
                             'L\'empreinte épinglée ne correspond plus à la DLL livrée : ' + str(path))

    def test_aucun_add_type_compilant_dans_le_produit(self):
        # L'évaluation 63 est livrée : les sites Add-Type du produit ne chargent que des assemblys.
        offenders = []
        for ps1 in sorted(WAD.glob('*.ps1')):
            if ps1.name == 'Pesto.Engine.Runtime.ps1':
                continue
            for line in read(ps1).splitlines():
                stripped = line.strip()
                if re.match(r'^(Add-Type|\[void\]\s*Add-Type|\s*Add-Type)\b', stripped) or 'Add-Type ' in stripped:
                    if 'Add-Type' not in stripped or stripped.startswith('#'):
                        continue
                    if not re.search(r'Add-Type\s+-AssemblyName', stripped):
                        offenders.append(ps1.name + ': ' + stripped[:80])
        self.assertEqual(offenders, [],
                         'Des sites Add-Type compilant sont réapparus dans wad/ : ' + '; '.join(offenders))

    def test_porte_du_canal_garde_le_secret(self):
        for path in (DEV / 'wad' / 'Pesto-Operations.ps1', MODULE):
            text = read(path)
            gate = text.find('Test-PestoPipeClient -Pipe')
            secret = text.find('GetNetworkCredential().Password')
            self.assertGreater(gate, -1, 'Porte du canal absent de ' + str(path))
            self.assertGreater(secret, -1, 'Lecture du secret absente de ' + str(path))
            self.assertLess(gate, secret,
                            'La porte native ne précède plus la lecture du secret dans ' + str(path))


class TestMutationHarness63(unittest.TestCase):
    """Le harnais rejoue la non-tautologie de la suite ; son exécution est jouée par
    tests/Run-CompiledHelpers63MutationTests.ps1, branchée dans Run-AllTests.ps1 et suites.json."""

    def test_harness_epingle_les_mutations_attendues(self):
        harness = read(HARNESS)
        for needle in HARNESS_EXPECTED_FAILURES:
            self.assertIn(needle, harness,
                          'Message d échec attendu absent du harnais : ' + needle)
        self.assertIn('Run-CompiledHelpers63Tests.ps1', harness,
                      'Le harnais ne rejoue pas la suite 63')
        self.assertIn('CompiledHelpers63Mutations', harness,
                      'Ligne de résumé du harnais absente')

    def test_harness_ne_copie_que_la_liste_blanche(self):
        harness = read(HARNESS)
        m = re.search(r"\$copiedFiles=@\(([^)]*)\)", harness)
        self.assertIsNotNone(m, 'Liste blanche de copie absente du harnais')
        copied = set(re.findall(r"'([^']+)'", m.group(1)))
        self.assertEqual(copied, HARNESS_WHITELIST,
                         'La copie du harnais a divergé des fichiers requis par la suite')
        self.assertNotIn('cfg.json', [p.rsplit('/', 1)[-1] for p in copied],
                         'Le harnais copierait la configuration privée')
        for relative in sorted(copied):
            self.assertTrue((DEV / relative).is_file(),
                            'Le harnais nomme un fichier qui nexiste pas : ' + relative)

    def test_harness_branché_dans_les_deux_lanceurs(self):
        name = 'Run-CompiledHelpers63MutationTests.ps1'
        self.assertIn("'" + name + "'", read(RUN_ALL),
                      'Harnais absent de Run-AllTests.ps1')
        suites = json.loads(SUITES_JSON.read_text(encoding='utf-8-sig'))
        self.assertIn(name, [s['file'] for s in suites],
                      'Harnais absent de tests/suites.json')


class TestCompiledHelpersEvaluation(unittest.TestCase):
    """L'évaluation 63 est mesurée par tests/Measure-Engine120.ps1 et consommée par
    tests/Run-CompiledHelpers63Tests.ps1 : les deux fichiers sont relus ici, leur exécution est jouée
    par les suites PowerShell branchées dans Run-AllTests.ps1 et tests/suites.json."""

    def test_le_banc_compile_les_quatre_sources_du_build_tool(self):
        bench = read(BENCH)
        m = re.search(r"\$PestoCompiledHelperSources=@\(([^)]*)\)", bench)
        self.assertIsNotNone(m, 'La liste des sources des helpers précompilés a disparu du banc')
        self.assertEqual(re.findall(r"'([^']+)'", m.group(1)), HELPER_SOURCES,
                         'Le banc ne compile plus les quatre sources attendues')
        build = read(BUILD_TOOL)
        mb = re.search(r"foreach\(\$relative in @\(([^)]*)\)\)", build)
        self.assertIsNotNone(mb, 'La liste des sources du build tool est illisible')
        self.assertEqual(re.findall(r"'([^']+)'", mb.group(1)), HELPER_SOURCES,
                         'Le banc et tools/Build-PestoRuntimeTypes.ps1 ne compilent plus les mêmes sources')
        for relative in HELPER_SOURCES:
            self.assertTrue((DEV / relative).is_file(),
                            'Source de helper précompilé absente du dépôt : ' + relative)

    def test_le_banc_refuse_une_comparaison_non_equivalente(self):
        bench = read(BENCH)
        self.assertIn('-CompiledHelpersWorker', bench,
                      'Le banc noblique plus les deux modes de livraison')
        self.assertIn('CompiledHelpers=$compiledSummary', bench,
                      'Le rapport du banc ne publie plus le bloc CompiledHelpers')
        self.assertIn('Initialize-PestoRuntimeTypes -Root', bench,
                      "Le côté précompilé ne passe plus par le chargeur livré")
        for needle in BENCH_REFUSED_MEASURES:
            self.assertIn(needle, bench,
                          'Le banc ne refuse plus cette mesure : ' + needle)

    def test_la_suite_est_le_consommateur_branche_du_banc(self):
        suite = read(SUITE)
        self.assertIn('Measure-Engine120.ps1', suite,
                      'La suite 63 ne pilote plus le banc qui mesure l évaluation')
        self.assertIn('-CompiledHelpersWorker', suite,
                      'La suite 63 noblique plus les deux modes du banc')
        self.assertIn('PESTO63-FAIL', suite,
                      "La suite ne rend plus son échec sur une ligne lisible par le harnais")
        for needle in SUITE_CONSUMER_NEEDLES:
            self.assertIn(needle, suite,
                          'La suite 63 n asserte plus ce contrôle : ' + needle)

    def test_le_harnais_rejoue_les_mutations_de_levaluation(self):
        harness = read(HARNESS)
        for label in ('Audit writer payload drift',
                      'Precompiled side bypasses the verified loader',
                      'Add-Type side loses a shipped source'):
            self.assertIn(label, harness,
                          'Mutation de lévaluation absente du harnais : ' + label)
        self.assertIn('GetBytes\\(entry\\.Text\\)', harness,
                      'La mutation du journal d audit ne touche plus le contenu écrit')

    def test_le_harnais_frappe_les_deux_copies_et_le_chargeur(self):
        # Les gardes sont assertees deux fois (produit livre et module Engine genere) et le
        # chargeur verifie comme l outil de build sont des tiers distincts : le harnais doit
        # muter chacune de ces copies, pas seulement wad/Pesto-Operations.ps1 et Pesto-Core.ps1.
        harness = read(HARNESS)
        for label in ('Module gate without throw',
                      'Module gate after secret',
                      'Module icon call outside try',
                      'Gate loader call removed',
                      'Gate negation dropped',
                      'Verified loader tamper guards off',
                      'Build tool source list drift'):
            self.assertIn(label, harness,
                          'Mutation de la seconde copie ou du chargeur absente du harnais : ' + label)
        for path in ("Join-Path $temp 'wad/Pesto.Engine.Runtime.ps1'",
                     "Join-Path $temp 'wad/Pesto-Common.ps1'",
                     "Join-Path $temp 'tools/Build-PestoRuntimeTypes.ps1'"):
            self.assertIn(path, harness,
                          'Le harnais ne mute plus cette copie : ' + path)


class TestPublishedEvaluation(unittest.TestCase):
    """Le bloc CompiledHelpers publie par le banc est le resultat de l evaluation 63. Il n a de valeur que
    branché : la suite 63 le rejoue (-CompiledHelpersOnly), le relit et en asserte la conclusion, le harnais
    le frappe, et l'artefat consigne aux preuves reste raccroche a l'empreinte citee dans ENGINE_120.md."""

    def test_le_banc_publie_le_resultat_de_levaluation(self):
        bench = read(BENCH)
        for needle in BENCH_PUBLISHED_NEEDLES:
            self.assertIn(needle, bench,
                          'Le banc ne publie plus ce morceau du resultat de l evaluation : ' + needle)
        self.assertEqual(bench.count('function Measure-PestoCompiledHelpers'), 1,
                         'Le bloc publie nest plus produit par un seul chemin de code')

    def test_la_suite_relit_le_bloc_publie_du_banc(self):
        suite = read(SUITE)
        for needle in SUITE_PUBLISHED_NEEDLES:
            self.assertIn(needle, suite,
                          'La suite 63 ne relit plus le bloc publie du banc : ' + needle)

    def test_le_harnais_frappe_le_bloc_publie(self):
        harness = read(HARNESS)
        for label in PUBLISHED_MUTATION_LABELS:
            self.assertIn(label, harness,
                          'Mutation du bloc publie absente du harnais : ' + label)
        for anchor in ('$compiledPair.Summary', 'CompiledHelpersSamples=',
                       'Assembly des helpers precompiles absente'):
            self.assertIn(anchor, harness,
                          'La mutation du bloc publie ne frappe plus ce point d accroche : ' + anchor)

    def test_la_preuve_de_evaluation_est_coherente(self):
        self.assertTrue(PROOF.is_file(), 'Artefact de mesure absent : ' + str(PROOF))
        report = json.loads(PROOF.read_text(encoding='utf-8-sig'))
        self.assertEqual(report.get('Schema'), 1, "L'artefact de mesure n'est plus au schema 1")
        self.assertEqual(report.get('Section'), 'CompiledHelpers')
        self.assertFalse(report.get('WindowsADExecuted'),
                         "L'artefact pretendrait une execution native sur cible")
        self.assertTrue(report.get('PowerShell') and report.get('Platform'),
                        "L'artefact ne dit plus sur quel hote non produit il a joue")
        self.assertEqual(report.get('Iterations'), 3)
        modes = {entry['Mode']: entry for entry in report['CompiledHelpers']}
        self.assertEqual(set(modes), {'AddType', 'Precompiled'},
                         "Le bloc publie ne compare plus les deux modes de livraison")
        self.assertEqual(len(report['CompiledHelpersSamples']), 6,
                         "L'artefact ne rend plus les six echantillons joues")
        for mode, entry in modes.items():
            self.assertEqual(entry['Samples'], 3, mode)
            self.assertEqual(entry['Rows'], 2000, mode)
            self.assertEqual(entry['NativeEntries'], 4, mode)
            self.assertGreaterEqual(entry['P95Ms'], entry['MedianMs'], mode)
        self.assertEqual(modes['AddType']['Assemblies'], 4)
        self.assertEqual(modes['Precompiled']['Assemblies'], 1)
        self.assertEqual(modes['AddType']['Digest'], modes['Precompiled']['Digest'],
                         'Les deux modes ne rendent plus le meme ouvrage dans la preuve consignee')
        self.assertRegex(modes['AddType']['Digest'], r'^[0-9a-f]{64}$')
        self.assertGreaterEqual(modes['AddType']['MedianMs'], 2 * modes['Precompiled']['MedianMs'],
                                'Le ratio publie ne tient plus : la conclusion de l evaluation est a rejouer')
        m = re.search(r"empreinte `([0-9a-f]{6,})", read(DOC))
        self.assertIsNotNone(m, "L'empreinte d'ouvrage n'est plus citee dans ENGINE_120.md")
        self.assertTrue(modes['AddType']['Digest'].startswith(m.group(1)),
                        "L'empreinte de la preuve n'est plus celle citee dans ENGINE_120.md")


if __name__ == '__main__':
    unittest.main()
