# Recette cible RC21 : à exécuter sous Windows

## Préparation

VM Windows 11 de test avec instantané, comptes délégués de test et domaine de recette. Ne pas utiliser un poste de production pour provoquer une coupure ou tester un retour tardif. Extraire une copie complète DEV et débloquer les fichiers seulement après avoir vérifié leur provenance. L’UAC et les politiques de sécurité restent celles de l’organisation.

`TESTER.cmd` exécute trois groupes sous Windows PowerShell 5.1 x64 STA : tests natifs hérités mis à jour, 25 cas de noms et **61 cas RC21**. Ceux-ci incluent les règles pures, la pagination, un index réutilisé, les types malformés, les reçus modifiés, une coordination en répertoire temporaire, le writer C# et les panneaux WPF réels. Les 3 996 combinaisons de nommage sont une boucle dans un cas, pas 3 996 tests déjà exécutés ici.

`tests\Run-Pesto21Tests.ps1 -Wpf` peut être lancé isolément. Sans `-Wpf`, le test marque la partie visuelle SKIP et renvoie un code d’échec de recette incomplète. Les fixtures sont créées dans un nouveau répertoire temporaire, jamais dans vos reçus métier. Aucun accès AD réel, renommage, /leave ou UAC n’est requis par ces tests isolés.

Pester 5.7.1 et PSScriptAnalyzer 1.24.0 sont à préprovisionner depuis une source approuvée pour `tools\Verify-Release.ps1`. PROD ne télécharge et n’exige ni ces modules ni Python. La CI manuelle possède des actions figées et exige les preuves ; elle n’a pas été exécutée dans cet environnement et ne publie rien automatiquement.

## Matrice interactive minimale

| Parcours | Essai | Attendu à observer |
|---|---|---|
| Lancement | Chemin avec espaces/accents, EXE et wad complets | RC21, aucune console en mode normal, même identité Windows après UAC |
| Connexion domaine | UAC acceptée puis refusée ; compte différent | Pas de login Pesto redondant par défaut ; refus sans boucle d’élévation |
| Consultation | `--consult` depuis session standard | Pas d’UAC ; commandes métier refusées, lectures autorisées selon le compte |
| Hors domaine | Login puis formulaire de jonction | Login lisible/non maximisable ; jonction sans file |
| Apparence | Clair/sombre/système avant/après cfg/UAC | Thème stable, texte lisible, erreurs et panneaux dans le bon thème |
| Échelles | 100/125/150/200 %, RDP, petit écran, écran retiré | Aucun champ inaccessible ; commandes défilables, focus visible, pas de fenêtre hors écran |
| Accessibilité | Tab/Échap/Ctrl+K/F1, Narrateur et contraste élevé | Nom/action compréhensibles ; retour du focus après panneau ; limites visuelles consignées |
| Noms | Inventaire absent, ancien, échec ; filtres changés vite | Progression réelle, ancien résultat non validable, dernier filtre seul publié |
| Noms | Sites vides, AD occupé, file et retenue personnelle | États distincts ; aucun nom présumé réservé dans AD |
| Pagination | Plusieurs pages, plage vide, au-delà de limite | 250 lignes max ; compteurs cohérents ; export de la page affichée |
| Candidats | Premier trou/après séquence, contrôle explicite | Cinq max ; source et heure visibles ; relecture avant mutation |
| Favoris/brouillons | Ancien favori, nouveau domaine, import modifié | Champs non sensibles seulement ; aucun accord ou reboot restauré |
| Lot pilote | 3 machines de test, pilote activé | Première exécutée, autres non lancées jusqu’à une nouvelle confirmation |
| Reprise | Retirer la ligne d’une intervention incertaine | Reçu consultable ; aucune suppression de verrou au retrait |
| Plan | OU supprimée/recréée ou compte recréé après contrôle | Plan refusé avant mutation ; nouvelle vérification exigée |
| Coordination | Deux clients configurés pour même cible puis cibles distinctes | Un seul engagement conflictuel ; pas de déverrouillage par âge du fichier |
| Coordination | Rupture de partage après engagement | État à vérifier, pas de seconde mutation automatique |
| Protection | Erreur contrôlée code 32, vrai/faux initial | Restauration exacte après confirmation ; crash ambigu reste à examiner |
| Tâches | Modifiée, active, absente, fin confirmée | Seule la tâche exacte et terminée peut être nettoyée ; aucun balayage par préfixe |
| Entra | AD seul, hybride autorisé/refusé, sortie illisible | Pas de /leave AD seul ; refus avant rename si préparation non confirmée |
| Post-reboot | Nom/AD cohérents mais Entra non joint | Postconditions séparées ; pas de SSO utilisateur certifié |
| Journal | Disque lent puis plein dans fixture | UI mesurée, perte visible, mutation suivante refusée ; reçu critique distinct |
| Mise à jour | Exception de copie et interruption brutale distinctes | Restauration sur exception ; après crash, vérifier sauvegarde/verrou, pas de prétendue atomicité globale |

## Budgets de performance à qualifier, pas résultats annoncés

Mesurer dans le même environnement 100 changements de filtre, 1 000 ouvertures/fermetures de panneau, une session de deux heures, et un inventaire représentatif (par exemple celui réellement utilisé en recette). Consigner temps de calcul, délai jusqu’au rendu, mémoire privée, handles, threads et débit du journal. Les seuils doivent être fixés après une mesure initiale de ce parc, pas inventés à partir du nombre de postes.

Les mesures de la palette sont locales et bornées à 200 échantillons. Elles ne constituent pas une télémétrie exhaustive. Une réussite de compilation C ou de XML ne prouve pas la fluidité sous WPF.

## Sortie de recette

Conserver version exacte, SHA-256 de l’EXE, build Windows/PowerShell, dates, PASS/FAIL/SKIP et captures des vrais écrans. Ne pas marquer PASS les cas ignorés. Signature d’entreprise, recette interactive UAC et opérations AD réelles sont des étapes séparées de la CI isolée. `PublicReleaseAuthorized` reste faux dans les rapports générés automatiquement tant que l’autorisation de diffusion n’a pas été donnée par l’organisation.
