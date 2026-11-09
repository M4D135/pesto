# Pesto 1.0 Livraison et composants communs

Ce document suit les points 73–78 et 87–108 du catalogue autorisé. Les états distinguent l'implémentation locale, l'intégration aux consommateurs et les qualifications externes. Aucun certificat ni résultat Windows n'est créé par les tests locaux.

## État par point

| ID | Réalisation | État et preuve |
| --- | --- | --- |
| 73 | Common.Core : validation bornée, résultat typé, sérialisation JSON UTF-8 bornée | Implémenté et bundle 0.2.0 intégré avec commit a050525 ; tests locaux et compatibilité API |
| 74 | Common.Diagnostics : tampon borné, évictions visibles, journal asynchrone borné, échecs/fermeture explicites et masquage défensif | Tests locaux ; masquage des diagnostics réutilisé, writer métier conservé |
| 75 | Common.Wpf séparé : géométrie bornée, coalescence Dispatcher, actualisation de pairs existants | Compilé net472/C#5 ; sept contrats WPF isolés PASS sous Windows PowerShell 5.1 |
| 76 | Common.IO : écriture temporaire, flush, remplacement avec sauvegarde, refus de liens et aucun fallback de suppression | Tests locaux et cinq contrôles de liens NTFS réels PASS ; aucune qualification exhaustive des ACL |
| 77 | Surface publique 0.1.1 préservée, version de fichier 0.2.0 additive, refus de downgrade dans pipeline | 167 membres publics anciens comparés ; contrats isolés Windows PowerShell 5.1 PASS |
| 78 | Build, manifeste, vérification SHA256 et génération de locks par consommateur dans dépôt canonique | Pipeline et snapshot vendor intégrés ; digest sources/commit/lock vérifiés |
| 87 | `.github/workflows/validate.yml` à la racine, push master/PR/manuelle, chemins DEV, actions épinglées | Contrat local contrôlé ; huit nouveaux bancs 120 intégrés, exécution GitHub après publication |
| 88 | Signature sur copie dédiée : scripts propres, DLL Common, reconstruction, EXE, horodatage et vérification ; Microsoft préservé | Retiré de la livraison courante (décision David 18/10). Script documenté comme option hors périmètre. Contrôles SHA maintenus. |
| 89 | Profil de versions compilateur épinglé, contrôle et deux builds indépendants comparés | C2 : deux builds sur le profil Mac comparés, runtime identique ; aucune portabilité entre compilateurs inférée |
| 90 | SBOM CycloneDX 1.6 du runtime fermé avec SHA256 | Générateur et schéma officiel 1.6 validés sur fixture ; SBOM du build final généré dans preuves/finition-120-2026-10-15/release |
| 91 | Statement in-toto/SLSA non signé + workflow manuel d’attestation GitHub des rapports générés | Workflow fourni ; service/plan requis, aucune exécution distante revendiquée |
| 92 | Inventaire en lecture seule signatures/langage/politiques et protocole App Control audit/imposé | Banc prêt ; aucune politique changée ni qualification revendiquée |
| 93 | Installation gérée optionnelle, détection, aperçu de désinstallation ; configuration et profils GP conservés | Reçu intégré à la transaction ; 16 régressions dédiées réussies dans la suite Python C2, avec retours arrière et reprises sur fichiers temporaires |
| 94 | Sélection pilote/général par version + hash EXE + hash manifeste ; updater existant seul effectue la transaction | Tests locaux ; aucune recherche réseau ni mise à jour automatique |
| 95 | Inventaire des DLL Microsoft, versions/signatures et statut de redistribution séparé | Droits de redistribution NON ATTESTÉS ; justificatif de licence source requis |
| 96 | Dossier release : runtime, guides, packs fournis, rapports référencés, hashes, limites et versions | Assemblage DEV/PROD neutre et guides v1.0 réalisés ; dossier final dans preuves/finition-120-2026-10-15/release |
| 97 | Enveloppe de preuve avec plateforme, périmètre, build, hash de rapport brut et exécution déclarée | Tests locaux ; pas de conversion d'un SKIP/NOT_RUN en PASS |
| 98 | Matrice Windows/langue/.NET/identité/politique documentée | Protocole prêt ; cases non jouées restent NOT_RUN |
| 99 | Parcours bout en bout et capture foreground + arbre UIA en lecture seule | Banc prêt ; gestes/résultats réels doivent être consignés |
| 100 | Matrice DPI/résolutions/zoom/thèmes/petites fenêtres et captures avec empreintes | Protocole prêt ; comparaison finale à jouer après gel UI |
| 101 | Parcours clavier/F6/Narrator documenté avec retour de focus et annonces | Protocole prêt ; écoute Narrator réelle à qualifier |
| 102 | Injection d'échec copie/publication/rollback ; contrats moteur dans Run-Engine120Tests | Tests locaux ciblés ; panne NTFS/SMB réelle non déduite |
| 103 | Scénarios deux machines/deux opérateurs SMB et refus de vol de réservation | Protocole prêt ; SMB réel non exécuté dans ce lot |
| 104 | Scénarios deux DC sans bascule ou réplication forcée | Protocole prêt ; labo multi-DC requis |
| 105 | Corpus génératif Unicode/JSON/bornes Common et contrats moteur DN/états | Tests locaux, pas de mutation AD |
| 106 | Détection de marqueurs secrets factices UTF-8/UTF-16 sans afficher leur valeur ; limites images explicites | Tests locaux ; captures à relire visuellement/OCR |
| 107 | Mesure répétée mémoire/handles/threads/CPU du processus choisi | Banc prêt ; verdict de fuite non inféré d'une mesure |
| 108 | Guide court par tâches et protocole de qualification, sources Markdown | Livré ; DOCX/PDF finaux mis à jour après gel UI par le responsable des guides |

