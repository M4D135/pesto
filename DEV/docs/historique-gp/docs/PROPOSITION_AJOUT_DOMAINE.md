# Proposition : une page « Ajouter au domaine » dédiée

**Statut : proposition de parcours. Non implémentée dans la RC12.**

## Pourquoi quitter la file pour cette opération

La file actuelle mutualise l'exécution, les confirmations, le journal et la gestion des erreurs. Ce mécanisme est utile pour renommer ou déplacer plusieurs postes. La fonction AddToDomain, elle, joint uniquement le poste local. Faire ajouter une ligne, la cocher puis exécuter une file n'apporte donc pas la même valeur pour la jonction de ce PC.

Le principe proposé : conserver les contrôles et le worker du moteur existant, mais présenter une seule opération dédiée. Ce ne serait ni une file cachée avec les mêmes contraintes ni une deuxième implémentation d'Add-Computer.

## Navigation

Ajouter « Ajouter au domaine » à la barre latérale. Ouvrir cette page par défaut quand l'état du poste est confirmé hors domaine. Garder « Renommer » et sa file pour le parc déjà joint.

La nouvelle page concernerait explicitement **ce PC**, sans champ de cible distante. Si Windows est déjà joint au domaine visé, afficher l'état et proposer la page Renommer. S'il appartient à un autre domaine ou si son état est indéterminé, bloquer la jonction sans déclencher de sortie du domaine existant.

## Un écran, trois cartes

### 1. Ce PC

Afficher en lecture seule le nom actuel, le domaine ou groupe de travail constaté, le domaine cible et l'identité utilisée. Montrer séparément l'élévation locale et l'authentification AD. Une absence de droits ou de credential nécessaire doit être expliquée avant de pouvoir lancer l'action, pas par une nouvelle fenêtre de login au milieu.

### 2. Son nom et son emplacement

Réutiliser la convention de nommage, avec type, organisme, site, service et numéro. Afficher le nom complet généré et le chemin lisible de l'OU, avec le DN technique dans une infobulle ou un volet de détail.

Respecter le mode de jonction configuré : production directe si DirectProd l'autorise, sinon OU de préproduction. Afficher séparément le **site souhaité** et l'**emplacement réel à la jonction** si ces valeurs diffèrent. Ne pas présenter un interrupteur qui contourne la politique de configuration.

### 3. Vérifier et ajouter

Un bouton « Vérifier » effectuerait seulement les lectures nécessaires : état local, configuration, découverte du contrôleur, nom disponible, OU existante et autorisée, credential présent. Les lectures réussies ne garantiraient pas les droits effectifs d'écriture d'Add-Computer.

Afficher un récapitulatif stable : ce PC, nom futur, domaine, OU réelle de jonction et redémarrage ultérieur requis. Les modifications des champs invalideraient la vérification précédente. Le moteur effectuerait de nouveau les vérifications critiques juste avant mutation.

Un seul bouton principal : **Ajouter ce PC au domaine**. Une confirmation explicite serait conservée, mais aucune insertion manuelle dans une file, case à cocher ou seconde commande Exécuter ne serait nécessaire.

## Progression et résultat

Afficher une étape courante, une durée et un accès au journal. Conserver l'exécution asynchrone, la prévention des doubles clics, un identifiant d'opération et un état persistant permettant de retrouver une action interrompue.

Un arrêt de supervision ne prouve pas l'annulation Windows : un résultat indéterminé resterait verrouillé, sans nouvelle tentative automatique. Après l'appel Windows, seule une confirmation fiable ferait afficher un succès.

Texte de réussite proposé : **« Ajout accepté · redémarrage nécessaire »**. Ne pas annoncer une jointure totalement active avant le redémarrage et sa vérification. Deux choix explicites : « Redémarrer maintenant » et « Plus tard ». Aucun compte à rebours ni redémarrage imposé.

## Préserver les protections

- Refuser un nom déjà présent dans AD, sans supprimer ni reprendre silencieusement un objet existant.
- Ne jamais lancer dsregcmd /leave pour cette jonction : le traitement Entra existant reste attaché au renommage.
- Conserver audit et historique, même sans file visible.
- Refuser une nouvelle soumission si un redémarrage requis ou un résultat incertain n'a pas été vérifié.
- Ne pas promettre une authentification unique : utiliser le credential établi au démarrage et signaler clairement son absence avant la mutation.

## Exemples d'états affichés

| Situation | Présentation proposée |
|---|---|
| PC hors domaine, informations incomplètes | « Choisissez son nom et son emplacement. » |
| Nom déjà utilisé | « Ce nom existe déjà. Choisissez un autre numéro. » |
| OU de préproduction imposée | « Ajout dans la zone de préparation configurée. » |
| Traitement lancé | « Ajout au domaine en cours », durée et journal |
| Confirmation Windows reçue | « Ajout accepté · redémarrage nécessaire » |
| Résultat incertain | « Résultat à vérifier. Ne relancez pas l'ajout. » |
| PC déjà dans le domaine | État en lecture seule et accès à Renommer |

## Optimisation envisageable

La page pourrait charger seulement les informations de jonction et les recherches de nom ciblées, sans attendre l'inventaire complet du parc. Cette optimisation nécessite un travail distinct sur le chargement AD actuel ; elle n'est pas présente dans la RC12.

Référence technique pour NewName, OUPath, PassThru et l'effet du redémarrage d'Add-Computer : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer?view=powershell-5.1
