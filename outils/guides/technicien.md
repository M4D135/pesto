# 1 Mettre un PC au domaine

Quand : le PC devant vous n'est pas dans le domaine et la demande précise de l'y ajouter avec un nom et un emplacement précis.

Avant de commencer :

- Le PC est devant vous et branché au réseau de l'entreprise.
- Vous avez le compte de domaine fourni par l'administrateur.
- Le PC est disponible pour le redémarrage prévu après la jonction.

## Préparer

1. **Ouvrir Pesto.** Lancez Pesto et acceptez la fenêtre Windows de contrôle de compte (UAC).
2. **Se connecter.** Dans « Connexion à Pesto », saisissez le compte dans « Compte Windows » et le « Mot de passe », puis cliquez sur « Se connecter ». La fenêtre reste au premier plan pendant la saisie.
3. **Ouvrir la page.** Cliquez sur « Ajouter au domaine » dans le menu de gauche, ou appuyez sur Ctrl+4.
4. **Contrôler le PC.** Dans « 1. Ce PC », relisez le « Nom actuel », le « Domaine cible » et le « Compte utilisé pour AD ».
5. **Lire le bandeau bleu.** Il indique « Production directe autorisée par la configuration. » ou « Zone de préparation imposée par la configuration. ». Dans le second cas, le site PREPROD est imposé : c'est normal.
6. **Choisir le nom.** Choisissez le « Type de poste », l'« Organisme », le « Site », puis le « Service · 3 caractères ». Pour un service nouveau, tapez le nombre de caractères défini par la convention (trois par défaut).
7. **Relire le nom proposé.** Vérifiez le « Nouveau nom proposé ». Par défaut, il est tiré parmi tous les noms libres du type, du site et du service choisis. « Autre nom » demande une autre proposition.

> [!NOTE] Cochez « Utiliser un compte ordinateur précréé » seulement si l'administrateur vous le demande.


## Vérifier puis ajouter

1. **Vérifier sans rien changer.** Cliquez sur « Vérifier sans ajouter ». Le résultat s'affiche dans « 3. Vérifier et ajouter ». Attendez « Vérifications préalables réussies ».

2. **Lancer l'ajout.** Cliquez sur « Ajouter ce PC au domaine ». Pesto vérifie de nouveau, puis ouvre la fenêtre « Vérifier avant de confirmer ».
3. **Relire et confirmer.** Comparez à la demande « Ce PC », « Nouveau nom », « Domaine » et « Emplacement ». Cliquez sur « Ajouter ce poste au domaine ». Si une ligne est fausse, cliquez sur « Annuler » : rien n'est lancé.
4. **Attendre.** « Ajout au domaine en cours » s'affiche. Pesto prépare le nom local puis demande la jonction. Ne fermez pas Pesto.

## Si le nom vient d'être pris

1. **Lire le message.** « Nom déjà pris : nom suivant proposé » s'affiche : un collègue a pris ce nom. Rien n'a été fait.
2. **Confirmer le nom suivant.** La fenêtre « Vérifier avant de confirmer » se rouvre avec le nom suivant. Relisez-le, puis cliquez sur « Ajouter ce poste au domaine ».

> [!NOTE] Avec un registre partagé, Pesto saute aussi les noms qu'un collègue est en train d'utiliser ; le Journal indique « … déjà réservé par … ; autre nom proposé ». Si vous êtes partis au même moment, Pesto change de nom pendant la vérification, avant de vous demander de confirmer.

> [!ATTENTION] Pesto n'utilise jamais un nom que vous n'avez pas confirmé. Après cinq noms pris de suite, il s'arrête sur « Plusieurs noms déjà pris » : actualisez la page « Noms disponibles » (chapitre 5), puis choisissez un nom.

## Bilan et redémarrage

1. **Lire le bilan.** La fenêtre de bilan s'ouvre. Le titre attendu est « Ajout accepté · redémarrage nécessaire ».

2. **Conserver le compte rendu.** Cliquez sur « Copier le texte », conservez-le avec les informations de l’intervention, puis cliquez sur « Fermer ».
3. **Redémarrer.** Cliquez sur « Redémarrer maintenant », puis confirmez. Pour redémarrer plus tard, cliquez sur « Plus tard ».
4. **Contrôler si besoin.** Après le redémarrage, le chapitre 4 permet de vérifier et de consigner le résultat sur ce même PC. Ce suivi est facultatif pour une opération terminée.

> [!RESULTAT] Après redémarrage et vérification, le PC porte le nouveau nom, il est dans le domaine et au bon emplacement.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| La liste des services reste vide | Attendez quelques secondes. Sinon, tapez le code de service de l’intervention (trois caractères par défaut). |
| « Ce PC appartient déjà à un domaine » | Le PC est déjà joint. Cliquez sur « Ouvrir Renommer / déplacer » et suivez le chapitre 2. |
| « Ajout non lancé » | Lisez les points listés dans « 3. Vérifier et ajouter ». Corrigez, puis cliquez sur « Vérifier sans ajouter ». |
| « Ajout refusé » | Lisez le motif. Si vous ne pouvez pas le corriger, prévenez l'administrateur. |
| « Résultat à vérifier » | Ne relancez pas l'ajout : le nom local peut déjà être préparé pour le prochain démarrage. Prévenez l'administrateur. |
| « Réservation AD conservée » ou « Réservation AD à vérifier » | Cliquez sur « Vérifier l’état ». Relisez le nom proposé ; la jonction reste à confirmer séparément. Si le résultat reste incertain, prévenez l’administrateur et ne supprimez rien. |

