# 8 octobre 2026 — nom pris : essais successifs puis abandon (signalé par David)

Signalement : « il cherche plusieurs poste à la mise sur domaine avant de trouver le bon alors qu'avant il trouvait le bon
poste direct. aussi, il cherche 3 postes et abandonne, il faut le relancer ».

Causes (code relu) :

1. Noms proposés calculés sur l'inventaire local (OU racine, chargé en arrière-plan hors domaine) ; contrôle AD sur tout le
   domaine. Inventaire absent ou plus étroit : chaque numéro pris coûtait un contrôle AD complet.
2. Inventaire arrivé pendant l'enchaînement : liste recalculée, sélection changée, contrôle en cours rejeté (« Contrôle
   périmé. Relancez la vérification. ») : arrêt.
3. Compteur de bascules remis à zéro seulement après un contrôle réussi ou à l'ouverture de la vue.

Correctifs (`Pesto-Join.ps1`, `Pesto-Core.ps1`, `Pesto-Direct.ps1`) : série du nom pris (12 premiers caractères) lue dans
tout le domaine en une requête (nom, sAMAccountName, dNSHostName) et écartée pour la session, en jonction et au contrôle
préalable du renommage ; lecture d'appoint (un échec ne change rien d'autre) ; relance automatique quand seule la liste a
changé (3 au plus) ; compteurs remis à zéro à chaque clic ; inventaire des noms (OUScanNoms) pris en compte. Nom suivant
toujours annoncé, revérifié et confirmé par le technicien.

| Contrôle | Résultat | Preuve |
|---|---|---|
| Mac : tests Python, contrôles portables, UX, connexion compacte, banc C | 254 tests OK ; 344/344 ; 50/50 ; 33/33 ; 48 scénarios C | — |
| Windows PowerShell 5.1 sur `PESTO-W11-TEST` (sans bureau) : parseur, `--check-json` DEV et PROD, RC23, stabilisation | 66 fichiers / 0 erreur ; 0 et 0 ; 65 contrôles, 0 échec, 1 ignoré ; 27/27 | `controles-windows.txt` |
| Vraie vue de jonction, WPF sous 5.1 (STA, doubles pour l'AD) : cas du 07/10 + série, inventaire arrivé pendant le contrôle, résultat valide mais périmé, bornes, refus 13 avec série | 25/25 | `noms-suite-wpf.ps1`, `noms-suite-wpf.txt` |
| Instruction de série extraite des fichiers livrés, exécutée sous 5.1 avec un double de `Get-ADComputer` (variantes sAMAccountName, dNSHostName en minuscules) | série 001, 002, 003, 005 ; nom suivant 004 | `outils/labo/vm/banc-noms-serie.ps1` (contrôle à blanc) |
| AD réel du labo (`banc-noms-serie.sh`, compte saisi par David) | en attente de la saisie de David | `banc-noms-serie.txt` |

EXE `4636913b…` (clang/lld 23.1.2). Packs : `pesto-packs/2026-10-08-noms-suite`. Non testé : plusieurs postes réels en
même temps, vue en session console avec l'AD réel (la VM est hors domaine, instantané 04).
