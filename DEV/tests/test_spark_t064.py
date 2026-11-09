"""Point 64 : pagination/top-k Common.Query.

Controle statique : la pagination est bien branchee sur le registre (Offset, Limit, tri Updated
decroissant, retour a la derniere page), la suite du moteur compare le chemin integre a un oracle
de tri complet independant, et le banc du moteur mesure les deux sur 100/1 000/10 000 lignes en
refusant toute mesure ou les pages divergent. Ce module n'execute pas PowerShell : l'execution
est faite par tests/Run-Engine120Tests.ps1 et tests/Measure-Engine120.ps1 eux-memes.
"""
import json
import sys
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEV / "tests"))
from ps_lexical import functions  # noqa: E402

WAD = DEV / "wad"
INTERVENTIONS = WAD / "Pesto-Interventions.ps1"
ENGINE_SUITE = DEV / "tests" / "Run-Engine120Tests.ps1"
ENGINE_MEASURE = DEV / "tests" / "Measure-Engine120.ps1"
CATALOGUE = DEV / "docs" / "implementation" / "catalogue-120.json"


def read_ps(path):
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf"), "UTF-8 BOM attendu : " + str(path)
    return raw.decode("utf-8-sig")


def body(text, name):
    spans = functions(text)
    assert name in spans, "Fonction absente : " + name
    start, stop = spans[name]
    return text[start:stop]


class TestPestoQueryPaging(unittest.TestCase):
    def test_shipped_query_is_paged_sorted_and_wired(self):
        text = read_ps(INTERVENTIONS)
        query = body(text, "Get-PestoInterventionQuery")
        for needle in ("$options.Offset=$Offset", "$options.Limit=$PageSize",
                       "$options.SortField='Updated'", "$options.Descending=$true"):
            self.assertIn(needle, query, "La requete livree ne cablerait plus " + needle)
        self.assertIn("-Offset $ui.Offset -PageSize $ui.PageSize", text,
                      "La page du registre ne passerait plus decalage et taille de page a la requete")
        self.assertIn("-State $state -PageSize 5000", text,
                      "L export ne relirait plus tout le filtre au-dela de la page affichee")

    def test_engine_suite_compares_paging_to_independent_full_sort(self):
        # Sans oracle independant, la comparaison serait tautologique : l integrated se comparerait a
        # lui-meme. La fonction testee est relue de la source livree, jamais recopiee dans la suite.
        suite = read_ps(ENGINE_SUITE)
        self.assertNotIn("function Get-PestoInterventionQuery", suite,
                         "La suite redefinirait la requete ici et repondrait d'une copie")
        self.assertIn("FunctionDefinitionAst", suite,
                      "La suite ne relirait plus Get-PestoInterventionQuery dans la source livree")
        for needle in ("Get-PestoEngineQueryFullSort", "OrderByDescending", "OrdinalIgnoreCase",
                       "La pagination integree rend la meme page que le tri complet existant",
                       "La pagination recouvre le tri complet sans doublon ni omission",
                       "Le registre reste branche sur la pagination Common.Query",
                       "q000248|q000249", "Retour a la derniere page"):
            self.assertIn(needle, suite, needle + " : la comparaison page a page a disparu de la suite")

    def test_engine_measure_compares_integrated_path_on_volumes(self):
        measure = read_ps(ENGINE_MEASURE)
        self.assertNotIn("function Get-PestoInterventionQuery", measure,
                         "Le banc redefinirait la requete ici et repondrait d'une copie")
        self.assertIn("Initialize-PestoCommon", measure,
                      "Le banc ne chargerait plus les vraies DLL Common.Query")
        for needle in ("Query.Paging.Integrated", "Query.FullSort.Existing",
                       "Pagination integree et tri complet existant non equivalents",
                       "QueryPaging=$pagingSummary", "QueryPagingSamples=$pagingMeasures.ToArray()",
                       "IntegratedMedianMs", "FullSortMedianMs"):
            self.assertIn(needle, measure, needle + " : la mesure comparee ne sort plus du rapport")
        self.assertIn("foreach($count in @(100,1000,10000))", measure,
                      "La mesure comparee ne couvre plus les trois volumes")

    def test_catalogue_records_the_integrated_paging(self):
        catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8-sig"))
        item = next(i for i in catalogue["items"] if i["id"] == 64)
        self.assertEqual("implemented", item["state"],
                         "La pagination est branchee et comparee : le point ne peut rester en cours")
        self.assertIn("tri complet", item["implementation"])
        for evidence in item["evidence"]:
            self.assertTrue((DEV.parent / evidence).is_file(), evidence)
        states = [i["state"] for i in catalogue["items"]]
        declared = dict(catalogue["counts"]["states"])
        for state, total in declared.items():
            self.assertEqual(total, states.count(state), "Total " + state + " du catalogue perime")
        self.assertEqual(len(states), sum(declared.values()))


if __name__ == "__main__":
    unittest.main()