## Reconnaître une jonction vérifiée

![Exemple après redémarrage et contrôle facultatif consigné : le nom enregistré est conservé.](fig:jonction-verifiee)

Le PC est membre du domaine et la page conserve le nom de la demande. « Dernière jonction vérifiée précédemment » rappelle une vérification déjà consignée. Pour une nouvelle lecture, cliquez sur « Vérifier dans AD » et suivez le chapitre 4.

# 2 Renommer un poste

Quand : le poste est déjà dans le domaine, il reste sur le même site et seul son nom change.


Avant de commencer :

- L'utilisateur a enregistré son travail.
- Un créneau de redémarrage est convenu.
- Pour un autre poste que celui devant vous : Pesto est ouvert avec le compte de domaine fourni par l'administrateur (lancement Pesto.exe -AskCredential). Ouvert avec votre compte Windows, Pesto refuse ce renommage.

1. **Ouvrir la page.** Cliquez sur « Un seul poste » dans le menu ou dans l'Accueil.
2. **Choisir le poste.** Pour le PC devant vous, son nom est déjà rempli. Pour un autre PC, cochez « Un autre poste du domaine » et tapez son nom. Cliquez sur « Lire le poste ».

3. **Définir le nouveau nom.** Dans « 2. Définir le nouveau nom », choisissez l'« Organisme », le même « Site », le « Service » et le « Type ». « Nouveau nom » propose par défaut un nom tiré parmi tous les noms libres de ces filtres. « Autre nom » demande une autre proposition, sans lancer d’action.
4. **Relire l'aperçu.** Dans « Avant / après », « Opération prévue » doit indiquer « Renommer seulement ». Les cinq parties du nom permettent de repérer ce qui change.
5. **Lancer la vérification.** Si le bouton principal affiche « Compléter le formulaire », cliquez dessus : le curseur va au choix qui manque. Quand il affiche « Vérifier puis renommer », cliquez dessus.
6. **Relire et confirmer.** La fenêtre affiche « RÉEL · Renommer uniquement », le « Nom final » et l'« Emplacement », inchangé. Cliquez sur « Renommer uniquement », ou sur « Annuler » si un détail est faux.

7. **Lire le bilan.** Le bilan confirme le renommage accepté et le redémarrage nécessaire. Cliquez sur « Copier le texte » pour le compte rendu, puis sur « Fermer ».
8. **Redémarrer.** Redémarrez le poste au créneau convenu. Vous pouvez ensuite contrôler le résultat selon le chapitre 4.

> [!NOTE] Pesto ne redémarre pas le poste de lui-même : redémarrez-le vous-même au créneau convenu.

> [!ATTENTION] Ne renommez pas une deuxième fois avant le redémarrage. Tant que le poste n'a pas redémarré, Windows affiche encore l'ancien nom : c'est normal.

> [!RESULTAT] Après redémarrage et vérification, le poste porte le nouveau nom, au même emplacement.

## Choisir précisément et poursuivre

« Choisir un nom exact… » retrouve un nom complet parmi les candidats libres du filtre en cours. Saisissez-le, puis cliquez sur « Choisir ce candidat ». Cette action remplace la proposition ; elle ne réserve pas le nom et ne lance rien.

Après le bilan, « Préparer une autre opération » revient au choix du poste et conserve le reçu précédent. Pour préparer le même poste, attendez son redémarrage si le renommage le nécessite. Une intervention incertaine ou partielle doit toujours être examinée avant reprise.

« Détails » permet de relire le plan, le code et les observations enregistrées de l’opération.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| Le bouton reste sur « Compléter le formulaire » | Lisez le texte sous le bouton : il dit ce qui manque. Cliquez sur le bouton : il vous amène au choix à faire. |
| Une opération en cours, incertaine ou partielle est signalée | Attendez la fin d’une opération active. Sinon, examinez son reçu dans « Interventions et reprises » : le chapitre 4 explique la vérification et l’acquittement avant une nouvelle préparation. |
| « Paramètres enregistrés : fermez puis relancez Pesto » | Fermez Pesto, puis relancez-le. |
| « Ce nom est déjà utilisé dans l'AD » | Choisissez un autre « Nouveau nom ». |
| « Nom déjà pris : nom suivant proposé » | Relisez le nom suivant, puis cliquez sur le bouton portant l’action annoncée. |
| « Plusieurs noms déjà pris » | Actualisez la page « Noms disponibles », puis choisissez un nom (chapitre 5). |
| « Le contrôle a plus de deux minutes » | Relancez la vérification puis confirmez à nouveau. Aucune opération n’est partie avec ce contrôle expiré. |
| Code 96 | Rien n'a été lancé, par exemple parce que le nouveau nom est identique à l'actuel. Corrigez, puis relancez. |

# 3 Changer de site ou déplacer un poste

## Changer de site


Quand : le poste change de site physique. Pesto le renomme, puis le déplace dans l'emplacement du nouveau site.

