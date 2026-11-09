# Index des preuves Pesto V2

**Release actuelle 2.0.9 : [rapport, empreintes et résultats](RELEASE-v2.0.9.md), [campagne officielle](https://github.com/M4D135/pesto/actions/runs/41284549253).** Tous les contrôles Windows V2 ont réussi sur le commit `ee40af18458ae0bb604f02665a6f4e2df57d7378` ; les cinq fichiers publiés ont été téléchargés et vérifiés. AD, UAC réel, UNC et retour depuis les boutons UI restent non qualifiés.

**Release historique 2.0.0 : [v2.0.0](https://github.com/M4D135/pesto/releases/tag/v2.0.0), source `84d76fc022eb11172021447672cfde5381a2d4ea`, [campagne 40720801680](https://github.com/M4D135/pesto/actions/runs/40720801680).** Les ZIP PROD/DEV publiés sont les octets testés sous Windows et revérifiés après téléchargement ; une installation DEV de `de527313` passe à 2.0.0 par nouvelle installation. `qualification=unqualified` : AD, UAC réel, UNC et retour depuis les boutons UI non qualifiés. Détails : [rapport de release](RELEASE-v2.0.0.md).

**Historique C18 (dernier candidat avant la première release 2.0.0) : `2adf60e15f8f7d5fd808c0471a63e1fd4457cd90`, [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761).** Les [preuves C18](evidence/20261028/windows-2adf60e/README.md) rattachent les 25 étapes réussies, 616 tests moteur, 250 gardes de restauration et 16 suites navigateur aux packs exacts PROD/DEV. Installation depuis les boutons, retour séparé par le service et reconstruction depuis les sources DEV avec SDK 10.0.302 réussissent. Les trois archives ont été téléchargées et leurs empreintes vérifiées ; les deux packs passent aussi `make-pack --verify` localement. Le [rapport C18](VALIDATION-C18-20261028.md) conserve l’échec initial `07dc741` et le correctif du banc. AD, UAC et UNC réels, profil ordinaire et retour depuis les boutons UI ne sont pas qualifiés par cette CI ; les preuves du harnais de domaine ne se transmettent pas aux ZIP.

**Historique C17 : `e087bb16aed175bc35906fa533e9cd172d2fdaca`, [40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690).** Les [preuves relues le 28 octobre](evidence/20261028/windows-e087bb1/README.md) confirment l’installation depuis les boutons en PROD et DEV, le retour séparé par le service, la recompilation depuis les sources du DEV livré avec cache NuGet neuf et SDK 10.0.302, puis le démarrage natif du résultat. Le [rapport C17](VALIDATION-C17-20261027.md) distingue ces acquis du retour par bouton UI, de l’AD, de l’UAC, de l’UNC réels et du profil ordinaire non qualifiés par cette campagne. Chaque preuve reste attachée à ce commit et à ses empreintes.

## Chaîne de preuves C18

Les [contrôles portables initiaux](evidence/20261028/portable-c18/README.md) précèdent le commit. La [première CI 07dc741](evidence/20261028/windows-07dc741-failed/README.md) échoue à 15/23 dans le banc de reprise encore lié à la recopie ; elle ne publie aucun candidat. Après correction du seul test, les [16 suites locales](evidence/20261028/portable-browser-c18-followup/README.md) réussissent, puis la [CI finale 2adf60e](evidence/20261028/windows-2adf60e/README.md) réussit intégralement. Les trois enveloppes, les deux ZIP intérieurs, les EXE et les sources DEV/web ont été vérifiés ; les limites de comparaison CRLF/LF sont consignées. Les comptes locaux et Windows se recouvrent et ne s’additionnent pas.

## Historique C16

Le rapport [VALIDATION-C16-20261027.md](VALIDATION-C16-20261027.md) est lié au lot fonctionnel initial `d803d72` puis aux correctifs natifs `1dbdda1` et `3a8c49d`. Il décrit les corrections des lots et CSV, la protection des brouillons, la dernière revalidation du plan et de l’état AD observé, la documentation des packs et l’extension du banc natif de configuration.

Les [preuves portables C16](evidence/20261027/portable-d803d72/README.md) conservent **615 tests moteur**, **15 du pont**, **46 contrôles de fabrication**, **12 étapes DOM compilées** et les **seize suites JavaScript/navigateur** réussis, avec journaux, limites et empreintes. Ces résultats utilisent des fixtures déclarées et une publication Windows croisée ; ils ne prouvent aucune opération AD réelle. Les suites ciblées et les suites complètes se recouvrent.

La [campagne finale 40491875705 sur `3a8c49d`](https://github.com/M4D135/pesto/actions/runs/40491875705) est **entièrement réussie** : suites complètes moteur/pont, fabrication, seize suites JavaScript/navigateur, accueil et saisie natifs, démonstration, **36 contrôles de configuration par canal** et **quatre scénarios de mise à jour entre builds distincts**. La [synthèse finale](evidence/20261027/windows-3a8c49d/README.md) conserve les huit JSON natifs, 24 journaux, les métadonnées et les empreintes. L’enveloppe de preuves a été téléchargée et hashée ; les chemins, les compteurs, les sources/ZIP/EXE et les huit tentatives de santé ont été recoupés. Les grosses enveloppes binaires n’ont pas été retéléchargées localement. Aucun AD, UNC ni UAC réel n’est qualifié par cette campagne, et l’installation confirmée depuis l’interface reste hors du parcours natif de configuration.

Les [preuves de la première tentative](evidence/20261027/windows-d803d72-failed/README.md) conservent l’arrêt à l’export, après deux contrôles, sur `d803d72`. Les [preuves de la deuxième](evidence/20261027/windows-1dbdda1-failed/README.md) conservent les 19 contrôles réussis puis le défaut du filtre de dossier sur `1dbdda1`. Les deux tentatives passent les suites complètes et les premiers bancs natifs, mais ignorent les transactions et ne publient aucun pack. Les [contrôles locaux du premier correctif](evidence/20261027/portable-1dbdda1/README.md) et du [filtre de dossier](evidence/20261027/portable-3a8c49d/README.md) restent séparés des preuves Windows.

## Historique C15

Le [rapport historique C15](VALIDATION-C15-20261027.md) reste lié au candidat de code `b875174`. Il décrit les corrections des choix de poste, les lectures de sites et le nettoyage des inspections ZIP. Les [preuves portables C15](evidence/20261027/portable-b875174/summary.json) conservent 108 tests moteur ciblés, 39 contrôles métier Chromium et 149 contrôles web, avec leurs portées et leurs empreintes. Les dix nouveaux scénarios UI refusent l’ancienne interface avant de réussir avec les correctifs.

La [campagne Windows C15 40479609012](https://github.com/M4D135/pesto/actions/runs/40479609012) réussit intégralement sur `b875174` : **229 tests moteur**, 15 du pont, 30 contrôles du compagnon, 70 gardes AD sans mutation, PS5.1 et UTF-8, puis **299 contrôles web** dont les 39 métier. Les bancs natifs passent accueil 5, saisie 16, configuration 14 par canal et démonstration PROD/DEV avec 44 refus par canal. Les quatre transactions entre builds distincts passent, avec huit tentatives de santé et conservation des sources et de la configuration sentinelle. Les [preuves C15](evidence/20261027/windows-b875174/README.md) conservent les huit JSON natifs, les empreintes et les liens des candidats. L’enveloppe des preuves a été téléchargée et vérifiée ; les deux grosses enveloppes binaires n’ont pas été retéléchargées localement. Aucun AD, UNC ou UAC réel n’est qualifié par C15. Les comptes locaux et Windows se recouvrent.

## Historique C14 et laboratoire

Le [rapport C14](VALIDATION-C14-20261026.md) conserve l’accueil/UAC, la saisie native, les réglages de démonstration et d’animations, les gardes du harnais AD et sa recette finale. Les rapports [C9](VALIDATION-C9-20261026.md), [C8](VALIDATION-C8-20261026.md), [C7](VALIDATION-C7-20261026.md) et [C6](VALIDATION-C6-20261026.md) restent historiques.

La [campagne 40368778290](https://github.com/M4D135/pesto/actions/runs/40368778290) est entièrement réussie sur `e5a6722` : [synthèse, empreintes et candidats](evidence/20261026/windows-e5a6722/README.md). Elle passe 203 tests moteur, 15 du pont, 30 du compagnon et 70 gardes du retour AD sur fixtures, ainsi que les contrôles PS5.1 et UTF-8. Chromium : 33/41/9/28/149. Les bancs natifs passent accueil 5, saisie AD 16, configuration 14 par canal et démo avec six transitions et 44 refus par canal.

Les quatre transactions entre deux compilations produisent huit reçus santé et sept lancements du helper. Sources, ZIP et configuration sentinelle restent inchangés. Les trois enveloppes GitHub et les deux ZIP sont vérifiés.

**Laboratoire historique C14 :** Le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0. Les bancs restent isolés du profil ordinaire et ne font aucun appel AD. Le renommage réel `P111301VA765158` → `P111301VA765586`, sa vérification après redémarrage et le retour au nom initial sont confirmés. L’inspection finale du 26 octobre à 17:41 UTC retrouve le même GUID, Paris, UAC4096, protection false, domaine et canal sécurisé sains, noms actif/configuré cohérents et aucun renommage en attente. Les cinq anciennes entrées V1 sont inchangées. Le déplacement Paris → Lyon → Paris reste lié au moteur C9 et à son rapport historique.

## Sources vérifiables

| Sujet | Code / banc | Portée |
|---|---|---|
| Métier, plans, reçus, files et GP | `src/Pesto.Engine`, `src/Pesto.Engine.Live`, `tests/Pesto.Engine.Tests` | Comportements sur doubles contrôlés ; natif seulement si rapport explicite |
| Configuration et référentiels | `ProfileConfigurationTests`, `ReferenceImportTests` | Schémas, empreintes, choix par profil, atomicité, conflits, concurrence |
| Démo et frontière API | `DemonstrationTests`, `ApplicationServicesTests`, `demo-check.mjs`, `demo-dom-check.mjs` | Monde fictif et refus avant effets réels |
| Politiques V1 | `OperationPolicyTests` et contrôles natifs ciblés | Restrictions importées/HKLM, préparation et dernier contrôle avant envoi |
| Mises à jour | `UpdateTests`, `pack-check.mjs` | Validation et transitions de dossiers ; fixtures explicitement identifiées |
| Attributs, ODJ et CLI | `Attribute*Tests`, `OfflineJoin*Tests`, `AutomationTests`, `ConsultationGuardTests`, `parity-ui-check.mjs` | Plans/identités, preuve durable, mode local fermé, non-rejeu et résultats honnêtes ; fixtures sans qualification AD |
| Boutons natifs de configuration | `--qualify-configuration`, `ConfigurationQualificationScripts`, `ConfigurationQualificationObservation` | MainForm/WebView2 et dialogues Windows ; C18 réussie, installation confirmée dans un banc UI séparé |
| Interface raccordée | `web-check.mjs`, `web-dom-check.mjs`, `web-business-check.mjs`, `web-maintenance-check.mjs` | Vrais modules/formulaires/dialogues dans Chromium avec pont de test |
| Démarrage/fermeture natifs | `MaintenanceHost --qualify-demo`, workflow V2 | Vrai MainForm et WebView2 fixe ; preuves JSON par canal |
| Accueil et saisie native | `StartupPolicyTests`, `--qualify-login` ; `--qualify-welcome` et `--qualify-uac` retirés en 2.0.2 avec l’écran d’accueil | C18 : mise en page, annulation/reprise et saisie protégée synthétiques ; preuve UAC réelle historique C14 liée à son EXE |
| Retour AD de qualification | `RestoreNamePolicy`, `RestoreHistoryPolicy`, `RestoreRenameMovePolicy`, `RestoreRenameMoveReceiptGate`, `V1BarrierPolicy` | C18 : 250 gardes synthétiques Windows, dont deux écritures de reçus bloquées ; historique C14 de retour réel séparé, aucune qualification AD des ZIP C18 |
| Qualification AD | [Checklist Windows](QUALIFICATION-WINDOWS.md) | Canari réel uniquement, lié au binaire exact |
| Packs complets | `make-pack.mjs --verify`, workflow V2 | Inventaire fermé, hashes, manifestes, runtime embarqué |

Les [journaux portables de la reprise](evidence/20261025/README.md), dépourvus de données d’annuaire réel, sont conservés avec leurs SHA-256. Les autres journaux de travail `v2/logs` et sorties `v2/out` ne sont pas suivis dans Git. Le rapport courant donne les commandes et résultats réels. Les campagnes candidates conservent les preuves et les packs séparément. Une publication explicite depuis `master` peut créer une release après la réussite complète du job Windows et les contrôles du second job de publication. Les publications du labo utilisent le transfert local vérifié décrit dans le guide de qualification ; les anciens ZIP candidats nettoyés le 1er novembre ne sont plus téléchargeables, leurs preuves restent conservées.

## Rapports historiques

[VALIDATION.md](VALIDATION.md) conserve les campagnes initiales du 23–24 octobre ; [VALIDATION-20261025.md](VALIDATION-20261025.md) conserve la campagne précédente liée aux commits antérieurs. Leurs nombres de tests, leurs anciennes restrictions d’injection et leurs anciennes captures ne décrivent pas automatiquement le code courant.

L’existence de code sur le Spark non poussé n’est pas une preuve d’intégration à cette branche. Seuls les fichiers réellement présents dans le commit et les validations identifiées ici sont pris en compte.