## Commandes de livraison

Depuis DEV, travailler sur un dossier neuf et conserver l'original :

```text
python tools/check_toolchain.py --profile macos-reference
python tools/reproducible_build.py --source CHEMIN_DEV --output CHEMIN_NEUF --profile macos-reference --powershell CHEMIN_PWSH
python tools/release_assurance.py create --source CHEMIN_DEV --output CHEMIN_NEUF --evidence rapport.json --pack Pesto_PROD.zip --pack Pesto_DEV.zip
python tools/release_assurance.py compare PREMIER_BUILD SECOND_BUILD
```

Le profil Mac verrouille les versions observées Apple clang 21.0.0 et Homebrew LLD 23.1.2. Il ne prétend pas qu'un autre compilateur produit les mêmes octets. Les sorties de builds et les signatures modifient les hashes : générer métadonnées et packs seulement après gel.

```powershell
powershell -NoProfile -File tools/Sign-PestoRelease.ps1 -CertificateThumbprint EMPREINTE -TimestampServer https://HORODATEUR_APPROUVE -OutputDirectory DOSSIER_NEUF
```

Cette commande exige un certificat existant avec clé privée et usage Code Signing. Elle n'installe aucune confiance. Un échec laisse `signature.json` marqué incomplet ; le dossier ne doit pas être distribué. Les DLL Microsoft ne sont pas resignées.

## Installation gérée et canaux

```text
python tools/managed_install.py install --source PROD --destination DESTINATION
python tools/managed_install.py install --source PROD --destination DESTINATION --execute
python tools/managed_install.py detect --destination DESTINATION
python tools/managed_install.py uninstall --destination DESTINATION
python tools/managed_install.py uninstall --destination DESTINATION --execute
python tools/update_channels.py --catalogue canaux.json --ring pilot --source PROD --target DESTINATION
```

`detect` retourne 0 uniquement pour une installation gérée saine, 1 pour une absence/altération. Aucune clé de registre, service ou tâche planifiée n'est créé. La désinstallation conserve cfg.json, les fichiers non possédés et tous les profils GP. Un échec partiel conserve une barrière de mise à jour à examiner, sans suppression automatique. Une installation portable non gérée n'est pas adoptée implicitement.

La mise à jour reconnaît uniquement un `pesto-installation.json` existant, valide et
concordant avec tous les fichiers possédés. Elle sauvegarde ce reçu avec le code,
prépare le nouveau reçu et le publie en dernier sous la même barrière durable. Le
retour arrière restaure les octets de l’ancien reçu ; une interruption après
validation complète conserve le nouveau code et son reçu lors de `--recover --apply`.
Une altération concurrente ou une sauvegarde invalide maintient la
barrière. Le reçu d’installation est une métadonnée de propriété locale, distincte
des reçus d’opérations Windows/AD, qui restent intacts.

Les helpers possédés, actuellement `wad/support/DEBLOQUER_TOUT.cmd`, sont conservés
à l’identique et inclus dans les vérifications de la transaction. Un composant
retiré du nouveau runtime reste sur disque sans être repris par le nouveau reçu ;
la désinstallation le conserve comme tout fichier non possédé. Aucun reçu de
gestion trouvé dans la distribution source ne peut adopter une destination
portable. Les cas dédiés sont dans `tests/test_managed_update.py` : succès puis
détection/désinstallation, chaque frontière de retour arrière, reprise avant et
après publication du reçu, interruption finale, altérations et propriété refusée.
Ces 16 cas figurent dans la [suite Python C2](../../../preuves/ameliorations-120-2026-10-13/local/python-c2.log)
de 405 tests réussis. Ils emploient des fichiers temporaires et des sous-processus
interrompus volontairement ; ils ne simulent pas une coupure électrique NTFS/SMB.

Le catalogue de canaux possède le schéma 1 et deux entrées `pilot`/`general`, chacune contenant exactement `version`, `exeSHA256` et `manifestSHA256`. Il ne contient ni URL ni identifiants. `--execute` utilise le même updater que le parcours normal ; sans ce drapeau, aperçu uniquement.

## Références primaires et limites

