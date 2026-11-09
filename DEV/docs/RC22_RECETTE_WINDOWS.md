# Recette Windows RC22 à réaliser

## Tests isolés

VM de recette, instantané et aucune donnée de production. Garder les politiques Windows normales.
`TESTER.cmd` enchaîne les tests précédents, les 25 cas Noms, les 61 cas RC21 et les **33 cas RC22**.
`TEST_RC22.cmd` lance uniquement le nouveau groupe, avec `-Wpf`.
Le groupe RC22 extrait les fonctions par le vrai parseur PS5.1, utilise des doubles pour les écritures, puis teste les vrais contrôles WPF.
Aucun compte réel, aucune commande AD, aucun /leave ni UAC n'est nécessaire à ces tests isolés.
Sans `-Wpf`, un SKIP empêche de considérer le groupe accepté. Les erreurs de parseur restent bloquantes.
`tools/Verify-Release.ps1` exige aussi le rapport rc22.json. Pester/ScriptAnalyzer restent à préprovisionner dans DEV/CI seulement.
La CI n'a pas été exécutée ici. Les rapports d'une ancienne version ne servent pas de preuves actuelles.

## Essais manuels supplémentaires

1. Domaine et hors domaine : vérifier le compte effectif après UAC, le login attendu, refus UAC et annulation. Aucun deuxième login automatique ajouté dans le parcours domaine.
2. Clair/sombre/système, 100/125/150/200 %, RDP et petite fenêtre : champs, messages et boutons lisibles ; login non maximisable.
3. Actions : rechercher « deplacer poste » sans accents ; recherche vide, caractères « [ » ou « .* », aucun résultat, flèches/Entrée/Échap. Ne pas déclencher une mutation par une sélection.
4. Colonnes : déplacer/redimensionner, mémoriser, fermer/rouvrir ; colonnes d'identité immobiles ; aucune coche ou sélection restaurée. Réinitialiser sans perte de lignes.
5. Charger explicitement l'inventaire. Contrôler capacité avec combinaison vide déclarée, doublons et retenue déjà occupée. Afficher le périmètre et la date, pas une réservation AD.
6. Conformité : bons/mauvais sites, sous-OU, préproduction, virgule échappée, TAGS absents, code ambigu et métadonnées absentes. Aucun déplacement exécuté par l'analyse.
7. Fermer un calcul ; remplacer l'inventaire ou la configuration avant retour : aucun ancien résultat publié.
8. Sur une VM dédiée : vérifier les reçus avant/après renommage et déplacement ; le second effet ne remplace pas la première photographie.
9. Conserver une lecture incohérente/partielle mais identifiée : la phase et les verrous restent inchangés. Une lecture vieille ou une autre identité est refusée.
10. Ouvrir un reçu ancien sans photographie : « Non enregistré », aucune reconstruction présentée comme mesure passée.
11. Recréer en recette un objet de même nom après préparation d'un brouillon : GUID différent refusé avant reprise des champs.
12. Injecter refus après déplacement confirmé et code entier inconnu : partiel/incertain, pas simple échec libérant l'opération.
13. Mettre à jour sur NTFS de test : coupure du processus de copie à plusieurs étapes, `--recover` en aperçu puis en application ; retour exact au code précédent, configuration et reçus conservés.
14. Modifier volontairement une copie du code ou de la sauvegarde après interruption : reprise automatique refusée. Ne pas effacer le verrou pour rendre le test vert.
15. Conserver les preuves : version/empreinte exacte, Windows/build/PS, PASS/FAIL/SKIP, captures de recette, durée et anomalies. Les données de domaine restent locales, pas de télémétrie imposée.

## Points non prouvés par ces outils

Une compilation C et un lint ne valident pas UAC/WPF. Une copie restaurée sous Linux ne prouve pas une panne électrique NTFS/SMB. Une photographie ne certifie pas la réinscription Entra ni le SSO de l'utilisateur. Une signature exige un certificat approuvé.
La publication et la fermeture des 90 critères restent séparées de cette recette.
