# Candidat C6 — qualification Windows du 26 octobre 2026

**Campagne entièrement réussie : [40294452798](https://github.com/M4D135/pesto/actions/runs/40294452798).**
Commit source testé : `51ee27058c74c27b237bff2e6250aa384198b345`, branche `codex/pesto-v2-20261023`.

Les deux candidats ont été construits, assemblés et exécutés sur le runner Windows 2025
(Windows NT 10.0.26100.0), avec leur runtime WebView2 fixe **156.0.4314.42** et le SDK de CI
**10.0.302**. Le commit documentaire qui consigne ce bilan ne reconstruit pas les binaires.
Les packs restent `official=false`, `distribution=candidate`, `qualification=unqualified` :
la campagne ne qualifie pas une opération AD de production. Aucune release V1 n’est modifiée.

## Packs téléchargeables

| Canal | Artefact GitHub Actions | Archive interne |
|---|---|---|
| PROD | [Télécharger le candidat PROD](https://github.com/M4D135/pesto/actions/runs/40294452798/artifacts/12638181271) | `Pesto_V2_PROD_candidate.zip` |
| DEV | [Télécharger le candidat DEV](https://github.com/M4D135/pesto/actions/runs/40294452798/artifacts/12638410766) | `Pesto_V2_DEV_candidate.zip` |

Extraire l’enveloppe GitHub puis son ZIP interne. Le dossier `PROD` ou `DEV` contient
**`Pesto.exe` et `wad` à sa racine** ; conserver cet ensemble. .NET, WebView2 et le module Microsoft
ActiveDirectory épinglé sont inclus. Un seul lanceur Pesto est fourni ; ni Spark, ni OpenCode,
ni SDK .NET, ni PowerShell 7 ne sont requis à l’exécution. DEV ajoute les sources et outils de développement.
La rétention des artefacts est de **30 jours**, jusqu’au **25 novembre 2026** ; ce ne sont pas des assets de release.

Sans configuration, le lancement ouvre les Paramètres locaux. `Pesto.exe --settings` permet également
cette entrée sans adaptateur AD. La Démonstration s’ouvre dans une fenêtre et un profil distincts.
Après configuration, le bouton **Définir comme configuration par défaut** prépare un nouveau pack
personnalisé, avec paramètres nettoyés et manifeste recalculé. Cette distribution est marquée `custom`,
distincte d’une release officielle. Les conditions et parcours sont détaillés dans
[Configuration](../../../CONFIGURATION.md) et [Packaging](../../../PACKAGING.md).

### Empreintes du contenu distribué

Les ZIP suivants ont été créés avant les transactions, utilisés par le banc puis archivés sans réécriture.
Leurs empreintes figurent dans les preuves d’acquisition, les rapports finaux et `artifacts.json`.

| Fichier | SHA-256 |
|---|---|
| `Pesto.exe`, commun aux deux canaux | `b196f141d83a043c1f81a42da29fdc0f9d68fe6b72219aafd1236fda902a858f` |
| `Pesto_V2_PROD_candidate.zip` | `b1365d338ca8d75efda352d8939983c3ce3ac51f38cea3c4c6b98e960a8b2813` |
| `Pesto_V2_DEV_candidate.zip` | `506cce5eeb0d216ced2acf976a227d1bcec2ba74d39b59c20d8c8f23abc8f3ff` |

Les enveloppes d’artefacts GitHub ont des empreintes distinctes :

| Artefact | Taille en octets | SHA-256 de l’enveloppe |
|---|---:|---|
| PROD | 369772715 | `99cc7fa72f096963532f1ff7af9247bb0049e41b47e0d726be124106962a4e35` |
| DEV | 383906185 | `44b0c6d52340d75bcc3e011cb48a69b0f6ee27e8a43de3d853608a15149c57fc` |
| Preuves | 1175668 | `cc6c71d4056257d42b07a3efa9a69592582ad07524e9c408046171dadba333f4` |

L’enveloppe des preuves a été téléchargée et son SHA-256 vérifié avant rédaction. Les deux gros packs
n’ont pas été retéléchargés dans l’environnement de développement : leurs identités proviennent des
contrôles exécutés dans le workflow et des métadonnées GitHub Actions.

## Résultats Windows établis

| Essai | Résultat |
|---|---|
| Compilations Windows | Réussies, sans avertissement ni erreur |
| Tests moteur ciblés sur fixtures Windows | **200/200**, pont **15/15**, compagnon portable **30/30** |
| Windows PowerShell 5.1 | **18/18** variantes métier analysées, sans exécution métier ; script d’entrée du banc également analysé, zéro erreur |
| Démarrage et fermeture PROD/DEV | Vrai EXE et WebView2 embarqué prêts puis fermés, profils temporaires supprimés |
| Frontière démo PROD/DEV | **44 refus directs par canal**, zéro invocation de l’hôte sentinelle, aucun profil réel créé |
| Coexistence locale PROD/DEV | Parent sans adaptateur AD conservé ; brouillon, route et préférences inchangés ; bannière, reset, redémarrage fictif et fermetures vérifiés |
| Transitions de démo | Six nouveaux montages de page par canal ; trois profils, deux instances et trois IDs de reçus distincts ; huit captures relues |
| PROD normal | Acquisition du ZIP B, installation et santé B, rollback explicite puis santé A |
| PROD santé négative | Échec B attesté par reçu négatif, restauration et santé A |
| PROD interruption/reprise | Arrêt réel pendant `checking`, reprise explicite `recover`, restauration et santé A |
| DEV normal | Acquisition du ZIP B, installation et santé B, rollback explicite puis santé A |
| Conservation des quatre cas | Packs A/B, ZIP candidat et configuration sentinelle inchangés ; état final `rolledBack`, deux tentatives de santé distinctes par cas |

Le parent de coexistence est explicitement `configuration-only-no-adapter`, sur profils temporaires.
Le banc parcourt `pendingRestart`, `joined` et le reset vers `standard`. Le reçu conserve son ID
pendant le redémarrage fictif, puis les IDs restent distincts après reset et entre les deux fenêtres.
Les durées mesurées sont **35,446 s en PROD** et **35,515 s en DEV**. Le compteur d’accès au fournisseur
de coordination est nul ; aucune configuration réelle n’est créée. Les huit captures montrent
la bannière et les champs fictifs attendus, avec le contexte parent préservé.

## Mise à jour entre deux compilations réelles

**A** est reconstruit depuis `de527313b98f30d52802ec6abd51804e12f8c298` dans cette campagne ; son EXE vaut
`62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c`.
**B** provient de `51ee27058c74c27b237bff2e6250aa384198b345`, avec le hash indiqué ci-dessus.
Le helper est celui de A ; la santé du candidat utilise B et celle du retour utilise A.
Les deux gardent leur vraie version `2.0.0`, sans version de manifeste synthétique.
Le hash d’arbre du runtime commun est
`d58a8ea7fa738af0f7f60dfeaeb38e02c55954b0e03f848dd675e63df4850970`.

Les deux cas négatifs PROD utilisent des copies déclarées de B avec une page de santé volontairement
invalide, un manifeste recalculé et la déclaration de source intacte retirée. L’EXE et le runtime restent
ceux de B ; leur empreinte de pack modifiée n’est pas confondue avec celle du ZIP B intact.

Dans le cas d’interruption, l’inventaire attribue le helper et ses **trois descendants** au banc :
le processus santé B et deux processus WebView2. Leurs identités, les hashes A/B et le journal encore
à `checking` sont vérifiés avant l’arrêt. Le journal reste à cette frontière après arrêt ; une nouvelle
demande explicite `recover` produit `rolledBack`, une santé A positive, une boîte de résultat fermée et
un code de sortie zéro. La tentative B reste `interrupted`, `accepted=false`, sans nouvel essai B.
La campagne ne rencontre aucun refus d’attribution : elle valide le parcours complet, sans prétendre
avoir sollicité la branche d’attente d’un inventaire ambigu.

La [synthèse JSON](summary.json) ne reprend que résultats, compteurs et identités publiques des candidats.
Les [preuves originales et captures](https://github.com/M4D135/pesto/actions/runs/40294452798/artifacts/12638096574)
restent dans leur artefact GitHub ; les journaux bruts ne sont pas recopiés dans le dépôt.

## Limites et blocage réel

- La coexistence native ne comporte pas de session AD authentifiée ni d’autre identité UAC.
  Les huit scénarios implémentés ne sont pas tous parcourus par ce banc natif.
- Les refus directs et compteurs du banc ne sont pas une capture réseau indépendante.
- DEV couvre installation et rollback normaux ; les pannes et l’interruption/reprise natives sont testées en PROD.
  L’interruption native est provoquée pendant `checking` ; les autres frontières ont des contrôles sur fixtures.
- Les transactions portent sur copies locales temporaires et configuration sentinelle synthétique.
  L’acquisition d’une release officielle par HTTP, UNC/SMB réels, ACL Program Files et vraie configuration
  opérateur restent distincts.
- Authentification native, UAC avec autre administrateur et profil d’origine, dialogues natifs
  d’import/export/récupération, fabrication complète d’un pack personnalisé, ACL et DPAPI restent à qualifier.
- Le canari AD réversible, les attributs réels, ODJ/djoin, CLI avec identité réelle, Entra et redémarrage
  réel ne sont pas qualifiés. Le contrôle du laboratoire du 26 octobre à **08:51 UTC** a encore reçu
  `Connection refused`, code **255**. Aucune session du laboratoire ni opération AD n’a eu lieu ;
  ce refus ne permet pas de conclure à l’arrêt de la VM.

Le [rapport C6](../../../VALIDATION-C6-20261026.md) conserve les corrections et les cinq campagnes
précédentes, y compris leurs échecs. La [recette Windows](../../../QUALIFICATION-WINDOWS.md) identifie
les contrôles encore ouverts. Les preuves C5 restent attachées à leurs anciens binaires.
