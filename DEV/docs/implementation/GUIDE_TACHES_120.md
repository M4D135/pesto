# Pesto 1.0 Guide des tâches

Ce guide court sert de point d'entrée. Les guides technicien et administrateur détaillent les procédures et les limites.

## Ajouter le PC au domaine

Ouvrir la jonction, sélectionner le site et le service puis vérifier le nom et l'OU proposés. Utiliser la vérification en lecture seule avant la confirmation. Après acceptation, redémarrer explicitement quand le PC est disponible. Consulter le reçu en cas de résultat partiel ou indéterminé ; ne pas relancer la commande pour tenter de débloquer l'écran.

## Modifier un seul poste

Lire le poste, compléter les champs nécessaires, puis comparer l'état actuel et l'état demandé. Confirmer seulement l'opération affichée. Le déplacement intervient selon la procédure du moteur après le renommage confirmé. Une commande terminée conserve son reçu ; son suivi complémentaire est facultatif. Une opération active, incertaine ou partielle reste protégée.

## Préparer plusieurs postes

Ouvrir Plusieurs postes, préparer la liste puis contrôler chaque ligne et le récapitulatif. Corriger toutes les erreurs avant exécution. L'arrêt demandé conserve l'action en cours et laisse les postes suivants non lancés. Une annulation de brouillon ne revient jamais sur une mutation AD.

## Choisir un nom

Régler les filtres Type, site et service ainsi que la plage des numéros. Le tirage aléatoire est actif par défaut parmi tous les candidats libres de cette plage. Une lecture ancienne ou incomplète ne garantit pas la disponibilité ; le moteur relit la cible au moment prévu par le précontrôle.

## Modifier la configuration

Travailler dans le brouillon, lire les erreurs près des champs et prévisualiser les différences. Importer un fichier ne l'active pas automatiquement : enregistrer séparément. En présence d'une modification externe, relire la version courante avant de décider quoi conserver.

## Comprendre un résultat

Ouvrir Interventions et le reçu correspondant. Distinguer commande acceptée, état observé, suivi facultatif, résultat incertain et action partielle. Le compte rendu masque les identifiants par défaut. Le dossier de support doit être prévisualisé avant transmission.

## Afficher moins ou plus d'informations

Utiliser les rubriques et les détails de la page. La barre de zoom conserve ses boutons −, pourcentage et + ; le pourcentage rétablit 100 %. Réduire le menu avec son icône en bas. F6/Maj+F6 permet de changer de grande zone lorsque ce parcours est disponible dans le build livré.

## Automatiser

Utiliser les commandes et adaptateurs livrés avec le même build. Préparer un plan avant `-Execute`, fournir les credentials en mémoire et traiter les codes de résultat. Un résultat incertain n'est jamais une autorisation de relancer automatiquement. Le redémarrage reste une décision explicite du système d'orchestration. Pour les campagnes approuvées, fournir l'objet accord signé via `-Approval`. Pour les attributs AD, utiliser le parcours extension avec diff et relecture.
