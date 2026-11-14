# Candidat C7 — qualification Windows du 26 octobre 2026

**Campagne entièrement réussie : [40304895510](https://github.com/M4D135/pesto/actions/runs/40304895510).**
Source testée : `95f8ce0b1f9605dcaddfdc97c0b7b017762567be`, branche `codex/pesto-v2-20261023`.
Le bilan documentaire est commité ensuite sans reconstruire les ZIP testés.

Le candidat corrige les réponses de maintenance reçues après navigation, les doubles
préparations d’enregistrement et la perte de brouillons pendant les lectures ou sauvegardes.
La première lecture lente est également couverte. Les octets du kit web sont préservés
au checkout Windows ; les empreintes de provenance originales restent inchangées.
Voir le [rapport des corrections et commandes](../../../VALIDATION-C7-20261026.md).

## Télécharger et lancer

| Canal | Artefact GitHub Actions | Archive interne |
|---|---|---|
| PROD | [Télécharger PROD](https://github.com/M4D135/pesto/actions/runs/40304895510/artifacts/12643277054) | `Pesto_V2_PROD_candidate.zip` |
| DEV | [Télécharger DEV](https://github.com/M4D135/pesto/actions/runs/40304895510/artifacts/12642109528) | `Pesto_V2_DEV_candidate.zip` |

Extraire l’enveloppe GitHub puis le ZIP interne. Conserver ensemble **Pesto.exe** et **wad**
à la racine du dossier PROD ou DEV. .NET, WebView2 fixe et le module Microsoft ActiveDirectory
épinglé sont inclus. Ni SDK .NET, ni PowerShell 7, ni Spark ne sont requis à l’exécution.
DEV ajoute les sources et outils ; les dépendances `node_modules` du banc ne sont pas distribuées.
Sans configuration, le lancement ouvre les Paramètres locaux ; `Pesto.exe --settings` le permet aussi.

Ces fichiers sont des **artefacts Actions**, avec rétention de 30 jours jusqu’au
**2026-11-25**, pas des assets de release.
Ils restent `official=false`, `distribution=candidate`, `qualification=unqualified`.
Aucune release V1 n’est remplacée et aucune opération AD réelle n’est qualifiée.

## Identités vérifiées

| Contenu | SHA-256 |
|---|---|
| `Pesto.exe`, commun aux deux canaux | `5940441cfb349497829fa6f78bdde53b788fbf01a9328b13d5be69822dc8a233` |
| ZIP PROD réellement testé | `b1dc5f8bf6b34a082b1ba3e383fee6a6fabcfc447f61f6cbe6207f6ed2fcd46b` |
| ZIP DEV réellement testé | `6028bba1903b9470db3599758ed0a1c3b4a3cb058a15f298a6e4639097f5452a` |
| EXE baseline A reconstruit dans cette campagne | `62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c` |

A provient de `de527313b98f30d52802ec6abd51804e12f8c298` ; B provient du commit C7 indiqué ci-dessus.
Les deux EXE diffèrent et gardent leur version réelle `2.0.0`.
Le runner Windows 2025 utilise le SDK **10.0.302** et WebView2 fixe **156.0.4314.42**.

Les enveloppes GitHub ont leurs propres empreintes :

| Enveloppe | Octets | SHA-256 |
|---|---:|---|
| PROD | 369786136 | `22c6089311c6004c304a4ca55dd951d84f8f0e46ef968a99c5a78e7f70d7105d` |
| Preuves | 1161462 | `a390167f513d0960255c93e6f936b31c447339f571bbe91a03caec2e39875f0a` |
| DEV | 383922253 | `162fb64467936396c4a2a13adc17d69e8bf22593e9249422180098b2fd3ecfa1` |

L’enveloppe des [preuves et captures](https://github.com/M4D135/pesto/actions/runs/40304895510/artifacts/12642508610) a été téléchargée et son SHA-256 vérifié.
Les gros packs restent sur GitHub : leurs empreintes viennent du workflow et des métadonnées Actions,
sans prétendre les avoir retéléchargés. Le ZIP acquis par le banc correspond dans chaque canal
au SHA archivé ; aucun ZIP n’est reconstruit après les essais.

## Résultats et recoupements

| Contrôle | Résultat |
|---|---|
| Compilations Windows | Réussies, zéro avertissement et zéro erreur |
| Moteur sur fixtures Windows | 200/200 ; pont 15/15 ; compagnon portable 30/30 |
| PowerShell 5.1 | 18/18 variantes métier analysées et script du banc analysé sans erreur ; aucun script métier exécuté |
| Chromium sur fixtures déclarées | Maintenance 33/33 ; opérateur 32/32 ; démo DOM 8/8 ; statique 149/149 |
| Démarrage et démo native PROD/DEV | Vrai EXE/WebView2 ; 44 refus directs d’API par canal ; aucun profil réel créé ; profils temporaires supprimés |
| Coexistence locale PROD/DEV | Brouillon, route et préférences préservés ; bannière, reset, redémarrage fictif et fermetures réussis |
| Transitions et captures | Six nouveaux montages par canal ; trois profils, deux instances et trois IDs distincts ; huit captures relues |
| PROD normal | ZIP B → installation/santé B → rollback explicite/santé A |
| PROD santé négative | Échec B durable → restauration/santé A |
| PROD interruption | Arrêt à `checking` → reprise explicite → restauration/santé A |
| DEV normal | ZIP B → installation/santé B → rollback explicite/santé A |
| Conservation | Quatre états finaux `rolledBack` ; sources A/B, ZIP et configuration sentinelle inchangés |

Les quatre transactions distinctes sont recoupées avec **huit reçus de santé** et **sept lancements
du helper**, y compris leurs identités A/B. Les cas négatifs utilisent une copie déclarée de B dont
la page de santé est volontairement invalide, distincte du ZIP B intact. L’échec B reste consigné.
L’interruption est observée à `checking`, avec **3 descendants attribués**
et **un refus d’attribution** enregistré avant un inventaire complet accepté. Le premier
inventaire signalait une image système hors du dossier du cas (`descendant-image-outside-case`).
La branche de refus puis nouvelle observation est donc exercée dans C7 ; les gardes ne sont pas
contournées. Les trois descendants sont ensuite attribués au cas, revérifiés puis arrêtés avec
le helper. Le reçu B interrompu reste `accepted=false` et n’est pas rejoué.

Le parent de la démo est **configuration-only-no-adapter**. Les scénarios natifs sont
`pendingRestart`, `joined` et le reset vers `standard`. La coexistence dure
**36.862 s en PROD** et
**36.885 s en DEV**.
Les captures montrent le contexte parent conservé et le reçu passant de redémarrage en attente à simulé.
Ces durées décrivent le parcours automatisé complet, pas le temps de démarrage de l’application.

La [synthèse JSON](summary.json) ne contient que résultats, compteurs et identités publiques.
Les journaux bruts du laboratoire restent hors Git. Les preuves C6 demeurent attachées à `51ee270`.

## Limites et suite de recette

Le canari AD, l’authentification native, la coexistence avec une session AD, UAC avec un autre compte,
les dialogues natifs de configuration et la création complète d’un pack personnalisé restent ouverts.
ACL/DPAPI, UNC/SMB et concurrence intermachines, acquisition GitHub officielle par HTTP, Program Files,
attributs AD, ODJ/djoin, CLI avec identité réelle, Entra et redémarrage Windows restent non qualifiés.
DEV couvre le cas normal ; les pannes et la reprise native sont testées en PROD, à la frontière `checking`.
Les huit scénarios de démo ne sont pas tous parcourus ; aucune capture réseau indépendante n’est produite.

Le bastion répond, mais l’identité invitée n’a pas été obtenue : Guest Control `VERR_NOT_IMPLEMENTED`
(code 33 sur hostname), capture `E_FAIL`, refus de vérification de clé SSH. La VM PESTO-W11-TEST
reste **running**, avec l’instantané à froid **C7-avant-verification-20261026** conservé.
Aucun contournement, restauration, redémarrage Windows ni changement AD n’a été engagé.

Recette restante : rétablir un accès invité vérifié sur le seul client autorisé, confirmer son identité
et le retour à froid, vérifier l’EXE et le ZIP C7, contrôler le nom affiché avant l’ajout au domaine,
puis exécuter le canari réversible et sa relecture par GUID selon la
[checklist Windows](../../../QUALIFICATION-WINDOWS.md). Une ancienne identité ne remplace pas ces observations.
