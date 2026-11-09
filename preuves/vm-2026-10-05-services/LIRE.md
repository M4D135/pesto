# 5 octobre 2026 — liste des services en jonction (S1) et libellé « Service » (S2)

Signalés par David : « on n'a plus la liste des services en mode domifier le poste » (critique) et, dans Noms
disponibles, « Service » affiché « Équipe ». Les deux défauts existaient dans la RC23 reçue.

- VM `PESTO-W11-TEST`, session SSH non interactive (session 0, sans bureau), Windows PowerShell 5.1.26100.6584 Desktop,
  hors domaine ; aucun AD réel, aucune mutation. EXE `98eba546…` construit sur le Mac (clang/lld 23.1.2 ; stabilisation et test WPF rejoués sur cet EXE final, `TESTER.cmd` et banc UX joués sur `1870136d…`, qui ne diffère que par deux gardes « pas pendant un traitement »), DEV copié dans
  un `C:\PestoTest` neuf (l'ancien est conservé dans `C:\PestoTest-avant-0510`, EXE `aed2be19…`). Contexte : `contexte.txt`.

| Contrôle | Résultat | Preuve |
|---|---|---|
| Parseur 5.1 | 66 fichiers, 0 erreur | `parse.txt` |
| `--check-json` | Runtime PASS, 38 composants, ParsedFiles 27, EmbeddedScripts 3, AuditWriter PASS | `check-json.json` |
| Stabilisation | 27/27, dont « Services du site : OU du site ou code site du nom » | `stabilisation.txt` |
| WPF réel sans bureau (STA) | 10/10 : `JnService` liste éditable ; services de Paris et de Lyon ; saisie libre conservée après actualisation ; zone éditable 3 caractères en majuscules ; frappe et choix dans la liste invalident le brouillon et relancent le calcul des noms ; changement de site : liste refaite et inventaire demandé ; fenêtre principale réelle : colonne et filtre « Service » | `services-wpf.ps1`, `services-wpf.txt` |
| `TESTER.cmd` | Code 0, 240 OK/PASS, 0 échec | `tester.txt` |
| Banc UX (`Run-UxTests.ps1`) | 42 OK ; 2 « KO » de mise en page hors écran, **identiques sur l'ancien pack** `aed2be19…` (connus en SSH depuis le 04/10) | `ux.txt`, `ux-avant.txt` |

Doubles : aucune lecture AD réelle ; l'inventaire est simulé par des postes fictifs et la demande de lecture est comptée,
pas exécutée. Non joué : vue en session console (démonstration, puis poste hors domaine avec AD réel), export CSV.
Fichiers convertis en UTF-8.
