# Pesto : pistes d'amélioration de l'interface et du moteur

> **État au 8 octobre 2026, 19 h 30.** Déjà traité ce soir dans la version livrée (exe `df41450b`) :
> - n° 1 : l'inventaire complet n'est plus lancé au choix d'un site ni à l'ouverture de la jonction (recherche ciblée du site à la place) ;
> - n° 7, en partie : enregistrer sans changement ne demande plus de relance (EntraPolicy, ClearProtectionOnMove et POLICY comparés sur leurs valeurs appliquées) ; le drapeau n'est pas encore levé quand on revient à l'état chargé ;
> - n° 9, en partie : « Vérifier la jonction » directement depuis « Un poste », et reprise après redémarrage optionnelle (Pesto se relance et ouvre la vérification) ;
> - « Déjà en cours » : registre partagé, réservation AD à la jonction, numéro au hasard, onglets Paramètres « Noms et coordination » et « Politique ».
>
> Sources : six relectures du code par des agents (173 suggestions après fusion, 2 « corrections » rejetées à la contre-vérification), puis idées du Spark (fin du document, non vérifiées dans le code). Grok n'a rien produit : son crédit est épuisé.


*Branche cloud/points-suite · relecture du 8 octobre 2026 · 173 suggestions*

## Comment lire cette liste

Cette liste réunit six relectures du code faites en lecture seule : interface, design, moteur, fonctions, configuration et qualité. Les doublons sont fusionnés.

Chaque suggestion indique trois choses :
- **Effort** : S = quelques heures, M = un à quelques jours, L = gros chantier.
- **Priorité** : P1 = répond à vos retours ou corrige un défaut prouvé, P2 = nette amélioration, P3 = confort ou nettoyage.
- **Risque** : il n'est indiqué que lorsqu'il est moyen ou élevé.

Deux mentions reviennent :
- *(correction)* signale un défaut constaté dans le code.
- *(décision à prendre)* touche une règle de sûreté que vous seul pouvez trancher.

Les preuves renvoient à `DEV/wad` sauf mention contraire. Les numéros de ligne sont ceux de la version commitée et peuvent bouger avec la réservation de noms en cours.

Aucune suggestion n'assouplit les règles métier :
- la jonction et le renommage unitaire restent sans file ;
- aucun redémarrage ni retrait Entra implicite ;
- un résultat incertain n'est jamais un succès ;
- aucun verrou effacé pour débloquer ;
- Windows PowerShell 5.1 seulement ;
- aucun service permanent.

Les 15 premières sont les plus rentables. Elles ne sont pas répétées dans les catégories, qui y renvoient.

## Les 15 premières à faire

1. **Ne plus lancer l'inventaire complet en dehors de la page Noms** *(correction)* — Choisir un site (dans Un poste ou Ajouter au domaine) ou passer en Plusieurs postes déclenche un scan de toute l'OU racine dès que l'inventaire n'est pas chargé, donc après chaque intervention. Pendant ce temps, « Vérifier puis renommer » répond « Patientez » sans rien afficher. La recherche ciblée du site fournit déjà les services et les numéros pris : réserver l'inventaire complet à la page Noms, aux lots et au bouton Actualiser. À défaut, afficher « Inventaire en cours (x s) » sous le bouton. C'est la cause directe des attentes de 30 s et plus. · Effort M · Priorité P1 · Risque moyen · (Pesto-Core.ps1:3036, 4495 ; Pesto-Join.ps1:406-413 ; Pesto-SuiteUI.ps1:14 ; Pesto-Direct.ps1:200)
2. **Alléger l'inventaire complet** — Quand OUScanNoms est sous ROOT, le parc est lu deux fois : filtrer en mémoire à la place de la seconde lecture. Lire seulement le nom, le DN et le GUID (Get-ADObject), publier la progression tous les 250 à 500 postes au lieu d'un objet par poste, fixer la taille de page à 1 000 et mesurer le gain sous 5.1. · Effort M · Priorité P1 · (Pesto-Directory.ps1:474-491)
3. **Importer le module AD sans monter le lecteur `AD:`** — Chaque lecture ouvre un runspace neuf et réimporte ActiveDirectory. Cet import contacte un contrôleur pour monter le lecteur `AD:`. Poser `$env:ADPS_LoadDefaultDrive='0'` avant l'import, après avoir vérifié qu'aucun code n'utilise de chemin `AD:\`, puis mesurer l'import séparément. Le gain est immédiat sur chaque liste, chaque contrôle et chaque lecture de poste. · Effort S · Priorité P1 · (Pesto-Safety.ps1:31 ; Pesto-Async.ps1:199-203)
4. **Après une opération, compléter la liste des noms au lieu de tout relire** — Tout résultat autre qu'un refus invalide l'inventaire, et la fin d'un lot relance un scan complet : les boutons restent grisés 30 s entre deux postes. Ajouter le nouveau nom aux noms pris, relire seulement la série du site concerné et garder la relecture complète à la demande. · Effort M · Priorité P1 · Risque moyen · (Pesto-Core.ps1:465, 3575 ; Pesto-Join.ps1:616 ; Pesto-Direct.ps1:405)
5. **Une raison lisible pour chaque bouton grisé, calculée à un seul endroit** — Les conditions de blocage sont recopiées dans quatre fonctions qui ne disent pas la même chose :
   - « Exécuter la file » grisé affiche « Afficher la confirmation puis exécuter N ligne(s) » ;
   - « Ajouter au domaine » dit « Attendez la fin du traitement » alors que rien ne tourne ;
   - « Préparer un lot » et « Contrôler dans AD » n'ont qu'une infobulle fixe.

   Une seule fonction (cause, action qui débloque, ordre de priorité fixe) alimenterait l'état du bouton, l'infobulle, le texte d'accessibilité et une ligne sous le bouton. Le modèle existe déjà pour « Retirer de la file ». · Effort M · Priorité P1 · (Pesto-Core.ps1:2528 contre 4437-4444, 864-868, 3318-3337 ; Pesto-Join.ps1:348, 376 ; Pesto-UXFlow.ps1:27-40)