1. **Lire le poste.** Ouvrez « Un seul poste », choisissez le poste et cliquez sur « Lire le poste ».
2. **Choisir le nouveau site.** Choisissez l'« Organisme », le nouveau « Site », le « Service » et le « Type ».
3. **Relire l'aperçu.** « Opération prévue » doit indiquer « Renommer puis déplacer ».
4. **Lancer la vérification.** Cliquez sur « Vérifier puis renommer ».
5. **Relire et confirmer.** La fenêtre affiche « RÉEL · Renommer puis déplacer », le « Nom final » et l'« Emplacement » du nouveau site. Cliquez sur « Renommer puis déplacer ».

6. **Finir.** Copiez le texte du bilan pour le compte rendu. Redémarrez le poste ; le contrôle décrit au chapitre 4 reste disponible si vous en avez besoin.

> [!RESULTAT] Le poste porte le nouveau nom et se trouve dans l'emplacement du nouveau site.


## Déplacer sans renommer

![Déplacement seul : le nom est conservé et l’emplacement change.](fig:deplacer-seul)

Quand : seul l'emplacement du poste change, pas son nom.

1. **Lire le poste.** Ouvrez « Un seul poste », choisissez le poste et cliquez sur « Lire le poste ».
2. **Choisir la destination.** Choisissez l'« Organisme » et le « Site » de destination.
3. **Régler les options.** Dépliez « Options : déplacement seul et redémarrage ». Décochez « Renommer », cochez « Déplacer ».

4. **Lancer la vérification.** Le bouton principal devient « Vérifier puis déplacer ». Cliquez dessus.
5. **Relire et confirmer.** La fenêtre affiche « RÉEL · Déplacer uniquement » et l'« Emplacement » de destination. Cliquez sur « Déplacer uniquement ».

> [!RESULTAT] Le code 30 confirme le déplacement. Le code 33 indique que le poste était déjà au bon emplacement.

## Finir un déplacement après le code 89

Quand : le bilan affiche « Renommage accepté · déplacement restant à vérifier. » (code 89). Le renommage est fait : ne le relancez pas.

1. **Ouvrir le suivi.** Sur la page « Un seul poste », cliquez sur le bouton principal « Vérifier l'opération ». Si ce bouton n'est pas proposé, ouvrez « Historique », puis « Interventions et reprises », sélectionnez le poste et cliquez sur « Vérifier l’état du poste ». La fenêtre « État du poste » s'ouvre.
2. **Relire l'état.** Cliquez sur « Relire l’état », puis sur « Préparer le déplacement restant ». Confirmez.
3. **Lancer le déplacement.** Le bouton principal affiche « Vérifier puis déplacer seulement ». Cliquez dessus, relisez la fenêtre, puis cliquez sur « Déplacer uniquement ».

> [!RESULTAT] Le poste est dans l'emplacement prévu. L'intervention garde la trace du code 89 : c'est normal.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| La case « Déplacer » est grisée | Le poste est déjà dans cet emplacement. Rien à faire. |
| L'emplacement prévu ne correspond pas au site | Cliquez sur « Annuler » et prévenez l'administrateur. |
| Code 32 | Le déplacement est fait mais un réglage reste à corriger. Ne relancez pas. Prévenez l'administrateur. |
| Code 97 | Ne relancez rien. Prévenez l'administrateur. |

# 4 Vérifier après le redémarrage

Quand : vous souhaitez contrôler le résultat d’un ajout au domaine, d’un renommage ou d’un changement de site, après le redémarrage. Pour une opération terminée, cette vérification et sa consignation sont facultatives : leur absence ne bloque pas une nouvelle opération au lancement suivant.

1. **Rouvrir Pesto.** Pour un ajout au domaine, faites-le sur le PC qui vient d'être ajouté.
2. **Ouvrir la vérification.** Ouvrez « Historique », puis « Interventions et reprises ». Sélectionnez le reçu et cliquez sur « Vérifier l’état du poste » (chapitre 7). Pour une jonction, faites-le sur le PC joint. Pour une ligne de lot, « Vérifier puis reprendre » reste dans « Outils de la file », onglet « Suivi ».
3. **Relire l'état.** Cliquez sur « Relire l’état ».

4. **Comparer à la demande.** Contrôlez le nom, le domaine et l'emplacement affichés. Une valeur absente n'est pas une valeur correcte.
5. **Consigner si souhaité.** Si tout correspond et que vous souhaitez garder la preuve du contrôle, cliquez sur « Consigner la vérification », puis confirmez.

![Exemple de contrôle facultatif après jonction : comparer Windows, AD et le canal sécurisé au plan.](fig:etat-verifie)

> [!RESULTAT] La consignation fait passer le reçu à « Windows / AD vérifié ». Sans consignation, le résultat enregistré reste consultable et n’est pas présenté comme vérifié.

> [!ATTENTION] Une opération active et un nom en attente de redémarrage restent bloquants. Un résultat incertain, partiel ou en protection exige une décision explicite : vérification ou acquittement décrit ci-dessous.

> [!NOTE] Pesto ne vérifie pas l'inscription Entra ni la connexion unique de l'utilisateur. Pour un poste hybride, suivez les contrôles prévus par l'administrateur.

## Acquitter un résultat qui bloque une nouvelle opération

Quand : une ancienne opération reste « Résultat incertain », partielle ou en protection, et vous avez décidé avec le support de préparer une nouvelle opération. L'acquittement conserve son résultat réel ; il ne le valide pas.

