# 8 octobre 2026 — cfg.json livré : Simulation à false, toutes les options, commentaires

Demande de David : « passe simulation à false et donne le zip et ajoute toutes les options dans le cfg.json avec
commentaires ». Le fichier (valeurs de David, DN de l'organisme) n'est pas versionné ; il est livré dans `PESTO/cfg.json`.

- JSON strict (Windows PowerShell 5.1 refuse `//`) : commentaires en clés « _Nom » à la racine, dans `CONF[0]` et `DEBUG`
  (ignorées par Pesto, conservées par « Enregistrer les paramètres ») ; `POLICY` est fermée : ses explications sont dans
  `_POLICY` à la racine.
- Ajouts à valeur par défaut (même comportement) : `Configured`, `EntraPolicy`=HybridOnly, `ClearProtectionOnMove`=true,
  `NameCatalogue`=[], `POLICY` complète. Anciens réglages sans effet listés dans `_Anciens_reglages`.
- Seul changement de comportement : `DEBUG.Simulation` passe de "true" à "false" (mode réel).

`valide-cfg.ps1` (vraies fonctions de Pesto, Windows PowerShell 5.1) : 12/12 — `Test-CfgValid` sans erreur, POLICY égale
aux valeurs par défaut, valeurs appliquées par le moteur identiques à l'ancien fichier hors Simulation, commentaires
conservés et signature inchangée après « Enregistrer », commentaire dans POLICY refusé (contre-épreuve).
`Pesto.exe --check-json` avec ce fichier dans le pack PROD : code 0.
