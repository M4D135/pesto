# Socle commun de Pesto 1.0

Pesto embarque **M4D.Admin.Common 0.2.0** : quatre DLL, **Core**, **Query**, **IO**
et **Diagnostics**. Le source canonique est le dépôt privé
[M4D135/m4d-admin-common](https://github.com/M4D135/m4d-admin-common), révision
`a050525abb46696d6b1516b18cccc2b837908a09`.

| Module | Primitives fournies |
| --- | --- |
| Core | Tirage uniforme parmi les candidats admissibles, validation de texte, résultat typé et sérialisation JSON bornée. |
| Query | Filtres typés et agrégations réutilisables. |
| IO | Lecture de fichiers et écriture atomique avec sauvegarde, refus des chemins liés. |
| Diagnostics | Tampon borné, masquage défensif de texte et journal asynchrone borné. |

Pesto réutilise le tirage et les requêtes ainsi que le masquage complémentaire des
diagnostics textuels. Les opérations AD/Windows, confirmations, reçus et règles de
persistance restent dans le moteur métier. Le writer d’audit Pesto conserve son
contrat append/flush ; utiliser une primitive commune demande une compatibilité
vérifiée avec les besoins de chaque parcours. DOMENIA et FILPRO conservent leurs
propres locks et qualifications.

## Versions et chargement

Les DLL ciblent .NET Framework 4.7.2, en C# 5. Leur identité CLR
`AssemblyVersion=0.1.1.0` est stable ; leur version de fichier est `0.2.0.0` et leur
version informative `0.2.0`.

`wad/common.lock.json` indique versions, tailles, empreintes, digest des sources,
révision canonique et compilateur. Le manifeste global Pesto et le lanceur lient
également ces fichiers. Le chargeur vérifie tout le lot avant chargement, refuse
les liens et les assemblies préchargées d’une autre provenance, puis conserve les
identités vérifiées dans l’AppDomain. Aucun téléchargement ni compilation n’a lieu
sur le poste utilisateur.

`Common.Wpf` est une DLL séparée. Elle fournit des primitives de présentation,
coalescence Dispatcher et actualisation des pairs UIA existants. Elle n’est pas
embarquée dans le pack Pesto actuel. Un consommateur qui l’adopte doit la déclarer
dans son lock et son runtime, puis la charger explicitement sous Windows. Une DLL
WPF déclarée au lock est toujours vérifiée, même lorsqu’elle n’est pas chargée.

## Fabriquer et intégrer

La copie `vendor/M4D.Admin.Common` permet d’examiner et de reconstruire le source
exact du pack DEV. `source-commit.txt` identifie son commit. Corriger le dépôt
canonique, le faire relire et committer, puis générer un bundle vérifié avant de
renouveler explicitement DLL, source vendor, lock et manifeste Pesto. Le pipeline
refuse un dist dont le digest ne correspond plus aux sources, ainsi qu’un downgrade
ou un arbre non committé pour une livraison normale.

La compilation canonique utilise les références Microsoft 4.7.2 vérifiées par
SHA512. Les DLL de tests ne font pas partie du runtime Pesto. Suivre la
[procédure d’intégration Common](implementation/COMMON_020_INTEGRATION.md) et les
[instructions de fabrication](FABRIQUER_PROD.md).

## Portée des validations

Les preuves du dépôt canonique couvrent la logique pure et la compatibilité de
surface et binaire sur Mac/.NET moderne. Des contrats isolés du même commit ont
également été exécutés sous Windows PowerShell 5.1/CLR 4, y compris le module WPF
séparé. Un banc PowerShell complémentaire contrôle de vrais liens NTFS et la
conservation des fichiers après refus.

La [synthèse de livraison](implementation/RELEASE_120.md) renvoie aux rapports et
à leurs empreintes. Ces contrats ne certifient ni toutes les ACL NTFS ni une recette
GUI/AD de Pesto. Chaque consommateur et chaque build de livraison gardent leur
qualification propre.