1. **Ouvrir le reçu.** Cliquez sur « Vérifier l'opération », ou ouvrez « Historique », puis « Interventions et reprises » et sélectionnez la ligne.
2. **Examiner l'état.** Dans la fiche État, relisez les informations disponibles. « Acquitter… » reste accessible si la lecture échoue. Vous pouvez aussi utiliser « Acquitter… » depuis Interventions.
3. **Donner le motif.** Cliquez sur « Acquitter… », saisissez ce qui a été contrôlé et la décision prise, puis cliquez sur « Acquitter ».
4. **Préparer à nouveau.** Revenez à « Un seul poste » et relisez le poste. Pesto effectue de nouveaux contrôles avant toute commande. Une étape déjà réalisée ne doit pas être demandée une seconde fois.

> [!RESULTAT] Le reçu conserve son code et « Résultat incertain », avec la mention « acquittée », votre compte, la date et le motif. Une nouvelle préparation est possible.

> [!ATTENTION] Une opération active ne peut pas être acquittée. Si une tâche Windows peut encore agir, ouvrez « Détails et outils », puis « Consulter » et « Relire les tâches ». Sa fin doit être confirmée avant l'acquittement. Pour un retrait Entra incertain, faites contrôler l'inscription hybride par le support.

Pour un lot interrompu, ouvrez « Outils de la file », onglet « Suivi », puis « Acquitter le verrou… ». Les lignes concernées sont décochées et gardent leur résultat ; préparez de nouvelles lignes pour continuer.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| Le poste affiche encore l'ancien nom | Il n'a pas redémarré. Redémarrez-le, puis recommencez. |
| « Observation trop ancienne : relisez l'état. » | Cliquez de nouveau sur « Relire l’état ». |
| « Consigner la vérification » reste grisé | Lisez le message affiché sous l'état relu. Si une valeur ne correspond pas, prévenez l'administrateur. |
| Le bouton propose « Préparer le déplacement restant » | Le déplacement n'est pas fait. Suivez le chapitre 3, section code 89. |

# 5 Trouver un nom libre

![Les filtres définissent les candidats libres ; la page affichée ne limite pas le tirage.](fig:noms-filtres)

Quand : vous voulez choisir un nom avant un renommage, ou comprendre pourquoi un nom est refusé.

1. **Ouvrir la page.** Cliquez sur « Noms disponibles » dans le menu, ou appuyez sur Ctrl+2.
2. **Actualiser.** Lisez l’âge des données. « Actualiser le site » relit le site filtré. Pour relire tout l'inventaire, dépliez « Préparation et inventaire », onglet « Inventaire », puis cliquez sur « Actualiser ». Si la lecture est incomplète, attendez une actualisation réussie ou prévenez l’administrateur.
3. **Filtrer.** Réglez « Site », « Service », « Type » et « Statut ». « (tous) » enlève le filtre de site ou de service. « Recherche » trouve un nom qui contient votre texte.
4. **Choisir la numérotation.** Sous la grille, dépliez « Préparation et inventaire », puis l'onglet « Options ». Dans « Plage des numéros », « Depuis 001 » inclut les trous dès 001 ; « Après le dernier numéro » les exclut. Le tirage reste aléatoire s’il est activé.

5. **Choisir un candidat.** Prenez un nom dans « Prochains candidats » ou dans la grille. Utilisez les boutons de page pour parcourir les résultats ; 250 lignes au plus sont affichées à la fois. La page affichée ne limite pas le tirage parmi les noms libres du filtre.
6. **Vérifier dans le domaine.** Cliquez sur « Vérifier dans le domaine ». Pesto confirme si le nom est libre à cet instant.
7. **Utiliser le nom.** Lisez d'abord le poste dans « Un seul poste ». Revenez ici et cliquez sur « Utiliser dans Un poste » : le nom est reporté dans le formulaire, rien n'est lancé.

> [!RESULTAT] Le nom choisi est dans le formulaire de « Un seul poste ». Pesto le revérifiera juste avant d'agir.

> [!ASTUCE] Dans « Préparation et inventaire », onglet « Préparation », « Retenir les 5 propositions » garde des noms de côté pour vous ; « Libérer mon choix » rend le nom retenu sélectionné (filtre « Statut » sur « Réservés »). Ce n'est pas une réservation : un collègue peut prendre le même nom. Double-cliquez sur un nom pour le copier.

## Comprendre les résultats

Dans « Préparation et inventaire », onglet « Inventaire » :

| Commande | À quoi elle sert |
|---|---|
| Origine du nom… | Expliquer pourquoi le nom sélectionné est occupé ou écarté : AD, file locale, choix personnel ou coordination. Une date inconnue reste indiquée comme inconnue. |
| Capacité… | Choisir un seuil de noms libres, puis rechercher et trier les combinaisons site/service/type. 10 signale une plage critique ; 0 une plage épuisée. |
| Anomalies… | Examiner les écarts de nom ou d’emplacement présents dans l’inventaire chargé, sans les corriger automatiquement. |
| Vues et colonnes… | Choisir « Colonnes : Essentiel » ou « Colonnes : Diagnostic », ou conserver une recherche et un tri sous un nom. |

Ces tableaux décrivent l’inventaire daté. Ils ne remplacent pas la vérification du candidat juste avant une opération.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| « Choisissez un site ou un service » | Réduisez le filtre : le périmètre complet contient trop de combinaisons pour être affiché en une fois. |
| La grille est vide | Ouvrez « Préparation et inventaire », onglet « Inventaire », puis cliquez sur « Actualiser ». Remettez « Site » et « Service » sur « (tous) », « Type » sur « Tous ». |
| « Vérifier dans le domaine » trouve le nom pris | Prenez le candidat suivant et vérifiez-le. |
| « Lisez d'abord la machine dans Un poste » | Lisez le poste dans « Un seul poste », puis revenez cliquer sur « Utiliser dans Un poste ». |

