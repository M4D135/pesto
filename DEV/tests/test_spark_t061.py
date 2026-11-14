"""Point 61 : mise a jour WPF des seules lignes modifiees.

Ce module controle la source PowerShell 5.1 livree : il prouve que le mecanisme
incremental existe, qu il est branche sur le registre des interventions et que la
suite portable le couvre. Il controle aussi le banc qui doit en repondre,
tools/Measure-PestoWpfProjection.ps1 : celui-ci exerce le helper livre relu dans
wad/, jamais une copie locale. Il n execute ni WPF ni Windows PowerShell : le rendu
visuel reste a qualifier sur un poste Windows.
"""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEV / "tests"))
from ps_lexical import functions, smart_quote_hazards, tokens  # noqa: E402

WAD = DEV / "wad"
COLLECTIONS = WAD / "Pesto-Collections.ps1"
INTERVENTIONS = WAD / "Pesto-Interventions.ps1"
CORE = WAD / "Pesto-Core.ps1"
SUITE = DEV / "tests" / "Run-Collections120Tests.ps1"
BENCH = DEV / "tools" / "Measure-PestoWpfProjection.ps1"
BENCH_COMMON = DEV / "tools" / "PestoWpfBench.Common.ps1"
BENCH_SMOKE = DEV / "tests" / "Run-WpfProjectionBenchTests.ps1"
ENGINE_SUITE = DEV / "tests" / "Run-Engine120Tests.ps1"
ENGINE_MEASURE = DEV / "tests" / "Measure-Engine120.ps1"

PS7_ONLY = ("-Parallel", "Get-Error", "&&", "||", "?.", "?? ")

# Meme liste que Build-PestoEngineModule.ps1 : le module Engine est genere a partir de ces seules sources.
ENGINE_NAMES = ("Core", "Startup", "Authentication", "Integrity", "Common", "Contracts", "Configuration",
                "ManagedPolicy", "Policy", "Directory", "Async", "Journal", "AuditSink", "Operations", "Safety",
                "JoinRecovery", "Recovery", "Preparation", "Names", "Direct", "Join", "Inspection", "Support",
                "EngineContracts", "Diagnostics", "Catalogue", "Automation", "Enterprise", "Extensions")


def read_ps(path):
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf"), "UTF-8 BOM attendu : " + str(path)
    return raw.decode("utf-8-sig")


def body(text, name):
    spans = functions(text)
    assert name in spans, "Fonction absente : " + name
    start, stop = spans[name]
    return text[start:stop]


def worker_extent(texts, name):
    """Extents du texte de `$name = {...}` : la variable jusqu'a l'accolade fermante du bloc."""
    for text in texts.values():
        for kind, start, stop in tokens(text):
            if kind != "word" or text[start:stop] != name or not start or text[start - 1] != "$":
                continue
            opening = text.index("{", text.index("=", stop))
            depth = 0
            for index in range(opening, len(text)):
                if text[index] == "{":
                    depth += 1
                elif text[index] == "}":
                    depth -= 1
                    if depth == 0:
                        return "$" + text[start:index + 1]
    raise AssertionError("Worker moteur absent des sources : " + name)


def engine_runtime_bytes(meta):
    """Reconstruit Pesto.Engine.Runtime.ps1 exactement comme le script de build PowerShell."""
    funcs = {}
    order = []
    texts = {}
    for name in ENGINE_NAMES:
        path = WAD / ("Pesto-" + name + ".ps1")
        if not path.exists():
            continue
        text = read_ps(path)
        texts[path.name] = text
        for function, (start, stop) in functions(text).items():
            if function in funcs:
                continue
            funcs[function] = text[start:stop]
            order.append(function)
    parts = ["# Généré par Build-PestoEngineModule.ps1. Définitions uniquement ; ne pas éditer."]
    parts += [funcs[name] for name in order]
    parts.append("$script:PestoWorkerCoreNames=@(" + ",".join("'" + c + "'" for c in meta["WorkerClosure"]) + ")")
    for worker in meta["Workers"]:
        parts.append(worker_extent(texts, worker))
    assert len(order) == meta["Functions"], "Fonctions moteur : %d reconstruites vs %d declarees" % (
        len(order), meta["Functions"])
    rendered = ("\r\n".join(parts) + "\r\n").replace("\r\n", "\n").replace("\n", "\r\n")
    return b"\xef\xbb\xbf" + rendered.encode("utf-8")


