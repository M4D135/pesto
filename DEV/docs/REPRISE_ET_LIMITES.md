# Pesto : point de reprise et fichiers conservés

## Statut

**Travail de développement, pas une version certifiée pour le domaine de production.**

Les 44 modifications de l’audit ne sont pas annoncées comme toutes terminées. Les fichiers du chantier déjà présent ont été conservés. Le tableau ci-dessous est issu des retours réels des commandes exécutées par le script de reprise, pas d’un ancien compte rendu recopié.

## Modifications apportées par cette reprise

- `DEBLOQUER_TOUT.cmd` est dans `wad\support`, avec une résolution de la racine deux niveaux au-dessus et un contrôle de présence de Pesto.exe et des points d’entrée. Il ne part pas du dossier de travail courant.
- Le déblocage demande confirmation, ignore les liens repérés, contrôle le retrait des marques de téléchargement et produit un bilan dans `wad\logs`. Il ne change ni antivirus, ni stratégie de sécurité, ni verrou métier.
- Un générateur autonome `tools/Build-PestoPacks.py` fabrique des dossiers PROD et DEV, conserve seulement Pesto.exe et wad à la racine de PROD, refuse les composants incohérents et n’impose pas le support au démarrage.
- `FABRIQUER_PACKS.cmd` appelle ce générateur. La fabrication utilise un dossier de sortie nouveau, sans écraser une installation existante.
- Des tests isolés du générateur couvrent fichiers manquants ou modifiés, chemins traversants, code non couvert, exclusion des journaux et préférences, support facultatif et noms des dossiers des archives.

## Base récupérée

Version détectée dans la source : RC18.

Fichiers applicatifs conservés qui diffèrent de la RC18 : 0. Leurs empreintes sont dans le JSON. Ce nombre ne mesure ni la couverture de tests ni l’achèvement de l’audit.

## Résultats des commandes

| Contrôle | Résultat | Précision |
|---|---|---|
| native-build | PASS |  |
| python-tests | FAIL |  |
| powershell-core-parser | NOT_RUN | pwsh absent. |
| manifest | PASS |  |
| PE-x64 | PASS |  |
| XML | PASS |  |
| support-distribution | PASS |  |

## Vérifications non réalisées ici

Windows PowerShell 5.1 natif, lancement de l’EXE sous Windows, rendu WPF, UAC interactive, droits réels du poste, Planificateur Windows, authentification AD, jonction, renommage, déplacement et redémarrage réels. Une signature officielle demande le certificat autorisé de l’organisation. Ces étapes ne sont pas rendues « réussies » par une compilation ou une vérification de ZIP.

Les tests en échec restent des blocages à traiter. Le snapshot DEV est fourni pour conserver et poursuivre les sources, pas pour contourner ces blocages. Aucun ancien verrou, reçu ou fichier de configuration opérationnel ne doit être effacé pour lancer un essai.

## Continuer depuis ce dossier

Consulter `docs/bilan-reprise.json` et les fichiers de `verification` ; corriger les premiers tests réellement en échec avant une nouvelle mutation. Les tests historiques gardent leur statut historique. Examiner les différences avec la RC18 avant toute diffusion. Ne pas installer ce chantier à la place d’une installation utilisée sur des postes de production.