# 6 Traiter plusieurs postes

Quand : la demande concerne plusieurs postes déjà dans le domaine, avec les mêmes règles de nom.

Avant de commencer :

- La liste des postes et le créneau de redémarrage sont validés.
- Les postes sont allumés et sur le réseau de l'entreprise.
- Pesto est ouvert avec le compte de domaine fourni par l'administrateur (lancement Pesto.exe -AskCredential). Sinon, « Exécuter la file » refuse le lot.

## Préparer le lot

1. **Ouvrir la préparation.** Ouvrez « Plusieurs postes », puis cliquez sur « Préparer un lot ». Le formulaire unitaire n’a pas besoin d’être rempli.
2. **Choisir la destination.** Sélectionnez le site dans « Destination du lot », puis « Choisir ce site ». Saisissez le code service (trois caractères par défaut) et cliquez sur « Préparer le lot ».
3. **Coller les postes.** Collez les noms des postes, un par ligne. La limite est fixée par l’administrateur, jusqu’à 200 postes.
4. **Choisir les conservations.** Cochez au besoin « Conserver le service source », « Conserver le numéro source » ou « Conserver le type du nom source ».

5. **Construire le plan.** Cliquez sur « Construire le plan ». Relisez les nouveaux noms. Si « Conserver le numéro source » rencontre un conflit, corrigez le choix : Pesto ne remplace pas silencieusement ce numéro.
6. **Ajouter à la file.** Cliquez sur « Ajouter les lignes décochées ». Les lignes arrivent dans la file, décochées.

![Les outils de la file sont regroupés par usage ; le contrôle précède toute exécution.](fig:lot)

« Outils de la file » sépare « File » (modifier ou vider), « Import et export » et « Suivi ». Ouvrir ces onglets ne lance aucune opération sur un poste.

## Importer un tableau Excel ou CSV

1. **Choisir la source.** Dans « Outils de la file », onglet « Import et export », cliquez sur « Importer un tableau… ». Choisissez un CSV UTF-8 ou « Lire le tableau du presse-papiers ». Le tableau doit contenir une ligne de titres.
2. **Associer les colonnes.** Reliez les titres du tableau aux champs proposés. Une action non renseignée reste désactivée.
3. **Corriger.** Dans la grille, modifiez les cellules, puis cliquez sur « Valider les lignes ». La colonne des erreurs indique tous les points à corriger pour chaque ligne.
4. **Ajouter.** Une fois les lignes valides, cliquez sur « Ajouter à la file décochée », puis confirmez « Appliquer la préparation ». Aucune ligne ne sera exécutée avant votre sélection et le contrôle AD.

Pour relire un ancien historique Pesto, utilisez l’import CSV classique, pas cet import de préparation.

## Ajuster les préparations

Dans « Outils de la file », onglet « File », « Modifier plusieurs lignes… » permet de sélectionner avec Ctrl+clic les lignes sans résultat, puis de les corriger et de les valider ensemble. Les lignes modifiées reviennent décochées et doivent être contrôlées de nouveau.

« Annuler la préparation » annule le dernier changement local éligible. Il ne défait jamais un renommage ou un déplacement ; les accords d’exécution ne sont pas restaurés.

« Vues et colonnes… » peut mémoriser filtres et tri ou ouvrir une vue regroupée par site, organisme ou état. Le numéro « Ordre réel » rappelle l’ordre d’exécution inchangé.

Sélectionnez une ligne de la file puis « Détails » pour ouvrir son volet de plan, contrôle et résultat. « Fermer les détails » revient au tableau.

## Lancer avec un poste pilote

1. **Cocher les lignes.** Cochez les postes à traiter, ou cliquez sur « Tout cocher (visible) ». Les lignes cachées par un filtre restent cochées : contrôlez le nombre sur « Exécuter la file ».
2. **Contrôler.** Cliquez sur « Prévisualiser la file », puis sur « Contrôler dans AD ». Relisez les noms et les destinations. Un contrôle est valable deux minutes ; si Pesto l’annonce expiré, contrôlez de nouveau avant d’exécuter.
3. **Lancer le pilote.** Cochez « Faire un poste pilote puis arrêter le lot ». Cliquez sur « Exécuter la file », puis confirmez. Pesto traite le premier poste et s'arrête.
4. **Valider le pilote.** Redémarrez le poste pilote et vérifiez-le (chapitre 4).
5. **Lancer le reste.** Décochez « Faire un poste pilote puis arrêter le lot ». Vérifiez que seuls les postes restants sont cochés, cliquez sur « Exécuter la file », puis confirmez.

> [!ATTENTION] Pour arrêter, cliquez sur « Arrêter après cette action ». Pesto finit le poste en cours, puis s'arrête. Ne fermez jamais Pesto en plein traitement.

## Finir

1. **Lire le bilan.** La fenêtre « Bilan de la file » s'ouvre. Cliquez sur « Copier le texte » pour le compte rendu.
2. **Redémarrer.** Redémarrez chaque poste au créneau convenu.
3. **Contrôler si besoin.** Pour une opération terminée, ouvrez au besoin « Historique », « Interventions et reprises », puis « Vérifier l’état du poste » (chapitre 4). Examinez les lignes incertaines ou partielles avant toute reprise.

