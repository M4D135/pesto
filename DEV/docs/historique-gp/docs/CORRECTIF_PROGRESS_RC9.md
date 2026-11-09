# GP 17.0-RC9 : progression et attente de renommage

## Ce qui est établi, et ce qui ne l'est pas

Le journal fourni s'arrête après le contrôle local du journal d'audit, sans résultat de mutation. Il montre que le poste source est aussi celui qui exécute GP et que son processus n'est pas élevé. Il ne permet pas d'affirmer que Rename-Computer a démarré, qu'il a échoué ou qu'il a réussi.

Dans le source RC8, les traces internes de QueueAction étaient conservées jusqu'à la fin du worker. Le chemin d'élévation locale utilisait un runspace MTA, comme les lectures AD. Le helper pouvait attendre sa connexion jusqu'à 120 secondes, puis une réponse jusqu'à 600 secondes, sans étapes visibles. La demande QueueAction n'avait pas de délai global de supervision.

RC9 corrige cette absence de visibilité et sépare le thread du chemin d'élévation. L'UAC reste une hypothèse pour l'attente observée : le journal existant ne désigne pas la commande bloquée. Ce correctif n'est pas une preuve qu'un service AD/RPC ou qu'une politique de sécurité est fonctionnel.

## Si la RC8 est encore en cours

Ne pas relancer la ligne, redémarrer le poste ou tuer le helper sur la seule base du chronomètre. « Arrêter après cette action » arrête l'enchaînement, pas la commande Windows déjà engagée.

Le mini-paquet de diagnostic peut être extrait dans le dossier GP pendant que cette instance reste ouverte. Il ne contient ni moteur ni configuration. Après déblocage des fichiers approuvés, lancer **ETAT_RENOMMAGE.cmd**.

Ce diagnostic lit le nom Windows actif et celui inscrit pour le prochain démarrage, les PID PowerShell visibles, la fin du journal Windows NetSetup.log et la fin du journal GP de cette installation. Il ne modifie ni nom, ni domaine, ni OU et ne termine aucun processus. Il écrit un rapport local et l'ouvre dans le Bloc-notes. Il ne collecte pas les arguments de ligne de commande des processus.

Un nom inscrit différent du nom actif invite à vérifier un changement déjà enregistré, pas à relancer. Des noms identiques ne prouvent pas que toute commande est terminée. La liste des PID n'attribue pas avec certitude un processus à GP. Ce diagnostic ne contrôle pas AD : vérifier aussi l'identité/GUID de l'objet et son OU.

**N'appliquer le moteur RC9 qu'après vérification de l'opération déjà en cours et fermeture normale de GP.** Modifier le fichier sur disque ne corrige pas l'instance chargée en mémoire.

## Changements intégrés

- QueueAction utilise explicitement STA ; les lectures conservent MTA par défaut. Le helper élevé est lancé avec -STA et une fenêtre normale. Le contrôle du PID connecté au pipe est conservé avant toute transmission de credential. Aucun secret n'est ajouté aux arguments de lancement.
- Les étapes sont transmises au Dispatcher via une file concurrente, sans accès WPF depuis le worker. Chargement AD, précontrôle, demande UAC, connexion au helper, commande Windows et attente AD sont distingués. Le pied de page indique l'étape, son temps écoulé et, quand disponible, le PID du helper.
- Un rappel de l'étape est écrit au journal toutes les 15 secondes tant que la file est suivie. Ce rappel prouve que l'interface supervise toujours ; il ne prouve pas une progression du service Windows.
- Le helper qui quitte avant communication est signalé sans attendre aveuglément la fin des 120 secondes. L'attente de réponse est interrogée périodiquement, au lieu d'un unique Wait de dix minutes.
- La supervision d'une action expire après **300 secondes**. Son résultat devient **INCERTAIN**, le reste de la file n'est pas lancé et un verrou est conservé. Un retour tardif est journalisé mais ne transforme pas automatiquement le résultat en succès.
- Une barrière coopérative bloque l'admission des étapes suivantes après expiration. Elle n'interrompt pas une commande native déjà admise ou en cours. Aucun BeginStop ni Kill n'est imposé au worker de mutation. La restauration de protection AD dans finally reste autorisée.
- Le worker toujours actif reste suivi, ne peut pas être remplacé par une seconde QueueAction et empêche la levée du verrou. Un helper séparé peut continuer même après le retour du worker ; il faut toujours vérifier son état et celui du poste manuellement.
- Le bilan distingue les actions à vérifier des échecs confirmés et n'annonce pas la fin de Windows quand un worker est encore actif.
- Pas de test réseau ping pour renommer le poste qui exécute GP. Les lectures et contrôles AD préalables sont conservés.

