# 8 octobre 2026 — « Vérification requise » en renommage alors que tout est rempli (signalé par David)

Signalement : « blocage sur vérification requise alors que tous les champs sont remplis en renommage... teste en mise
domaine ». Enchaînement probable sur le réseau réel : mise au domaine par Pesto, redémarrage, puis renommage.

Causes : reçu de jonction « à vérifier » après redémarrage (`ReadyToObserve`, `Get-PestoJoinReceiptDecision`) qui bloque
toute écriture ; cause précise écrasée par un texte général dans « Un poste » ; « Enregistrer » sans changement qui posait
« redémarrage requis » quand `EntraPolicy` manquait au cfg.json.

| Contrôle | Résultat | Preuve |
|---|---|---|
| Banc 5.1 (vraies fonctions `Get-PestoPrimaryContext`, `Get-PestoPrimaryStep`, `Invoke-PestoPrimaryAction`, `Get-PestoConfigurationSignature` ; vrais contrôles WPF ; cfg.json livré, non versionné) | 14/14 | `blocage-wpf.ps1`, `blocage-wpf.txt` |
| Même banc sur la version précédente (contre-épreuve) | 9 échecs : texte général, aucun bouton actif, redémarrage après « Enregistrer » | `blocage-wpf-version-precedente.txt` |
| Parseur, `--check-json` DEV et PROD, RC23, stabilisation, bancs noms et services, UX | 66/0 ; 0 et 0 ; vert ; 27/27 ; 25/25 ; 14/14 ; 42/44 (2 KO sans bureau, identiques avant) | `controles-windows.txt` |

EXE `ef0cc654…`. Non joué : enchaînement réel jonction, redémarrage, vérification, renommage sur l'AD (identifiants de David).