> [!RESULTAT] Le bilan et les reçus conservent les résultats de chaque poste. Un renommage accepté reste distinct d’un contrôle après redémarrage consigné.

## Si ça ne marche pas

| Vous voyez | Que faire |
|---|---|
| « Préparer un lot » ne s'ouvre pas | Lisez le motif. Actualisez l’inventaire si aucun site n’est proposé ; terminez toute opération en cours avant de reprendre. |
| Code 69 ou 88 sur une ligne | Le nom est occupé. Actualisez « Noms disponibles » et choisissez un autre nom. |
| Code 89 sur une ligne | Le renommage est fait : ne le relancez pas. Sélectionnez la ligne, ouvrez « Outils de la file », onglet « Suivi », et cliquez sur « Vérifier puis reprendre », puis sur « Préparer le déplacement restant » et confirmez. Cochez la ligne, cliquez sur « Contrôler dans AD », puis sur « Exécuter la file ». |
| Code 97 sur une ligne | Ne relancez pas cette ligne. Prévenez l'administrateur. |

# 7 Retrouver une intervention

Quand : vous devez retrouver une opération, vérifier un poste plus tard ou rédiger le compte rendu de l’intervention.

1. **Ouvrir la liste.** Ouvrez « Historique », puis cliquez sur « Interventions et reprises ». Si l'Accueil affiche des interventions à vérifier, « Ouvrir les interventions » mène au même endroit. La fenêtre « Interventions à suivre » s'ouvre. « Acceptées · suivi facultatif » retrouve les commandes terminées ; « À vérifier avant reprise » isole les situations à examiner.

2. **Trouver la ligne.** Cliquez sur « Actualiser », saisissez le nom ou une partie du nom dans la recherche, puis choisissez le filtre d’état. Les deux filtres se combinent. « Précédent » et « Suivant » parcourent les pages de 200 lignes ; les dates sont celles de votre heure locale.
3. **Voir le détail.** Sélectionnez la ligne. Dépliez « Détails et outils », ouvrez l'onglet « Consulter », puis cliquez sur « Voir le reçu » pour consulter le plan, les étapes et le code de résultat.
4. **Agir.** Suivez le tableau ci-dessous.

| État affiché | Que faire |
|---|---|
| « Commande acceptée · contrôle facultatif » | Redémarrez si nécessaire. Contrôle facultatif au chapitre 4. |
| « Redémarrage puis contrôle » | Lisez le motif : le redémarrage ou la cohérence du reçu reste à vérifier avant reprise. |
| « Déplacement à préparer » ou « Effet partiel » | Suivez le chapitre 3, section code 89. |
| « Résultat incertain » ou « Issue à vérifier » | Le résultat n'est pas connu. Ne relancez rien. Prévenez l'administrateur. |
| « Refus confirmé » | L'opération a été refusée. Lisez le motif dans « Voir le reçu ». |
| « Windows / AD vérifié » | État vérifié ; aucune opération à rejouer. |

![Interventions : sélectionner un poste et lire l’état de son reçu.](fig:interventions)

## Rapprocher les reçus

Dans « Détails et outils », onglet « Consulter », « Chronologie du poste » rassemble les reçus de la vue actuelle qui portent la même identité de poste. Un changement de nom ne suffit pas à créer ou à fusionner une identité.

« Comparer deux reçus » ouvre une sélection : choisissez exactement deux lignes avec Ctrl+clic, puis « Comparer ces deux reçus ». Le tableau montre les différences sans modifier les observations.

Dans l’onglet « Données », « Consulter les archives » ouvre les reçus archivés. « Revenir aux reçus actifs » retrouve le catalogue courant.

## Compte rendu de l’intervention

1. **Préparer le texte.** Sélectionnez la ligne et cliquez sur « Compte rendu ». « Masquer poste et domaine » est coché par défaut. Décochez-le uniquement si le compte rendu doit contenir ces noms et si leur partage est autorisé. Vous pouvez aussi partir de « Copier le texte » de la fenêtre de bilan, puis relire ce texte.
2. **Relire.** Contrôlez les informations présentes, le résultat et la date de vérification. Vérifiez que le niveau de masquage convient au destinataire.
3. **Conserver le compte rendu.** Copiez le texte, conservez-le avec les informations de l’intervention, puis ajoutez ce qui reste à faire.

« Dossier de support… » (onglet « Consulter ») prévisualise le reçu et le diagnostic avant export. Le masquage s’y applique. Relisez avant « Exporter ce dossier ».

> [!ATTENTION] Ne mettez jamais de mot de passe dans un compte rendu. Les outils de protection, d’import et de nettoyage des tâches sont réservés à l’administrateur.

« Exporter le filtre » exporte tous les résultats du filtre, avec les noms des postes non masqués. Relisez le CSV avant partage. Un catalogue incomplet ou un reçu illisible doit être signalé à l’administrateur.

# 8 En cas de problème

Un code de résultat accompagne chaque opération. Vous le lisez dans « Détails » (page « Un seul poste ») ou dans « Voir le reçu » (liste des interventions) et dans la colonne « Code » de la file.

## Codes de résultat

