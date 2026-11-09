# Clôturer la livraison de Pesto 1.0

Cette procédure relie le [catalogue des 120 exigences](catalogue-120.json), les
rapports d’implémentation et les qualifications. Elle ne déclare aucun résultat
supplémentaire. Les [scénarios de qualification](QUALIFICATION_120.md) précisent les
observations nécessaires.

## Une identité exacte par candidat

Conserver pour chaque candidat : commit de base et état des sources, SHA256 de
`Pesto.exe`, de `wad/package.json`, des sources et des bancs exécutés. Une correction
du runtime exige un nouveau lanceur et un nouveau manifeste ; ses résultats restent
distincts de ceux du candidat précédent. Une correction des guides ou d’un outil
hors runtime peut conserver le même EXE, mais change les empreintes des fichiers
concernés et des archives qui les embarquent.

Le candidat C2 est identifié par l’EXE
`4bd73854d6499f3ded5d5712bd5869b441a5641c7401129d947461137bc70cd8`.
Les résultats disponibles pour ce candidat ne valent que dans leur périmètre :

| Preuve | Périmètre constaté |
| --- | --- |
| [Python C2](../../../preuves/ameliorations-120-2026-10-13/local/python-c2.log) | 405 tests locaux, incluant les 16 cas d’installation gérée ; pas d’exécution Windows/AD |
| [Moteur C2](../../../preuves/ameliorations-120-2026-10-13/local/engine-c2/summary.json) | 181 assertions de deux bancs sous PowerShell 7.4.20 sur Mac ; doubles Windows/AD |
| [Interface C2](../../../preuves/ameliorations-120-2026-10-13/local/ui-c2/summary.json) | 110 assertions portables ; aucune ouverture WPF |
| [Intégration C2](../../../preuves/ameliorations-120-2026-10-13/local/Integration-c2.json) | 18 cas du moteur CLI avec identité et écritures de reçus remplacées par doubles |
| [Reproductibilité C2](../../../preuves/ameliorations-120-2026-10-13/local/repro-c2.json) | Runtime identique entre deux compilations sur le même profil Mac |
| [Archives C2](../../../preuves/ameliorations-120-2026-10-13/release-audit/packs-c2.json) | Contenu fermé, octets ZIP/dossiers identiques, configuration neutre et recherche ciblée de secrets textuels |

Ne pas additionner ces nombres à ceux du socle Common, de la campagne Windows ou
des régressions rejouées. Une assertion, un test et un scénario utilisateur ne sont
pas des unités équivalentes.

## Rapprocher chaque exigence

1. Conserver exactement les IDs 1 à 120, leur texte et le commit de référence du
   catalogue. Travailler sur une copie de rapprochement avant de publier les états.
2. Pour chaque ID, relever le comportement présent et ses sources dans le rapport
   de lot : `UI_120`, `ENGINE_120`, `RELEASE_120`, `AUTOMATION_120` ou `EXTENSIONS_120`.
3. Joindre les preuves directes : chemin, SHA256 du rapport brut, build, plateforme,
   version PowerShell/.NET, commande et code de sortie. Distinguer les doubles,
   Windows isolé, WPF isolé, application interactive, AD réel et SMB réel.
4. Noter séparément **réalisation**, **validation dans ce périmètre** et
   **qualification restante**. Une fonction implémentée peut encore attendre une
   recette ; un outil de qualification prêt ne signifie pas que son scénario passe.
5. Pour une évaluation, joindre la mesure ou l’analyse et sa décision. Une conclusion
   motivée de conserver l’existant peut satisfaire une évaluation ; elle ne prouve
   pas une fonctionnalité activée ni une compatibilité supplémentaire.
6. Conserver les échecs, erreurs et SKIP avec leur raison et leur tentative suivante.
   Un rapport absent, un timeout ou un prérequis manquant reste ouvert. Un code de
   sortie nul sans rapport attendu ne suffit pas à qualifier un banc.

