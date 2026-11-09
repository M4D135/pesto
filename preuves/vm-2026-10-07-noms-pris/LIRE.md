# 7 octobre 2026 — nom pris par un autre poste du banc (S3)

Question de David : trois techniciens sur le banc de master ; si le nom proposé à l'un n'est pas encore validé dans l'AD,
Pesto peut proposer le même nom à un autre. Attendu : revérification juste avant l'opération ; si le nom est pris, le
suivant est proposé et c'est dit. Décision du 07/10 : proposer le nom suivant, confirmation en un clic, jamais d'opération
sous un nom non confirmé.

Avant correctif (code relu) : trois revérifications AD existaient déjà pour la jonction (contrôle, relance au lancement,
juste avant `Add-Computer`) et deux pour le renommage (contrôle, juste avant `Rename-Computer`) ; un nom pris **bloquait**
(« nom déjà utilisé », codes 96, 13 ou 69) sans proposer le suivant.

| Contrôle | Résultat | Preuve |
|---|---|---|
| AD réel du labo (`dc01.labo.local`, compte `LABO\administrateur` saisi par David) | PASS : OU de recette et compte `P111301ZZQA9001` créés (technicien n° 1) ; `Find-ADComputerByName` de Pesto le voit pris aussitôt ; filtre du contrôle de jonction : « Nouveau nom : Bloqué » ; compte et OU supprimés par GUID, contrôle final : absent | `banc-noms-pris.txt`, `outils/labo/vm/banc-noms-pris.ps1` |
| Vraie vue de jonction, WPF sous Windows PowerShell 5.1 (sans bureau, doubles pour l'AD) | 11/11 : nom pris au contrôle → nom suivant sélectionné, message avec les deux noms, relance du contrôle puis confirmation ; nom pris entre confirmation et ajout (code 13) → idem, sans bilan final ; borne à 5 bascules ; autre refus inchangé | `noms-pris-wpf.ps1`, `noms-pris-wpf.txt` |

EXE `9eb555ed…`, stabilisation 27/27, `--check --quiet` 0. Non testé : deux postes réels simultanés (une seule VM Pesto),
renommage direct en session (même logique, tests statiques seulement), course entre deux contrôleurs de domaine (un seul DC
au labo).

## Banc moteur sur l'AD réel (07/10 vers 21 h 10)

`banc-moteur-ad.txt` (`outils/labo/*/banc-moteur-ad.*`, compte `LABO\administrateur` saisi par David) : OU de recette
`Pesto-20261007-recette` (ROOT, Staging, SITES/ALPHA et BETA) et 4 postes désactivés créés, puis le **vrai worker de lecture
AD** de Pesto et ses fonctions : contrôleur = émulateur PDC (`dc01`, rôle PDC) ; sites ALPHA et BETA ; inventaire complet ;
services ALPHA = INF, RH0 et BETA = CPT ; premier nom proposé P999007AAINF003 ; ce nom créé par un « technicien n° 1 » est vu
pris sur le PDC ; nom suivant P999007AAINF004, libre. 8/8. Nettoyage : 5 postes et 6 OU supprimés, OU de recette absente.
Labo à un seul DC : la bascule vers un PDC distinct du DC découvert reste non observée.