| Code | Ce que ça veut dire | Que faire |
|---|---|---|
| 10 | Ajout au domaine accepté, redémarrage nécessaire | Redémarrez ; contrôle facultatif (chapitre 4). |
| 20 | Renommage accepté, redémarrage nécessaire | Redémarrez ; contrôle facultatif (chapitre 4). |
| 77 | Renommage et déplacement acceptés, redémarrage nécessaire | Redémarrez ; contrôle facultatif (chapitre 4). |
| 30 ou 33 | Déplacement fait, ou poste déjà au bon emplacement | Rien à refaire. |
| 89 | Renommage fait, déplacement restant | Ne renommez pas. Finissez le déplacement (chapitre 3 ; pour un lot, chapitre 6). |
| 69 ou 88 | Nom déjà occupé | Choisissez un autre nom (chapitre 5). |
| 32 | Déplacement fait, un réglage reste à corriger | Ne relancez pas. Prévenez l'administrateur. |
| 96 | Rien n'a été lancé | Lisez le motif, corrigez, puis relancez la vérification. |
| 97 | Résultat incertain | Ne relancez rien. Prévenez l'administrateur. |
| 98 ou 99 | Erreur technique | Ne relancez pas. Prévenez l'administrateur. |

## Messages fréquents

| Vous voyez | Que faire |
|---|---|
| « Nom déjà pris : nom suivant proposé » | Relisez le nouveau nom dans « Vérifier avant de confirmer », puis cliquez sur le bouton portant l’action annoncée. |
| « Plusieurs noms déjà pris » | Ouvrez « Noms disponibles », cliquez sur « Actualiser », puis choisissez un nom. |
| « Résultat à vérifier » | Ne relancez rien. Prévenez l'administrateur. |
| « Ce PC appartient déjà à un domaine » | Cliquez sur « Ouvrir Renommer / déplacer ». |
| « Accès AD non établi. » à l'ouverture | Vérifiez le compte choisi dans l'UAC et le réseau, puis cliquez sur « Réessayer ». Sinon, prévenez l'administrateur. |
| « Le renommage d'un autre PC nécessite un compte AD explicite » | Fermez Pesto. Relancez-le avec Pesto.exe -AskCredential et connectez-vous avec le compte de domaine fourni par l'administrateur. |
| « Pesto est déjà ouvert depuis ce dossier. » | Revenez à la fenêtre Pesto déjà ouverte. |
| Pesto demande sa configuration ou refuse de démarrer | Prévenez l'administrateur. Ne modifiez aucun fichier. |
| Un bouton est grisé | Survolez-le : l'infobulle dit ce qui manque. |

## Prévenir l'administrateur

Donnez-lui ces éléments :

- le texte du bilan, obtenu avec « Copier le texte » ;
- le nom du poste, l'heure et l’identifiant de l’opération ;
- ce que vous avez fait juste avant.

> [!ATTENTION] En attendant sa réponse, ne relancez pas l'opération et ne supprimez rien.

# 9 Repères

## Le nom d'un poste

Par défaut, un nom compte 15 caractères, en cinq parties collées. Pesto le compose à partir de vos choix selon la convention définie par l'administrateur. « Choisir un nom exact… » permet aussi de retrouver un candidat complet dans le filtre courant. Exemple par défaut : P111301VA765001.

| Partie | Exemple | Sens |
|---|---|---|
| Type | P | P portable, S fixe, V virtuel. |
| Département | 111301 | Code du département, six chiffres par défaut. |
| Site | VA | Code du site physique, deux lettres par défaut. |
| Service | 765 | Code du service, trois caractères par défaut. |
| Numéro | 001 | De 001 à 999 par défaut. |

> [!NOTE] La convention de nommage (ordre et largeur des parties) peut être modifiée par l'administrateur. Les largeurs ci-dessus correspondent au format par défaut. Vérifiez toujours le « Nouveau nom proposé » avant de confirmer. Si le bouton affiche des contraintes ou refuse une préparation, consultez le guide administrateur (chapitre 28) pour les scénarios administrés et corrigez le formulaire.

Même code site : Pesto renomme seulement. Code site différent : Pesto renomme, puis déplace le poste.

## La fenêtre de Pesto

- **Menu de gauche** : « Accueil », « Un seul poste », « Plusieurs postes », « Ajouter au domaine », « Noms disponibles », « Historique », « Journal », « Paramètres ». La petite icône tout en bas réduit ou déploie le menu. Hors domaine, « Un seul poste » et « Plusieurs postes » sont grisés : utilisez « Ajouter au domaine ».
- **Accueil** : « Ce poste » indique le nom et le domaine lus dans Windows. « Actualiser » relit Windows et les reçus locaux ; il ne consulte pas l'AD. « Dernières interventions enregistrées » montre les trois derniers reçus ; sélectionnez une ligne puis « Ouvrir le reçu » pour la lire. « Interventions à vérifier » signale les reçus à examiner, pas les seuls contrôles facultatifs d’opérations terminées. Les raccourcis ouvrent les parcours ; « Historique des lots » donne accès au suivi complet.
- **En-tête** : le poste, le domaine, le compte, le contrôleur AD choisi et le mode (réel, consultation, simulation ou démonstration). Un bandeau explique un blocage commun. « Étapes de l’opération » montre les étapes réellement parcourues, sans estimation de pourcentage. En haut à droite : « Actions · Ctrl+K », « Audit », l'icône lune (soleil en thème sombre) pour le thème et « ? » pour l'aide.
- **Outils et navigation** : « Actions · Ctrl+K » ouvre les rubriques « Postes », « Préparer », « Analyser » et « Affichage ». La recherche porte sur tous les outils, quelle que soit la rubrique ouverte. Elle accepte aussi des mots comme « reçu », « config » ou « libres ».
- **Aide** : cliquez sur « ? », appuyez sur F1, ou survolez un champ ou un bouton, même grisé. Les boutons principaux restent au bas des pages de jonction et de poste ; faites défiler les champs au-dessus si l’écran est petit.