6. **Bandeau de blocage sur toutes les pages, avec le bouton qui débloque** — La cause du blocage (jonction à vérifier, verrou, opération unitaire à vérifier, relance requise) n'apparaît qu'en gris, en 12 px, sous les Favoris et sur la seule page Un poste. Afficher sous l'en-tête un bandeau ambre avec un seul bouton (« Vérifier la jonction », « Ouvrir les interventions », « Fermer Pesto »). Placer aussi la raison juste sous le bouton principal, sur la même ligne que « Vérifier seulement », et descendre les Favoris en bas de la carte. · Effort M · Priorité P1 · (Pesto-UXFlow.ps1:27-40 ; Pesto-SuiteUI.ps1:118-132 ; Pesto-Shell.xaml:155-161)
7. **Ne plus exiger « relancez Pesto » à tort après Paramètres** *(correction)* — La signature de configuration est calculée sur le texte JSON brut. Réenregistrer sans rien changer réécrit les booléens en texte et ajoute les clés absentes : Pesto exige alors une relance et grise tout. Ce drapeau n'est jamais levé, même quand la configuration revient à l'état chargé. Il faut calculer la signature sur les valeurs effectives et lever le drapeau quand les signatures redeviennent égales. Il faut aussi proposer « Annuler ce changement » et tester l'aller-retour écran → fichier. · Effort M · Priorité P1 · (Pesto-Configuration.ps1:22-38, 281-329, 369-386 ; Pesto-Core.ps1:4169)
8. **Poste distant qui ne répond pas au ping : sortir de l'impasse** *(correction)* — Quand le ping échoue (filtrage par défaut du pare-feu Windows), « Renommer » est décoché et grisé, la liste Service reste vide et aucun message n'apparaît. « Compléter le formulaire » met alors le focus sur un champ grisé. Il faut afficher la cause sous le nom et traiter le ping comme indicatif, comme le promet l'infobulle : le contrôle RPC tranche au moment de vérifier. Le parcours ne doit jamais renvoyer vers un champ grisé. · Effort M · Priorité P1 · Risque moyen · (Pesto-Core.ps1:3026-3029 ; Pesto-Shell.xaml:153 ; Pesto-UXFlow.ps1:45-46, 68-71)
9. **Après la jonction : vérifier et consigner en deux clics au premier lancement** — Au redémarrage, Pesto sait déjà que le poste est prêt à être vérifié. Mais le message reste sur la page de jonction, masquée une fois le PC dans le domaine. Il faut alors passer par Interventions puis État du poste, et tout autre renommage est bloqué en attendant. Afficher dès l'arrivée « Ce PC a été ajouté le … sous le nom … : vérifier maintenant ». Ce bandeau lit l'objet AD et propose « Consigner la vérification », avec confirmation explicite et observation positive obligatoire. Si le reçu central manque, proposer « Importer et vérifier ». · Effort M · Priorité P1 · Risque moyen · (Pesto-Join.ps1:116-118, 286-300, 771-781 ; Pesto-Core.ps1:5246 ; Pesto-UXFlow.ps1:30-38)
10. **Vérifier la jonction sur le contrôleur qui l'a écrite** — La vérification et le test du canal sécurisé interrogent le contrôleur de la session. Après le redémarrage, Windows peut en avoir choisi un autre, pas encore répliqué, et la jonction reste « non confirmée ». Il faut d'abord lire sur le contrôleur noté dans le reçu, puis sur celui de la session, et dire lequel a répondu (« réplication en cours » en cas d'écart). Le canal doit être testé sans forcer de serveur. C'est une lecture seule : le contrôleur de travail ne change pas (décision du 08/10). · Effort S · Priorité P1 · (Pesto-Inspection.ps1:24-27, 41-42, 264 ; Pesto-JoinRecovery.ps1:99-105)
11. **Un refus net de Windows ne doit plus finir en « incertain » (97)** — Sous PowerShell 5.1, Add-Computer et Rename-Computer signalent un mot de passe faux, un droit manquant ou un nom existant sans code Win32 lisible. Pesto conclut alors 97, et le poste reste en « Vérification requise ». Il faut classer en refus (11 ou 21) seulement si trois conditions sont réunies : l'erreur est un refus identifié, la relecture locale montre le poste inchangé et le compte est absent de l'AD. Sinon, garder 97. À confirmer d'abord sur la VM (voir n° 154). · Effort M · Priorité P1 · Risque moyen · (Pesto-Operations.ps1:1138-1143, 1196-1212 ; Pesto-Safety.ps1:4-14)
12. **File : un échec avant toute commande ne doit pas poser le verrou global** *(correction)* — Toute exception du worker de file devient un 98, qui bloque toutes les écritures. C'est le cas même si l'exception survient avant la première commande (précontrôle refusé, module AD non chargé). Le parcours unitaire distingue déjà ce cas et rend 96 : il faut appliquer la même règle à la file. · Effort S · Priorité P1 · Risque moyen · (Pesto-Core.ps1:442-446, 485-487, 3481 ; Pesto-Direct.ps1:395-402)
13. **Messages lisibles : accents et vrais noms de boutons et de pages** *(correction)* — Plusieurs défauts de texte :
    - une vingtaine de messages visibles sont sans accents (« File non lancee », « Le recu a change… », « Redemarrage reel non autorise ») ;
    - d'autres citent des libellés qui n'existent pas (« Cochez Traiter un poste distant », « Utilisez Reprendre déplacement », « Traitement par lot ») ;
    - la page Un poste apparaît sous quatre autres noms.

    Il faut corriger les chaînes et les tests qui les comparent, puis créer une table unique des noms de pages et de boutons, réutilisée par les messages. · Effort S · Priorité P1 · (Pesto-Join.ps1:206, 376, 687, 707-708 ; Pesto-Operations.ps1:107-137, 1112, 1171 ; Pesto-Core.ps1:290, 427, 1095, 3656, 4430 ; Pesto-SuiteUI.ps1:87, 109, 146)
14. **Compte rendu et bilan prêts à coller dans le ticket** *(correction)* — « Compte rendu » remplace toujours le poste, le nom prévu et le domaine par « [MASQUÉ] », et ne donne ni l'OU ni la date de vérification. Le bilan d'une jonction réussie ignore le message qui contient l'ancien nom, le nouveau nom et l'OU. Il faut produire par défaut un texte non masqué, le masquage devenant une case à cocher comme dans Diagnostic. Ce texte doit donner le nom avant et après, l'OU lisible, la date locale, le contrôleur, le vérificateur et la suite à donner. · Effort S · Priorité P1 · (Pesto-Interventions.ps1:57 ; Pesto-Workspace.ps1:139-156 ; Pesto-Join.ps1:325-330, 619)
15. **Accueil : ce qui attend une action, en un clic** — La carte « Interventions à vérifier » n'affiche aucun nombre, les compteurs portent sur le cache et la file, et « À la demande » s'affiche en 30 points. L'accueil doit afficher :
    - le nombre de reçus non résolus (redémarrage, déplacement à finir, résultat incertain) ;
    - le plus ancien d'entre eux, avec un bouton « Vérifier » ;
    - l'âge de l'inventaire, avec un bouton « Charger » ;
    - des tuiles cliquables ;
    - hors domaine, un premier bouton « Ajouter ce PC au domaine ».

    · Effort M · Priorité P1 · (Pesto-Shell.xaml:556-557 ; Pesto-Core.ps1:4408, 4449 ; Pesto-SuiteUI.ps1:144-146)

## Interface

*Voir aussi dans les 15 premières : n° 1, 5, 6, 8, 9, 13, 14, 15.*

16. **Fiche « État du poste » : verdict en tête, tableau Attendu / Observé** — Le résultat s'affiche dans un bloc à police fixe : colonnes tronquées, True/False, en-têtes sans accents, verdict en gris discret. Les messages regroupent en outre plusieurs conditions sans dire laquelle échoue. Il faut une grille Contrôle / Attendu / Observé / État, avec ✓ ou ✗ accompagné du texte, et un verdict en grand. Le rapport brut passe dans un volet « Détails techniques ». · Effort M · Priorité P1 · (Pesto-Inspection.ps1:187, 224-225, 292 ; Pesto-Contracts.ps1:134-154)
17. **Interventions : l'action utile selon la ligne, outils administrateur à part** — L'écran aligne onze boutons de même poids, affiche des valeurs brutes (« Skipped », « NotRequested ») et des dates UTC au format ISO. Il faut traduire ces valeurs à l'affichage seulement (les reçus restent inchangés), dater en heure locale et colorer l'état. Le bouton utile doit être mis en avant (Vérifier l'état, Finir le déplacement, Compte rendu), et le reste rangé sous « Outils administrateur ». Le filtre par défaut doit être « Non résolues », avec une recherche par poste. · Effort M · Priorité P1 · (Pesto-Interventions.ps1:12, 15, 25 ; Pesto-Safety.ps1:322 ; outils/guides/technicien.md:300)
18. **Une seule fonction « ce qui manque au formulaire »** *(correction)* — Le bouton principal et le texte d'aide calculent les manques chacun de leur côté, et ils divergent déjà. Deux exemples : une OU cible invalide en déplacement seul, ou un nom refusé par la règle de nommage. Dans ces cas, le bouton reste grisé, l'aide reste générique, et « Compléter le formulaire » met le focus sur le nom même si le renommage est décoché. Une seule fonction doit décider à la fois de l'état du bouton, de l'aide et du focus. · Effort M · Priorité P1 · (Pesto-Core.ps1:3147-3172 ; Pesto-UXFlow.ps1:45, 51, 68)
19. **Poste distant ouvert avec le compte Windows : prévenir tout de suite** — Le renommage d'un autre poste exige un compte AD explicite, mais le refus n'arrive qu'au clic sur Vérifier ou à l'exécution de la file. Dès que « Un autre poste du domaine » est coché dans une session Windows, il faut afficher un bandeau avec « Relancer Pesto avec le compte AD ». Ce bouton ferme Pesto proprement s'il n'y a rien en cours et relance par le chemin -AskCredential existant. C'est un choix explicite du technicien. · Effort M · Priorité P1 · Risque moyen · (Pesto-Direct.ps1:179 ; Pesto-Core.ps1:3659 ; Pesto-Operations.ps1:1174 ; outils/guides/technicien.md:93-95, 224)
20. **Palette Ctrl+K : ouvrir les pages par la navigation normale** *(correction)* — Les commandes join, names et single changent l'onglet directement, sans charger la page :
    - Ajouter au domaine s'ouvre sans lire les services du site ;
    - Noms s'ouvre sans inventaire ;
    - « Un poste » hors domaine affiche Renommer au lieu de la jonction.

    Toute navigation doit passer par Set-PestoUxPage, sans index d'onglet en dur. · Effort S · Priorité P1 · (Pesto-Workspace.ps1:189-194 ; Pesto-Core.ps1:4490-4499, 4531-4533)
21. **Page Noms disponibles réorganisée** — L'en-tête déborde : « Portable : (filtrer site + service) », répété trois fois, chevauche le compteur. Le pied aligne neuf commandes de natures différentes. La page doit garder une ligne de filtres, la grille paginée et un panneau « Choisir un nom » (candidats, Vérifier dans le domaine, Utiliser dans Un poste, Retenir, Libérer). Tant que rien n'est choisi, une seule phrase suffit : « Choisissez un site et un service ». · Effort M · Priorité P1 · (Pesto-Shell.xaml:278-290, 347-353 ; Pesto-Core.ps1:4137)
22. **Préparer un lot sans détour** *(correction)* — « Préparer un lot » pose deux conditions cachées :
    - il faut d'abord lire un poste quelconque, car Organisme n'est activé qu'après ;
    - « Un autre poste du domaine » doit être coché, or cette case est grisée dès que la file contient une ligne. Une file importée ou créée en local bloque donc la préparation sans explication.

    Il faut mettre l'organisme, le site, le service et le type dans la fenêtre de lot, et la rendre accessible dès le mode Plusieurs postes. · Effort M · Priorité P2 · (Pesto-Core.ps1:1095-1098, 2532, 2574 ; Pesto-Shell.xaml:141, 149)
23. **Ne plus effacer l'organisme, le site et le service à chaque frappe dans le nom** — Chaque caractère tapé efface les choix : corriger une faute oblige à tout ressaisir. Il faut garder les choix en brouillon, à revalider après la lecture, et afficher l'aide « appuyez sur Entrée », aujourd'hui écrite dans un libellé masqué. Il faut aussi retirer le minuteur de lecture automatique, qui n'est jamais démarré. · Effort M · Priorité P2 · Risque moyen · (Pesto-Core.ps1:4410, 4581-4601, 4642-4644, 4732)
24. **Étapes internes traduites et heures locales partout** — Le démarrage affiche « Dernière opération unitaire : PendingRestart ». Détails et Interventions montrent « Début UTC », « Rename: Confirmed » et des dates ISO. Il faut réutiliser partout la table de libellés et la conversion en heure locale qui existent déjà pour l'Historique. · Effort S · Priorité P2 · (Pesto-Direct.ps1:430, 439-449 ; Pesto-Interventions.ps1:12, 38 ; Pesto-Core.ps1:4545)
25. **Un verbe pour chaque sens : Contrôler avant, Vérifier après, Relire pour actualiser** — Plus de dix boutons commencent par « Vérifier », avec des sens différents ; la seule page de jonction en compte trois. Il faut fixer ce glossaire, renommer les boutons et mettre à jour les guides en même temps. · Effort M · Priorité P2 · (Pesto-Shell.xaml:155, 160, 194, 253, 254, 353 ; Pesto-Join.xaml:12, 13, 84)
26. **Catalogue unique des messages (cause, explication, action)** — Une même cause est rédigée différemment selon l'endroit : le message de relance après enregistrement existe en quatre versions. Le filet d'exception global affiche en plus un type .NET brut. Il faut centraliser les messages par identifiant dans un fichier testé, réutilisé par le bandeau, les raisons sous les boutons et les infobulles, avec le détail technique repliable. · Effort M · Priorité P2 · (Pesto-UXFlow.ps1:34 ; Pesto-SuiteUI.ps1:123 ; Pesto-Core.ps1:4374, 4442, 5162-5174 ; Pesto-Join.ps1:376)
27. **Confirmation claire : avant → après, mode très visible, action nommée sur le bouton** — La confirmation est un texte brut, avec un bouton « Confirmer » générique et des chemins d'OU bruts. Il faut une carte qui contient :
    - un bandeau RÉEL (rouge) ou SIMULATION (ambre) ;
    - un tableau Nom / Emplacement / Site, avant → après ;
    - les lectures sous forme de liste cochée ;
    - un bouton qui nomme l'action (« Renommer PC-A en P111301… »).

    Annuler reste le choix par défaut, et « Copier le texte » est conservé. · Effort M · Priorité P2 · (Pesto-Core.ps1:1276-1295 ; Pesto-Workspace.ps1:41-80 ; Pesto-Direct.ps1:307-311 ; Pesto-Join.ps1:570)
28. **Lot : confirmation et bilan poste par poste** — La confirmation et le bilan de file ne donnent que des compteurs. La confirmation doit lister les postes (ancien → nouveau nom, site), les 50 premiers puis « et N autres ». Le bilan doit présenter un tableau par poste (code, état, suite à donner), avec un filtre « à vérifier » et un bouton « Copier pour le ticket ». · Effort M · Priorité P2 · (Pesto-Core.ps1:3558-3575, 3590-3591, 3691)
29. **Code 89 ou résultat incertain : l'action directement sur la ligne de la file** — Finir un déplacement après un code 89 demande sept étapes, en passant par « Plus d'outils… ». Il faut proposer « Finir le déplacement » quand le code vaut 89 et « Vérifier l'état » quand le statut est INCERTAIN, dans le menu contextuel ou la cellule Résultat. Le moteur garde exactement les mêmes contrôles. · Effort M · Priorité P2 · (outils/guides/technicien.md:257 ; Pesto-Shell.xaml:253)
30. **Observation trop ancienne : relire au lieu de refuser** — Au-delà de 120 s, « Consigner la vérification » répond seulement « relisez l'état ». Il faut relancer la lecture au clic, présenter le nouveau résultat avant la confirmation et afficher la durée de validité restante. La règle de fraîcheur ne change pas. · Effort S · Priorité P2 · (Pesto-Inspection.ps1:314 ; Pesto-JoinRecovery.ps1:107-111)
31. **Canal sécurisé pas encore prêt : proposer « Relire dans 30 s »** — Juste après l'ouverture de session, le service Netlogon peut ne pas être prêt, et le canal n'est lu qu'une fois. Il faut proposer une relecture différée, en lecture seule, avec une explication, au lieu du seul message « Aucune réparation automatique ». · Effort S · Priorité P2 · (Pesto-JoinRecovery.ps1:105-106 ; Pesto-Inspection.ps1:24-31)
32. **Étapes 1 à 4 : suivre aussi le parcours Un poste** — Les étapes ne suivent que la file : en mode unitaire, l'étape 4 ne s'allume jamais et l'étape 3 invite à « Ajouter ce brouillon à la file ». Seule l'étape courante est colorée. Il faut suivre le parcours unitaire, marquer d'un ✓ les étapes faites et écrire l'étape en clair (« Étape 2 sur 4 »). · Effort M · Priorité P2 · (Pesto-Core.ps1:4334-4385, 4415-4417, 4451-4455)
33. **Progression d'une opération en liste d'étapes** — L'activité tient sur une ligne : `Étape | N s | détail | helper PID 1234`. Il faut afficher la liste prévue (Contrôle, Entra, Renommage, Attente AD, Déplacement, Résultat), avec pour chacune fait, en cours ou à venir, et sa durée. Le PID et le thread partent au journal. · Effort M · Priorité P2 · (Pesto-Async.ps1:67-76)
34. **Services du site : chargement et échec visibles** — La lecture des services n'affiche rien. Un échec (droits, délai, contrôleur) ne laisse qu'un avertissement au journal, et la liste reste vide sans explication. Il faut afficher « Lecture des services du site… » près du champ, et en cas d'échec « Lecture du site impossible : cause » avec un bouton « Réessayer », dans Un poste comme dans Ajouter au domaine. · Effort S · Priorité P2 · (Pesto-Directory.ps1:283-316)
35. **En-tête : contrôleur utilisé, âge de l'inventaire, mode permanent** — La pastille Domaine ne dit pas quel contrôleur est interrogé, et le mode RÉEL n'apparaît qu'au pied de la file. Il faut ajouter le contrôleur et l'heure de l'inventaire à la pastille Domaine, une pastille de mode permanente (RÉEL, SIMULATION ou DÉMO), et le contrôleur dans la confirmation. Cela aide à comprendre un « nom pris » dû à la réplication. · Effort S · Priorité P2 · (Pesto-Core.ps1:5014, 5034-5035 ; Pesto-Directory.ps1:140-141)
36. **Ctrl+F reste sur la page active** *(correction)* — Depuis l'Accueil, l'Historique, les Paramètres ou la jonction, Ctrl+F bascule en Plusieurs postes et peut lancer l'inventaire complet. Le panneau d'aide annonce pourtant « recherche dans la page active ». Il faut limiter Ctrl+F aux pages qui ont une recherche (ou à la recherche de poste, n° 112) et mettre la page Aide en accord. · Effort S · Priorité P2 · (Pesto-Core.ps1:4810-4818 ; Pesto-SuiteUI.ps1:89 ; Pesto-Shell.xaml:561)
37. **Un poste / Plusieurs postes : ne pas ignorer le clic sans rien dire** *(correction)* — Pendant une lecture ou une opération, le changement de mode s'arrête sans message, et le technicien croit l'application figée. Il faut griser ces entrées avec « Traitement en cours… », ou afficher la raison dans le bandeau (n° 6). · Effort S · Priorité P2 · (Pesto-SuiteUI.ps1:6)
38. **Fenêtre de démarrage propre** *(correction)* — Plusieurs défauts :
    - l'infobulle générée est vide (« Contrôle . Suivez les indications… ») ;
    - le nom interne TxtStartupDetail s'affiche ;
    - le titre reste l'ancien « Gestion des Postes » ;
    - la fenêtre reste toujours au premier plan pendant un démarrage qui peut dépasser une minute.

    Il faut des textes utiles, la marque Pesto, et retirer le premier plan forcé une fois la fenêtre affichée. · Effort S · Priorité P2 · (Pesto-Core.ps1:2316-2318, 2327, 2329)
39. **Ping : ne plus le signaler par la seule couleur** — La réponse au ping n'est rendue que par le fond vert ou rouge du champ nom, et cette information disparaît en contraste élevé. Il faut ajouter un texte (« Répond au ping » / « Ne répond pas, indicatif ») et un état lisible par le lecteur d'écran. · Effort S · Priorité P2 · (Pesto-Core.ps1:2593-2599 ; Pesto-Appearance.ps1:86)
40. **Noms lus par le lecteur d'écran identiques aux libellés visibles** *(correction)* — Plusieurs noms annoncés ne correspondent pas à l'écran :
    - « Un poste » est annoncé « Renommer » ;
    - « Vérifier les résultats » est annoncé « Lever le verrou » ;
    - les onglets Domaine et Options avancées sont annoncés « page Général » et « page Debug » ;
    - l'assistant annonce une phrase d'aide entière comme nom de champ.

    Le nom annoncé doit contenir le libellé visible (règle WCAG 2.5.3) et l'explication passer dans l'aide. Les tests d'accessibilité sont à mettre à jour en même temps. · Effort S · Priorité P2 · (Pesto-Shell.xaml:114, 253, 254, 370, 380, 495, 567 ; Pesto-Join.xaml:13 ; Pesto-Configuration.ps1:463)
41. **Panneaux et fiches annoncés au lecteur d'écran** — Les panneaux superposés n'ont pas de nom, le focus va sur « Fermer » et le titre n'est jamais lu. Il faut donner le titre comme nom du panneau et placer le focus initial sur le titre ou le corps. La lecture automatique des zones qui changent (LiveSetting) exige .NET 4.7.1 ou plus : à vérifier sur le parc avant de s'y fier. · Effort S · Priorité P2 · (Pesto-Workspace.ps1:46, 79, 302-318)
42. **Palette Ctrl+K en sections, et un seul « modèle de préparation »** — La palette mélange navigation, brouillons et outils d'analyse (« Mesures de performance locales » en tableau brut). Favoris et Brouillon font presque la même chose. Il faut des sections Aller à / Préparer / Outils avancés, ces derniers masqués aux techniciens, et fusionner Favoris et Brouillon en « Modèle de préparation ». · Effort S · Priorité P3 · (Pesto-Workspace.ps1:159-175, 198-201 ; Pesto-Shell.xaml:156-159)
43. **Raccourcis clavier cohérents** — Aucun bouton n'a de touche d'accès (Alt+lettre) ni de bouton Entrée par défaut, et Ctrl+1 à Ctrl+4 ne suivent pas l'ordre du menu. Il faut ajouter :
    - les touches d'accès ;
    - Ctrl+Entrée pour le bouton principal (qui ouvre toujours la confirmation) ;
    - Ctrl+1 à Ctrl+8 dans l'ordre du menu ;
    - F5 pour relire.

    Chaque raccourci doit être rappelé dans l'infobulle, la page Aide et les guides. · Effort S · Priorité P3 · (Pesto-Shell.xaml et Pesto-Join.xaml : aucune touche d'accès ni IsDefault ; Pesto-Core.ps1:4614-4634)
44. **Aide courte visible sous les champs clés** — Les règles importantes ne se lisent qu'au survol du « ⓘ » : changer de site entraîne un déplacement, le service fait 3 caractères, le nom n'est pas réservé. Il faut une ligne d'aide sous Site, Service et Nouveau nom, en gardant les infobulles détaillées. · Effort S · Priorité P3 · (Pesto-Shell.xaml:142, 149-150)
45. **Boutons d'en-tête plus parlants** — « Actions · Ctrl+K » ouvre une recherche et « Audit » ouvre un dossier. Il faut renommer le premier « Rechercher (Ctrl+K) » avec une loupe, et déplacer le second dans la page Journal sous le nom « Ouvrir le dossier des journaux ». · Effort S · Priorité P3 · (Pesto-Shell.xaml:125-126)
46. **Page Aide repérée dans le menu** — Quand F1 ouvre l'Aide, aucune entrée du menu n'est active, et le panneau s'intitule « À vos côtés ». Il faut marquer le « ? » de l'en-tête comme actif et intituler le panneau « Aide ». · Effort S · Priorité P3 · (Pesto-Shell.xaml:116, 567 ; Pesto-Core.ps1:4506)
47. **« Vider la file » : dire ce qui sera perdu** — La confirmation dit seulement « Vider toute la file ? ». Elle doit indiquer le nombre de lignes, dont celles qui portent un résultat non exporté, rappeler que les reçus sont conservés et proposer d'exporter le bilan avant. · Effort S · Priorité P3 · (Pesto-Core.ps1:4786)
48. **Barre de chargement des noms : infobulle exacte** *(correction)* — L'infobulle fixe dit « pas un pourcentage », alors qu'un vrai pourcentage s'affiche dès que le total est connu. Il faut adapter le texte et afficher « x postes lus sur y ». · Effort S · Priorité P3 · (Pesto-Shell.xaml:340 ; Pesto-Core.ps1:3997-3998)
49. **Avertissement de secours : bonne icône, rattaché à la bonne fenêtre** *(correction)* — La boîte d'avertissement de secours (Show-MsgWarning) affiche l'icône Information et n'est rattachée à aucune fenêtre : elle peut passer derrière la fenêtre Diagnostic. Il faut la rattacher à la fenêtre active et utiliser l'icône Avertissement. · Effort S · Priorité P3 · (Pesto-Core.ps1:1256-1265 ; Pesto-Support.ps1:151)
50. **Classement des erreurs : « OU » trouvé dans « brouillon » ou « vous »** *(correction)* — Le motif « OU.*invalide », insensible à la casse, fait conseiller « vérifiez l'OU dans Paramètres » pour un « Fichier de brouillon invalide ». Il faut chercher le mot `\bOU\b` en respectant la casse, ou classer par code d'erreur. · Effort S · Priorité P3 · (Pesto-Support.ps1:29 ; Pesto-Workspace.ps1:114, 250)

## Design

*Voir aussi dans les 15 premières : n° 6.*

51. **Panneaux de message : gravité visible et taille adaptée** — Les panneaux d'information, d'erreur et de confirmation se ressemblent. Ils s'étirent sur toute la fenêtre (deux lignes de texte dans 500 px vides), répètent le titre dans le corps et affichent l'aide toujours en orange. En mode panneau, l'erreur mélange titre, effet, conseil et détail dans une seule zone. Il faut une hauteur ajustée au contenu et une gravité (info, succès, attention, erreur) signalée par un bandeau et une icône. La structure doit être la même partout : titre, effet, prochaine étape, détails repliés. · Effort M · Priorité P1 · (Pesto-Workspace.ps1:45-58 ; Pesto-Support.ps1:46-64 ; Pesto-Join.ps1:329)
52. **Une vraie couleur « erreur »** — Échec, Bloqué, Partiel et À vérifier partagent la même pastille ambre, car aucune couleur d'erreur n'existe. Il faut ajouter une couleur rouge sobre pour KO, BLOQUÉ et TECHNIQUE, avec son équivalent en contraste élevé. L'ambre reste pour INCERTAIN, PARTIEL et PÉRIMÉ, et chaque pastille reçoit un symbole (✓ ! ✕ ?). Un résultat incertain ne ressemble alors ni à un succès ni à un échec. · Effort S · Priorité P1 · (Pesto-Shell.xaml:4, 216-217 ; Pesto-Core.ps1:1648-1752 ; Pesto-Appearance.ps1:82-90)
53. **Typographie : une échelle, 12 px minimum, taille réglable** — On compte 17 tailles de police (de 10 à 30) et 8 rayons d'angle. Les titres de carte font 15, 16 ou 17 points selon la page, 18 textes sont en 11 px et « APRÈS LA JONCTION » en 10 px. Il faut quelques styles fixes (titre de carte, légende, chiffre clé, sous-titre de page) et des marges standard (4, 8, 12, 16, 24). Les textes d'état doivent faire au moins 12 px, et Apparence doit proposer un réglage « Taille du texte » (100, 115 ou 130 %). · Effort M · Priorité P2 · (Pesto-Shell.xaml:139, 169, 183, 196 ; Pesto-Join.xaml:7, 14, 56 ; Pesto-SuiteUI.ps1:38-39)
54. **Icônes homogènes** — Le menu mélange des symboles Unicode tirés de polices différentes (⌂ ✎ ▦ + ▤ ◷ ≡ ⚙), de taille et de graisse inégales. Il faut utiliser Segoe MDL2 Assets, présente sous Windows 10 et 11 (Segoe Fluent Icons n'existe que sous Windows 11), à travers un style unique, avec repli sur le symbole actuel. · Effort M · Priorité P2 · (Pesto-Shell.xaml:113-115, 199 ; Pesto-Authentication.ps1:376)
55. **Sélecteur Un seul poste / Plusieurs postes lisible** — Le mode actif n'est marqué que par la graisse du texte, alors que les boutons sont déjà en semi-gras : les deux paraissent identiques. Il faut en faire un sélecteur à deux segments, avec le segment actif nettement marqué, ou le retirer, puisque le menu latéral porte déjà ces deux entrées. · Effort S · Priorité P2 · (Pesto-SuiteUI.ps1:106-107 ; Pesto-Shell.xaml:16, 135)
56. **Grille des noms plus reposante** — Toutes les lignes libres sont teintées en vert, et toute la grille est en police à chasse fixe. Il faut des lignes neutres, une pastille dans la colonne État (Libre, Utilisé, Réservé par… jusqu'à…, en lien avec la réservation en cours) et la police à chasse fixe réservée à la colonne Nom. · Effort S · Priorité P2 · (Pesto-Shell.xaml:317-326)
57. **Historique plus lisible** — Deux boutons sont empilés, les chiffres n'ont pas de couleur, le texte contient l'anglicisme « checkpoints » et aucun détail n'est accessible par lot. Il faut une barre d'outils sur une ligne, les échecs en rouge quand ils sont non nuls, une pastille de mode, un double-clic qui ouvre le détail du lot et un message clair quand la liste est vide. C'est une étape avant l'historique unifié (n° 109). · Effort S · Priorité P2 · (Pesto-Shell.xaml:560 ; Pesto-Core.ps1:4554)
58. **Ajouter au domaine : pied compact et résultat clair** — Le pied fixe occupe environ 130 px même vide, l'état des vérifications est du texte brut et le titre est en 25 points au lieu du style de page. Il faut mettre la raison et les boutons sur une ligne et afficher les états en pastilles comme dans la file. Après acceptation, une carte « Redémarrage nécessaire » propose Redémarrer maintenant ou Plus tard, sans jamais redémarrer d'office. · Effort S · Priorité P2 · (Pesto-Join.xaml:7, 71, 78-90)
59. **Barres de défilement, volets dépliables et listes au style de l'application** — Les barres de défilement, les listes et les barres de progression gardent le style Windows d'origine, tout comme les volets dépliables. On voit donc des flèches classiques et la sélection système au milieu d'une interface arrondie. Il faut des modèles fins aux couleurs de l'application, contraste élevé compris, vérifiés sous PowerShell 5.1. · Effort M · Priorité P2 · (Pesto-Shell.xaml:91 ; Pesto-Workspace.ps1:51)
60. **Pages vides, en chargement ou en erreur traitées de la même façon** — Seules la file et la page Noms ont un message quand elles sont vides ou en chargement. Historique, Interventions, journal filtré et vérifications de jonction affichent une grille blanche. Il faut un même bloc (icône, phrase, bouton d'action) pour ces trois situations. · Effort M · Priorité P2 · (Pesto-Shell.xaml:251, 337, 560 ; Pesto-Interventions.ps1:12 ; Pesto-Join.xaml:70)
61. **Panneau d'aide sur les écrans de moins de 1450 px** — En dessous de cette largeur, le panneau (220 à 320 px) recouvre l'aperçu Avant / Après, et son ouverture est mémorisée d'une session à l'autre. Il faut le transformer en tiroir qui se ferme au clic à côté, ou en simple icône. · Effort S · Priorité P2 · (Pesto-SuiteUI.ps1:66-76)
62. **Entrée « Ajouter au domaine » alignée sur les autres** *(correction)* — L'icône « + » ne prend pas la couleur active, mesure 28 px au lieu de 29, et le libellé est en 12 au lieu de 13 points. Il faut reprendre le gabarit de l'entrée Accueil. · Effort S · Priorité P2 · (Pesto-Shell.xaml:115)
63. **Écran de connexion lisible en contraste élevé** *(correction)* — Le bouton « Se connecter » et le logo forcent du texte blanc sur une couleur qui devient claire en contraste élevé : le blanc y devient illisible. Il faut utiliser la couleur de texte prévue par le thème. Par ailleurs, hors domaine, le bandeau dit « Compte de domaine requis » mais le champ s'intitule « Compte Windows » : écrire « Compte AD (`DOMAINE\utilisateur`) ». · Effort S · Priorité P2 · (Pesto-Authentication.ps1:366, 377, 380, 394 ; Pesto-Appearance.ps1:85)
64. **Journal en contraste élevé : distinguer erreurs et informations** *(correction)* — En contraste élevé, toutes les couleurs de texte deviennent identiques et une erreur ne se repère plus. Il faut préfixer chaque ligne d'un repère texte (« ✕ Erreur », « ! Attention », « ✓ »). · Effort S · Priorité P2 · (Pesto-Appearance.ps1:86 ; Pesto-Journal.ps1:116-136)
65. **Couleurs définies à un seul endroit** — Les couleurs du thème clair sont écrites deux fois (dans l'interface et dans le script), quatre couleurs ne servent nulle part, et le changement de thème recolore à la main des listes qui suivent déjà le thème. Il faut charger les couleurs depuis la table des thèmes au démarrage et retirer l'inutile. · Effort S · Priorité P3 · (Pesto-Shell.xaml:4 ; Pesto-Core.ps1:1648-1752, 1803-1805)
66. **Texte net aux échelles d'affichage de 125 à 200 %** — La fenêtre force un rendu du texte prévu pour une échelle de 100 %. Il peut paraître crénelé sur les portables à haute densité de pixels, qui ne sont pas encore recettés. Il faut changer de mode de rendu au-delà de 100 % et vérifier sur la VM. · Effort S · Priorité P3 · Risque moyen · (Pesto-Shell.xaml:2)
67. **Cadre pointillé autour de la page Noms** — La capture montre le cadre de focus par défaut de Windows autour de tout le contenu (cause à confirmer). Il faut le supprimer sur les conteneurs de page, en gardant l'anneau de focus sur les contrôles. · Effort S · Priorité P3 · (outils/guides/images/noms.png)
68. **Messages du lanceur et du démarrage avec accents** — Les premières boîtes que voit un technicien sont sans accents : « Pesto n'a pas pu demarrer », « Aucune action n'a ete lancee », « Deja ouvert ». Les fonctions d'affichage et l'encodage des fichiers les acceptent pourtant. Il faut corriger ces textes, reconstruire l'EXE et rafraîchir le manifeste, après avoir vérifié l'affichage en console. · Effort S · Priorité P3 · (Pesto-Startup.ps1:143, 448, 453, 486, 492 ; tools/launcher/Pesto-launcher.c:88, 137, 164, 195)

## Moteur et performance

*Voir aussi dans les 15 premières : n° 1, 2, 3, 4, 11, 12.*

69. **Liste des noms du site : expiration et âge affiché** — Une fois un site lu, sa liste reste en cache toute la session. Les noms créés par les collègues ne sont donc jamais vus, d'où un même nom proposé à plusieurs techniciens. Il faut dater chaque liste, la relire après 2 minutes (durée réglable) et juste avant chaque contrôle, et afficher « Liste lue à 14:02 (il y a 6 min) · Relire ». Cela complète la réservation en cours. · Effort S · Priorité P1 · (Pesto-Directory.ps1:298-302, 318-319 ; Pesto-Names.ps1:197-199)
70. **« Nom déjà pris » : supprimer le scan complet dans le worker** *(correction)* — Quand le nom cible est pris, le worker relit tout l'annuaire puis jette ce résultat en se terminant. Sur un grand domaine, cela ajoute 30 s ou plus et peut dépasser la limite de surveillance de 300 s : un refus net (88) devient alors un incertain (97). Il faut supprimer ces lectures, ainsi que la fonction GoJoinDomain, jamais appelée mais toujours copiée dans le worker. · Effort S · Priorité P1 · (Pesto-Operations.ps1:1307-1311, 1365-1369, 1429 ; Pesto-Core.ps1:3417)
71. **Services et noms calculés une fois par chargement** — À chaque choix de site, tout le parc est relu nom par nom, et deux fois quand OUScanNoms vaut ROOT. Il faut construire une fois deux index (« 12 premiers caractères → numéros pris » et « site → services ») et supprimer la source en double. Le changement de site devient instantané, sans figer la fenêtre. · Effort M · Priorité P1 · (Pesto-Directory.ps1:109, 247-281, 482 ; Pesto-Join.ps1:382-397, 484-496 ; Pesto-Core.ps1:1489-1517, 3070-3087)
72. **Contrôle de lot : délai proportionnel et résultats conservés** — Le contrôle traite jusqu'à 200 lignes une par une, avec un délai fixe de 120 s, et un dépassement annule tout (« aucune ligne déclarée vérifiée »). Il faut un délai proportionnel au nombre de lignes et des requêtes AD groupées par paquets de 50 noms. Chaque ligne terminée doit être publiée avec sa date, pour ne rien perdre en cas de dépassement. · Effort M · Priorité P1 · Risque moyen · (Pesto-Core.ps1:745-752, 925-939, 952, 983, 994)
73. **Préparer un lot sans attendre l'inventaire complet** — La préparation refuse tout poste source absent du cache, et doit donc attendre l'inventaire. Il faut lire les postes sources (200 au plus) par requêtes LDAP groupées, et les séries de noms par la recherche ciblée du site. · Effort M · Priorité P2 · (Pesto-Core.ps1:606-631)
74. **Dernier inventaire gardé sur disque et affiché tout de suite** — L'inventaire est relu en entier à chaque ouverture. Il faut le conserver dans le dossier du profil, daté et rangé par domaine et contrôleur, et l'afficher avec la mention « inventaire du 08/10 14:32 » pendant la relecture. Il ne sert qu'aux propositions et aux listes, jamais à décider : le contrôle AD reste obligatoire. · Effort M · Priorité P2 · (Pesto-Names.ps1:194-203 ; Pesto-Directory.ps1:131-198 ; Pesto-Core.ps1:175-185)
75. **Actualisation partielle de l'inventaire** — Après un chargement complet, il suffit de relire les ordinateurs modifiés depuis la dernière lecture sur le même contrôleur (compteur de modifications AD). L'inventaire est rechargé en entier si le contrôleur change, ou une fois par jour. Une suppression manquée reste sans danger : un nom resté « pris » n'est simplement pas proposé. · Effort M · Priorité P3 · Risque moyen · (Pesto-Directory.ps1:429-532)
76. **Environnements de lecture préparés à l'avance** — Chaque lecture, même un simple Vérifier, crée un environnement PowerShell neuf : elle y recharge tout le code des fonctions puis réimporte le module AD. Il faut préparer à la connexion un petit lot d'environnements de lecture, avec le module et les fonctions chargés une fois, et le fermer avec la fenêtre. Les écritures gardent un environnement neuf et isolé. Le gain se mesure avec les temps déjà collectés. · Effort L · Priorité P2 · Risque moyen · (Pesto-Async.ps1:199-221 ; Pesto-Core.ps1:3430-3466 ; Pesto-Directory.ps1:438-439, 540-547)
77. **Compiler le C# embarqué une fois, au build** — Le code C# du journal d'audit et des appels Windows est recompilé à chaque lancement, parfois deux fois. Il faut produire une DLL au build, contrôlée par empreinte comme les autres composants, et la charger directement. Le démarrage raccourcit et Pesto n'écrit plus de fichiers temporaires dans le dossier %TEMP% du compte administrateur. · Effort M · Priorité P2 · Risque moyen · (Pesto-Journal.ps1:41 ; Pesto-Integrity.ps1:163 ; Pesto-Core.ps1:2199 ; Pesto-Operations.ps1:237)
78. **Contrôle du paquet fait une seule fois au démarrage** — Le calcul d'empreinte des 38 composants et l'analyse des scripts tournent d'abord sans droits administrateur, puis à nouveau après l'élévation, alors que Pesto.exe a déjà vérifié les empreintes. Il faut garder le calcul d'empreinte dans le premier processus et l'analyse dans le seul processus qui charge le moteur. · Effort S · Priorité P2 · (Pesto-Startup.ps1:387-388, 436, 450-456)
79. **Ne plus attendre le ping avant de lire l'AD** — La lecture d'un poste distant commence par un ping lent (plusieurs secondes si le ping est filtré), et le worker en refait un purement indicatif. Il faut lire l'AD d'abord, lancer le ping en parallèle avec un délai de 500 ms, et retirer le ping du worker. · Effort S · Priorité P2 · (Pesto-Core.ps1:2738 ; Pesto-Operations.ps1:1449-1454)
80. **Les lectures demandées par le technicien passent en priorité** — État du poste, état de jonction et contrôle de lot attendent une place libre derrière les lectures de fond. Ils échouent au bout de 30 s si l'inventaire et des recherches de site occupent la place. Toute lecture lancée par un clic doit passer en priorité. · Effort S · Priorité P2 · (Pesto-Async.ps1:209-216)
81. **Poste distant éteint : réponse immédiate** — L'observation à distance enchaîne cinq appels de 12 s chacun, sur l'ancien puis sur le nouveau nom. Il faut d'abord tester la résolution du nom et le port 135 (800 ms), répondre aussitôt « poste injoignable (RPC 135) » si besoin, et interroger les deux noms en parallèle. · Effort S · Priorité P2 · (Pesto-Inspection.ps1:64-96)
82. **Attente de réplication avant déplacement réglable** — Le renommage attend 60 s fixes que le nouveau nom apparaisse sur le contrôleur, puis rend un code 89. Sur un réseau à plusieurs sites, c'est souvent trop court. Il faut rendre cette attente réglable (dans la limite des 300 s) et retrouver le poste par son identifiant (GUID) plutôt que par son nom. Pour un 89, Interventions doit relire toutes les 15 s et activer « Reprendre le déplacement » dès que possible ; le clic reste obligatoire. · Effort M · Priorité P2 · (Pesto-Operations.ps1:1337-1356, 1397-1407)
83. **Contrôleur indisponible : en chercher un autre sur demande** — Le contrôleur est trouvé une fois à la connexion. S'il tombe, tout échoue jusqu'à la relance de Pesto. En cas de panne, il faut proposer un bouton « Chercher un autre contrôleur », jamais pendant une opération ni sans clic, et sans bascule automatique vers le PDC (décision du 08/10). Une option administrateur, désactivée par défaut, désignerait un « contrôleur préféré du banc », testé en 2 s, avec repli immédiat sur la découverte Windows. · Effort M · Priorité P2 · Risque moyen · (Pesto-Directory.ps1:29-38, 443-448 ; Pesto-Authentication.ps1:59 ; DEV/docs/V1_CONSTATS_OUVERTS.md:146-150)
84. **Mesures de performance gardées dans l'audit** — Les durées des opérations ne sont gardées qu'en mémoire (200 au plus) et se perdent à la fermeture. Il faut écrire une ligne par opération dans l'audit (opération, contrôleur, attente, durée, nombre d'objets) et un résumé dans le diagnostic. Cela permet de mesurer la lenteur sur votre réseau réel au lieu de la deviner. · Effort S · Priorité P2 · (Pesto-Async.ps1:327-333 ; Pesto-Names.ps1:4-16)
85. **Page Jonction recalculée chaque seconde, même masquée** — Chaque seconde, la page relit la politique, reconstruit le plan et réécrit ses textes, même quand elle n'est pas affichée. Il faut ne la rafraîchir que si elle est visible ou si une lecture est en cours, et garder la politique en mémoire tant que la configuration ne change pas. · Effort S · Priorité P3 · (Pesto-Join.ps1:340-380, 674-680, 762-763)
86. **Jonction : éviter un contrôle AD en double** — « Ajouter » refait un contrôle complet avant la confirmation, même si « Vérifier sans ajouter » vient de réussir. Si un contrôle valide du même plan date de moins de 60 s, il faut passer directement à la confirmation. Le contrôle après confirmation reste obligatoire. · Effort S · Priorité P3 · (Pesto-Join.ps1:192-200, 520-545)
87. **Journal : couleurs créées une seule fois** — Le journal recrée une couleur pour chaque ligne affichée, jusqu'à 500 fois à chaque reconstruction (changement de thème, de recherche ou de taille). Il faut créer ces couleurs une fois par thème. · Effort S · Priorité P3 · (Pesto-Journal.ps1:116-125, 176)
88. **Machine virtuelle proposée comme « Fixe »** *(correction)* — Le type de poste n'est déduit que du type de boîtier, et une VM Hyper-V se déclare comme un poste fixe. Il faut aussi lire le modèle et le fabricant (Virtual Machine, VMware, VirtualBox, QEMU, KVM). Seule la présélection change. · Effort S · Priorité P3 · (Pesto-Directory.ps1:201-211, 510-522)

## Fiabilité et sécurité

*Voir aussi dans les 15 premières : n° 7, 10, 11, 12.*

89. **Ne plus effacer les journaux d'audit après 30 jours** *(correction)* — Au démarrage, les fichiers `Pesto_*.log` de plus de 30 jours sont supprimés sans le dire. La règle du projet interdit pourtant d'effacer les journaux, qui servent à instruire un 97. Il faut supprimer cette purge, ou la rendre explicite et documentée : durée réglable, 0 = jamais par défaut. Il faut aussi changer de fichier à minuit (une session qui passe minuit écrit dans le fichier de la veille) et permettre un niveau de détail renforcé temporaire. · Effort S · Priorité P1 · (Pesto-Journal.ps1:38, 44-49 ; Pesto-Core.ps1:1845 ; CLAUDE.md:29)
90. **Droits du dossier de reçus réappliqués à chaque écriture** — Chaque écriture de reçu (6 à 10 par opération) réapplique les droits du dossier, qui se propagent à tous les fichiers déjà présents. Le coût grandit avec l'historique, et un fichier tenu par l'antivirus peut faire échouer l'écriture (97 « reçu final non enregistré »). Il faut appliquer les droits à la création du dossier, ou seulement s'ils diffèrent. · Effort S · Priorité P1 · (Pesto-Join.ps1:89-95 ; Pesto-Safety.ps1:119-127, 174-185 ; Pesto-Direct.ps1:34-40)
91. **Reçus relus en entier à chaque opération, blocage à 5 000** — Chaque opération lit et valide tous les reçus, même ceux déjà vérifiés. Au-delà de 5 000, toute écriture est refusée, sans outil d'archivage. Il faut tenir un index des reçus (nom, date, étape, identifiant, noms) reconstruit s'il diverge, ne relire en détail que les reçus non résolus, et appliquer le plafond à ces seuls reçus. Aucun reçu n'est déplacé ni effacé. · Effort M · Priorité P1 · Risque moyen · (Pesto-Safety.ps1:110-117, 129-151)
92. **Verrou du registre partagé jamais libéré si le partage était injoignable** — La libération du verrou n'est tentée qu'une fois, juste après le reçu final. Si le partage est momentanément coupé, le verrou reste et bloque le poste visé sur tous les postes de travail, sans expiration. Au démarrage et à l'ouverture d'Interventions, il faut retenter la libération normale pour les reçus terminés dont le verrou porte encore le même identifiant d'opération. C'est une libération par son propriétaire, pas un effacement forcé. · Effort M · Priorité P1 · (Pesto-Safety.ps1:208, 324 ; Pesto-Policy.ps1:82, 118)
93. **Un reçu illisible ne doit plus vider Interventions** — Une erreur sur un seul fichier vide toute la grille (« Lecture des reçus impossible »), alors que c'est l'écran qui sert à débloquer. Pour l'affichage, il faut lire les fichiers un par un en arrière-plan et montrer une ligne « reçu illisible : nom du fichier, bloquant » avec un bouton d'ouverture du dossier. Le contrôle avant écriture reste strict. · Effort S · Priorité P2 · (Pesto-Interventions.ps1:35-44 ; Pesto-Safety.ps1:116)
94. **Fichier momentanément verrouillé : réessayer brièvement** — Le remplacement d'un fichier n'est tenté qu'une fois. Si l'antivirus tient le reçu une fraction de seconde, la fin de jonction devient un 97. Il faut réessayer trois fois (après 100, 300 et 900 ms), seulement sur les erreurs de partage ou de verrou, et journaliser chaque essai. · Effort S · Priorité P2 · (Pesto-Core.ps1:147-173 ; Pesto-Join.ps1:243-247)
95. **Nouvel essai de lecture efficace sur les pannes AD** — Le nouvel essai ne reconnaît que certains codes d'erreur Windows, alors que les pannes du service web AD (ADWS) se présentent autrement (serveur indisponible, délai dépassé). Il ne sert en outre qu'à une seule recherche. Il faut reconnaître ces pannes et appliquer le nouvel essai à toutes les lectures, jamais aux écritures. · Effort S · Priorité P2 · (Pesto-Contracts.ps1:106-115 ; Pesto-Directory.ps1:60)
96. **Liste des noms du site incomplète : le dire** — La recherche par OU masque toute erreur, pas seulement « OU absente », et les recherches de série s'arrêtent à 2 000 ou 5 000 résultats sans le signaler. Les numéros pris peuvent donc être sous-estimés, et le nom proposé être déjà pris. Il faut signaler une liste incomplète ou tronquée, la noter au journal et afficher « liste partielle, revérification avant l'action ». · Effort S · Priorité P2 · (Pesto-Directory.ps1:554, 558 ; Pesto-Core.ps1:722 ; Pesto-Join.ps1:183)
97. **Doublons de réplication nommés clairement** — Si deux techniciens créent le même nom sur deux contrôleurs, l'AD renomme un objet en `NOM\0ACNF:GUID`, ou son nom de compte en `$DUPLICATE-…`. Pesto ne dit alors que « nom final non attendu ». Il faut chercher ces formes pendant les vérifications et afficher un message dédié avec la conduite à tenir. · Effort M · Priorité P2 · (Pesto-Directory.ps1:59-61 ; Pesto-Inspection.ps1:46-52 ; Pesto-JoinRecovery.ps1:99-100)
98. **Contrôle de l'horloge avant la jonction** — Le contrôle avant jonction ne vérifie pas l'écart d'horloge. Or l'authentification du domaine (Kerberos) refuse au-delà de 5 minutes d'écart, et les masters neufs sont souvent décalés. Il faut lire l'heure du contrôleur, avertir au-delà d'une minute d'écart et bloquer au-delà de quatre avec « réglez l'heure du PC ». · Effort S · Priorité P2 · (Pesto-Join.ps1:134-190)
99. **Liste des opérations qui écrivent définie une seule fois** — La liste des quatre opérations qui écrivent est recopiée 14 fois. Une future opération qui écrit (une réservation dans l'AD, par exemple) oubliée dans une seule copie serait traitée comme une lecture, sans ses protections. Il faut une seule définition, avec un test qui vérifie chaque usage. · Effort S · Priorité P2 · (Pesto-Async.ps1:80, 101, 176-182, 274-291, 330-364)
100. **Verrou d'opération : savoir qui le détient** — Le verrou ne contient qu'un identifiant, une clé chiffrée et un état jamais mis à jour, et le message de conflit n'affiche qu'un code (GUID). Il faut y ajouter le poste de travail, le compte, le nom du poste visé et l'état courant, comme pour les réservations en cours, et afficher « Détenu par X sur Y depuis 10:42 ». · Effort S · Priorité P2 · (Pesto-Policy.ps1:118-120)
101. **Journal de démarrage perdu avant l'élévation** — Avant l'élévation, Pesto écrit son journal de démarrage sous Program Files, où il n'a pas le droit d'écrire. L'échec reste invisible, alors que la boîte d'erreur renvoie justement vers ce fichier. Il faut écrire dans `%LOCALAPPDATA%\Pesto\logs` et citer le chemin réellement utilisé. · Effort S · Priorité P2 · (Pesto-Startup.ps1:134-144, 486)
102. **Retrait Entra : ne pas citer un reçu non écrit** *(correction)* — Si l'écriture du reçu Entra échoue, le message annonce quand même « Reçu cible : chemin ». Il faut vérifier que l'écriture a réussi et écrire « reçu non enregistré » dans le cas contraire. · Effort S · Priorité P3 · (Pesto-Operations.ps1:849-851)
103. **Réconciliation des tâches : garder le journal** *(correction)* — La réconciliation des tâches planifiées remplace la fonction de journal par une fonction vide : toutes ses erreurs sont perdues. Il faut les envoyer au journal comme le font déjà la reprise et la jonction. · Effort S · Priorité P3 · (Pesto-Interventions.ps1:158 ; Pesto-Recovery.ps1:81)
104. **Filet d'exception global : couvrir l'action unitaire et la reprise** — Une erreur imprévue de l'interface déclenche la mesure de prudence pour la file et la jonction, mais pas pour une action unitaire ou une reprise en cours. Il faut traiter les quatre cas de la même façon, ou documenter pourquoi ce n'est pas nécessaire. · Effort S · Priorité P3 · (Pesto-Core.ps1:5162-5163 ; Pesto-Async.ps1:83-85)
105. **Contrôle de déploiement : signature et politique d'exécution** — Le rapport `--check-json` indique « signature non vérifiée » en dur. Il doit donner l'état de la signature de Pesto.exe et des scripts, ainsi que la politique d'exécution effective : une stratégie de groupe AllSigned refuse les scripts non signés. Il faut aussi pouvoir signer avec un certificat rangé ailleurs que dans le magasin de l'utilisateur courant. · Effort S · Priorité P3 · (Pesto-Startup.ps1:105, 409 ; tools/Sign-PestoRelease.ps1:7)
106. **Verrous limités aux postes concernés** *(décision à prendre)* — Après un code 32, 97 ou 98 dans la file, toutes les écritures sur tous les postes sont bloquées. Une jonction locale à vérifier bloque aussi le renommage d'autres postes. Le parcours unitaire, lui, ne bloque que le poste visé. Il s'agirait de limiter ces verrous aux postes concernés, en gardant le blocage global tant qu'une opération tourne. Les verrous sont restreints, jamais levés. C'est une règle de sûreté, à vous de décider. · Effort M · Priorité P3 · Risque élevé · (Pesto-Policy.ps1:155-181 ; Pesto-Core.ps1:2528, 3535-3547 ; Pesto-UXFlow.ps1:30-37)
107. **Clôture administrateur « constaté non appliqué »** *(décision à prendre)* — Un 97 où rien ne s'est passé ne peut se clore que si le poste devient conforme au plan. L'idée est une action réservée à l'administrateur, possible seulement si une lecture récente retrouve exactement l'état d'avant : même identifiant, mêmes noms, même OU, aucun renommage en attente, Entra non demandé. Le reçu passe alors en échec « non appliqué constaté », après double confirmation, et jamais en succès. · Effort M · Priorité P3 · Risque élevé · (DEV/docs/V1_CONSTATS_OUVERTS.md:198-199)

## Fonctionnalités

*Voir aussi dans les 15 premières : n° 9, 14, 15.*

108. **Référence de ticket et technicien dans chaque reçu** — Le reçu central ne contient ni référence ni auteur (seul le vérificateur est noté), et Un poste n'a pas de champ ticket. Il faut ajouter un champ « Référence ou ticket » et noter qui lance l'opération. Cela demande un nouveau format de reçu qui relit toujours les anciens, avec des tests de compatibilité. · Effort M · Priorité P1 · Risque moyen · (Pesto-Safety.ps1:59-60, 141-160 ; Pesto-Workspace.ps1:106)
109. **Historique unifié, filtrable, exportable** — L'Historique ne garde que 100 synthèses sans nom de poste, et Interventions n'a ni filtre, ni recherche, ni export. L'Historique deviendrait la liste des interventions, avec pour chacune : date locale, poste, nouveau nom, opération, état, code, technicien et ticket. Il aurait des filtres (période, état, texte) et un export CSV ; les synthèses de lots deviendraient une vue secondaire. · Effort L · Priorité P1 · (Pesto-Core.ps1:532, 1180-1194, 4536-4556 ; Pesto-Interventions.ps1:3-45)
110. **Vérifier d'un coup les postes d'un lot après redémarrage** — Aujourd'hui, chaque poste du lot se vérifie un par un depuis Interventions. Un bouton « Vérifier les postes du lot » lancerait les lectures en parallèle (dans la limite réglée par MaxReaders) et afficherait un tableau Conforme / À revoir. Une confirmation listerait ensuite les seuls postes conformes à consigner. Les autres restent en attente et aucun verrou n'est levé. · Effort L · Priorité P2 · Risque moyen · (outils/guides/technicien.md:254, 268 ; Pesto-Inspection.ps1:191-238 ; Pesto-Policy.ps1:7)
111. **Modèles de banc définis par l'administrateur** — Les favoris sont rangés dans le profil du PC qui exécute Pesto, deviennent inutilisables à chaque changement de configuration et n'existent pas pour la jonction. Or, sur un banc, Pesto tourne sur chaque master neuf. Il faut une section de modèles dans cfg.json (nom, organisme, site, service, type), affichée en boutons en tête de la jonction et de Un poste. La revérification et la confirmation restent inchangées. · Effort M · Priorité P2 · (Pesto-Preparation.ps1:77 ; Pesto-Appearance.ps1:10-40)
112. **Recherche rapide de poste** — Un poste et la palette exigent le nom exact. Il faut un champ de recherche global qui propose des postes dès 4 caractères (20 résultats au plus), complété par les reçus locaux. Chaque résultat montre le nom, l'OU lisible et une éventuelle intervention en attente, avec « Ouvrir dans Un poste ». Lecture seule. · Effort M · Priorité P2 · (Pesto-Workspace.ps1:221-223 ; Pesto-Core.ps1:4810-4818)
113. **Identité matérielle sur la page de jonction** — La partie « Ce PC » ne montre que le nom, le domaine et le compte. Il faut ajouter le numéro de série, le modèle et l'adresse MAC active, puis les reprendre dans la confirmation, le reçu local et le compte rendu. Un bouton « Afficher le nom en grand » aiderait à étiqueter les boîtiers. · Effort S · Priorité P2 · (Pesto-Join.xaml:13-25 ; Pesto-JoinRecovery.ps1:6)
114. **Import de lot au format technicien** — L'import exige des chemins d'OU complets et exacts, et la préparation impose un seul site et un seul service pour tout le lot. Il faut accepter un CSV ou un collage Excel « Poste;Site;Service;Type[;Ticket] ». Chaque ligne passe par le générateur de noms et la règle de site, et entre dans la file décochée. Un rapport d'erreurs est produit par ligne, et la taille maximale de lot (MaxBatch) est respectée. · Effort M · Priorité P2 · (Pesto-Core.ps1:606-612, 3727-3740)
115. **Journal : jours précédents, filtre par niveau, copie des erreurs** — La page ne montre que la session en cours, avec l'heure sans la date, et ne propose qu'une recherche texte. Il faut :
     - un sélecteur de date en lecture seule ;
     - des filtres Tout / Attentions et erreurs / Erreurs, et par poste ;
     - une colonne date ;
     - un bouton « Copier les erreurs pour le support ».

     Le fichier d'audit reste inchangé. · Effort M · Priorité P2 · (Pesto-Journal.ps1:107-114, 139-150, 166 ; Pesto-Shell.xaml:531-535)
116. **Signaler la fin d'un traitement** — Rien ne prévient quand Pesto est en arrière-plan. Il faut afficher la progression dans la barre des tâches (possible directement en WPF) et faire clignoter la fenêtre à la fin d'une jonction, d'un lot ou d'un inventaire si Pesto n'a pas le focus. Un son système peut être proposé en option. · Effort S · Priorité P3 · (aucune notification de ce type dans DEV/wad)
117. **Registre partagé des comptes rendus du banc** — Les reçus et l'historique restent sur chaque master. En option, Pesto écrirait un résumé dans le dossier partagé de coordination et proposerait une vue « Banc » en lecture qui regroupe la journée. Pas de service permanent, et un échec d'écriture ne donne qu'un avertissement. À coordonner avec le registre de réservations. · Effort L · Priorité P3 · Risque moyen · (Pesto-Safety.ps1:47-51 ; Pesto-Policy.ps1:77)
118. **Mode « banc de master » guidé** — Ce mode assemble les briques précédentes en un parcours pas à pas pour un technicien peu formé : modèle choisi une fois, nom en grand, Vérifier puis Ajouter, redémarrage proposé, vérification à la relance, puis bandeau « PC suivant ». Les règles ne changent pas : confirmation, aucun redémarrage implicite, consignation explicite. · Effort M · Priorité P3

## Configuration et administration

*Le menu de configuration complet est déjà en cours (voir la dernière section) : les items ci-dessous le complètent sans le recompter. Voir aussi dans les 15 premières : n° 7.*

119. **« Recharger » montre l'ancienne configuration, pas cfg.json** *(correction)* — Quand une relance est en attente, « Recharger » remplit l'écran avec la configuration encore en mémoire, tout en annonçant « Relu depuis cfg.json ». Un clic sur Enregistrer réécrit ensuite ces anciennes valeurs et annule sans prévenir le changement déjà enregistré. Il faut remplir l'écran avec la configuration relue sur le disque, et le dire. · Effort S · Priorité P1 · (Pesto-Configuration.ps1:252, 369-386, 402-416)
120. **Profil technicien : interface simplifiée, réglages métier en lecture seule** — Tout utilisateur voit et peut enregistrer le domaine, les OU, DirectProd et les modes de test (Simulation, GUI). Un réglage d'administration permettrait :
     - de masquer les options avancées, les colonnes techniques et, si vous le voulez, Plusieurs postes ;
     - de mettre les paramètres métier en lecture seule, avec un bouton « Déverrouiller » confirmé et journalisé ;
     - de retirer les modes de test du paquet de production.

     Ce n'est pas une protection de sécurité : le moteur garde tous ses contrôles. · Effort M · Priorité P1 · Risque moyen · (Pesto-Shell.xaml:383-510 ; Pesto-Configuration.ps1:331-355 ; Pesto-SuiteUI.ps1:150-155)
121. **Code de site deviné à partir des deux dernières lettres** *(correction)* — Si aucun code de site ne correspond, Pesto prend les deux dernières lettres du nom du site : « LYON » et « TOULON » donnent tous deux « ON ». Le seul signe est une ligne au journal, alors que l'assistant affirme qu'aucun code n'est attribué au hasard. Il faut refuser par défaut avec « Ajoutez le code du site X dans Paramètres » et ne garder ce repli que comme option explicite. Il faut aussi afficher un avertissement sous le nom proposé et lister les sites concernés. · Effort M · Priorité P1 · Risque moyen · (Pesto-Core.ps1:1477-1484 ; Pesto-Configuration.ps1:462)
122. **Appliquer sans relance ce qui ne touche pas au contexte AD** — Tout changement impose une relance, même pour les codes de sites, les exclusions, la taille maximale de lot ou la durée de réservation. Or les plans en cours sont déjà invalidés et la configuration est recontrôlée avant chaque exécution. On peut donc tout appliquer immédiatement, sauf le domaine, DirectProd, les OU de base, les modes de test et le dossier de coordination. · Effort M · Priorité P1 · Risque moyen · (Pesto-Configuration.ps1:40-54, 369-397 ; Pesto-Direct.ps1:330)
123. **Paramètres : erreur affichée sur le champ et modifications non enregistrées signalées** — Une erreur de saisie n'apparaît que dans une boîte qui liste des clés JSON, et rien ne signale une saisie en cours : Recharger ou fermer la perd sans demander. Il faut encadrer le champ fautif avec un message en dessous et placer le curseur sur la première erreur. L'onglet doit indiquer « Modifications non enregistrées », et Pesto doit demander confirmation avant de recharger ou de fermer. · Effort M · Priorité P1 · (Pesto-Configuration.ps1:337-342, 402-416 ; Pesto-Shell.xaml:517-519)
124. **Décrire chaque réglage une seule fois** — Chaque clé est décrite à cinq endroits du code, plus le guide. Une seule table (clé, type, valeur par défaut, bornes, section, libellé, aide, application immédiate ou après relance) produirait la validation, l'écran et la signature de configuration. Un test vérifierait que chaque clé figure dans le guide administrateur. À faire avec le menu en cours. · Effort L · Priorité P1 · Risque moyen · (Pesto-Configuration.ps1:22-38, 119-329 ; Pesto-Policy.ps1:3-43)
125. **Aperçu des changements et versions de cfg.json** — Rien ne montre ce qui va changer, et une seule copie de sauvegarde est écrasée à chaque enregistrement. Il faut afficher les changements clé par clé avant l'écriture (« DirectProd : false → true, relance requise »). Il faut aussi garder des copies datées, en nombre réglable et sans suppression silencieuse, avec un bouton « Historique… » pour comparer et restaurer une version validée. · Effort M · Priorité P2 · (Pesto-Core.ps1:161-162 ; Pesto-Configuration.ps1:331-355)
126. **Mode Consultation : enregistrement refusé avec une raison** *(correction)* — L'enregistrement ne vérifie pas le mode Consultation. Il échoue alors en « accès refusé » sous Program Files, ou modifie réellement cfg.json si Pesto est installé ailleurs. Il faut griser Enregistrer avec « Consultation : paramètres en lecture seule ». · Effort S · Priorité P2 · (Pesto-Configuration.ps1:331-335 ; Pesto-Core.ps1:6)
127. **Bouton « Relancer Pesto maintenant »** — Après un changement qui exige une relance, celle-ci reste manuelle. Un bouton vérifierait qu'aucune opération n'est en cours, relancerait Pesto.exe avec les mêmes options (nouvelle demande UAC), puis fermerait l'instance courante. Il trouverait sa place dans le bandeau du n° 6. · Effort S · Priorité P2 · (Pesto-Configuration.ps1:395 ; Pesto-UXFlow.ps1:34)
128. **Domaine différent au démarrage : proposer la correction** — Si le domaine configuré diffère de celui du PC, Pesto quitte. Une faute de frappe enregistrée bloque donc tout lancement jusqu'à une correction à la main du fichier. Il faut proposer « Corriger la configuration » ou « Restaurer la sauvegarde », et avertir dès l'enregistrement quand le domaine diffère de celui du poste. · Effort S · Priorité P2 · (Pesto-Core.ps1:4959-4960 ; Pesto-Configuration.ps1:106-117)
129. **Fenêtre de correction : restaurer la sauvegarde, montrer où est l'erreur** — Cette fenêtre propose l'assistant, l'import, la validation et Quitter, mais pas « Restaurer la sauvegarde ». De plus, sous PowerShell 5.1, une erreur dans le fichier JSON est signalée sans ligne ni colonne. Il faut ajouter la restauration, avec aperçu et validation, et calculer la position de l'erreur. · Effort M · Priorité P2 · (Pesto-Configuration.ps1:80, 113-114)
130. **Réglages sans effet acceptés sans avertissement** *(correction)* — MoveRollbackOnRenameFail, DsregLeaveOnMove, AllowHybridRepair, BPVerifNomAD et ForceADM sont acceptés ou réécrits, mais jamais utilisés. Il faut afficher « réglage sans effet dans cette version », ne plus les réécrire et retirer le code correspondant. · Effort S · Priorité P2 · (Pesto-Core.ps1:4870, 4872, 4877 ; Pesto-Configuration.ps1:155, 161, 302-303)
131. **Assistant : protection contre la suppression choisie explicitement** *(correction)* — L'assistant écrit ClearProtectionOnMove=false, alors que le moteur prend true quand la clé est absente. Une configuration créée par l'assistant refuse donc tout déplacement d'objet protégé (code 31). Il faut demander ce choix par une case expliquée. · Effort S · Priorité P2 · (Pesto-Configuration.ps1:480 ; Pesto-Core.ps1:4876 ; Pesto-Operations.ps1:1252)
132. **Codes de sites ambigus détectés à l'enregistrement** — Seuls les motifs exactement en double sont refusés. Deux motifs qui se chevauchent passent la validation, puis le nommage échoue devant le technicien. À l'enregistrement, il faut tester chaque site connu contre tous les motifs, et ajouter un champ « Tester un nom de site → code ». · Effort M · Priorité P2 · (Pesto-Configuration.ps1:210-233 ; Pesto-Core.ps1:1465-1470)
133. **Vérifier la configuration dans l'AD** — La validation actuelle ne regarde que le fichier. Un bouton en lecture seule vérifierait l'AD et donnerait un rapport à copier :
     - existence de chaque OU configurée ;
     - groupes exclus retrouvés ;
     - nombre de sites par organisme ;
     - sites sans code ou codés par repli ;
     - contrôleur trouvé et temps de réponse.

     · Effort M · Priorité P2 · (Pesto-Configuration.ps1:119-247 ; outils/guides/administrateur.md:533)
134. **Avertissements non bloquants, dont les clés inconnues** — La validation ne connaît que les erreurs bloquantes, et une faute de frappe dans un nom de clé (« DirecProd ») est ignorée sans rien dire. Il faut un niveau « avertissement » affiché avant l'écriture pour :
     - une clé inconnue (hors commentaires « _… ») ;
     - un mode Simulation ou GUI actif ;
     - une OU hors de la racine ;
     - un réglage sans effet ;
     - des motifs de site qui se chevauchent.

     · Effort M · Priorité P2 · (Pesto-Configuration.ps1:119-247, 339-342 ; Pesto-Policy.ps1:10)
135. **Erreurs de politique précises** — Des messages comme « Limite invalide : MaxReaders » ou « Valeur de politique invalide. » ne disent ni la section, ni la valeur, ni la plage attendue, et la validation s'arrête à la première erreur. Il faut toutes les lister sous la forme « POLICY.MaxReaders = 12 : entier de 1 à 8 attendu », et accepter les commentaires « _… » comme dans le reste du fichier. · Effort S · Priorité P2 · (Pesto-Policy.ps1:9, 16, 23-26 ; Pesto-Contracts.ps1:8)
136. **Journaliser chaque modification de configuration** — L'audit ne dit que « cfg.json enregistré ». Il doit noter le compte, chaque clé modifiée (ancienne puis nouvelle valeur, sans secret) et les signatures de configuration avant et après. · Effort S · Priorité P2 · (Pesto-Configuration.ps1:348)
137. **Délais et limites réglables** — Tous les délais et limites sont fixés dans le code : inventaire 180 s, recherche de site 60 s, contrôle de jonction 90 s, écriture 300 s, contrôle avant lot 120 s, réplication 60 s, 12 lectures simultanées. Il faut les rendre réglables avec des bornes sûres, sur le modèle de MaxReaders, pour adapter Pesto à un réseau lent sans nouvelle version. · Effort M · Priorité P2 · (Pesto-Policy.ps1:3-17 ; Pesto-Async.ps1:183, 215 ; Pesto-Directory.ps1:190, 305 ; Pesto-Join.ps1:538, 592 ; Pesto-Operations.ps1:1399)
138. **Empreinte de configuration visible et comparable** — La coordination entre techniciens suppose les mêmes règles sur tous les postes, mais rien n'affiche la configuration active. Il faut afficher son empreinte courte dans Paramètres, l'audit et le diagnostic, et en option la comparer à une configuration de référence sur un partage. · Effort S · Priorité P2 · (Pesto-Configuration.ps1:22-38 ; DEV/tools/Initialize-Coordination.ps1:20)
139. **Diagnostic complet** *(correction)* — L'export de diagnostic ne contrôle que 11 fichiers d'une liste figée : il en manque plusieurs, dont Pesto.exe. Il faut utiliser la liste officielle des composants et ajouter un résumé sans information sensible : empreinte de configuration, DirectProd, politique Entra, modes de test, état de l'audit, partage de coordination joignable et contrôleur utilisé. · Effort S · Priorité P2 · (Pesto-Support.ps1:92, 110 ; Pesto-Integrity.ps1:3-47 ; Pesto-Journal.ps1:196-201)
140. **Paramètres en langage métier** — L'écran reprend le vocabulaire et la structure du fichier :
     - titres « GÉNÉRAL (section CONF) », « DRAPEAUX DE TEST (section DEBUG) » ou « OUScanNoms » ;
     - onglet Apparence intitulé « Gestion des postes » ;
     - « Préfixe (6 caractères) » alors qu'il faut 6 chiffres ;
     - « Site pré-prod », appelé ailleurs « Code service de préparation ».

     Il faut des libellés métier, garder le nom de la clé dans l'infobulle et n'accepter que des chiffres dans le préfixe. · Effort S · Priorité P2 · (Pesto-Shell.xaml:153, 291, 293, 370, 383, 396-400, 433, 457, 476, 495, 498 ; Pesto-SuiteUI.ps1:102 ; Pesto-Configuration.ps1:444-451)
141. **Réglages d'affichage regroupés dans Apparence** — La densité et la mémoire des colonnes ne s'atteignent que par Ctrl+K, et la hauteur de ligne en mode Confort n'est pas la même dans le script (36) et dans l'interface (38). Il faut regrouper dans Apparence le thème, la densité, les colonnes, la taille du journal, le menu réduit et le panneau d'aide, et utiliser une seule hauteur de ligne. · Effort S · Priorité P2 · (Pesto-Workspace.ps1:214-218, 262-265 ; Pesto-Shell.xaml:87, 369-378)
142. **Mise à jour sans Python, refusée si Pesto est ouvert** — L'outil de mise à jour exige Python, s'exprime en anglais et ne vérifie que l'absence d'opération en cours : un Pesto ouvert mais inactif voit ses fichiers remplacés. Il faut le réécrire en PowerShell 5.1 (ou en `Pesto.exe --update`) et le refuser si Pesto est ouvert. Dès l'aperçu, il doit valider le cfg.json en place avec la nouvelle version. · Effort L · Priorité P2 · Risque moyen · (tools/update_installation.py:341-384)
143. **Vue en lecture seule du registre partagé** — Aucun écran ne liste les verrous et les réservations actifs. Il faut une vue « Registre partagé » dans Interventions : poste visé, propriétaire, ancienneté, reçu local associé, partage joignable. Aucun bouton d'effacement. · Effort M · Priorité P3 · (Pesto-Policy.ps1:74-92)
144. **Version du format de configuration contrôlée** — Le modèle livré et l'assistant ne nomment pas la version du format de la même façon, et aucun des deux n'est lu. Une configuration écrite par une version plus récente de Pesto provoque donc un obscur « Champ non autorisé ». Il faut unifier ce champ, le contrôler et afficher « configuration écrite par une version plus récente : mettez Pesto à jour ». · Effort S · Priorité P3 · (tools/cfg.template.json:2 ; Pesto-Configuration.ps1:480 ; Pesto-Policy.ps1:9)
145. **Profils de configuration (plusieurs départements ou domaines)** — Pesto ne charge qu'une configuration par lancement, choisie seulement en ligne de commande (-ConfigPath). Il faut proposer au lancement un choix parmi les fichiers validés d'un dossier de profils. Les files de chaque configuration sont déjà séparées. · Effort M · Priorité P3 · Risque moyen · (Pesto-Configuration.ps1:131 ; Pesto-Startup.ps1:185-191 ; Pesto-launcher.c:137)
146. **Script d'installation qui pose et vérifie les droits** — L'installation est entièrement manuelle (copie, droits des dossiers, contrôle). Un script PowerShell 5.1, avec mode simulation, ferait tout : copier les fichiers, appliquer et vérifier les droits, préserver un cfg.json existant, lancer le contrôle. Il rendrait un code de sortie utilisable par l'outil de déploiement du parc. · Effort M · Priorité P3 · (outils/guides/administrateur.md, chap. 11 ; DEV/docs/V1_CONSTATS_OUVERTS.md, conditions 1 à 3)
147. **Groupes exclus choisis par nom, OU exclues avec le navigateur** — L'onglet Politique en cours de développement demande des identifiants de groupe bruts (GUID) et des chemins d'OU tapés à la main. Il faut un sélecteur de groupe AD (recherche par nom, identifiant enregistré, nom affiché) et réutiliser « Parcourir… » pour les OU. · Effort M · Priorité P3 · (Pesto-Policy.ps1:26 ; modifications non commitées de Pesto-Shell.xaml)
148. **Catalogue des noms modifiable à l'écran** — Le catalogue site / service est validé et sert à calculer la capacité de nommage, mais il n'apparaît dans aucun écran, ni dans l'onglet Politique en cours. Il faut une grille Site (2 lettres) / Service (3 caractères), avec import depuis les services déjà présents dans l'AD. · Effort M · Priorité P3 · (Pesto-Configuration.ps1:127-129, 281-329 ; Pesto-Core.ps1:3836)
149. **Exporter et importer la configuration depuis Paramètres** — L'import n'existe que dans la fenêtre de correction au démarrage. Il faut « Exporter… » (fichier et empreinte) et « Importer… », avec validation, aperçu des changements et mention de la relance éventuelle. · Effort M · Priorité P3 · (Pesto-Configuration.ps1:100-101, 418-432)

## Qualité et tests

*Voir aussi dans les 15 premières : n° 7 (test aller-retour de la configuration), n° 11 (à confirmer sur la VM).*

150. **Un seul lancement pour toute la validation** — TEST_TOUT.cmd se présente comme une validation complète, mais ne lance ni la suite de stabilisation (27 cas, la référence), ni les tests de jonction, ni les suites 21 à 23. Il faut un point d'entrée unique, avec un profil Rapide et un profil Complet, et un seul résumé des résultats. · Effort S · Priorité P1 · (tests/Run-AllTests.ps1:7 ; TESTER.cmd ; tests/Run-RC14Validation.ps1:51)
151. **Vérifier que chaque worker a toutes ses fonctions** — Le contrôle des fonctions manquantes ne couvre qu'une des sept sources de code des workers. Une fonction oubliée donne en production un 98 « terme non reconnu », sur un chemin rare. Il faut étendre le contrôle aux sept sources, et ajouter un test sous PowerShell 5.1 qui charge chaque source à vide et vérifie que chaque commande est trouvée. · Effort M · Priorité P1 · (tools/checks/validate_pesto.py:87-102 ; Pesto-Inspection.ps1:140 ; Pesto-Core.ps1:673 ; Pesto-Review.ps1:82 ; Pesto-Safety.ps1:274)
152. **Banc d'états de l'interface en WPF réel, sans AD** — Le code qui décide de « Vérification requise » ou d'un bouton « Vérifier » grisé n'a aucun test PowerShell, seulement des recherches de texte. Il faut charger les écrans sous 5.1 et parcourir toutes les combinaisons d'états (occupé, bloqué, champs remplis ou non, dans ou hors domaine). Le test exige qu'un bouton principal grisé ait toujours une raison, et qu'un blocage propose toujours une action. Complète les tests GUI réels en cours. · Effort M · Priorité P1 · (Pesto-UXFlow.ps1:28-53 ; tests/test_blocage_explique.py)
153. **Simulateur AD à plusieurs contrôleurs, avec trois techniciens** — Des doublures de l'AD gardent un état par contrôleur avec un délai de réplication réglable. Trois « techniciens » simulés rejouent la proposition de noms, le contrôle et la jonction. On reproduit ainsi à volonté « même nom proposé » et on mesure l'effet de la réservation et du numéro au hasard, sans votre réseau réel. · Effort M · Priorité P1 · (DEV/docs/V1_CONSTATS_OUVERTS.md ; Pesto-Core.ps1:715-725 ; Pesto-Join.ps1:177-186)
154. **Tests avec les vraies erreurs de Windows** — Les tests qui distinguent refus et incertain utilisent des erreurs fabriquées, que Add-Computer et Rename-Computer ne produisent pas sous 5.1. Il faut jouer sur la VM : mot de passe faux, compte sans droit sur l'OU, nom existant, renommage distant refusé. On enregistre l'erreur exacte et on construit des doublures fidèles. C'est un préalable au n° 11. · Effort M · Priorité P1 · (tests/Pesto.Safety.Tests.ps1:16 ; tests/Run-Pesto21Tests.ps1:105-106)
155. **Suite de tests de la configuration** — Quatre cas seulement couvrent la validation. Il faut ajouter :
     - l'aller-retour écran → fichier → signature (défaut du 08/10) ;
     - la configuration produite par l'assistant ;
     - la conservation des commentaires « _ » ;
     - Recharger pendant l'attente de relance ;
     - le retour à la configuration d'origine ;
     - les codes de sites ambigus et une politique partielle.

     · Effort M · Priorité P2 · (tests/Run-EngineTests.ps1:221-224)
156. **Contrôles automatiques des messages** — Il faut étendre les vérifications statiques pour que :
     - tout libellé cité entre « » dans un message existe à l'écran ;
     - aucun mot français courant ne reste sans accent ;
     - le nom lu par le lecteur d'écran contienne le texte visible ;
     - aucune infobulle ne soit générée vide.

     Il faut aussi détecter les variables d'état lues mais jamais écrites : ce contrôle aurait trouvé le minuteur mort du n° 23. · Effort S · Priorité P2 · (tests/ux_static_checks.py ; tests/test_accessibility_uia.py ; tools/checks/validate_pesto.py)
157. **Faire réellement tourner le contrôle GitHub sous Windows** — Le workflow est rangé sous DEV/.github, alors que GitHub ne lit que .github/workflows à la racine du dépôt : il ne tourne jamais. Il faut le déplacer en indiquant DEV comme dossier de travail, y ajouter la stabilisation et les tests Python, et le déclencher sur les branches cloud/*. On obtient ainsi Windows PowerShell 5.1 et WPF réels à chaque commit, sans AD ni UAC. · Effort S · Priorité P2 · (DEV/.github/workflows/validate.yml)
158. **Retirer les suites de tests mortes ou cassées** — Plusieurs suites visent des fichiers ou des versions qui n'existent plus. Deux contrôles lisent DEV/Pesto.ps1, disparu, et une validation cherche un écran autrefois intégré au code. Les suites Test-Pesto15/16/18 et validate_rc14 à rc17 attendent d'anciennes versions. Il faut les ranger dans tests/historique_rc18 et les exclure du paquet DEV. · Effort S · Priorité P2 · (tests/static_checks.py:31 ; tests/Run-RC14Validation.ps1:22-25 ; wad/maintenance/Test-Pesto15.ps1:30 ; tools/package_distribution.py:23)
159. **Tests Python : un outil commun, et tester le comportement plutôt que le texte** — 338 vérifications comparent du texte source, et 9 copies de l'outil d'extraction découpent les fonctions différemment. Il faut un outil d'extraction partagé, garder la comparaison de texte pour les seules règles de sécurité (aucun Restart-Computer…), et transformer le reste en tests PowerShell exécutables. · Effort M · Priorité P2 · (tests/test_services_rapides.py:11-17 ; tests/test_blocage_explique.py:11-17)
160. **Boîte à outils de test PowerShell commune** — L'extraction des fonctions est recopiée dans une vingtaine de scripts, et 16 fichiers redéfinissent leurs propres vérifications. Il faut un module commun sans dépendance externe (Pester n'est pas installé par défaut sous Windows) : extraction de fonction, vérifications, cas de test et rapport JSON standard. · Effort M · Priorité P2 · (tests/Run-StabilisationTests.ps1:10-29 ; outils/labo/vm/banc-moteur-ad.ps1:15-21)
161. **Banc AD réel du parcours complet, et second contrôleur au labo** — Il faut étendre le banc AD à l'enchaînement jamais joué : jonction, redémarrage, vérification, renommage, puis déplacement d'un objet protégé. Chaque phase doit être précédée d'un instantané à froid et produire une preuve JSON. Un second contrôleur (LABO-DC02) reproduirait la réplication, mais demande votre décision sur la mémoire disponible sur l'hôte. · Effort L · Priorité P2 · Risque moyen · (DEV/docs/V1_CONSTATS_OUVERTS.md ; outils/labo/vm/banc-moteur-ad.ps1:1-4)
162. **Une seule règle « nom pris »** — La recherche « nom pris » existe en cinq copies, et la lecture de série en deux, avec des limites et des portées différentes. Les valeurs y sont insérées sans échappement, et le domaine est relu à chaque vérification. Il faut une seule fonction qui dise si le nom est pris, quels numéros de la série le sont, si la liste est tronquée et quel contrôleur a répondu. · Effort M · Priorité P2 · (Pesto-Core.ps1:698, 715-726 ; Pesto-Join.ps1:164, 177-187 ; Pesto-Names.ps1:69-70 ; Pesto-Directory.ps1:60, 411 ; Pesto-Inspection.ps1:48)
163. **Compilation du lanceur : imposer le bon compilateur** — Le script de compilation prend le premier compilateur clang trouvé, et celui d'Apple s'est déjà glissé deux fois (03/10, 07/10). Il faut fixer la version attendue dans tools/version.json et refuser toute autre version. Un script unique doit enchaîner compilation, manifeste, contrôle et validation portable, dans cet ordre. · Effort S · Priorité P2 · (tools/launcher/build_native.py:69)
164. **Un seul code écrit chaque texte de l'interface** — Le titre de page, le résumé de redémarrage et l'étape suivante sont écrits par deux fonctions, avec des textes différents (« Renommer un poste » puis « Modifier un poste »). Les premiers réglages du bouton principal sont aussitôt écrasés, et le rappel du poste visé commence par « · » quand le nom est vide. Chaque texte doit avoir un seul auteur. · Effort S · Priorité P3 · (Pesto-Core.ps1:4430 ; Pesto-SuiteUI.ps1:109, 113-117, 129-135, 148)
165. **Code mort à retirer** — La gestion du bouton principal contient une branche hors domaine qui ne s'exécute jamais. La fonction qui décide de la relance contient des variables inutilisées et un test toujours vrai. Il faut nettoyer ce code avant d'y ajouter l'application sans relance (n° 122). · Effort S · Priorité P3 · (Pesto-Core.ps1:3152, 3158-3164 ; Pesto-Configuration.ps1:381-398)
166. **Découper Pesto-Core.ps1** — Le fichier fait 5 262 lignes et 172 fonctions, et sa section « utilitaires sans interface » contient de l'interface. Il faut extraire par étapes la file, la vue Noms, la navigation et le navigateur d'OU. Chaque nouveau fichier est ajouté aux composants contrôlés, puis suivi d'une compilation, d'un manifeste et d'une stabilisation. · Effort L · Priorité P3 · Risque moyen · (Pesto-Core.ps1:112, 1090, 1321, 2471, 3177, 3403, 3796, 4228)
167. **Icône lue depuis Pesto.ico** — Pesto-Core.ps1 contient l'icône sous forme de texte encodé (130 lignes), alors que Pesto.ico est déjà un composant livré et contrôlé. Il faut lire le fichier. · Effort S · Priorité P3 · (Pesto-Core.ps1:1907-2037, 2178 ; Pesto-Integrity.ps1:44)
168. **Analyse du code : aucune nouvelle régression** — Seules les erreurs de l'analyseur PowerShell bloquent la livraison, et l'on compte 156 blocs d'erreur vides, dont 69 dans Pesto-Core.ps1. Il faut figer la liste des avertissements actuels, refuser toute nouvelle occurrence et exiger un commentaire pour chaque bloc vide conservé. · Effort S · Priorité P3 · (tools/Verify-Release.ps1:23)
169. **Rapports de test générés hors de Git** — 34 fichiers JSON sont suivis dans tests/, dont des rapports réécrits à chaque exécution : les différences sont bruyantes et les conflits fréquents entre sessions. Il faut écrire les résultats dans tests/results/, ignoré par Git, et ranger à part les références historiques. · Effort S · Priorité P3 · (tools/checks/validate_pesto.py:172)
170. **Fichiers d'interface : une ligne par élément** — Certaines lignes de Pesto-Shell.xaml font de 2 500 à 5 000 caractères, ce qui rend les relectures et les différences illisibles. Il faut reformater sans changer le contenu, puis refaire empreintes et compilation, après avoir vérifié les tests qui comparent du texte exact. · Effort S · Priorité P3 · (Pesto-Shell.xaml:4, 115, 135, 150, 197, 216, 253)

## Documentation

*Voir aussi dans les 15 premières : n° 13.*

171. **Guide technicien et page Aide alignés sur le logiciel** — Le guide doit dire qu'il faut lire un poste avant de choisir l'organisme d'un lot (tant que le n° 22 n'est pas fait) et expliquer le cas du ping filtré. Les raccourcis doivent être les mêmes partout : Ctrl+K et Échap manquent dans l'Aide, Ctrl+F dans le guide. Il faut aussi reprendre le vocabulaire du n° 25 et refaire les captures après chaque refonte d'écran. · Effort S · Priorité P2 · (outils/guides/technicien.md:228, 379-387 ; Pesto-Shell.xaml:561)
172. **Guide administrateur complété** — Le guide doit décrire ce que le code fait aujourd'hui sans le dire :
     - la suppression des journaux de plus de 30 jours (n° 89) ;
     - le repli sur les deux dernières lettres pour le code de site (n° 121) ;
     - les réglages sans effet (n° 130) ;
     - la valeur par défaut de ClearProtectionOnMove, différente entre l'assistant et le moteur (n° 131) ;
     - le besoin de Python pour la mise à jour (n° 142).

     · Effort S · Priorité P2 · (outils/guides/administrateur.md, chap. 12 à 15 et 21)
173. **Aide contextuelle reliée aux guides** — F1 n'affiche que l'infobulle, et la page Aide est un texte fixe. Il faut un lien « Ouvrir le chapitre du guide » sur chaque page, avec une table page → chapitre. Le PDF est cherché dans un dossier configuré ou dans le dossier DOC voisin, sans réseau. · Effort M · Priorité P3 · (Pesto-Core.ps1:4614-4625 ; Pesto-Shell.xaml:561)

## Déjà en cours (non comptés dans cette liste)

Ces chantiers sont menés dans une autre session. Les items cités les complètent sans les recouper.

- **Réservation de noms partagée** : un nom retenu par un technicien (poste, compte, échéance) n'est plus proposé aux autres. Compléments :
  - n° 56 : état « Réservé » dans la grille ;
  - n° 69 : liste du site datée et relue ;
  - n° 100 : savoir qui détient un verrou ;
  - n° 143 : vue du registre partagé ;
  - n° 153 : banc à trois techniciens.
- **Réservation AD à la jonction**. Compléments :
  - n° 97 : doublons de réplication nommés clairement ;
  - n° 99 : toute écriture AD de réservation doit figurer dans la liste unique des opérations qui écrivent.
- **Numéro au hasard** : tirage parmi les numéros libres pour réduire les collisions entre techniciens. Complément : n° 153, pour en mesurer l'effet.
- **Menu de configuration complet** : onglet Politique (exclusions, coordination, jonction précréée ou hors ligne, limites de lecture et de lot, durée de réservation, protection au déplacement). Compléments : n° 119 à 149, en particulier 120, 123, 124, 125, 147 et 148.
- **Tests GUI réels** : pilotage de l'interface sur la VM. Compléments :
  - n° 40 : noms d'accessibilité à aligner avec les tests ;
  - n° 152 : banc d'états sans AD ;
  - n° 156 : contrôles automatiques des messages.

## Idées complémentaires du Spark (brouillon, non vérifiées dans le code)

Le Spark a reçu le résumé du logiciel et les deux guides, sans le code. Ses idées recoupent souvent la liste ci-dessus ; elles sont gardées telles quelles pour la discussion.

### Interface

1. **Panneau « Pourquoi c'est bloqué »** — Sous chaque bouton grisé, afficher la cause exacte, l'action attendue et un bouton contextuel. Bénéfice : le technicien comprend et débloque sans appeler l'administrateur. Effort : S. Risque : faible.

2. **Bandeau d'étapes unique** — Pour jonction, renommage, déplacement, afficher 1 Préparation, 2 Vérification, 3 Confirmation, 4 Redémarrage, 5 Vérification. Bénéfice : orientation claire dans le parcours. Effort : M. Risque : faible.

3. **Confirmation avec diff AVANT/APRÈS** — Dans la fenêtre de confirmation, comparer nom, OU, GUID, protection et site. Bénéfice : le technicien voit précisément ce qui change. Effort : M. Risque : faible.

4. **Bouton contextuel « Ouvrir la vérification »** — Quand une intervention bloque, proposer directement le bouton qui ouvre l'état du poste concerné. Bénéfice : déblocage guidé sans recherche dans l'historique. Effort : S. Risque : faible.

5. **Recherche globale Ctrl+K** — Ajouter une recherche unique pour poste, ticket, code résultat, intervention, page. Bénéfice : navigation rapide pour technicien expérimenté. Effort : M. Risque : faible.

6. **Filtres mémorisés par page** — Mémoriser Site, Service, Type, Statut et recherche dans « Noms disponibles » et « Historique ». Bénéfice : moins de ressaisie entre postes. Effort : S. Risque : faible.

7. **Messages d'erreur avec action** — Chaque message doit contenir motif, cause probable, bouton ou chemin à suivre. Bénéfice : autonomie du technicien. Effort : M. Risque : faible.

8. **Bouton « Copier le diagnostic »** — Dans chaque erreur, copier un résumé expurgé : poste, compte, DC, code, heure, référence. Bénéfice : escalade plus rapide vers l'administrateur. Effort : S. Risque : faible.

9. **Avertissement poste distant sans AskCredential** — Si « Un autre poste du domaine » est coché sans compte AD explicite, afficher l'action « Relancer avec Pesto.exe -AskCredential ». Bénéfice : évite un échec 96 tardif. Effort : S. Risque : faible.

### Design visuel

10. **Badges de mode très visibles** — Afficher Réel, Consultation, Démonstration, Simulation avec couleur, texte et icône. Bénéfice : évite de croire agir en mode réel alors que rien n'est écrit. Effort : S. Risque : faible.

11. **Couleurs + texte pour les états** — Ne jamais coder Succès, Échec, Incertain, Partiel par couleur seule. Bénéfice : lisible en contraste élevé et pour daltonisme. Effort : S. Risque : faible.

12. **Icônes d'étape cohérentes** — Utiliser des icônes fixes pour Vérification, Confirmation, Redémarrage, Déplacement, Reprise. Bénéfice : repères visuels rapides. Effort : S. Risque : faible.

13. **Timeline d'intervention** — Dans « État du poste », afficher chronologiquement plan, demande, effet constaté, vérification. Bénéfice : comprend mieux les cas 89, 97, 32. Effort : M. Risque : faible.

14. **Grille « Noms disponibles » compacte** — Prioriser nom, site, service, type, statut, réservation, ticket. Bénéfice : choix de nom plus rapide. Effort : M. Risque : faible.

15. **Compte rendu imprimable** — Générer une vue ticket avec poste, nom, OU, code, date, vérification, opérateur. Bénéfice : archivage propre et lisible. Effort : M. Risque : faible.

16. **Accessibilité clavier et lecteur d'écran** — Ajouter labels, ordre de tabulation, focus visible, annonces WPF. Bénéfice : utilisable avec Narrateur et navigation clavier. Effort : M. Risque : moyen.

### Moteur et performance

17. **Lecture ciblée du site avec cache** — Étendre la lecture ciblée à tous les besoins de nommage, avec cache par site et TTL. Bénéfice : moins d'appels AD et meilleure réactivité. Effort : M. Risque : moyen si cache trop ancien.

18. **Pagination des lectures AD** — Lire les postes par pages de 500 ou 1000 objets. Bénéfice : évite les timeouts sur grands domaines. Effort : M. Risque : moyen.

19. **Exécution asynchrone de l'interface** — Déplacer toutes les lectures AD en tâches non bloquantes. Bénéfice : Pesto ne gèle plus pendant une recherche. Effort : M. Risque : moyen.

20. **Annulation propre des lectures** — Permettre d'annuler une lecture AD sans jamais couper une écriture engagée. Bénéfice : contrôle utilisateur sans risque métier. Effort : M. Risque : moyen.

21. **Affichage du contrôleur utilisé** — Montrer le DC trouvé par Windows, son rôle, sa latence et son état d'inscriptibilité. Bénéfice : diagnostic immédiat sur réseau multi-DC. Effort : M. Risque : faible.

22. **Conscience de la réplication** — Après création ou renommage, détecter si le nom est absent sur le DC lu et afficher un message de délai. Bénéfice : réduit les faux « nom libre » entre techniciens. Effort : M. Risque : moyen.

23. **Réservation atomique des noms** — Utiliser un registre partagé avec création exclusive, TTL, propriétaire et libération explicite. Bénéfice : évite que deux techniciens prennent le même nom. Effort : L. Risque : moyen.

24. **Numérotation par série en une requête** — Pour une série type+département+site+service, lire tous les numéros utilisés en une seule requête. Bénéfice : proposition de nom plus rapide et plus fiable. Effort : M. Risque : moyen.

25. **Retry de lecture avec backoff** — Ajouter 2 tentatives de lecture AD avec délai court, sans jamais relancer une écriture. Bénéfice : tolérance aux pics réseau. Effort : S. Risque : faible.

26. **Timeouts par opération** — Définir des timeouts distincts pour lecture AD, DNS, RPC, tâche distante. Bénéfice : messages plus rapides et plus précis. Effort : M. Risque : moyen.

27. **Mesures de performance locales** — Afficher temps de lecture, P95, moyenne, maximum par opération. Bénéfice : l'administrateur voit où ça ralentit. Effort : S. Risque : faible.

### Fiabilité et sécurité

28. **Signature Authenticode** — Signer Pesto.exe et les composants critiques avec un certificat approuvé. Bénéfice : confiance, AppLocker, antivirus, déploiement parc. Effort : L. Risque : moyen si chaîne de certificat mal préparée.

29. **ACL durcies à l'installation** — Contrôler automatiquement que Users n'ont que lecture/exécution sur Pesto.exe et wad. Bénéfice : empêche la modification locale du moteur. Effort : S. Risque : faible.

30. **Manifeste d'intégrité complet** — Inclure tous les fichiers exécutables et ressources critiques dans package.json. Bénéfice : le lanceur bloque toute altération. Effort : S. Risque : faible.

31. **Verrou d'instance robuste** — Refuser une seconde instance du même profil et afficher la fenêtre existante. Bénéfice : évite deux files ou deux reçus concurrents. Effort : S. Risque : faible.

32. **Reçu append-only** — Écrire les reçus en journal JSONL avec hash chaîné, sans écrasement. Bénéfice : preuve d'exploitation plus forte. Effort : M. Risque : moyen.

33. **Audit local structuré** — Journaliser actions, compte, cible, GUID, OU, résultat, mode, version. Bénéfice : diagnostic et conformité. Effort : M. Risque : moyen.

34. **Masquage systématique des secrets** — Interdire mot de passe, jeton ou capture sensible dans logs, tickets, exports. Bénéfice : sécurité des données internes. Effort : S. Risque : faible.

35. **Blocage de double écriture** — Refuser toute nouvelle écriture si une intervention active ou incertaine existe sur la même cible. Bénéfice : respecte la règle « une opération confirmée n'est jamais rejouée ». Effort : M. Risque : faible.

36. **Idempotence par GUID et OU** — Avant toute écriture, relire GUID, nom, OU, protection et comparer au plan confirmé. Bénéfice : aucune action sur un objet devenu différent. Effort : M. Risque : moyen.

37. **Workflow dédié au code 97** — Pour un résultat incertain, imposer relire, tâches, preuves, décision admin, sans bouton « relancer ». Bénéfice : évite les doubles créations. Effort : M. Risque : moyen.

38. **Protection contre la suppression accidentelle** — Contrôler protect flag, ClearProtectionOnMove, restauration de protection et relecture finale. Bénéfice : ne casse pas les objets sensibles. Effort : M. Risque : moyen.

### Fonctionnalités

39. **Réservation partagée des noms** — Ajouter un registre réseau partagé pour réserver temporairement un nom pendant une préparation. Bénéfice : réduit les collisions entre techniciens. Effort : L. Risque : moyen.

40. **Statut de réservation visible** — Afficher réservé par qui, depuis quand, expiration, poste concerné. Bénéfice : évite de choisir un nom déjà engagé. Effort : M. Risque : moyen.

41. **Import CSV pour les lots** — Permettre d'importer une liste de postes avec validation, doublons, exclusions. Bénéfice : prépare un lot de 200 postes sans copier-coller fragile. Effort : M. Risque : moyen.

42. **Export bilan de lot** — Exporter lignes, codes, tickets, GUID, destination, statut de vérification. Bénéfice : suivi administrable après un lot. Effort : S. Risque : faible.

43. **Compte rendu ticket prêt à coller** — Générer un texte avec poste, nom, OU, code, date, opérateur, référence. Bénéfice : ticket propre et homogène. Effort : S. Risque : faible.

44. **Suivi des redémarrages dus** — Lister les postes en attente de redémarrage et de vérification. Bénéfice : évite les interventions inachevées. Effort : M. Risque : faible.

45. **Vérification post-redémarrage guidée** — Sur le poste joint, proposer un parcours unique : relire, comparer, consigner. Bénéfice : fin d'intervention claire. Effort : M. Risque : faible.

46. **Nom suivant intelligent** — Proposer le premier numéro réellement libre dans la série, avec vérification AD immédiate. Bénéfice : moins de bascules et moins de tickets bloqués. Effort : M. Risque : moyen.

47. **Catalogue de services par site** — Suggérer les services observés et déclarés pour le site choisi. Bénéfice : moins d'erreurs de code service. Effort : M. Risque : faible.

48. **Analyse de conformité nom/OU** — Comparer site du nom, OU réelle, doublons, anomalies. Bénéfice : audit rapide du parc. Effort : M. Risque : moyen.

49. **Pause et reprise de lot** — Permettre de mettre en pause après pilote ou incident, puis reprendre ligne par ligne. Bénéfice : contrôle opérationnel renforcé. Effort : M. Risque : moyen.

### Configuration et administration

50. **Assistant de configuration avec validation AD** — Vérifier domaine, OU, droits, sites, préfixe, compte, DC. Bénéfice : évite une configuration fausse au démarrage. Effort : L. Risque : moyen.

51. **Diff de configuration avant enregistrement** — Montrer les clés modifiées, valeurs avant/après, impact métier. Bénéfice : l'administrateur ne sauvegarde pas une erreur par inadvertance. Effort : M. Risque : faible.

52. **Éditeur POLICY dans l'interface** — Gérer exclusions, MaxBatch, MaxReaders, ReadAttempts, coordination, compte précréé. Bénéfice : administration sans éditer JSON à la main. Effort : M. Risque : moyen.

53. **Page « Santé système »** — Contrôler PowerShell 5.1, AD, DNS, DC, ACL, manifeste, reçus, disque, réseau. Bénéfice : diagnostic centralisé avant intervention. Effort : M. Risque : faible.

54. **Audit des changements de configuration** — Journaliser qui a changé quoi, quand, avant/après. Bénéfice : traçabilité administrative. Effort : M. Risque : moyen.

55. **Gestion de versions visible** — Afficher version, SHA256, date, mode, chemin de configuration. Bénéfice : contrôle du livrable déployé. Effort : S. Risque : faible.

56. **Modèles de configuration approuvés** — Import/export de cfg.json validés par l'administrateur. Bénéfice : déploiement reproductible. Effort : M. Risque : moyen.

57. **Contrôle ACL intégré** — Bouton pour vérifier ACL de l'installation et afficher les droits effectifs. Bénéfice : sécurité vérifiable sans PowerShell manuel. Effort : S. Risque : faible.

58. **Sauvegarde automatique de la configuration** — Conserver .bak versionnés avec empreinte et date. Bénéfice : retour arrière rapide. Effort : S. Risque : faible.

59. **Monitoring des interventions à vérifier** — Compteurs sur accueil : redémarrages dus, effets partiels, incertains, déplacements à reprendre. Bénéfice : supervision quotidienne. Effort : M. Risque : faible.

60. **Profils de politique par site ou organisme** — Permettre des règles différentes par périmètre. Bénéfice : administration plus fine. Effort : L. Risque : moyen.

### Qualité et tests

61. **Page « Tests visibles » dans l'interface** — Boutons de test : lecture site, nom libre, DC, réplication, lot pilote, ACL. Bénéfice : l'administrateur teste dans la vraie interface. Effort : M. Risque : moyen.

62. **Scénario multi-contrôleurs** — Tester avec deux DC, réplication lente, création simultanée, nom pris. Bénéfice : couvre le réseau réel signalé par les techniciens. Effort : L. Risque : moyen.

63. **Test de concurrence sur les noms** — Deux techniciens préparent la même série et doivent obtenir des noms différents. Bénéfice : valide la coordination. Effort : M. Risque : moyen.

64. **Test du code 97** — Injecter une perte de réponse après demande, vérifier qu'aucune relance n'est proposée. Bénéfice : protège la règle « résultat incertain n'est jamais succès ». Effort : M. Risque : moyen.

65. **Test du code 89** — Renommage réussi, déplacement échoué, puis reprise du déplacement seul. Bénéfice : valide la reprise sans rejouer le renommage. Effort : M. Risque : moyen.

66. **Test du code 32** — Déplacement fait mais protection non rétablie, puis réparation admin. Bénéfice : sécurise les objets protégés. Effort : M. Risque : moyen.

67. **Test de lot à 200 postes** — Vérifier préparation, contrôle AD, pilote, arrêt, reprise, bilan. Bénéfice : confirme la capacité réelle des lots. Effort : M. Risque : moyen.

68. **Test d'accessibilité** — Narrateur, navigation clavier, contraste élevé, focus visible. Bénéfice : interface utilisable par tous. Effort : M. Risque : moyen.

69. **Test en RDP** — Vérifier UAC, AskCredential, rendu, fenêtres modales, échelles. Bénéfice : couvre le support à distance. Effort : M. Risque : moyen.

70. **Test des échelles d'affichage** — Tester 100 %, 125 %, 150 %, 200 % sur tous les parcours critiques. Bénéfice : évite les boutons coupés ou illisibles. Effort : S. Risque : faible.

### Mes 10 priorités

1. **Panneau « Pourquoi c'est bloqué »** : réduit immédiatement les appels techniciens.
2. **Confirmation avec diff AVANT/APRÈS** : renforce la confiance avant écriture.
3. **Conscience de la réplication** : répond directement au problème réseau multi-DC.
4. **Réservation atomique des noms** : empêche les doublons entre techniciens.
5. **Idempotence par GUID et OU** : protège la règle « ne jamais rejouer une opération confirmée ».
6. **Assistant de configuration avec validation AD** : évite les erreurs de mise en service.
7. **Page « Santé système »** : donne un diagnostic clair avant intervention.
8. **Page « Tests visibles »** : rend la qualification vérifiable dans la vraie interface.
9. **Scénario multi-contrôleurs** : couvre le cas réel le plus risqué.
10. **Workflow dédié au code 97** : sécurise les résultats incertains sans relance dangereuse.