class TestWpfIncrementalRows(unittest.TestCase):
    def test_sources_parse_as_balanced_powershell(self):
        for path in (COLLECTIONS, INTERVENTIONS, CORE, SUITE):
            with self.subTest(path=path.name):
                tokens(read_ps(path))

    def test_no_typographic_quotes_inside_powershell_strings(self):
        for path in (COLLECTIONS, INTERVENTIONS, CORE, SUITE):
            with self.subTest(path=path.name):
                self.assertEqual([], smart_quote_hazards(read_ps(path)))

    def test_line_endings_are_preserved_per_file(self):
        self.assertIn(b"\r\n", COLLECTIONS.read_bytes())
        self.assertNotIn(b"\r\n", INTERVENTIONS.read_bytes())
        core = CORE.read_bytes()
        self.assertTrue(core.startswith(b"\xef\xbb\xbf"), "Pesto-Core.ps1 doit garder son BOM")
        self.assertNotIn(b"\r\n", core, "Pesto-Core.ps1 est livré en LF : le module Engine est haché octet à octet")

    def test_row_update_helpers_are_defined(self):
        text = read_ps(COLLECTIONS)
        spans = functions(text)
        for name in ("Get-PestoGridRowId", "New-PestoGridRowCollection", "Update-PestoGridRows"):
            self.assertIn(name, spans)
        self.assertIn("ObservableCollection[object]", body(text, "New-PestoGridRowCollection"))

    def test_update_only_touches_changed_rows_and_keeps_the_view(self):
        text = body(read_ps(COLLECTIONS), "Update-PestoGridRows")
        self.assertIn("[object]::ReferenceEquals($current,$target)", text)
        self.assertIn("Get-PestoStableHash", text)
        self.assertIn("$collection[$i]=$target", text)
        self.assertIn("SortDescriptions", text)
        self.assertIn("$Grid.SelectedItem=$restored", text)
        self.assertIn("ScrollIntoView", text)
        self.assertIn("MaximumInPlaceOperations", text)
        self.assertNotIn("Move($i,", text)

    def test_row_identity_is_required_and_unique(self):
        text = body(read_ps(COLLECTIONS), "Update-PestoGridRows")
        self.assertIn("dupliquée dans le tableau", text)
        self.assertIn("dupliquée dans le résultat", text)
        helper = body(read_ps(COLLECTIONS), "Get-PestoGridRowId")
        self.assertIn("Identité de ligne absente", helper)
        self.assertIn("Identité de ligne vide", helper)

    def test_row_identity_lookup_is_direct_and_still_case_strict(self):
        # L'identite etait lue en enumerant toutes les proprietes de la ligne, sept fois par ligne
        # affichee. L'indexeur est direct et refuse toujours une propriete dont seule la casse differe.
        helper = body(read_ps(COLLECTIONS), "Get-PestoGridRowId")
        self.assertIn("$Row.PSObject.Properties[$IdProperty]", helper)
        self.assertIn("$property.Name -cne $IdProperty", helper)
        self.assertIn("if($null -eq $value)", helper,
                      "Une propriete presente mais vide doit rester refusee comme identite absente")
        self.assertNotIn("foreach($property in $Row.PSObject.Properties)", helper,
                         "L'enumeration de toutes les proprietes etait payee a chaque lecture d'identite")

    def test_row_identity_is_read_once_per_side_and_the_suite_counts_it(self):
        # Le contrat du chemin livre ne porte pas que sur les notifications : relue a chaque phase,
        # l'identite faisait payer le prix de toute la page affichee pour une seule ligne changee.
        text = body(read_ps(COLLECTIONS), "Update-PestoGridRows")
        # Cinq occurrences, et chacune est hors du chemin ordinaire ou lineaire par nature : la ligne
        # selectionnee (une par projection), la liaison complete, les deux cotes de la comparaison, et le
        # seul repli de rendu de la selection. Le chemin en place n'en fait que deux par ligne.
        self.assertLessEqual(text.count("Get-PestoGridRowId"), 5,
                             "L'identite de ligne est relue par phase au lieu d'une fois par cote")
        self.assertIn("$sourceIds=[Collections.Generic.List[string]]::new()", text)
        self.assertIn("$nextIds=[Collections.Generic.List[string]]::new()", text)
        self.assertIn("$liveIds[$i] -ceq $id", text)
        self.assertNotIn("foreach($key in @($positions.Keys))", text,
                         "Chaque suppression corrigerait les index en relisant toute la page")
        suite = read_ps(SUITE)
        self.assertIn("A projection reads each row identity once per side", suite)
        self.assertIn("$script:PestoRowIdCalls -eq (2*$rendered.Count)", suite,
                      "Le nombre de lectures d'identite n'est plus asserte a volume")
        self.assertIn("Set-Item -LiteralPath 'function:\\Get-PestoGridRowId' -Value $script:PestoRowIdOriginal", suite,
                      "La fonction d'identite doit etre restituee a la suite")

    def test_no_powershell_seven_only_construct(self):
        # Pesto-Core.ps1 est hors de ce balayage : il porte deja Get-ErrorDetail, dont le simple
        # test de sous-chaine ferait un faux positif. La compatibilite 5.1 du moteur est couverte
        # par tests/test_ps51_compat.py et par le garde-fou de module Engine ci-dessous.
        for path in (COLLECTIONS, INTERVENTIONS, SUITE):
            text = read_ps(path)
            for token in PS7_ONLY:
                self.assertNotIn(token, text, token + " interdit en PowerShell 5.1")

    def test_names_page_adds_no_powershell_seven_only_construct(self):
        text = body(read_ps(CORE), "Complete-PestoNamesProjection")
        for token in PS7_ONLY:
            self.assertNotIn(token, text, token + " interdit en PowerShell 5.1")

    def test_ledger_page_is_the_wired_consumer(self):
        text = body(read_ps(INTERVENTIONS), "Update-PestoInterventionPage")
        self.assertIn("Update-PestoGridRows -Grid $ui.Grid", text)
        self.assertIn("-IdProperty 'RowId'", text)
        self.assertNotIn("$ui.Grid.ItemsSource", text)

    def test_ledger_no_longer_rebinds_the_whole_grid(self):
        text = read_ps(INTERVENTIONS)
        self.assertNotIn("$ui.Grid.ItemsSource=", text)

    def test_names_page_is_the_second_wired_consumer(self):
        text = body(read_ps(CORE), "Complete-PestoNamesProjection")
        self.assertIn("Update-PestoGridRows -Grid $NmGrid", text)
        self.assertIn("-IdProperty 'Nom'", text)
        # Le recalcul de page ne remplace plus tout le tableau d'un coup.
        self.assertNotIn("$NmGrid.ItemsSource=$Result.Rows", text)

    def test_names_page_keeps_the_saved_view_sort_priority(self):
        text = body(read_ps(CORE), "Complete-PestoNamesProjection")
        self.assertLess(text.index("Update-PestoGridRows -Grid $NmGrid"), text.index("$script:PestoNamesViewSort"),
                        "Le tri porte par la vue ecrase desormais celui demande par la vue enregistree")

    def test_queue_pump_no_longer_force_refreshes_the_bound_dataview(self):
        # La file etait la derniere liaison qui reciait tous ses conteneurs de ligne a chaque ligne
        # traitee : Sync-Grid forcait le rafraichissement complet alors que la DataView, reliee par
        # New-QueueTable et par tous les replis de re-liaison, notifie deja chaque DataRow ecrite.
        # Le rafraichissement complet ne reste que le repli des liaisons qui ne notifient rien.
        sync = body(read_ps(CORE), "Sync-Grid")
        self.assertIn("$source=$Grid.ItemsSource", sync)
        self.assertIn("[Data.DataView]", sync)
        self.assertIn("[Collections.Specialized.INotifyCollectionChanged]", sync)
        self.assertLess(sync.index("if($source -is"), sync.index("$Grid.Items.Refresh()"),
                        "Items.Refresh() doit rester derriere la garde de liaison muette")
        self.assertIn("CommitEdit", sync)
        self.assertIn("CancelEdit", sync)
        # La file n'est jamais reliee a autre chose qu'a sa DataView : le chemin garde ne peut
        # pas etre atteint par erreur sur la seule liaison vivante du produit.
        core = read_ps(CORE)
        self.assertIn("$Grid.ItemsSource = $script:table.DefaultView", core)
        self.assertIn("$Grid.ItemsSource=$candidate.DefaultView", core)
        self.assertNotIn("$Grid.ItemsSource=@(", core, "La file n'est jamais reliee a un tableau muet")
        self.assertNotIn("$Grid.ItemsSource=$rows", core)

    def test_portable_suite_covers_the_queue_refresh_contract(self):
        suite = read_ps(SUITE)
        self.assertIn("'Sync-Grid'", suite, "Sync-Grid doit etre chargee par la suite portable")
        for needle in ("The queue pump no longer force-refreshes its DataView-bound grid",
                       "A queue status write notifies its own cell and nothing else",
                       "A silent binding still gets the full refresh fallback"):
            self.assertIn(needle, suite)
        self.assertIn("-Value {,$script:QueueGridSource}", suite,
                      "Le getter de la grille factice de file doit emettre la source elle-meme, pas son enumeration")

    def test_names_rows_carry_the_identity_the_grid_is_updated_by(self):
        text = read_ps(CORE)
        self.assertIn("Nom=$name", text, "Le nom n'est plus la premiere propriete de la ligne projetee")

    def test_wpf_bench_measures_the_delivered_helper_not_a_copy(self):
        # L'evaluation du point 61 ne vaut que si le banc WPF exerce le chemin reellement livre. Une copie
        # locale du helper dans tools/ mesurerait une implementation qui n'est jamais chargee par Pesto.
        bench = read_ps(BENCH)
        common = read_ps(BENCH_COMMON)
        smoke = read_ps(BENCH_SMOKE)
        for copied in ("function Update-PestoGridRows", "function New-PestoGridRowCollection",
                       "function Get-PestoGridRowId", "function Get-PestoStableHash"):
            self.assertNotIn(copied, bench, copied + " : le banc recopie le helper livre au lieu de le charger")
            self.assertNotIn(copied, common, copied + " : le banc recopie le helper livre au lieu de le charger")
        self.assertIn("Get-PestoBenchGridHelperDefinitions -Root (Split-Path $PSScriptRoot -Parent)", bench)
        self.assertIn("[void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId')", bench)
        self.assertIn("'ObservableInPlace'", bench)
        # Le chargement se fait par analyse syntaxique des sources livrees, sans module ni execution de Pesto.
        extraction = common[common.index("function Get-PestoBenchGridHelperDefinitions"):]
        self.assertIn("FunctionDefinitionAst", extraction)
        self.assertIn("Extent.Text", extraction)
        for helper in ("Get-PestoGridRowId", "New-PestoGridRowCollection", "Update-PestoGridRows",
                       "Get-PestoStableHash"):
            self.assertIn("'" + helper + "'", extraction, helper + " n'est plus relu depuis la source livree")
        # Le contrat mesure sur un vrai tableau WPF : une notification par ligne changee, tri et selection gardes.
        self.assertIn("'FullRebind,InPlace,ObservableInPlace'", smoke)
        for needle in ("Notifications", "SortKept", "SelectionKept"):
            self.assertIn(needle, smoke, needle + " : la fumee Windows ne releve plus le contrat du chemin livre")
        for path in (BENCH, BENCH_COMMON, BENCH_SMOKE):
            for token in PS7_ONLY:
                self.assertNotIn(token, read_ps(path), path.name + " : " + token + " interdit en PowerShell 5.1")

    def test_ledger_query_renders_the_instances_already_displayed(self):
        # Tout le contrat de cout du chemin livre repose sur la reuse d'instance : tant que la requete du
        # registre rend les objets deja affiches, une ligne inchangee ne coute aucune empreinte. Si elle
        # rendait des clones, chaque page repaierait une empreinte canonique par ligne sans en remplacer
        # une seule, et les vingt cas portables ne prouveraient plus rien sur le produit.
        text = body(read_ps(INTERVENTIONS), "Get-PestoInterventionQuery")
        self.assertIn("$byId[[string]$row.RowId]=$row", text)
        self.assertIn("$byId[$record.Id]", text)
        self.assertNotIn("Copy()", text, "La requete du registre recopierait les lignes rendues")

    def test_names_projection_rebuilds_every_row_so_its_cost_profile_differs(self):
        # Consignee, pas corrigee : la page de noms sort du moteur avec des instances neuves a chaque calcul,
        # donc chaque projection paie une empreinte canonique par ligne affichee, y compris quand rien n'a
        # change. Le gain reel du chemin livre est celui du registre, qui relit sans reprojeter.
        consumer = body(read_ps(CORE), "Complete-PestoNamesProjection")
        self.assertIn("$rows=@($Result.Rows)", consumer)
        producer = body(read_ps(CORE), "Invoke-PestoBuildNamesView")
        self.assertIn("$rows.Add($row)", producer)
        self.assertIn("$row=& $makeRow", producer)
        self.assertNotIn("PestoRowFingerprints", producer,
                         "La projection des noms pretendrait réutiliser un cache qu'elle ne reçoit jamais")

    def test_generated_engine_runtime_matches_the_delivered_sources(self):
        meta = json.loads((WAD / "Pesto.Engine.build.json").read_text(encoding="utf-8-sig"))
        runtime = (WAD / "Pesto.Engine.Runtime.ps1").read_bytes()
        rebuilt = engine_runtime_bytes(meta)
        self.assertEqual(rebuilt, runtime, "Pesto.Engine.Runtime.ps1 ne correspond plus aux sources du moteur")
        digest = hashlib.sha256(runtime).hexdigest()
        self.assertEqual(meta["RuntimeSHA256"], digest, "Empreinte du runtime perimee dans Pesto.Engine.build.json")
        module = (WAD / "Pesto.Engine.psm1").read_text(encoding="utf-8-sig")
        self.assertIn(digest, module, "Pesto.Engine.psm1 ne refuse pas le runtime livre : empreinte divergente")

    def test_portable_suite_covers_the_incremental_path(self):
        text = read_ps(SUITE)
        for name in ("Get-PestoGridRowId", "New-PestoGridRowCollection", "Update-PestoGridRows"):
            self.assertIn("'" + name + "'", text, name + " doit etre charge par la suite")
        for needle in (
            "notifies no row at all",
            "Only the row whose receipt changed",
            "Selection follows the receipt identity",
            "Selection is cleared when the selected receipt leaves the page",
            "restored when a full rebind drops it",
            "keep the requested page order",
            "replaces only the row whose availability changed",
            "follows the candidate name across a re-projected page",
            "A names page change falls back to one full rebind",
            "The names page updates its rows in place",
            "At a thousand rows only the changed rows are replaced and notified",
            "The row fingerprint is computed only for rows projected again",
            "A projection reads each row identity once per side and not once per phase",
            "In-place update and full rebind are measured at the same volume",
        ):
            self.assertIn(needle, text)

    def test_portable_suite_quantifies_the_incremental_path_at_volume(self):
        # Le contrat du point 61 est un contrat de cout : il doit etre verifie a volume reel, pas seulement
        # sur deux lignes, et la mesure doit sortir du rapport pour etre relue dans la CI Windows.
        text = read_ps(SUITE)
        volume = text[text.index("At a thousand rows"):text.index("The row fingerprint is computed")]
        self.assertIn("New-BulkLedgerRows 1000", volume)
        self.assertIn("foreach($changed in @(1,10,100))", volume)
        for needle in ("(-not $r.Rebound)", "$r.Replaced -eq $changed", "$r.Unchanged -eq ($rendered.Count-$changed)",
                       "$script:LedgerNotifications.Count -eq $changed", "[object]::ReferenceEquals($grid.ItemsSource[$i],$rendered[$i])"):
            self.assertIn(needle, volume, needle + " : le contrat de cout n'est plus asserte a volume")
        cost = text[text.index("The row fingerprint is computed"):text.index("In-place update and full rebind are measured")]
        self.assertIn("Set-Item -LiteralPath 'function:\\Get-PestoStableHash' -Value $wrapper", cost)
        self.assertIn("$script:PestoHashCalls -eq 5", cost)
        self.assertIn("finally", cost, "La fonction d'empreinte doit etre restituee a la suite")
        self.assertIn("Set-Item -LiteralPath 'function:\\Get-PestoStableHash' -Value $script:PestoHashOriginal", cost)
        report = text[text.index("$failed=@($results"):]
        self.assertIn("GridRowUpdate=$script:PestoGridMeasure.ToArray()", report,
                      "La mesure consignée ne sort pas du rapport de la suite")

    def test_fingerprint_cache_is_attached_to_the_collection_and_rewatched_once(self):
        # Trois defauts rendaient fausse la preuve du point pendant quatre sous-lots, et aucun ne se
        # voyait a la lecture de la source : la note d'empreintes etait pipee aux lignes plutot qu'a la
        # collection, le getter de la grille factice rendait un Object[], et l'abonnement s'accumulait.
        text = read_ps(COLLECTIONS)
        self.assertIn("Add-Member -InputObject $collection -NotePropertyName PestoRowFingerprints", text,
                      "Le cache d'empreintes doit etre pose sur la collection liee, jamais pipe aux lignes")
        self.assertNotIn("|Add-Member -NotePropertyName PestoRowFingerprints", text,
                         "Le pipeline repandrait la note sur chaque ligne et rendrait le cache illisible")
        self.assertIn("$stored -is [hashtable]", text, "La source du cache doit rester un hashtable")
        suite = read_ps(SUITE)
        self.assertIn("-Value {,$script:FakeGridSource}", suite,
                      "Le getter de la grille factice doit emettre la collection elle-meme, pas son enumeration")
        self.assertNotIn("-Set {", suite, "Add-Member n'a pas de parametre -Set : le setter etait ignore")
        self.assertIn("remove_CollectionChanged($script:LedgerHandler)", suite,
                      "Sans desabonnement, chaque iteration compte deux fois chaque notification")
        self.assertIn("NotifyCollectionChangedEventHandler", suite,
                      "Le delegue de CollectionChanged n'est pas EventHandler<T>")

    def test_catalogue_records_delivery_and_remaining_windows_qualification(self):
        catalogue = json.loads((DEV / "docs" / "implementation" / "catalogue-120.json").read_text(encoding="utf-8-sig"))
        item = next(i for i in catalogue["items"] if i["id"] == 61)
        # Le code et le lanceur sont livres ; le rendu WPF cible reste a qualifier.
        self.assertEqual("implemented", item["state"])
        self.assertIn("Windows PowerShell 5.1", item["remaining"])
        self.assertIn("Measure-PestoWpfProjection.ps1", item["remaining"])
        self.assertNotIn("refuse de charger PowerShell", item["remaining"])
        for evidence in item["evidence"]:
            self.assertTrue((DEV.parent / evidence).is_file(), evidence)
        # L'etat declare doit rester coherent avec les totaux publies du catalogue.
        states = [i["state"] for i in catalogue["items"]]
        declared = dict(catalogue["counts"]["states"])
        for state, total in declared.items():
            self.assertEqual(total, states.count(state), "Total " + state + " du catalogue perime")
        self.assertEqual(len(states), sum(declared.values()))

    def test_runtime_manifest_hashes_match_the_delivered_files(self):
        tracked = ("wad/Pesto-Collections.ps1", "wad/Pesto-Interventions.ps1", "wad/Pesto-Core.ps1",
                   "wad/Pesto.Engine.Runtime.ps1", "wad/Pesto.Engine.psm1", "wad/Pesto.Engine.build.json")
        manifest = json.loads((WAD / "package.json").read_text(encoding="utf-8-sig"))
        entries = {entry["Path"]: entry["SHA256"] for entry in manifest["Files"]}
        self.assertEqual([], [path for path in tracked if path not in entries])
        for path in tracked:
            digest = hashlib.sha256((DEV / path).read_bytes()).hexdigest()
            self.assertEqual(entries[path], digest, path + " : manifest perime")

    def test_native_launcher_header_pins_the_delivered_runtime_bytes(self):
        # pesto_runtime.h est l'entree de la recompilation epinglee : s'il reste perime, le prochain
        # Pesto.exe de la chaîne LLVM serait compile contre les empreintes d'un etat anterieur.
        sys.path.insert(0, str(DEV / "tools"))
        from refresh_manifest import runtime_files, safe_file
        header = (DEV / "tools" / "launcher" / "pesto_runtime.h").read_text(encoding="utf-8")
        paths = [p for p in runtime_files(DEV) if p != "Pesto.exe"]
        self.assertIn("#define PESTO_RUNTIME_COUNT %d" % len(paths), header)
        stale = [p for p in paths
                 if p + "|" + hashlib.sha256(safe_file(DEV, p).read_bytes()).hexdigest() not in header]
        self.assertEqual([], stale, "pesto_runtime.h perime : relancer generate_binding.py avant la recompilation")

    def test_integrity_gate_names_every_divergent_component(self):
        # Le blocage du point 61 a ete sous-estime pendant quatre sous-lots parce que la borne ne nommait
        # que la premiere divergence : un seul commit en wad/ en desaligne souvent plusieurs composants.
        sys.path.insert(0, str(DEV / "tools"))
        import refresh_manifest as integrity
        with tempfile.TemporaryDirectory(prefix="pesto-t061-binding-") as temp:
            root = Path(temp).resolve()
            paths = ["Pesto.exe", "wad/Pesto-Integrity.ps1", "wad/Pesto-Core.ps1",
                     "wad/Pesto-Collections.ps1", "wad/Pesto-Interventions.ps1"]
            (root / "wad").mkdir(parents=True)
            closed = ("# BEGIN Pesto_RUNTIME_FILES\n@(\n"
                      + ",\n".join(repr(p) for p in paths) + ")\n# END Pesto_RUNTIME_FILES\n")
            (root / "wad/Pesto-Integrity.ps1").write_text(closed, encoding="utf-8")
            for relative in paths:
                if relative not in ("Pesto.exe", "wad/Pesto-Integrity.ps1"):
                    (root / relative).write_text("inert fixture: " + relative, encoding="utf-8")
            pinned = [p for p in paths if p != "Pesto.exe"]
            description = "\n".join(p + "|" + "0" * 64 for p in pinned)
            (root / "Pesto.exe").write_bytes(b"INERT - NEVER EXECUTED\nPESTO_BINDING_V1\n"
                                             + description.encode() + b"\nPESTO_BINDING_END")
            with self.assertRaises(ValueError) as caught:
                integrity.verify_native_binding(root)
            message = str(caught.exception)
            for relative in pinned:
                self.assertIn(relative, message, "La borne ne nomme qu'une partie des composants perimes")
            self.assertIn("%d of %d" % (len(pinned), len(pinned)), message,
                          "La borne ne dit pas combien de composants la recompilation doit reprendre")

    def test_engine_measure_script_measures_the_delivered_row_path(self):
        # Le catalogue nomme tests/Measure-Engine120.ps1 comme preuve du point 61. Jusqu'au 18 octobre
        # ce fichier ne disait rien du contrat : une preuve nommee qui ne porte pas son objet se relit
        # verte alors que la mesure n'a jamais existe. Le banc du moteur mesure donc le helper livre,
        # par echantillons repetes, et refuse une mesure tombee sur le repli de liaison complete.
        text = read_ps(ENGINE_MEASURE)
        self.assertIn("Get-PestoBenchGridHelperDefinitions", text,
                      "La mesure du moteur doit exercer le helper relu des sources livrees, jamais une copie")
        self.assertNotIn("function Update-PestoGridRows", text,
                         "Le banc redéfinirait le helper ici et repondrait d'une copie")
        for needle in ("GridRowUpdate.InPlace.", "ReusedInstances", "FreshInstances",
                       "GridRowUpdate=$gridSummary", "GridRowSamples=$gridMeasures.ToArray()",
                       "MedianMs", "P95Ms", "Notifications=$update.Replaced"):
            self.assertIn(needle, text, needle + " : la mesure du chemin en place ne sort plus du rapport")
        self.assertIn("if($update.Rebound -or $update.Replaced -ne $changed)", text,
                      "Rien arrete desormais une mesure tombee sur le repli de liaison complete")

    def test_engine_suite_guards_the_shipped_helper_and_its_fingerprint(self):
        # La suite portable joue le comportement du helper ; la suite du moteur repond que le produit
        # charge atteint vraiment le helper livre, et que sa regle d'empreinte reste la meme d'un
        # runspace a l'autre. Sans ces deux cas le point pouvait disparaitre du produit sans refus.
        text = read_ps(ENGINE_SUITE)
        for needle in ("Pesto-Collections.ps1", "Update-PestoGridRows", "Get-PestoGridRowId",
                       "New-PestoGridRowCollection", "wad/Pesto-Integrity.ps1"):
            self.assertIn(needle, text, needle + " : la surface livree du point 61 n'est plus gardee")
        for needle in ("Get-PestoStableHash", "[PowerShell]::Create()",
                       "insensible a lordre des proprietes"):
            self.assertIn(needle, text,
                          needle + " : la regle d'empreinte n'est plus assertee par la suite du moteur")


if __name__ == "__main__":
    unittest.main()