- [GitHub Actions checkout](https://github.com/actions/checkout) ; [setup-python](https://github.com/actions/setup-python) ; [upload-artifact](https://github.com/actions/upload-artifact).
- [CycloneDX JSON 1.6](https://cyclonedx.org/docs/1.6/json/) et [provenance SLSA](https://slsa.dev/provenance/v1).
- [Authenticode et SignTool Microsoft](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).
- [App Control et scripts](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/script-enforcement).
- [Attestations GitHub](https://github.com/actions/attest-build-provenance) : les dépôts privés nécessitent un plan pris en charge, actuellement Enterprise Cloud. Le statement local reste non signé ; il ne prouve ni un niveau SLSA ni la confiance d'éditeur. Le workflow manuel `release-evidence.yml` atteste uniquement les rapports JSON qu’il génère : il n’atteste pas une compilation de Pesto.exe dans ce job et ne remplace pas Authenticode. Il exige un lancement sur master et un compte GitHub autorisé ; aucun certificat de production n’est créé.

L'inventaire d'une signature Microsoft ne prouve pas un droit de redistribution. Documenter la provenance et la licence des fichiers RSAT avant une diffusion nécessitant cette autorisation. Le protocole [QUALIFICATION_120](QUALIFICATION_120.md) conserve toutes les cases externes non exécutées. Les nouveaux tests de livraison utilisent des fichiers synthétiques, pas un lancement de Pesto.

## Preuves locales et intégration

La clôture se fait avec la [procédure de rapprochement des preuves](CLOTURE_120.md),
en conservant les périmètres et les builds. Le [double build C2](../../../preuves/ameliorations-120-2026-10-13/local/repro-c2.json)
compare deux compilations indépendantes sur le même profil Mac et constate des
octets runtime identiques. L’[inspection des packs C2](../../../preuves/ameliorations-120-2026-10-13/release-audit/packs-c2.json)
porte sur les archives de préparation : elle ne désigne pas les futurs ZIP finaux
après actualisation des guides et des outils de livraison.

Le [rapport de livraison](../../../preuves/implementation-120-2026-10-13/release/summary.json) lie les sources et les journaux : 34 cas nouveaux de livraison, 35 cas de chemins, 13 cas de fabrication et 3 cas de cohérence Common passent. Le chargeur intégré passe 19 cas sur Mac ; la fixture comprenant aussi la DLL Wpf couvre un cas supplémentaire de refus d’altération sans chargement. Ces nombres restent séparés, car les granularités diffèrent.

Le socle canonique `a050525abb46696d6b1516b18cccc2b837908a09` fournit Core/Query/IO/Diagnostics. Les [contrats communs](../../vendor/M4D.Admin.Common/validation/catalogue-120/contracts.json) passent respectivement 2625, 81, 25 et 15 assertions. La comparaison préserve 167 membres publics de 0.1.1 ; les anciens tests binaires passent également contre les DLL 0.2.0. Ces preuves sont exécutées sur Mac/.NET 8, avec compilation C# 5/net472, et ne remplacent pas la qualification Windows. Les sources vendor et `source-commit.txt` concordent avec le lock.

La validation du [SBOM contre le schéma officiel](../../../preuves/implementation-120-2026-10-13/release/sbom-schema.json) et le [parsage des outils PowerShell](../../../preuves/implementation-120-2026-10-13/release/powershell-parser.json) sont conservés séparément. Les [instructions d’intégration Common](COMMON_020_INTEGRATION.md) expliquent l’ordre commit, build, bundle, snapshot, lanceur et manifeste. Aucun certificat ni résultat de politique App Control, Narrator, SMB ou multi-DC n’est déduit de ces tests.


Le [banc Windows du socle](../../../preuves/ameliorations-120-2026-10-13/common-windows/report.json), exécuté par le responsable de recette sous Windows PowerShell 5.1/CLR 4, confirme Core 2625, Query 81, IO 22 et Diagnostics 15 assertions, ainsi que sept contrats WPF isolés. Trois contrôles de liens ignorés par le banc C# net472 sont complétés par [cinq contrôles PowerShell sur de vrais liens NTFS](../../../preuves/ameliorations-120-2026-10-13/common-windows/links-report.json), dont le refus d’une écriture AtomicFile via un parent lié et la conservation du contenu. Ces résultats ne constituent ni une recette GUI de Pesto ni une qualification générale des ACL ou des pannes NTFS.

## Livraison locale finale du 15 octobre 2026

Le [dossier final](../../../preuves/finition-120-2026-10-15/README.md) lie les rapports
locaux, le build exact, les guides et les deux archives neutres. Le SBOM et le statement
in-toto décrivent les octets fournis ; ce statement reste non signé. Les preuves Windows
C2 ci-dessus ne sont pas transférées au build final. Les [correctifs et contrats locaux](../../../preuves/correctifs-ci-2026-10-15/README.md) complètent cette livraison : point 105 qualifié pour les contrats purs, 11 qualifications encore ouvertes et mesure prolongée 107 restante. Les états courants sont consignés dans le catalogue.