> [!ATTENTION] Si le domaine ou le compte de l'en-tête n'est pas le bon, arrêtez-vous et prévenez l'administrateur.

La liste des services indique une lecture en cours, partielle ou indisponible et l’âge des données. Vous pouvez saisir un code service sans attendre l’inventaire complet ; le nom sera revérifié avant l’action.

**Zoom.** En bas à droite, « − » et « + » règlent la taille d'affichage de 80 à 150 %, par pas de 10. Cliquez sur le pourcentage pour revenir à 100 %. Cette barre reste visible pendant le défilement. Sur une petite fenêtre, faites défiler le contenu pour atteindre tous les champs et boutons. Le réglage est mémorisé immédiatement pour votre utilisateur et retrouvé à la prochaine ouverture.

![Zoom à 150 % : les commandes fixes restent en bas à droite.](fig:zoom-interface)

Le journal affiche la date et l’heure complètes. Choisissez un niveau (informations, avertissements ou erreurs), puis utilisez la recherche pour préciser les résultats. « Copier les erreurs » copie les erreurs conservées dans la session ; le fichier d’audit reste accessible par « Audit ».

## Raccourcis clavier

| Raccourci | Effet |
|---|---|
| Ctrl+1 | Ouvrir le formulaire, dans le dernier mode choisi (« Un seul poste » ou « Plusieurs postes ») |
| Ctrl+2 | Ouvrir « Noms disponibles » |
| Ctrl+3 | Ouvrir « Journal » |
| Ctrl+4 | Ouvrir « Ajouter au domaine » |
| Ctrl+K | Ouvrir la palette Actions |
| Ctrl+F | Rechercher dans la page active ou placer le curseur dans son champ principal |
| F5 | Actualiser la page active, selon les commandes disponibles |
| F1 | Aide sur le champ actif |
| F6 / Maj+F6 | Passer à la grande zone suivante / précédente sans sortir d’un panneau ouvert |
| Échap | Fermer la palette ou le panneau ouvert |

## Réutiliser une préparation

Dans « Favoris de préparation », donnez un nom aux choix organisme/site/service/type puis cliquez sur « Mémoriser ». Choisissez un favori et « Rappeler » pour remplir ces champs. « Proposer le type… » peut lire le matériel du PC local et vous suggérer un type ; la proposition reste modifiable.

Pour conserver également la cible et le nom proposé, ouvrez Ctrl+K, rubrique « Préparer », puis « Enregistrer le brouillon ». Donnez-lui un nom. « Restaurer le brouillon » permet de le choisir, de le prévisualiser puis de relire le poste. Aucun ancien accord, contrôle AD ou redémarrage n’est réutilisé.

« Partager des modèles… » montre les favoris et brouillons avant export. « Importer des modèles… » indique leur compatibilité avec le domaine et la configuration ; seuls les modèles compatibles sont proposés, avec confirmation des remplacements.

Dans « Paramètres », onglet « Apparence », « Son en fin de lot lorsque Pesto est en arrière-plan » active une notification facultative. Le résultat demeure dans le bilan et les reçus.

## Avant une intervention

- Notez l’identifiant de l’opération, le nom actuel du poste, le site, le service et le type demandés.
- Pour un renommage, prévenez l'utilisateur afin qu'il enregistre son travail.
- Convenez d'un créneau de redémarrage.
- Vérifiez que le poste est branché au réseau de l'entreprise.
- Pour un PC hors domaine, ayez le compte de domaine fourni par l'administrateur.

# 10 Mots à connaître

| Terme | En clair |
|---|---|
| AD (Active Directory) | Annuaire qui gère les comptes et les ordinateurs du domaine. |
| Domaine | Ensemble des postes et des comptes gérés par le même AD. |
| Ajout au domaine | Inscription d'un PC dans le domaine, avec son nom et son emplacement. |
| OU, emplacement | Dossier de l'AD où le poste est rangé, selon son site. |
| Site | Lieu physique du poste, codé sur deux lettres par défaut dans son nom. |
| Service | Code de trois lettres ou chiffres par défaut dans le nom du poste. |
| Inventaire | Liste des postes du domaine lue par Pesto, mise à jour avec « Actualiser ». |
| Nom retenu | Nom gardé de côté pour vous, sans réservation. |
| Intervention | Trace d'une opération dans Pesto, de la demande à la vérification. |
| Bilan | Fenêtre qui résume le résultat d'une opération ou d'un lot. |
| Code de résultat | Numéro qui dit comment l'opération s'est terminée (10, 20, 89…). |
| Lot, file | Postes préparés ensemble, puis traités l'un après l'autre. |
| Poste pilote | Premier poste d'un lot, traité seul pour valider le reste. |
| UAC | Fenêtre Windows qui demande votre accord avant d'ouvrir Pesto. |
| Entra, poste hybride | Entra est l'annuaire en ligne de Microsoft. Un poste hybride est inscrit à la fois dans l'AD et dans Entra. |
