# Prise en main de Pesto V2

Pesto sert à préparer et suivre la jonction d’un poste au domaine, son renommage et son déplacement dans l’annuaire. Le pack courant reste un candidat : sa [qualification Windows](QUALIFICATION-WINDOWS.md) précise les essais réalisés sur son binaire et ceux qui demandent encore un environnement AD.

## 1. Installer le dossier de l’application

Télécharger le ZIP choisi dans la release GitHub et l’extraire. Le dossier obtenu doit contenir `Pesto.exe` et `wad/`. Conserver ces deux éléments ensemble. Si les fichiers portent une marque de téléchargement Windows, le script `wad/support/DEBLOQUER_TOUT.cmd` débloque tout le dossier de l’application.

À partir de la 2.0.10, un seul pack est publié : **LIGHT** (asset `Pesto_V2_PRODLIGHT_<version>.zip`). Il contient `Pesto.exe` et `wad/`, sans runtime WebView2 intégré. Décompressez le ZIP complet dans un nouveau dossier et lancez `Pesto.exe`. Les sources et outils sont disponibles dans le dépôt au tag de la version.

Au démarrage, Pesto choisit un seul moteur pour toute la session :

1. **WebView2 Evergreen** installé sur le poste (cas courant) ;
2. sinon le **Socle WebView2** extrait dans `wad\runtime\webview2\` (version Microsoft 156.0.4314.42, disponible dans le dépôt privé `M4D135/socle-windows`, release `webview2-156.0.4314.42`) ;
3. sinon un message clair en français : installer Evergreen, ou extraire le pack WebView2 du Socle dans `wad\`, avec le lien de sa release.

N’extrayez le Socle que si Evergreen manque : sinon Evergreen passe en premier. Une installation 2.0.9 PROD (WebView2 intégré) ne se met pas à jour en place : installez le pack LIGHT dans un nouveau dossier.

Pesto vérifie l’inventaire du Socle (fichiers attendus, tailles, empreinte de l’exécutable) contre l’index embarqué. Un fichier modifié, en trop ou manquant est refusé. Le Socle reste hors de l’identité du pack : il n’entre ni dans `wad\SHA256SUMS`, ni dans l’empreinte, ni dans le nombre de fichiers.

## 2. Préparer la configuration

Au premier lancement sans configuration distribuée, Pesto ouvre les Paramètres. Renseigner le domaine, le périmètre d’OU, la convention de nommage et les sites/services utiles, ou importer une configuration existante. Relire les différences avant de confirmer l’import ou l’enregistrement.

La configuration active est conservée dans le profil de l’opérateur. **Exporter** produit un fichier partageable. **Définir comme configuration par défaut** écrit, après confirmation (**Enregistrer comme défaut**), la configuration partageable de ce profil dans `wad\defaults\configuration.json` de ce dossier Pesto. Depuis 2.0.14, aucun pack n’est recréé : les fichiers du programme et leurs empreintes restent inchangés, un pack officiel reste officiel. Un fichier déjà présent est remplacé et sa copie est conservée dans votre profil. Diffusez ensuite ce dossier : un opérateur sans configuration importe automatiquement ces paramètres au premier lancement ; un profil déjà configuré choisit explicitement **Remplacer** ou **Conserver**. Ce fichier contient le domaine et les OU : diffusez ce dossier comme un fichier privé, ne le publiez jamais.

Sous `C:\Program Files`, avec les droits Windows habituels, `--settings` (lancé sans élévation) ne peut pas écrire : la configuration par défaut n’est pas enregistrée et Pesto le dit. Lancez Pesto normalement (UAC), ou exportez la configuration et copiez le fichier sous `wad\defaults\configuration.json`. Une installation issue d’un ancien pack personnalisé (2.0.13 ou antérieur) refuse cette écriture : installez le pack officiel dans un nouveau dossier, puis définissez-y la configuration par défaut.

`Pesto.exe --settings` ouvre la configuration locale sans connexion AD ni demande d’élévation. Après la configuration, **Reconnecter Pesto** ouvre explicitement la session annuaire. Au démarrage normal, Windows demande l’élévation immédiatement ; après une annulation, Pesto propose **Réessayer** ou **Fermer**. Sur un poste joint, l’identité Windows effective est utilisée. Hors domaine, les identifiants sont saisis dans la fenêtre native Pesto. Pour un renommage distant nécessitant un compte explicite, utiliser **Autre compte AD**.

Les réglages complets et les règles d’import sont décrits dans [CONFIGURATION.md](CONFIGURATION.md).

## 3. Découvrir les écrans sans opération réelle

Dans **Paramètres → Interface et démonstration**, ouvrir la démonstration. Elle possède sa propre fenêtre, une bannière permanente et des données fictives. La fenêtre de travail et ses brouillons restent ouverts. Les scénarios, la remise à zéro et le redémarrage fictif appartiennent à cette fenêtre de démonstration.

Les animations se règlent dans cette section ; le thème se choisit dans la barre supérieure. `Ctrl K` ouvre la palette de commandes, `Ctrl B` replie le menu et `F1` ouvre l’aide. Les diagnostics affichent ce qui a effectivement été observé ; une valeur inconnue ne devient pas un résultat positif.

## 4. Préparer une opération sur un poste

Pour ajouter le poste local, ouvrir l’écran d’ajout, choisir les éléments de nommage puis calculer le nom proposé. Le nom doit être visible avant de préparer l’opération. La jonction locale utilise cet écran dédié, sans passer par la file des lots.

Dans **Noms disponibles**, **Ajouter ce PC au domaine** et le formulaire de renommage, changer le site ou le service déclenche une nouvelle lecture de la série dans tout le domaine. Le bouton de calcul permet de la relire à la demande. Pour un portable de préfixe `111301`, site `PR`, service `765`, la série est `P111301PR765001` à `P111301PR765999` avec la convention historique. Le mode séquentiel propose le premier numéro libre. Si un autre technicien prend le nom avant le renommage, Pesto affiche un nouvel aperçu à confirmer. L’accueil lit les reçus dès l’ouverture. **Rafraîchir** charge les compteurs du parc.

Dans **Un poste**, rechercher puis sélectionner la machine. Attendre le catalogue des sites avant de modifier le renommage ou le déplacement. Un échec de chargement propose une nouvelle tentative. Le type portable, fixe ou VM et le site observés sont conservés lorsqu’ils sont identifiés ; une information inconnue demande un choix explicite.

Pour un renommage, **le même code de site conserve l’OU réelle**, y compris une sous-OU. Un changement de site prépare le renommage et le déplacement associé. Le déplacement seul possède son propre parcours. Avant l’envoi, relire le plan, ses étapes, le nom et l’OU, puis fournir la confirmation demandée. Un plan périmé exige une nouvelle préparation.

Les attributs AD disposent d’un aperçu des différences avant confirmation. Les brouillons de configuration et d’attributs demandent un accord avant d’être abandonnés par navigation ou relecture.

## 5. Préparer plusieurs postes

L’écran **Plusieurs postes** accepte la recherche annuaire, une liste collée ou un CSV local. Les colonnes CSV admises sont `name`, `type`, `site`, `service`, avec `;` ou `,` comme séparateur. Les types sont `P` pour portable, `S` pour fixe et `V` pour VM. Exemple de structure avec des valeurs fictives :

```csv
name;type;site;service
POSTE001;P;PA;INF
POSTE002;V;LY;INF
```

La sélection reste un aperçu avant **Ajouter à la file**. Pour corriger les indications d’un poste encore sélectionné, réimporter son nom : les colonnes renseignées remplacent les indications correspondantes. Un type, un site ou un service manquant bloque la ligne concernée ; aucun nom n’est inventé pour la faire passer.

Préparer ensuite le lot et relire chaque ligne. Le mode pilote limite la préparation et l’exécution à la première ligne. L’exécution est séquentielle et s’arrête sur un refus ou un résultat incertain. Un bilan incomplet ou contradictoire ne peut pas afficher un lot entièrement confirmé.

## 6. Lire le résultat et préparer la suite

Consulter les reçus dans **Interventions** et les détails dans le journal. Un résultat accepté avec redémarrage requis reste en attente ; le redémarrage constitue une action distincte. Après redémarrage, lancer explicitement la vérification proposée. Un résultat incertain ou partiel reste visible et n’est jamais rejoué automatiquement.

Si le renommage a réussi mais que le déplacement reste à effectuer, utiliser le parcours de reprise proposé par le reçu après vérification de l’identité. Une nouvelle tentative est préparée et confirmée séparément. Un acquittement motivé conserve le résultat historique ; il ne le transforme pas en succès.

Les mises à jour se préparent dans les Paramètres depuis une source prise en charge. Inspecter le candidat, relire ses différences, le préparer puis confirmer séparément l’installation. La configuration par défaut de l’installation est conservée par la mise à jour ; au retour arrière, ce qui a été fait depuis la mise à jour est conservé et ce qu’elle a apporté repart avec elle, comme l’annonce la confirmation. Un pack qui en apporte une différente est refusé sans remplacement. La qualification des transactions, les procédures de retour et les limites avec 2.0.13 figurent dans [PACKAGING.md](PACKAGING.md#configuration-par-défaut-pendant-la-mise-à-jour-et-le-retour-arrière). Conserver les preuves d’un échec avant toute nouvelle action.