Le champ `evidence` du catalogue référence les preuves vérifiées. Ne pas remplacer
globalement tous les `in_progress` par un état réussi ; le responsable clôt chaque
exigence selon son objet. Conserver un tableau utilisateur ID / résultat concret /
preuve / limite, sans transformer une limite externe en succès.

## Qualifier Windows et les fonctions externes

Rapprocher le manifeste de transfert, l’identité réellement chargée, `runner.json`,
les rapports et leurs journaux. Le drapeau `-Wpf` demandé ne prouve pas que la WPF a
été exécutée ; lire les cas et les SKIP. Une session 0 ou verrouillée ne remplace
pas une recette souris/clavier devant une fenêtre visible. Les corrections du
banc et leurs nouvelles tentatives restent reliées au rapport initial.

Les signatures et horodatages réels (88), attestations distantes (91), politiques
App Control (92), droits de redistribution Microsoft (95), matrice cible (98),
GUI/DPI/Narrator (99–101), SMB sur deux machines (103), réplication sur deux DC (104)
et longues sessions (107) exigent leurs preuves spécifiques. Les adaptateurs
d’orchestrateur (83–84) demandent une qualification dans le produit concerné.
Conserver `NOT_RUN` ou `BLOCKED` dans la campagne lorsqu’une observation manque ;
décrire précisément la limite dans le bilan.

## Fermer les quatre guides et les deux packs

1. Terminer les sources des guides Pesto 1.0, produire les deux DOCX et les deux PDF,
   puis relire les pages modifiées et vérifier les empreintes des pages conservées.
2. Copier les quatre livrables retenus dans `DEV/docs`. Une preuve visuelle d’un
   ancien rendu ne certifie pas un document modifié depuis.
3. Générer les packs dans un dossier neuf à partir des sources gelées. PROD doit
   contenir seulement `Pesto.exe` et `wad/`, avec les composants runtime nécessaires,
   le manifeste, le modèle neutre et le helper autorisé. Les DLL Common et RSAT sont
   des dépendances du runtime ; aucun banc de test, DLL de test, `vendor/`, outil DEV,
   `Common.Wpf` facultatif ou `Pesto.Engine.exports.json` n’entre dans PROD.
4. Vérifier les ZIP : noms uniques sans traversée ni liens, mêmes octets runtime
   dans DEV et PROD, `cfg.json` identique au modèle neutre (`Configured=false`),
   présence des guides/outils et `.gitattributes` autonome dans DEV.
5. Vérifier les secrets par périmètre : configuration et fichiers attendus, recherche
   textuelle ciblée, tests à marqueurs factices et relecture des captures. Une
   recherche sans candidat ne certifie pas tous les formats de secrets ou binaires.
6. Calculer les empreintes des archives finales, actualiser `packs/SHA256SUMS` et
   leur README avec le build et les qualifications réellement retenus. Les archives
   C2 de préparation et les anciens packs restent des preuves distinctes.

## Assembler le dossier de release

Après les guides et les packs, depuis DEV :

```text
python tools/release_assurance.py create --source CHEMIN_DEV --output DOSSIER_NEUF --pack Pesto_DEV.zip --pack Pesto_PROD.zip --evidence BILAN_FINAL.json
```

Le dossier produit contient SBOM CycloneDX, provenance in-toto non signée, identité
des guides/packs et empreintes des rapports fournis. Le générateur référence les
pièces, sans interpréter automatiquement leur réussite. Ajouter les rapports finaux
avec plusieurs `--evidence` ; utiliser des noms distincts ou joindre un index qui
relie chaque chemin à son hash. Vérifier séparément le schéma du SBOM, les limites
déclarées et les résultats de qualification.

La signature reste opt-in avec le certificat existant de l’organisation. Si elle
est demandée, suivre l’ordre de [signature et fabrication](RELEASE_120.md) avant les
packs et métadonnées finaux. Ne pas désigner un statement local comme une attestation
distante ni un fichier hashé comme signé. Le commit, le push et l’exécution CI restent
trois événements distincts à confirmer avec leurs reçus.
