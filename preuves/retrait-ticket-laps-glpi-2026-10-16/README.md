# Retrait des fonctions ticket, GLPI/CMDB et LAPS — 16 octobre 2026

Suppression du fournisseur LAPS et du générateur de lien de ticket, des champs de référence dans les formulaires, lots, brouillons, plans préparés et commandes silencieuses. Les nouvelles métadonnées refusent Ticket et AssetId. Les comptes rendus techniques et identifiants d’opération restent disponibles.

Les lecteurs de reçus historiques acceptent encore les anciens champs, sans réécrire les originaux ni les republier dans les comptes rendus. Les anciens plans préparés et brouillons contenant Reference doivent être préparés à nouveau : leur contrat fermé ne les accepte plus.

Validation locale : 555 tests Python réussis, suites PowerShell ciblées jointes ; aucune exécution AD ni VM. La suite RetiredFeatures couvre le retrait et la lecture des anciens reçus. Le moteur généré et le manifeste correspondent aux sources. Validation finale réussie sur Linux, Windows Server 2022 (en-US) et Windows Server 2025 (fr-FR), commit source `1c95f5df128372a106be0af6ee11439a6ec6e545`, [CI 38880078117](https://github.com/M4D135/pesto/actions/runs/38880078117). Les 52 suites isolées, contrôles WPF supplémentaires et cycles de fenêtres ont réussi sur les deux Windows. Les premières CI avaient détecté des attentes obsolètes dans les tests de pilotage et d’import CSV ; les fixtures ont été mises à jour, sans modifier le moteur.

Une revue complémentaire a été confiée au Spark avec les sources et le diff complets. Aucun résultat public reçu ; appel interrompu après réussite de la CI finale. Aucun avis Spark ni succès de revue ne sont revendiqués.

Guides Word et PDF actualisés : 24 pages technicien, 59 pages administrateur. Les PDF sont issus du rendu Word (LibreOffice via render_docx.py), avec contrôle visuel de toutes les pages ; captures obsolètes retirées et absence des anciennes commandes/champs vérifiée dans le texte extrait. Les captures conservées montrent uniquement les parcours inchangés.

Les points 51, 113 et 116 du catalogue sont retirés à la demande de David. Les autres points encore en développement ne sont pas déclarés terminés.