**300 secondes est une limite de supervision, pas une garantie d'annulation Windows.** L'application reste une application cliente : une commande native, un helper ou une tâche distante peut encore travailler. Aucun effacement automatique des verrous n'est ajouté. La fermeture du programme n'est pas une preuve d'annulation.

## Règles et fichiers conservés

Changement de site : renommage, puis déplacement après confirmation du renommage et vérifications AD. Même site : renommage seul. Aucun redémarrage implicite. GUID, périmètres et gestion de la protection anti-suppression sont conservés. Les fenêtres, la saisie de connexion et le retrait de file restent ceux de RC8, hors numéro de version.

La mise à jour ne contient aucun cfg*.json, DLL AD, état de file ou journal d'utilisateur. Le pack complet conserve les configurations d'origine du projet, qui ne sont pas celles éventuellement corrigées dans votre installation : **remettre votre propre wad/cfg.json**.

## Installation et recette

1. Attendre/vérifier l'issue de l'ancienne opération, puis fermer GP normalement et sauvegarder le dossier.
2. Extraire le correctif à côté du GP.cmd existant, accepter les remplacements. Ne pas créer un second dossier GP imbriqué.
3. Exécuter DEBLOQUER_TOUT.cmd sur les fichiers que vous approuvez, puis TEST_PROGRESS.cmd et TEST_TOUT.cmd. Un échec de test doit être examiné avant toute utilisation réelle.
4. Lancer GP.cmd et vérifier **17.0-RC9**. GP.cmd -Demo ne modifie pas AD, mais ne teste pas l'UAC ni la commande réelle.
5. Sur un poste de recette, vérifier d'abord le résultat de l'opération précédente. Ne pas rejouer un résultat INCERTAIN. Tester un renommage sur même site, puis un changement de site, avec et sans élévation initiale et sans redémarrage demandé.

Attendre les transitions visibles. « Autorisation Windows attendue » désigne la demande UAC ; « Connexion au helper élevé » précède l'envoi des identifiants ; « Renommage ou jonction dans Windows » signifie que la transmission est engagée, pas que le renommage est déjà réussi. « Attente du nouveau nom dans AD » suit un résultat Windows confirmé. Une fenêtre UAC n'est à valider que si elle correspond à l'action explicitement demandée et aux règles de votre organisation.

## Validation réellement disponible

Les contrôles lexicaux/XML, les contrats statiques et les vérifications d'archive sont exécutés dans l'environnement de livraison. Ils ne sont pas un parseur PowerShell natif et ne prouvent pas un fonctionnement Windows.

**21 nouveaux cas Windows isolés** sont fournis dans tests/Run-ProgressTests.ps1 : parseur natif, vrais runspaces STA/MTA, timers WPF, traces avant la fin du worker, expiration, retour tardif et barrière coopérative. Ils ne déclenchent ni élévation, ni commande AD réelle.

**Ces tests Windows n'ont pas été exécutés ici. Ni WPF réel, ni UAC, ni renommage/déplacement dans votre domaine ne sont validés ici.** Le workflow GitHub et le script de compilation sont fournis, pas exécutés. Aucun nouvel EXE compilé n'est livré.
