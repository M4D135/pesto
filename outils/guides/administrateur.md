# 1 Périmètre et prérequis de Pesto 1.0

Ce guide explique comment installer, configurer et exploiter Pesto 1.0 pour joindre un PC à un domaine Active Directory, renommer les postes et déplacer leurs objets dans les OU autorisées. Il décrit les contrôles, la conservation des reçus et les procédures de reprise. Le guide technicien accompagne les gestes quotidiens.

Pesto fonctionne sous Windows x64 avec Windows PowerShell 5.1 Desktop. Le lancement interactif utilise un jeton administrateur local. Les droits AD et les accès d'administration distante restent ceux du compte choisi ; le logiciel ne les accorde pas.

| Élément | Règle de fonctionnement |
|---|---|
| Distribution | Deux packs classiques : DEV pour les sources et les outils ; PROD pour Pesto.exe et le dossier wad. |
| Configuration | wad\cfg.json est un fichier JSON accessible normalement. Le paquet neutre demande l'import ou la création d'une configuration approuvée. |
| Mise au domaine | Concerne seulement le PC local hors domaine, avec un compte AD explicite. Aucun retrait d'un domaine existant. |
| Renommage | Un poste à la fois ou un lot séquentiel. Même code site : renommage seul, OU conservée. |
| Changement de site | Renommage, puis déplacement seulement après confirmation du renommage. |
| Choix du nom | Tirage activé par défaut parmi tous les candidats libres des filtres actifs. Disponibilité revérifiée avant l'action. |
| Options partagées | Registre de coordination et réservation AD inactifs par défaut, à qualifier avant activation. |
| Task sequence | Jonction silencieuse désactivée par défaut ; préparation en lecture seule, engagement seulement avec -Execute. |
| Suivi | Reçus conservés. Contrôle facultatif après une opération terminée ; les états en cours, incertains ou partiels restent protégés. |

Le contrôleur est découvert par Windows avec les services nécessaires ; Pesto ne force pas l'émulateur PDC. Les délais de réplication, les politiques Windows et les droits délégués doivent être pris en compte dans le pilote de déploiement.

> [!ATTENTION] Empreinte. Contrôlez le candidat exact que vous distribuez avec son manifeste wad\package.json et son EXE. Une empreinte confirme la cohérence du paquet ; elle ne remplace ni la provenance approuvée ni la qualification sur votre parc.

# 2 Démarrage rapide

Ces étapes mettent Pesto 1.0 en service. Chaque ligne renvoie au chapitre qui la détaille. Ne sautez pas l'étape 7 : un poste livré en simulation ou en démonstration ne modifie rien.

| Étape | Action | Chapitre |
|---|---|---|
| 1 | Vérifier la plateforme Windows, le réseau et les droits AD délégués. | 10 |
| 2 | Contrôler l'empreinte du livrable (Pesto.exe, Pesto_PROD.zip). | 11 et 26 |
| 3 | Extraire Pesto.exe et wad dans C:\Program Files\Pesto, puis contrôler les ACL. | 11 |
| 4 | Lancer Pesto.exe --check puis Pesto.exe --check-json. | 11 et 24 |
| 5 | Importer ou créer cfg.json, jamais celui de la démonstration. | 12 et 14 |
| 6 | Choisir le placement : production directe ou OU de préparation, codes des sites. | 3 et 13 |
| 7 | Mettre DEBUG.GUI et DEBUG.Simulation à false, puis relancer Pesto. | 9 |
| 8 | Écrire la politique POLICY : exclusions, options, taille des lots. | 15 |
| 9 | Vérifier que chaque poste du banc joint un contrôleur de domaine (DNS, flux AD) ; prévenir les techniciens du délai de réplication. | 8 |
| 10 | Qualifier les options activées, puis mener un pilote sur un périmètre dédié. | 18 et 25 |

# 3 Mise au domaine : fonctionnement et règles

La page « Ajouter au domaine » joint le PC sur lequel Pesto tourne, et lui seul. Elle ne passe jamais par la file et ne retire jamais un PC d'un domaine. Chaque étape est contrôlée, confirmée puis tracée dans un reçu ; le redémarrage reste un geste explicite.

## Deux circuits de placement

Le réglage DirectProd décide où le PC est joint. La configuration impose ce choix : le technicien ne peut pas le contourner.

| Réglage | Où le PC est joint | Bandeau affiché |
|---|---|---|
| DirectProd=true | Dans l'OU de son site : l'OU portant le nom du site, sous l'OU qui contient les sites de l'organisme (OUSite). | « Production directe autorisée par la configuration. » |
| DirectProd=false | Dans l'OU PREPROD déclarée dans OUBase. Organisme et site sont fixés à PREPROD, le service à la valeur de PreprodSite. | « Zone de préparation imposée par la configuration. Le nom utilise le site PREPROD et son service configuré. » |

Le moteur refuse un plan qui sort de la zone de préparation : « La configuration impose la zone de préparation. ». Le PC rejoint ensuite son OU définitive par un renommage avec changement de site (chapitres 4 et 5).

> [!NOTE] Sans production directe, un motif de TAGS doit couvrir PREPROD ou le code de PreprodSite. Sinon la configuration est refusée (chapitre 13).


## Liste des services

Le champ « Service · 3 caractères » propose les services connus du site choisi. Ce sont ceux des postes conformes rangés sous l'OU du site ou portant son code site. Un nouveau code (3 lettres ou chiffres par défaut) reste saisissable ; Pesto le met en majuscules.

Dès le choix du site, ici comme dans « Un seul poste », Pesto lit dans l'AD les seuls postes de ce site : noms qui commencent par le code du site dans tout le domaine, et postes de l'OU du site. Cette lecture remplit la liste des services et écarte les numéros déjà pris. Sa durée dépend de l’annuaire et du réseau. Le cache de site est réutilisable pendant 120 secondes ; son âge et une lecture incomplète sont signalés. « Actualiser le site » relance une lecture ciblée et conserve les choix encore valides. Après une intervention, Pesto demande une relecture ciblée des données concernées.

Hors domaine, l'inventaire complet des postes est aussi lu en arrière-plan, en lecture seule, à l'ouverture de la page et au choix d'un site, jamais pendant un traitement actif (jonction, action directe ou file en cours). À son arrivée, la liste et les noms se complètent sans effacer la saisie. La liste indique chargement, lecture partielle ou échec, ainsi que l’âge des données précédentes. Une saisie libre reste possible. Le Journal conserve le détail de l’échec.

La liste « Nouveau nom proposé » contient des noms absents du cache, de la lecture ciblée du site et de la file. Leur disponibilité réelle est relue dans l'AD juste avant l'ajout.

## Ce que contrôle « Vérifier sans ajouter »

Ce bouton relit le PC, le domaine, l'OU et le nom sans lancer Add-Computer. La liste des contrôles comprend notamment « Ce PC », « Formulaire », « Élévation locale », « Domaine », « Compte AD », « Emplacement réel », « Nouveau nom », « Compte précréé » et « Opération précédente ».

Le réglage facultatif POLICY.BlockJoinOnClockSkew, désactivé par défaut, ajoute une observation d’horloge avant jonction. Un décalage effectivement mesuré d’au moins cinq minutes en valeur absolue bloque l’ajout. Une mesure indisponible donne un avertissement. Pesto ne règle jamais l’heure.

Si tout est conforme, Pesto affiche « Vérifications préalables réussies » et précise : « Les droits d'écriture seront évalués par Windows au moment de l'ajout. ». Sinon, il affiche « Ajout non lancé » : « Corrigez les points indiqués ci-dessous. Aucun objet AD n'a été modifié. ».

> [!NOTE] Pourquoi lire d'abord. Une lecture réussie prouve la cohérence du domaine, de l'OU et du nom à cet instant. Elle ne prouve ni les droits d'écriture, ni que le nom sera encore libre au moment de l'écriture.

## Revérification du nom et nom suivant

L'inventaire est une photographie. Un collègue peut prendre le même nom entre la lecture et l'action. Pesto relit donc le nom dans l'AD juste avant d'agir.

1. **Nom pris.** Rien n'est fait sous ce nom. Pesto l'écarte pour la session et affiche « Nom déjà pris : nom suivant proposé ».
2. **Nom suivant.** Pesto lit dans l'AD, en une seule requête, tous les noms déjà utilisés de la même série (mêmes type, département, site et service). Il propose un candidat parmi tous les libres du filtre si le tirage est activé, ou le premier numéro libre si ce réglage est désactivé. Le nouveau nom est annoncé puis revérifié ; sa confirmation reste obligatoire.
3. **Nouvelle confirmation.** La fenêtre « Vérifier avant de confirmer » se rouvre avec ce nom. Le bouton par défaut est « Annuler ».
4. **Inventaire arrivé entre-temps.** Hors domaine, l'inventaire se charge en arrière-plan. S'il arrive pendant la vérification et change le nom proposé, Pesto revérifie aussitôt le nouveau nom (trois fois au plus), sans nouveau clic.
5. **Limite.** Au-delà de cinq noms pris d'affilée, Pesto s'arrête sur « Plusieurs noms déjà pris » : « Cinq noms de suite étaient pris : actualisez l'inventaire (Noms disponibles) puis choisissez un nom. ».

> [!RESULTAT] Aucune opération n'est lancée sous un nom que le technicien n'a pas confirmé.

## Compte ordinateur précréé

Par défaut, Pesto ne joint jamais un PC sous un nom déjà présent dans l'AD. Le contrôle « Nouveau nom » le signale (« Nom déjà utilisé. Aucun objet supprimé. ») et Pesto propose le nom suivant (section précédente). Pesto ne supprime jamais un objet pour libérer un nom.

Avec AllowPrecreatedJoin=true dans POLICY, la case « Utiliser un compte ordinateur précréé » apparaît. Sans cette politique, elle reste masquée. Cochée, elle rend le nom saisissable et coupe la proposition du nom suivant. Règles :

- Le compte doit exister exactement dans l'OU choisie.
- Pesto l'identifie par son GUID, puis le recontrôle avant l'engagement. Un changement arrête tout : « Identité de l'OU, du compte précréé ou du PC modifiée depuis confirmation. Aucun ajout lancé. ».
- Pesto ne change ni le propriétaire ni les droits du compte. Windows applique ses propres règles de jonction (Netjoin) au moment de l'ajout.

Qualifiez ces règles de réutilisation sur votre domaine avant d'activer l'option (chapitre 18).

## Compte et droits

Hors domaine, le technicien saisit un compte AD explicite, affiché dans « Compte utilisé pour AD ». La fenêtre de connexion reste au premier plan pendant la saisie. Ce compte et le jeton administrateur local (UAC) sont deux contrôles distincts. Sans jeton administrateur, la jonction n'est pas lancée (code 96).

Le compte AD doit pouvoir créer ou réutiliser le compte ordinateur dans l'OU cible. La délégation se prépare au chapitre 10.

## Confirmation

Après les contrôles, la fenêtre « Vérifier avant de confirmer » récapitule le plan. Elle affiche le mode (« AJOUT RÉEL » ou « SIMULATION »), « Ce PC », « Nouveau nom », « Domaine », « Emplacement », puis « Aucun retrait Entra. Aucun redémarrage automatique. » et « Confirmer l’ajout ? ».

- « Annuler » est le bouton par défaut. Il affiche « Ajout annulé avant lancement » : le brouillon est conservé, aucune opération n'est lancée.
- Si le formulaire a changé pendant la confirmation, Pesto affiche « Le plan a changé » et demande une nouvelle vérification.

## Reçu de jonction

Pesto écrit un reçu local, %ProgramData%\GP\Join\receipt.json, avant toute commande Windows. La politique est contrôlée avant cette écriture. Le code 96 indique qu'aucune commande n'a été lancée.

Si le nom change, Pesto prépare d'abord le nom local avec Rename-Computer et vérifie le nom configuré. Il demande ensuite la jonction avec Add-Computer et les options JoinWithNewName et AccountCreate. Windows utilise ainsi le nom préparé pour l'ajout, sans joindre d'abord l'ancien nom.

Dès qu'une préparation du nom a été demandée, un échec ou une réponse incomplète reste en 97 : un renommage peut attendre le prochain démarrage, même si la jonction a été refusée. Le reçu bloque une seconde jonction. Vérifiez les noms actif et configuré, le domaine, l'objet AD et le reçu avant toute reprise (chapitre 20). Ne supprimez pas le reçu et ne rejouez pas l'ajout à l'aveugle.

## Résultats possibles

| Code | Sens | Conduite |
|---|---|---|
| 10 | Jonction acceptée, redémarrage requis. | Redémarrer ; contrôle complémentaire facultatif (chapitre 6). |
| 11 | Jonction refusée. | Lire le motif, corriger, refaire « Vérifier sans ajouter ». |
| 13 | Compte AD déjà existant. | Vérifier l'objet. Le compte précréé n'est admis que si la politique l'autorise. |
| 96 | Rien n'a été lancé. | Lire le motif, corriger la cause, refaire le contrôle. |
| 97 | Résultat incertain. | Ne rien relancer. Suivre le chapitre 20. |

## Redémarrage

Pesto ne redémarre jamais le poste seul. Après une jonction acceptée, deux boutons s'offrent au technicien :

- « Redémarrer maintenant » demande le redémarrage après confirmation, sans redémarrage forcé.
- « Plus tard » reporte le redémarrage. Le reçu reste enregistré ; tant que le nom ou la jonction attend le redémarrage, une nouvelle mutation est refusée.

## Vérification et canal sécurisé

Après un nouveau démarrage, Pesto relit l’identité du PC, les noms Windows courants, le domaine et le canal sécurisé. Si le PC et le domaine correspondent au reçu et que les noms courants concordent, avec un canal confirmé, le reçu ne bloque plus les opérations suivantes. Un renommage ultérieur légitime n’impose pas de revenir au nom de la jonction. Le reçu est conservé sans devenir « Windows / AD vérifié ». Une divergence ou un retour en groupe de travail restent à examiner.

La vérification complémentaire est facultative. La jonction se vérifie sur le PC joint, après redémarrage, par « Vérifier dans AD » (« Vérifier l’état » relit seulement l'état Windows et le reçu, sans rien consigner). Pesto compare l'identité locale du PC à celle du reçu. Depuis un autre PC, il refuse : « Cette jonction doit être vérifiée depuis le PC concerné. Identité locale non confirmée. ».

Le démarrage est établi à partir de l'événement Windows Kernel-General 12 du journal Système. Il doit être postérieur à la demande de jonction ; une correction de l'horloge ne vaut pas redémarrage. Si cet événement est absent ou illisible, Pesto refuse de conclure : conservez le reçu et faites contrôler le journal par l'administrateur.

Le canal sécurisé est le lien de confiance entre le poste et le domaine. Pesto le contrôle contre le contrôleur de domaine du plan. S'il n'est pas confirmé, Pesto le dit et ne répare rien : « Le canal sécurisé local n'est pas confirmé. Aucune réparation automatique. ».

> [!RESULTAT] Message d'une jonction vérifiée : « Nom actif, domaine, identité du PC, compte AD, emplacement et canal sécurisé confirmés après redémarrage. Entra reste un contrôle distinct. ». La consignation suit au chapitre 6.

## Le parcours après vérification

![Autre exemple, jonction vérifiée : le nom exécuté et l’emplacement restent affichés.](fig:jonction-verifiee)

La page rappelle le nom enregistré et la dernière vérification. Le champ de proposition ne tire plus un autre nom pour cette demande. « Vérifier dans AD » ouvre une nouvelle observation ; aucune seconde jonction n'est lancée depuis ce poste déjà membre du domaine.

# 4 Renommage : fonctionnement et règles

La page « Un seul poste » renomme un poste déjà dans le domaine, un seul à la fois, sans passer par la file. Si le code site du nom ne change pas, Pesto renomme seulement : l'objet reste dans son OU. Un renommage accepté rend le code 20 et attend un redémarrage. Le changement de site est traité au chapitre 5.

## Contrôles avant le renommage

Le bouton « Vérifier puis renommer » relit le plan dans l'AD, affiche le récapitulatif puis attend la confirmation. Le moteur refuse les cas suivants :

| Situation | Code | Ce que dit Pesto |
|---|---|---|
| Nouveau nom identique au nom actuel | 96 | « Nom actuel identique au nom demandé : aucun renommage lancé. Ce cas n'est jamais un succès de renommage. » |
| Nouveau nom hors convention | 21 | Nouveau nom hors convention. |
| Poste absent de l'AD | 99 | Poste source absent de l'AD. |
| Poste hors du périmètre configuré | 21 | Poste source hors périmètre configuré. |
| GUID ou OU changés depuis le contrôle | 21 | Motif du changement d'identité. |
| Nom pris dans l'AD | 69 | Le nom est déjà utilisé. |

Avant le renommage, une lecture du même contrôleur recherche aussi le nom DNS cible et les SPN HOST/RestrictedKrbHost, courts et complets. Un conflit avec un autre objet AD, ou une lecture impossible, empêche le lancement ; aucun SPN n’est corrigé automatiquement.

Le précontrôle expire après 120 secondes. Pesto vérifie encore son âge lorsque vous confirmez : si le délai est dépassé ou si l’horodatage est incohérent, aucune opération ne part. Relancez le contrôle puis confirmez le plan à nouveau.

## Revérification du nom

Le renommage direct suit la même protection que la jonction (chapitre 3). Un nom pris juste avant l'action est écarté. Pesto affiche « Nom déjà pris : nom suivant proposé. », revérifie le nom suivant et redemande confirmation. Au-delà de cinq bascules : « Plusieurs noms déjà pris. ».

## Poste local et poste distant

Le poste local se renomme avec le compte Windows élevé. Ce compte doit être un compte du domaine avec un jeton administrateur local. Les contrôleurs de domaine sont exclus.

Pour un poste distant, le jeton UAC ne fournit pas de mot de passe à déléguer. Lancez Pesto.exe -AskCredential pour ce parcours, qui utilise RPC avec des identifiants explicites. Sinon, le renommage distant n'est pas lancé (code 96).

- « Vérifier seulement » lit l'identité du poste, le nom et l'OU, sans rien modifier. Une lecture réussie ne certifie pas les droits d'écriture.
- Le ping est indicatif : le renommage est tenté même si ICMP est filtré. WinRM n’est pas requis : l’identité distante utilise CIM via DCOM.
- L’identité Windows, le domaine, le rôle et le GUID AD restent contrôlés. Les lectures distantes du nom configuré et de MachineGuid sont facultatives et bornées ; leur indisponibilité seule ne bloque pas le renommage. Un nom en attente de redémarrage effectivement observé bloque encore un nouveau renommage.
- La touche Entrée dans le champ du nom lit le poste ; elle ne renomme jamais.

## Après le renommage

Avant le redémarrage, le nom Windows actif et le nom configuré diffèrent. C'est normal. Un second renommage pour « corriger » ce décalage est interdit. Après le redémarrage, le reçu d’une commande terminée n’impose pas de consignation pour commencer une autre opération ; les contrôles Windows et AD sont refaits. Le contrôle complémentaire du chapitre 6 reste disponible.

## Entra hybride

Avant chaque renommage, Pesto relit l'état Entra. Le retrait exige un poste hybride et EntraPolicy=HybridOnly.

| État de la cible | Ce que fait Pesto |
|---|---|
| AD seul | Aucun retrait Entra. |
| Hybride, EntraPolicy=HybridOnly | Retrait (dsregcmd /leave), contrôle puis renommage. Réinscription à vérifier séparément. |
| Hybride, EntraPolicy=Disabled | Renommage refusé ; retrait préalable interdit. |
| État illisible ou ambigu | Arrêt sans retrait ni renommage. |

À distance, le contrôle et le retrait éventuel utilisent une tâche planifiée sous SYSTEM, pilotée par RPC, sans WinRM. Le programme dsregcmd s’exécute sur la cible. Un refus confirmé avant lancement ou avant retrait est signalé sans annoncer de mutation. Après un lancement dont l’issue reste inconnue, le résultat reste incertain (97), la tâche est conservée et aucune répétition automatique n’est effectuée : consultez le reçu cible avant toute reprise.

> [!ATTENTION] Sans EntraPolicy dans cfg.json, le moteur retient HybridOnly. Déclarez Disabled pour interdire le retrait. Qualifiez le parcours hybride et sa réinscription dans votre environnement (chapitre 18).

La jonction et le déplacement seul ne demandent jamais de retrait Entra.


# 5 Déplacement et changement de site

Un changement de site change le code site du nom, donc l'OU. Pesto renomme d'abord, puis déplace l'objet dans l'OU du nouveau site, seulement après confirmation du renommage. Le déplacement seul sert à changer d'OU sans changer de nom, et à reprendre un code 89.

## Renommage puis déplacement


L'aperçu de « Un seul poste » compare les emplacements de départ et de destination. Le récapitulatif de confirmation indique le nom final, l'OU cible et les contrôles effectués.

| Code | Sens |
|---|---|
| 77 | Renommage et déplacement réussis, redémarrage requis. |
| 88 | Nom déjà pris (renommage avec déplacement). |
| 89 | Renommage confirmé, déplacement à reprendre. |


![Avant confirmation : relire le nom, la destination et les limites du contrôle.](fig:confirmation)

## Déplacement seul

Le technicien déplie « Options : déplacement seul et redémarrage », décoche « Renommer » et coche « Déplacer ». Le bouton principal devient « Vérifier puis déplacer ». La case « Déplacer » est désactivée si le poste est déjà dans l'OU cible.

Ce parcours ne joint pas le poste au domaine et ne lance pas de retrait Entra. Un résultat 30 signifie déplacement vérifié ; 33 signifie que l'objet était déjà dans l'OU cible.

![Déplacement seul : le plan conserve le nom du PC.](fig:deplacer-seul)

## Comment Pesto déplace

- Pesto déplace l'objet par son GUID, celui du plan confirmé. Un GUID différent arrête tout : « Le plan confirmé ne possède pas l’identité AD observée. Refaire le contrôle. » (96).
- Il note la protection initiale de l'objet. Si elle est illisible : « Protection initiale AD non confirmée. » (96).
- Après la demande, il relit l'objet par son GUID. Il consigne le déplacement observé avant de contrôler la protection.
- Si la relecture finale échoue, le résultat est incertain (97).

## Protection contre la suppression accidentelle

Un objet protégé ne se déplace pas sans lever sa protection. Le réglage ClearProtectionOnMove décide si Pesto peut la lever temporairement.

| Situation | Résultat |
|---|---|
| Objet protégé, ClearProtectionOnMove=true | Levée, déplacement, rétablissement, puis relecture. 30 si tout est conforme. |
| Objet protégé, ClearProtectionOnMove=false | 31 : « Objet protégé ; levée temporaire interdite par la configuration. » |
| Rétablissement en échec | 32 : protection non rétablie. Le déplacement observé reste consigné. |
| Déplacement refusé, objet resté dans l'OU source | 31 : protection d'origine conservée. |

Si ClearProtectionOnMove est absent, le moteur retient true. L'assistant de configuration écrit false. Décidez explicitement de cette politique.

## Code 32 : rétablir la protection

Le déplacement est confirmé, mais la protection n'a pas été rétablie. Il faut réparer la protection, pas déplacer l'objet une seconde fois. Ce geste est réservé à l'administrateur.

1. **Vérifier la valeur initiale.** Le reçu doit documenter la cible et la protection avant action. Confirmez le GUID et l'absence de tâche incompatible. Si la valeur initiale manque ou si l'incident est ambigu, passez au diagnostic manuel encadré.
2. **Corriger la cause.** Rétablissez les droits ou l'accès qui ont empêché la restauration.
3. **Rétablir.** Dans « Pesto · Interventions », ouvrez « Détails et outils », puis « Entretien » et « Rétablir la protection ». La commande répare uniquement un code 32 documenté, selon la valeur initiale enregistrée. Confirmation et relecture sont obligatoires.
4. **Consigner.** Relisez l'état puis consignez la vérification complète (chapitre 6).

## Code 89 : reprendre le déplacement seul

Le renommage est confirmé, le déplacement reste à faire. Rejouer le renommage est interdit.

1. **Relire.** Rétablissez l'accès au poste et au contrôleur. Dans « Un seul poste », utilisez le bouton principal « Vérifier l'opération ». Vous pouvez aussi ouvrir « Historique », « Interventions et reprises », sélectionner le poste, puis « Vérifier l’état du poste ». Pour une ligne de lot, « Vérifier puis reprendre » se trouve dans « Outils de la file », onglet « Suivi ». Ces commandes ouvrent l’observation, sans rejouer le renommage.
2. **Préparer la reprise.** Si le renommage est confirmé, la fenêtre d'état propose « Préparer le déplacement restant ». Une reprise de déplacement n'est jamais proposée sans renommage confirmé.
3. **Déplacer.** Le bouton principal annonce « Vérifier puis déplacer seulement ». Relisez les identités et la destination dans le nouveau récapitulatif, puis confirmez.
4. **Lire le résultat.** Examinez l’intervention enfant et l’intervention parente. Redémarrez si le plan initial le demande. Quand le renommage et le déplacement sont confirmés et la protection rétablie, le contrôle complémentaire est facultatif.

> [!NOTE] Aucune reprise automatique. Des noms identiques à l'ancien état ne prouvent pas l'annulation. Un résultat tardif d'une reprise ne résout pas le parent : seul un résultat à temps et vérifié (30 ou 33) le fait. Le code initial 89 ou 97 peut rester affiché après une reprise réussie : il garde la trace de l'incident.

# 6 Vérification après redémarrage et consignation

Après une jonction ou un renommage accepté, le contrôle complémentaire après redémarrage et sa consignation sont facultatifs. Leur absence n’impose pas un passage par le suivi avant une nouvelle opération au lancement suivant. Le reçu est conservé avec son résultat ; seul un contrôle explicitement consigné le fait passer à « Windows / AD vérifié ».

Le redémarrage demandé reste nécessaire. Pesto refuse toujours une nouvelle mutation si un nom Windows attend son application, si une opération est en cours, si son résultat est incertain ou partiel, ou si la protection reste à rétablir. Une jonction exige aussi les concordances locales et le canal sécurisé décrits au chapitre 3.

Le contrôle complémentaire relit Windows et l’AD et les compare au plan confirmé. Vous pouvez l’effectuer et conserver sa preuve quand votre procédure d’exploitation le demande.

## Où ouvrir la vérification

| Parcours | Bouton |
|---|---|
| Jonction | « Vérifier dans AD », dans « Ajouter au domaine », sur le PC joint. « Vérifier l’état » relit seulement l'état, sans consigner. |
| Renommage ou déplacement unitaire terminé | « Vérifier l’état (facultatif) », dans le suivi de la page « Un seul poste ». Pour un état encore bloquant, « Vérifier l’opération » ou « Vérifier puis reprendre » conserve le parcours de reprise. |
| Toute intervention | « Historique », puis « Interventions et reprises », puis « Vérifier l’état du poste ». |
| Depuis l'accueil | « Ouvrir les interventions ». |

## La fenêtre « Pesto · État du poste »

| Bouton | Effet |
|---|---|
| « Relire l’état » | Prend une nouvelle observation de Windows et de l'AD. |
| « Conserver cette lecture » | Enregistre l'observation dans le reçu, sans changer le résultat. Proposé depuis les interventions et la vérification d'une jonction. |
| « Consigner la vérification » | Demande une confirmation, recontrôle les conditions, puis met à jour les reçus concordants. |
| « Préparer le déplacement restant » | Remplace « Consigner la vérification » quand la lecture conclut à une reprise de déplacement (code 89). |
| « Fermer » | Ferme sans rien changer. |

## Ce que Pesto compare

- Côté Windows : identité du PC, nom actif et nom configuré, domaine, démarrage postérieur à la préparation.
- Côté AD : GUID et nom de l'objet, OU, protection.
- Pour une jonction : canal sécurisé local, contrôlé contre le contrôleur du plan.

En mode réel, le rapport de la fenêtre ajoute une comparaison « AVANT / PRÉVU / OBSERVÉ ». Une donnée absente reste inconnue : une valeur inconnue n'est jamais une valeur conforme.

![Contrôle facultatif d’une jonction terminée : Windows, AD et canal sécurisé comparés au plan.](fig:etat-verifie)

## Règles de consignation

- Une observation de plus de deux minutes est refusée : « Observation trop ancienne : relisez l'état. ».
- La confirmation précise : « Consigner cette observation et préparer uniquement la suite indiquée ? Aucune commande n’est lancée par cette confirmation. ».
- La consignation est impossible pendant qu'une opération est encore active.
- Elle est grisée en simulation, en démonstration et en consultation.
- Une jonction se consigne sur le PC joint, nulle part ailleurs.
- La résolution met à jour les reçus concordants. Elle ne remplace pas un reçu local appartenant à une autre opération.
- Un résultat tardif ou incomplet reste incertain.

> [!ATTENTION] Si « Consigner la vérification » reste grisé, lisez la condition manquante dans l'infobulle. Ne supprimez jamais un reçu ou un verrou pour débloquer.

![Consignation facultative après renommage terminé : une lecture est enregistrée, sans nouvelle commande.](fig:verification-consignation)

## Entra reste un contrôle séparé

Un nom, une OU et un canal sécurisé conformes ne certifient ni la réinscription Entra ni la connexion unique (SSO) de l'utilisateur. Pour un poste hybride, prévoyez un contrôle distinct.

# 7 Lots et poste pilote

La page « Plusieurs postes » traite des postes déjà dans le domaine, l'un après l'autre, dans une file. La jonction n'y passe jamais. Le poste pilote exécute la première ligne cochée puis arrête le lot : on vérifie son résultat avant le reste.

## Préparer un lot

1. **Faire approuver.** Faites valider les cibles, les règles et une fenêtre de maintenance.
2. **Choisir la destination.** Dans « Plusieurs postes », cliquez sur « Préparer un lot ». Choisissez le site dans « Destination du lot », puis le code service dans « Modèle du lot ». Cette préparation est indépendante du formulaire unitaire. Le type source est conservé par défaut ; si vous décochez cette conservation, le modèle utilise le type portable.
3. **Saisir les cibles.** Collez les postes, un par ligne. Le nombre de postes est borné par MaxBatch (200 au plus).
4. **Choisir les conservations.** Relisez « Conserver le service source », « Conserver le numéro source » et « Conserver le type du nom source ».
5. **Construire le plan.** Cliquez sur « Construire le plan » : Pesto lit les sources et les séries de noms nécessaires en arrière-plan, sur le contrôleur et avec le compte de la session, sans attendre un inventaire complet. Une lecture interrompue ou trop volumineuse refuse l’aperçu. Le tirage applique RandomNameEnabled parmi les candidats libres et écarte les noms déjà préparés dans le lot. « Conserver le numéro source » refuse un conflit au lieu de renuméroter la ligne. Cliquez ensuite sur « Ajouter les lignes décochées » : le plan entre dans la file, sans aucune ligne cochée.

![Outils de la file : modifier, importer, exporter ou retrouver le suivi d'une ligne.](fig:lot)

## Importer et corriger un tableau

1. **Choisir la source.** Ouvrez « Outils de la file », « Import et export », « Importer un tableau… ». Choisissez un CSV UTF-8 ou un tableau Excel copié, avec ses en-têtes. Les séparateurs tabulation, point-virgule et virgule sont reconnus.
2. **Associer.** Associez les colonnes aux champs de préparation. Une action absente reste à false ; aucun accord d’exécution ou redémarrage n’est importé.
3. **Corriger toutes les lignes.** Modifiez les cellules dans l’aperçu, puis « Valider les lignes ». Chaque ligne conserve l’ensemble de ses erreurs ; aucune partie du tableau n’est ajoutée tant qu’une erreur subsiste.
4. **Publier la préparation.** « Ajouter à la file décochée », puis « Appliquer la préparation », ajoute les lignes sans les sélectionner pour exécution. Tout changement après validation impose une nouvelle validation.

Les anciens états et historiques passent par l’import CSV classique. Ils ne sont pas traités comme un nouveau tableau de préparation.

## Modifier et présenter la file

Dans « Outils de la file », onglet « File » :

| Commande | Effet et limite |
|---|---|
| Modifier plusieurs lignes… | Sélection Ctrl+clic des préparations sans résultat ; aperçu éditable, ordre réel conservé, anciens contrôles invalidés. |
| Annuler la préparation | Retour local sur les dix derniers changements éligibles au maximum ; aucune mutation AD n’est annulée. La pile est effacée dès une tentative d’exécution. |
| Vues et colonnes… | Préréglages Essentiel/Diagnostic ; vues nommées de filtres et tri ; regroupement de consultation par site, organisme ou état. |
| Depuis une collection… | Réévaluer les critères d’une collection, lire ses changements puis figer les membres avant de choisir la destination du lot. |

Un regroupement ne change ni l’ordre exécutant ni les cases cochées. Les vues restaurées ne contiennent aucun accord d’exécution.

## Préparer depuis une collection

Dans « Noms disponibles », appliquez site, service, type et recherche, puis ouvrez « Préparation et inventaire », « Inventaire », « Mémoriser la collection… ». La collection concerne les postes déjà observés dans AD, identifiés par GUID ; elle ne transforme pas les noms libres en postes.

Depuis « Plusieurs postes », « Depuis une collection… » réévalue ces critères sur l’inventaire chargé. Relisez les ajouts, les absences du périmètre et les changements de nom ou d’OU. Une absence du périmètre ne prouve pas une suppression. « Choisir la destination du lot » fige la liste affichée ; une modification de l’inventaire ou de la configuration impose une nouvelle préparation. Le domaine, l’empreinte de configuration et MaxBatch restent contrôlés.

## Contrôler avant d'exécuter

- « Contrôler dans AD » contrôle les lignes cochées. Aucune écriture. Ce contrôle ne certifie pas les droits RPC, WMI ou AD. Sa validité est de 120 secondes ; une ligne expirée doit être contrôlée de nouveau avant confirmation et exécution. Le délai alloué à la lecture du lot dépend de sa taille, de 120 à 1800 secondes, sans prolonger la validité d’un résultat déjà obtenu.
- « Prévisualiser la file » affiche le plan de toutes les lignes cochées, même masquées par un filtre.
- Comptez les lignes cochées : une ligne masquée par un filtre peut rester cochée.

## Exécuter

| Réglage | Effet |
|---|---|
| « Faire un poste pilote puis arrêter le lot » | Exécute la première ligne cochée puis arrête avant les suivantes. Le journal affiche « Poste pilote terminé : vérifiez son résultat et son redémarrage avant de sélectionner le reste du lot. » |
| « Confirmer chaque action » | Coché : une boîte de dialogue demande confirmation avant chaque action et affiche son résultat. Décoché : tout s'enchaîne. |
| « Redémarrer après réussite » | Demande un redémarrage après une action réussie. Décoché par défaut. |
| « Exécuter la file » | Affiche la confirmation, puis exécute toutes les lignes cochées, y compris celles masquées par un filtre. |

## Arrêts et sécurité

- Un code 32, 97 ou 98 arrête les lignes restantes. Un résultat incertain ou une protection non rétablie conserve le verrou de sécurité : vérifiez l'état réel avant toute reprise.
- « Arrêter après cette action » attend la fin de l'action en cours. Il ne coupe pas un renommage au milieu et n'annule pas les actions réussies.
- Ne tuez jamais le processus pour sauter une cible.
- À la fin, la fenêtre « Bilan de la file » résume le lot. Le contrôle complémentaire de chaque poste terminé reste disponible (chapitre 6). Les lignes incertaines ou partielles doivent être examinées avant reprise.
- « Retirer de la file » ne supprime ni poste, ni objet AD, ni reçu.

> [!NOTE] Si la sélection dépasse MaxBatch, Pesto refuse : « La sélection dépasse la limite de lot autorisée par la politique. ». La page « Historique » garde les 100 dernières synthèses de cette installation et de ce profil.

# 8 Plusieurs techniciens en même temps

Sur un banc de préparation, plusieurs techniciens peuvent recevoir le même nom tant que les créations ne sont pas visibles sur leur contrôleur. La revérification avant l'action réduit ce risque mais ne garantit pas l'absence de collision entre contrôleurs. Dans « Paramètres », « Noms et coordination », le tirage aléatoire est actif par défaut ; le registre partagé et la réservation AD restent désactivés.

## La revérification avant l'action

Un nom trouvé pris juste avant l'action est écarté pour la session. Le nom libre suivant est proposé, revérifié, puis confirmé par le technicien, cinq fois au plus (chapitre 3). Les noms retenus et la file ne donnent aucune exclusivité entre opérateurs.

## Registre partagé des réservations

Avec un dossier partagé (POLICY.CoordinationRoot), chaque Pesto réserve le nom qu'il propose, une seconde après son affichage. Si le technicien clique avant, ou si Pesto change de nom pendant la vérification (nom pris dans l'AD), le nom visé est réservé à la seconde suivante. Les autres Pesto ne proposent plus ce nom et passent à un autre ; le Journal l'indique : « NOMS : … déjà réservé par POSTE · compte ; autre nom proposé. ». Quand deux techniciens partent au même moment, ils peuvent voir le même nom pendant une à deux secondes : celui qui n'a pas obtenu la réservation passe au nom suivant pendant la vérification, avant la confirmation. La réservation dure NameReservationMinutes (15 par défaut), est prolongée tant que le nom reste proposé ou en cours d'opération, et disparaît après l'opération. À la fermeture, Pesto libère ses réservations (3 secondes au plus). Un poste arrêté laisse une réservation qui expire seule.

1. **Choisir le dossier.** Exemple : \\serveur\partage\Pesto, accessible en écriture à tous les techniciens.
2. **Préparer.** Paramètres, onglet « Noms et coordination » : saisissez le chemin, cliquez sur « Préparer ce dossier » puis confirmez. Pesto crée le dossier sous un parent existant, son marqueur de domaine et les sous-dossiers locks et reservations. Il ne crée ni partage ni droit.
3. **Tester.** Cliquez sur « Tester » : le message indique si l'écriture fonctionne et combien de noms sont réservés par d'autres postes.
4. **Enregistrer.** Cliquez sur « Enregistrer les paramètres », puis relancez Pesto sur chaque poste.

Poste hors domaine (mise au domaine) : le compte Windows local n'a aucun droit sur un partage du domaine. Pesto ouvre alors le partage avec le compte AD saisi à la connexion, sans lettre de lecteur ni mot de passe enregistré, et ferme cette connexion à sa fermeture ; ce compte doit pouvoir écrire dans le dossier.

Le même dossier reçoit aussi un verrou au moment où l'opération s'engage (chapitre 18). Dossier injoignable : les noms restent proposés, Pesto le signale une fois dans le Journal, mais l'opération est refusée avant toute écriture. Pour travailler sans registre, videz le chemin. « Rendre le registre partagé obligatoire » (CoordinationRequired) refuse une configuration sans dossier. En simulation, Pesto respecte les réservations des autres mais n'en écrit aucune.

## Consulter les réservations partagées

Dans « Noms disponibles », « Registre partagé » ouvre une lecture seule en arrière-plan : nom, station, compte, expiration et âge du fichier. « Active », « Expirée » et « Inconnue » décrivent les dates lues ; aucune réservation n’est modifiée. La lecture est limitée à 500 fichiers et signale les entrées ignorées ou la troncature. Un registre d’un autre domaine est refusé. Une erreur de lecture ne prouve pas qu’un nom est libre. Ce bouton est indisponible en simulation et en démonstration.

## Numéro au hasard

RandomNameEnabled=true active le tirage uniforme parmi tous les candidats libres des filtres actifs : type, préfixe, site et service. Par défaut, la série contient les numéros 001 à 999. Le choix utilise le générateur aléatoire du système, indépendant de l'horloge et d'un indice partagé entre PC. Il n'est pas limité aux premiers noms de la série ni à la page affichée.

Deux postes peuvent néanmoins obtenir le même candidat. Le tirage répartit les choix ; il ne réserve aucun nom et ne supprime pas les délais de réplication. RandomNameEnabled=false sélectionne le premier candidat libre. « Autre nom » permet de demander une autre proposition dans le même filtre, sans lancer d'opération.

## Réservation dans l'AD à la mise au domaine

ReserveNamesInAD = true : après le contrôle et avant la confirmation, Pesto crée le compte ordinateur dans l'emplacement choisi, sur le contrôleur du plan. Sa description contient « Réservé par Pesto [identifiant de l'opération] ». La jonction reprend ce compte par son GUID. Cette option est inactive par défaut et exige les droits de création et de suppression des comptes ordinateurs dans l'emplacement.

Avant l'appel AD, Pesto écrit un reçu local dans %ProgramData%\GP\Join\ad-reservation.json. Il conserve le nom, le GUID connu, l'emplacement, le domaine, le contrôleur et l'identité de la machine opérateur. Une panne réseau ou un délai dépassé laisse la réservation à vérifier ; un résultat tardif ne relance ni la jonction ni une suppression.

Si le technicien annule, modifie le formulaire ou si l'ajout est refusé sans résultat incertain, Pesto peut retirer sa réservation. Il relit d'abord le même GUID, le nom, l'emplacement et le marqueur exact ; le compte doit être sans nom DNS et sans SPN. Un objet déplacé, modifié ou utilisé est conservé. Une erreur d'accès AD n'est jamais interprétée comme une absence de compte.

À la fermeture, Pesto conserve la réservation et son reçu. Au lancement suivant, le parcours affiche « Réservation AD conservée ». Le technicien clique sur « Vérifier l’état » pour demander une inspection en lecture seule. Si le même compte inutilisé est retrouvé, Pesto repropose ce nom ; le contrôle et la confirmation de la jonction restent séparés. Si le compte est absent sur le contrôleur du reçu, seul le blocage de réservation peut être levé. Une jonction encore en cours, incertaine ou incohérente avec l’état Windows reste bloquante ; l’absence de consignation d’une jonction terminée et concordante ne l’est pas.

Tant que le worker de réservation ou de retrait travaille, Pesto empêche sa fermeture. Après une interruption ou un résultat incertain, conservez le reçu et contrôlez l'objet AD avant toute reprise. Une réservation liée à une autre machine, un autre domaine ou un autre contrôleur demande une vérification administrative.

Si le nom est déjà pris lors de la création, Pesto propose un autre candidat, le revérifie puis demande une confirmation. Des contrôleurs distincts peuvent avoir des vues différentes avant réplication.

![Tirage aléatoire actif ; registre partagé et réservation AD désactivés par défaut.](fig:parametres-noms)

## Choisir les options du banc

| Réglage | Usage |
|---|---|
| Tirage aléatoire seul | Répartir les propositions parmi tous les candidats libres, sans infrastructure supplémentaire. C'est le réglage par défaut. |
| Registre partagé | Coordonner les noms et engagements entre les installations qui utilisent le même registre approuvé. |
| Réservation AD | Précréer un compte identifié par GUID pour la jonction interactive ; exige les droits de création et de suppression nécessaires. |

Activez le registre ou la réservation seulement si leur fonctionnement, leurs droits et leur procédure de reprise sont définis. Aucun de ces réglages ne remplace le contrôle des créations faites par d'autres outils ni la surveillance des conflits de réplication.

## Contrôleur utilisé

Chaque poste utilise le contrôleur de domaine trouvé par Windows : inscriptible, avec les services web AD, le plus proche du poste. Avec plusieurs contrôleurs, deux postes peuvent interroger des contrôleurs différents. Un nom créé par un autre poste n'apparaît alors sur votre contrôleur qu'après réplication.

## Ce qui reste à surveiller

| Situation | Risque | Réponse |
|---|---|---|
| Plusieurs contrôleurs de domaine | Un nom écrit sur un autre contrôleur peut n'apparaître qu'après réplication. Deux créations du même nom avant réplication peuvent produire un conflit dans l'AD. | Prévenir les techniciens du banc, relire chaque nom proposé ; après des créations simultanées, vérifier dans l'AD qu'aucun compte n'est en double. |
| Objets créés hors de Pesto | Même délai de réplication. | Activer la coordination entre opérateurs (chapitre 18) si plusieurs outils coexistent. |

## Conduite à tenir

1. **Vérifier l'accès AD.** Depuis chaque poste du banc, la résolution DNS du domaine et les flux AD doivent fonctionner.
2. **Former les techniciens.** Devant « Nom déjà pris : nom suivant proposé », ils relisent le nouveau nom puis confirment ou annulent. Devant « Plusieurs noms déjà pris », ils actualisent l'inventaire dans « Noms disponibles » puis choisissent un nom.

# 9 Modes de lancement

Pesto n'a qu'un mode d'intervention : le mode réel. La consultation, la démonstration et la simulation servent à lire, former ou tester ; elles ne modifient ni Windows ni l'AD. Le guide technicien n'en parle pas : c'est à vous de livrer un poste en mode réel.

## Les quatre modes

| Mode | Comment l'obtenir | Accès AD | Modifications |
|---|---|---|---|
| Réel | Pesto.exe, lancement normal avec UAC. DEBUG.GUI et DEBUG.Simulation à false. | Oui | Après confirmation |
| Consultation | Pesto.exe --consult, sans UAC. | Lectures selon les droits du compte courant | Bloquées par le moteur, y compris la consignation |
| Démonstration | Pesto.exe -Demo ou -DemoJoin, ou DEBUG.GUI=true. | Aucun | Aucune ; données fictives |
| Simulation | DEBUG.Simulation=true dans cfg.json. | Lectures | Aucune : les commandes sont affichées, pas exécutées |

## Ce que voit le technicien

| Mode | En-tête | Indicateur de la file | Autres signes |
|---|---|---|---|
| Réel | « RÉEL », poste, domaine, compte et DC choisi. | « MODE RÉEL : écritures après confirmation » | « Ajouter ce PC au domaine ». |
| Consultation | « CONSULTATION » ; aucune mutation autorisée. | « CONSULTATION · aucune mutation » | « Exécuter la file », « Redémarrer après réussite » et la consignation sont grisés. |
| Démonstration | « démo · sans AD » et « Compte : démonstration ». Avec -Demo ou -DemoJoin, aussi « SIMULATION ». | « DÉMONSTRATION : aucun accès AD » | « Simuler l'ajout de ce PC ». OU affichée « Démonstration : aucune OU lue ». Bilan d'une action directe « SIMULATION TERMINÉE · aucune mutation réelle. ». Consignation grisée. |
| Simulation | « SIMULATION » : les commandes sont affichées mais pas exécutées. | « SIMULATION : aucune mutation réelle » | « Simuler l'ajout de ce PC ». Bilan d'une action directe « SIMULATION TERMINÉE · aucune mutation réelle. ». Consignation grisée. |


## Démonstration pour la formation

La démonstration montre tous les écrans avec des données fictives (example.local), sans aucun appel à l'AD.

- Le paquet DEV fournit DEMO.cmd, qui lance Pesto.exe -Demo, et DEMO_DOMAINE.cmd, qui lance Pesto.exe -DemoJoin (démonstration de la jonction, PC traité comme hors domaine).
- L'option -Demo lit wad\cfg.demo.json, présent dans le paquet DEV seulement. Sous Windows PowerShell 5.1, ce lancement s'ouvre sans UAC et sans connexion au contrôleur.
- Dans une configuration, la case « GUI — mode démonstration (aucun appel AD, données fictives) » de « Paramètres », onglet « Options avancées », correspond à DEBUG.GUI.
- Le cfg.json neutre des deux packs est non configuré. Le fichier cfg.demo.json reste distinct et réservé au pack DEV.

## Simulation pour tester un parcours

La simulation (« Simulation — affiche les commandes au lieu de les exécuter ») lit l'AD réel avec le compte réel, mais n'écrit rien. Exception : sur la page « Ajouter au domaine », « Vérifier sans ajouter » et « Vérifier l’état » sont simulés, sans lecture AD. Elle sert à tester une configuration et un parcours avant un pilote. Elle ne teste pas les droits d'écriture et ne permet pas de consigner une vérification.

## Consultation pour lire sans risque

Pesto.exe --consult ouvre Pesto avec le compte courant, sans UAC. Les lectures sont permises selon les droits de ce compte. Les modifications et la résolution des interventions sont bloquées dans le moteur. La consultation peut encore écrire des préférences et des traces locales. Elle n'est pas un test des droits d'écriture AD. Elle ne se combine ni avec -Demo ni avec -AskCredential (code 120).

## Options du lanceur

| Option | Effet |
|---|---|
| (aucune) | Lancement normal, UAC si nécessaire. |
| -AskCredential | Demander explicitement un autre compte AD (renommage distant, chapitre 4). |
| -ConfigPath fichier | Utiliser une configuration alternative. |
| -Demo, -DemoJoin | Démonstration, paquet DEV. |
| --consult | Consultation sans UAC, modifications interdites. |
| --check | Vérifier le paquet sans UAC ni AD ; avec --quiet, code de sortie sans fenêtre. |
| --check-json fichier | Rapport local du paquet, sans UAC ni AD. |
| --validate-plan brouillon rapport | Validation locale d'un brouillon JSON, sans autorisation. |
| --diagnostic | Ouvrir avec une console. |
| --help, --version | Aide du lanceur, version. |

Aucun mot de passe ne doit être passé en argument.

## Désactiver les modes de test avant la mise en service

1. **Ouvrir la configuration.** Éditez wad\cfg.json, ou ouvrez « Paramètres », onglet « Options avancées », section « DRAPEAUX DE TEST (section DEBUG) ».
2. **Décocher GUI et Simulation.** Mettez DEBUG.GUI et DEBUG.Simulation à false. L'écran le rappelle : « En PRODUCTION : laissez les drapeaux de test décochés (surtout GUI et Simulation). ».
3. **Laisser les autres drapeaux à false.** HorsDomaine et MauvaiseOU sont refusés en mode réel. BPVerifNomAD et ForceADM sont réservés et sans effet.
4. **Enregistrer et relancer.** Cliquez sur « Enregistrer les paramètres », puis relancez Pesto : le changement de mode demande un redémarrage de Pesto.
5. **Contrôler l'en-tête.** Ni « SIMULATION » ni « démo · sans AD » ne doivent apparaître. L'indicateur de la file affiche « MODE RÉEL : écritures après confirmation ».

> [!ATTENTION] Ne livrez jamais le cfg.json du pack de démonstration. Un technicien qui voit « SIMULATION » croit agir alors que rien n'est modifié.

# 10 Préparer Windows et les droits

Pesto tourne sur Windows x64 avec Windows PowerShell 5.1 Desktop et WPF/.NET. PowerShell 7 ne remplace pas le moteur attendu par le lanceur. Le paquet livre les ressources du module AD utilisées par Pesto.

## Réseau et contexte

Vérifiez la résolution DNS du domaine et du contrôleur, la cohérence de l'heure et l'accès au réseau AD. Prévoyez aussi les flux d'administration des parcours distants (RPC, WMI). Une lecture LDAP réussie ne certifie ni RPC/WMI ni le droit de renommer. Pesto n'active pas WinRM.

## Droits à qualifier

| Besoin | Contrôle à réaliser avant le pilote |
|---|---|
| Exécution locale | Le compte obtient le jeton administrateur Windows demandé par le lancement normal. |
| Lecture AD | Lire les ordinateurs, OU, groupes d'exclusion et attributs d'identité du périmètre. |
| Jonction | Créer ou réutiliser le compte ordinateur selon le parcours autorisé et les règles Windows du domaine. |
| Renommage | Administrer le poste cible et faire les modifications AD avec les droits délégués. Poste distant : identifiants explicites (-AskCredential). |
| Déplacement | Déplacer l'objet de l'OU source vers l'OU cible ; vérifier les droits effectifs des deux côtés. |
| Protection | Si sa levée temporaire est autorisée, pouvoir la rétablir à sa valeur initiale. |
| Coordination | Si elle est activée, droits SMB/NTFS et création exclusive dans le registre partagé. |

Qualifiez ces droits avec un compte dédié au périmètre et les délégations approuvées par votre organisation. Les droits nécessaires dépendent des opérations et des OU concernées. Le rôle Administrateurs du domaine n'est pas un prérequis à généraliser.

Laissez en place UAC, AppLocker, l'antivirus et les contrôles de confiance de l'organisation. Un refus se diagnostique dans ce cadre (chapitre 23).

# 11 Installer le paquet

Le paquet PROD ne contient que Pesto.exe et le dossier wad. Il s'installe sous Program Files, dans un dossier que les opérateurs ordinaires ne peuvent pas modifier. Le lanceur refuse de démarrer si un composant de wad diffère de son empreinte.

## Contenu de la livraison

Les sources de référence sont maintenues sur la branche master du dépôt M4D135/pesto. Le dossier packs contient exactement deux archives : Pesto_PROD.zip (Pesto.exe et wad) et Pesto_DEV.zip (même runtime, sources, tests et outils). Les guides administrateur et technicien sont fournis en Word et PDF dans DEV/docs. La distribution neutre contient un modèle cfg.json non configuré. Une distribution préparée par votre organisation peut intégrer son propre fichier validé ; conservez séparément le DEV neutre. Version affichée Pesto 1.0 ; FileVersion 1.0.0.0. Les outils DEV ne sont pas requis pour lancer PROD.

> [!NOTE] La signature Authenticode n'est pas appliquée sur cette livraison. Les contrôles d'intégrité par SHA256 restent obligatoires. L'outil de signature est disponible dans DEV mais hors périmètre de la distribution standard.

## Installer avec le script DEV

Le script copie un paquet cohérent dans un dossier neuf, sous un parent existant. Il ne remplace pas une installation et ne modifie pas les droits du parent. Depuis DEV, dans une console autorisée à écrire sous Program Files :

~~~
$installation = @{
  SourceDirectory = 'D:\Livraisons\PROD'
  Destination = 'C:\Program Files\Pesto'
}
.\tools\Install-Pesto.ps1 @installation
~~~

Ajoutez -ConfigPath 'D:\Configuration\cfg.json' pour fournir la configuration à copier. Le script contrôle sa forme JSON ; la validation métier complète est faite par Pesto au premier lancement. Les contrôles d'ACL et du paquet ci-dessous restent nécessaires.

## Installer manuellement

1. **Identifier le livrable.** Prenez Pesto_PROD.zip, ou le dossier PROD, de la même livraison. Avant toute copie, comparez l'empreinte de Pesto.exe à celle inscrite dans wad\package.json du même paquet (le paquet DEV la porte aussi dans tools\launcher\last-build.json).

~~~
Get-FileHash .\PROD\Pesto.exe -Algorithm SHA256
~~~

2. **Extraire dans un dossier maîtrisé.** Placez ensemble Pesto.exe et wad dans C:\Program Files\Pesto, sans sous-dossier PROD. N'installez pas dans Téléchargements, un profil utilisateur, un dossier synchronisé à la demande ou un emplacement inscriptible par les opérateurs ordinaires.

~~~
C:\Program Files\Pesto\
  Pesto.exe
  wad\
    cfg.json
    package.json
    Pesto-*.ps1 et ressources
    support\DEBLOQUER_TOUT.cmd
~~~

3. **Contrôler les ACL.** Vérifiez la racine, wad et le propriétaire. Les utilisateurs ordinaires n'ont que lecture et exécution ; l'écriture reste aux identités d'administration prévues.

~~~
icacls 'C:\Program Files\Pesto'
icacls 'C:\Program Files\Pesto\wad'
(Get-Acl -LiteralPath 'C:\Program Files\Pesto').Owner
~~~

> [!RESULTAT] Attendu pour Users et Authenticated Users s'ils sont présents : RX ou GR,GE ; aucun W, M ou F. Propriétaire : Administrators, SYSTEM ou TrustedInstaller.

4. **Débloquer si besoin.** Après contrôle de provenance, lancez wad\support\DEBLOQUER_TOUT.cmd si Windows a marqué les fichiers comme téléchargés. Ce script n'est pas nécessaire au démarrage.
5. **Contrôler le paquet.** Lancez --check, puis importez ou préparez cfg.json (chapitre 12). Ne mélangez jamais un EXE et des composants de versions différentes.

~~~
& 'C:\Program Files\Pesto\Pesto.exe' --check
~~~

> [!ATTENTION] Les ACL font partie des conditions de déploiement. Le lanceur vérifie les composants listés dans le manifeste, pas les fichiers ajoutés dans wad.

# 12 Créer ou importer la configuration

Un paquet neuf contient un cfg.json avec Configured=false. Ce n'est pas une configuration opérationnelle. Au démarrage, Pesto ouvre une correction locale avant toute connexion à l'AD.

## La fenêtre de correction

La fenêtre « Pesto · Corriger la configuration » liste les erreurs à corriger. Pour un paquet neuf, le message est : « Première utilisation : importez une configuration d'entreprise valide, puis validez. Aucun accès AD tant que cette étape n'est pas terminée. ».

Elle propose « Importer une configuration », « Créer avec l’assistant », « Valider, sauvegarder et continuer » et « Quitter ». Préférez l'import de votre fichier approuvé quand vous en avez un.

## Créer avec l'assistant

1. **Ouvrir l'assistant.** Choisissez « Créer avec l’assistant ». Il ne découvre pas votre annuaire et ne crée aucune OU.

2. **Renseigner les identités exactes.** Saisissez le domaine DNS, le préfixe (six chiffres par défaut), l'OU racine des postes, le nom de l'organisme et l'OU contenant ses sites. Utilisez les DN exacts lus dans l'AD : un libellé d'affichage n'est pas un DN.
3. **Continuer vers le placement.** La suite de l'assistant est décrite au chapitre 13.

> [!NOTE] Validation locale. Elle contrôle la structure et la cohérence des valeurs, pas l'existence des OU ni les droits AD. Les exemples du guide utilisent example.local, un domaine fictif à remplacer.

## Importer ensuite dans les paramètres

Une configuration déjà ouverte peut être remplacée dans le formulaire par « Paramètres », onglet « Fichiers », « Importer une configuration ». L’import valide les données, mais n’enregistre pas automatiquement le fichier. Utilisez « Prévisualiser », puis la procédure d’enregistrement du chapitre 13.

La configuration métier et les préférences personnelles restent séparées. Partager des favoris ou des brouillons avec « Partager des modèles… » ne distribue pas cfg.json.


> [!NOTE] JSON. Préférez les booléens true et false pour les nouveaux réglages. Les champs CONF et DEBUG prévus à cet effet acceptent aussi les chaînes correspondantes. POLICY exige de vrais booléens. Ne placez jamais de mot de passe dans la configuration.

> [!ATTENTION] Mode réel. DEBUG.GUI et DEBUG.Simulation doivent être faux. HorsDomaine et MauvaiseOU, qui simulent un faux état, sont refusés en mode réel.

# 13 Régler le placement et enregistrer

La seconde partie de l'assistant fixe le circuit de jonction et les codes des sites. Rien n'est sauvegardé automatiquement : le JSON est reporté, relu, puis validé.

## Régler l'assistant

1. **Choisir le circuit de jonction.** La case « Autoriser la jonction directement en production » donne DirectProd. Sans elle, renseignez « OU de préparation (obligatoire sans production directe) » et « Code service de préparation (3 caractères) ».
2. **Définir les codes des sites.** Dans « Codes des sites : un motif = deux lettres par ligne », écrivez une association par ligne, par exemple PREPROD=PR et Paris=VA. Les deux lettres décrivent le site physique. Évitez les motifs ambigus ou chevauchants.
3. **Décider pour Entra.** « Autoriser la préparation Entra avant renommage des postes hybrides » donne EntraPolicy=HybridOnly ; sinon Disabled (chapitre 4).
4. **Reporter puis relire.** Cliquez sur « Vérifier et reporter ». Le JSON est reporté dans la fenêtre précédente, sans sauvegarde. Relisez-le, puis cliquez sur « Valider, sauvegarder et continuer ».

> [!ASTUCE] L'assistant écrit ClearProtectionOnMove=false et des drapeaux DEBUG à false. Une configuration existante peut autoriser la levée de protection. Décidez-en explicitement (chapitre 5).

## Modifier une configuration en service

![L'onglet Fichiers regroupe import, export et restauration ; l'enregistrement reste explicite.](fig:parametres)

La page « Paramètres » regroupe « Apparence », « Domaine », « Noms et coordination », « Politique », « Tags », « OU & organismes », « Options avancées » et « Fichiers ». Le formulaire préparé, le fichier enregistré et le contexte utilisé par la session sont distingués.

1. **Trouver puis préparer.** « Rechercher un réglage… » recherche par nom, rubrique ou clé JSON ; choisissez « Ouvrir le réglage ». Modifiez les champs. Le message « Modifications non enregistrées » signale un brouillon ; les erreurs s'affichent près des champs concernés.
2. **Comparer.** Cliquez sur « Prévisualiser » pour voir le réglage, sa valeur avant/après et l’effet du changement. « Retrouver le réglage » ramène à son champ. Aucun fichier ni objet AD n’est modifié.
3. **Contrôler les destinations.** « Vérifier dans AD » lit le domaine, les OU et les correspondances des codes de site avec le compte de la session. Le tableau des observations indique le contrôle et son résultat ; « Ouvrir le réglage » ramène au champ concerné. Ce contrôle ne crée rien et ne certifie pas les droits d’écriture.
4. **Enregistrer.** « Enregistrer les paramètres » valide puis écrit cfg.json avec une sauvegarde .bak. Les valeurs complémentaires autorisées sont conservées. Si cfg.json a changé depuis son chargement, l’enregistrement est refusé : relisez la version externe avant de reprendre vos modifications.
5. **Appliquer le contexte.** Si Pesto demande une relance après un changement métier, fermez puis rouvrez le logiciel. Les plans sont conservés mais leurs contrôles doivent être refaits. Enregistrer sans changement métier ne demande pas de relance.

« Recharger » demande confirmation avant d'abandonner les modifications non enregistrées. L'onglet « Fichiers » propose :

| Commande | Effet |
|---|---|
| Importer une configuration | Valider le JSON choisi puis le reporter dans le formulaire ; sauvegarde séparée. |
| Exporter la configuration | Écrire le formulaire validé dans le fichier JSON choisi. |
| Restaurer la sauvegarde | Valider cfg.json.bak puis le reporter dans le formulaire ; prévisualiser et enregistrer séparément. |

La modification est bloquée pendant une jonction ou une opération. Une vérification AD incomplète doit être examinée ; elle n'autorise pas une destination inconnue.

## Corriger un champ sans perdre le reste

Dans « Fichiers », dépliez « Outils des réglages » :

| Commande | Parcours |
|---|---|
| Choisir une OU… | Sélectionner le champ cible ; lire les OU sous les racines configurées ; rechercher puis « Reporter ce DN ». La saisie manuelle du DN reste possible. |
| Exemples de noms | Lire des noms calculés depuis le formulaire et la règle de destination. Ce sont des exemples, sans contrôle de disponibilité. |
| Rétablir un champ… | Choisir le réglage puis confirmer « Rétablir dans le formulaire ». Les autres modifications sont conservées. |
| Rétablir une rubrique… | Reprendre seulement la rubrique choisie depuis la version chargée. L’enregistrement reste séparé. |
| Voir le JSON | Consulter la représentation du formulaire pour un examen avancé. |

Pour une OU de base ou d’organisme, sélectionnez sa ligne avant « Choisir une OU… ». La lecture est bornée à 2 000 OU ; réduisez le périmètre ou utilisez le DN manuel si cette limite est dépassée. Si le formulaire change pendant la lecture, recommencez le choix.

## Respecter la source des règles

« Options avancées » indique si les restrictions viennent de la configuration locale ou de HKLM\Software\Policies\M4D\Pesto. Les valeurs imposées sont désactivées dans le formulaire. Modifier cfg.json ne retire pas une règle administrée.

Le mode incident suspend les nouvelles mutations tout en conservant les lectures. Son changement nécessite une confirmation et un enregistrement explicites ; appliquez ensuite la relance demandée. L’activation des commandes silencieuses est également explicite et ne constitue pas une autorisation d’exécuter un plan.

## Régler la présentation

![Zoom à 150 % : les commandes fixes restent en bas à droite.](fig:zoom-interface)

Dans « Apparence », réglez thème, densité, aide, menu et son facultatif de fin de lot. « Vues et colonnes… » conserve filtres, tri et présentation, sans modifier les plans. L’icône au bas du menu le réduit. Hors domaine, les deux parcours de modification sont désactivés ; la jonction reste accessible.

La barre fixe règle le zoom de 80 à 150 %, par pas de 10 ; cliquez sur le pourcentage pour revenir à 100 %. Faites défiler les champs si nécessaire. F6 et Maj+F6 parcourent les grandes zones, sans quitter un panneau ouvert.

Le zoom est mémorisé immédiatement pour le compte de départ dans HKU\<SID>\Software\GP\Appearance, valeur Layout, propriété UiZoomPercent. En démonstration, il reste en mémoire. Le guide technicien détaille les commandes de présentation.

# 14 Champs de configuration

Le fichier usuel est wad\cfg.json. Une configuration alternative se passe avec -ConfigPath ; ce chemin participe à l'identité des états de l'installation. Gardez un emplacement stable lors des mises à jour.

| Champ | Usage et règle |
|---|---|
| CONF[0].Domaine | Domaine DNS. Tous les DN des OU doivent appartenir à ce domaine. |
| CONF[0].ADM | Compte d'administration prérempli à l'authentification hors domaine. |
| CONF[0].Prefixe | Code du département : six chiffres par défaut, selon la largeur Prefix de la convention. |
| CONF[0].PreprodSite | Code service de préparation : trois caractères alphanumériques par défaut, selon la largeur Service. |
| CONF[0].DirectProd | Autorise la jonction directe en production ; sinon l'OU PREPROD est obligatoire. |
| CONF[0].OUScanNoms | Racine d'inventaire des noms ; vide = OU ROOT. Ne remplace pas la recherche de collision dans tout le domaine. |
| CONF[0].Buffer | Entier de 0 à 999 : nombre de noms libres affichés au-delà du dernier utilisé. Ce n'est pas le parallélisme des écritures. |
| CONF[0].DarkMode | 0, 1 ou 2. |
| CONF[0].ClearProtectionOnMove | Levée temporaire puis rétablissement de la protection. Absent : true. L'assistant écrit false. |
| CONF[0].EntraPolicy | Disabled ou HybridOnly. Absent : HybridOnly. L'état hybride doit aussi être confirmé sur la cible. |
| OUBase | ROOT obligatoire ; PREPROD obligatoire si DirectProd est faux. |
| OUSite | Organismes et DN des racines contenant leurs sites. |
| TAGS | Motif de site et code à deux lettres par défaut, selon la largeur Site. Motifs à jokers, sans distinction de casse, sans doublon. |
| NameCatalogue | Combinaisons Site (deux lettres par défaut) et Service (trois caractères par défaut) déclarées pour les outils de noms. Ces deux clés sont les seules admises. |
| DEBUG | Drapeaux de test GUI, Simulation, HorsDomaine, MauvaiseOU, BPVerifNomAD, ForceADM. Tous à false en service (chapitre 9). |
| NamingConvention | Ordre et largeur des facettes du nom ; facultatif, format historique en son absence (chapitre 28). |
| POLICY | Politique optionnelle à schéma fermé (chapitre 15). |

> [!ASTUCE] Commentaires. Le JSON n'admet pas // ni /* */. Une clé qui commence par « _ » (par exemple "_Simulation" à côté de "Simulation") est un commentaire : Pesto l'ignore et « Enregistrer les paramètres » la conserve, à la racine, dans CONF et dans DEBUG. POLICY et NameCatalogue refusent toute clé inconnue : placez leurs explications à la racine (par exemple "_POLICY").

# 15 Encadrer les opérations avec POLICY

POLICY règle les exclusions et les capacités optionnelles. Son schéma est fermé : une clé inconnue, un type incorrect ou une valeur hors borne est refusé. Sans POLICY, les valeurs par défaut s'appliquent.

| Clé | Défaut | Règle |
|---|---|---|
| Schema | 1 | Obligatoire ; seule valeur reconnue. |
| ExcludedNames | [] | Noms exclus ; lettres, chiffres, tiret et jokers, 64 caractères au plus. |
| ExcludedOUs | [] | OU exclues des modifications ; DN valides. |
| ExcludedGroupGuids | [] | GUID des groupes exclus ; membres directs et imbriqués contrôlés. |
| CoordinationRoot | vide | Répertoire de coordination partagé déjà provisionné ; chemin absolu de 240 caractères au plus. |
| CoordinationRequired | false | Rend la coordination obligatoire ; exige CoordinationRoot. |
| AllowPasswordTaskFallback | false | Repli explicite par tâche utilisant un mot de passe. |
| AllowPrecreatedJoin | false | Autorise le choix d'un compte ordinateur précréé. |
| AllowOfflineJoin | false | Autorise le parcours distinct de jonction hors connexion après activation explicite (chapitre 28). |
| Scenario | absent | Champs requis, autorisés ou verrouillés dans les plans (chapitre 28). |
| MaxReaders | 4 | De 1 à 8 lecteurs dans le processus. |
| ReadAttempts | 2 | De 1 à 3 tentatives de lecture. |
| MaxBatch | 200 | De 1 à 200 postes dans un lot. |
| NameReservationMinutes | 15 | De 5 à 240 minutes : durée d'une réservation dans le registre partagé (chapitre 8). |
| ReserveNamesInAD | false | Réserve le nom dans l'AD à la mise au domaine (chapitre 8). |
| RandomNameEnabled | true | Tirage uniforme parmi tous les candidats libres des filtres ; false choisit le premier libre. |
| LogRetentionDays | 30 | Conservation des journaux de 1 à 3650 jours ; 0 désactive la purge. Les reçus ne sont jamais purgés par ce réglage. |
| BlockJoinOnClockSkew | false | Bloque la jonction si un décalage mesuré avec le DC atteint cinq minutes. Aucune correction d’heure. |
| UnattendedJoinEnabled | false | Autorise la jonction silencieuse ; -Execute reste requis pour agir (chapitre 18). |
| UnattendedOperationsEnabled | false | Autorise le renommage et le déplacement silencieux ; option distincte de la jonction. |
| IncidentMode | false | Suspend les nouvelles mutations ; les lectures et diagnostics restent disponibles. |

Chaque liste compte 200 entrées au plus.

## Exemple volontairement restrictif

~~~
"POLICY": {
  "Schema": 1,
  "AllowPrecreatedJoin": false,
  "AllowPasswordTaskFallback": false,
  "AllowOfflineJoin": false,
  "MaxReaders": 4,
  "ReadAttempts": 2,
  "MaxBatch": 20,
  "RandomNameEnabled": true,
  "ReserveNamesInAD": false,
  "CoordinationRequired": false,
  "CoordinationRoot": "",
  "LogRetentionDays": 30,
  "UnattendedJoinEnabled": false,
  "UnattendedOperationsEnabled": false,
  "IncidentMode": false
}
~~~

Cet extrait s'intègre au premier niveau d'une configuration complète ; il ne remplace pas le fichier. POLICY complète les délégations AD et les ACL du code. Elle n'est pas une frontière de sécurité face à un administrateur qui peut modifier ces éléments.

## Restrictions administrées par GPO

Le pack DEV contient les modèles ADMX/ADML dans integrations. Leur déploiement dans le magasin de stratégies relève de votre procédure d'administration. Pesto lit les valeurs DWORD ci-dessous sous HKLM\Software\Policies\M4D\Pesto ; il ne crée ni ne modifie cette stratégie. Les valeurs REG_SZ ScenarioJson et CampaignApprovalJson sont décrites au chapitre 28.

| Valeur administrée | Effet |
|---|---|
| IncidentMode = 1 | Suspend les nouvelles mutations, même si la configuration locale ne les suspend pas. |
| DisableUnattendedJoin = 1 | Interdit la jonction silencieuse. |
| DisableUnattendedOperations = 1 | Interdit le renommage et le déplacement silencieux. |
| MaxBatch, de 1 à 200 | Abaisse le plafond local du lot lorsqu'il est plus restrictif. |

La rubrique de configuration affiche l'origine et les restrictions administrées. Les choix locaux restent enregistrés séparément ; une GPO ne force jamais l'activation d'une option désactivée localement. Une valeur administrée mal formée provoque un refus explicite.

Le mode incident ne stoppe pas une commande Windows déjà engagée. Utilisez les reçus pour constater son résultat avant de reprendre les opérations.

# 16 Nommage et identité des objets

Pesto génère le nom selon les choix du formulaire et le contrôle dans l'AD avant toute action. Les objets restent suivis par GUID.

**Convention de nommage.** Par défaut, P111301VA765001 comprend P (portable), 111301 (département), VA (site), 765 (service) et 001 (numéro). S désigne un fixe, V une machine virtuelle. Le service comporte trois caractères alphanumériques. Pesto génère 001 à 999 ; 000 reste lisible dans un nom existant. Cette convention est définissable via le champ NamingConvention de la configuration (ordre des facettes, largeurs fixes, total limité à 15 caractères). En l'absence de ce champ, le format historique est conservé. Adaptez CONF.Prefixe, CONF.PreprodSite, TAGS et le catalogue aux largeurs déclarées si vous changez la convention.

**Identité avant libellé.** Pesto conserve le GUID du poste et, si possible, celui de l'OU prévue. Un objet recréé sous le même nom ne remplace jamais la cible confirmée. Les DN lus sont conservés ; le chemin convivial affiché ne reconstruit aucune destination.

## Disponibilité des noms

![Noms disponibles selon les filtres et la date de lecture de l’inventaire.](fig:noms-filtres)

« Vérifier dans le domaine » recherche les collisions sur name, sAMAccountName et dNSHostName dans tout le domaine. Cette lecture ne réserve rien. Le contrôle final utilise le contrôleur du plan ; la réplication reste à considérer (chapitre 8).

La grille limite l'affichage à 250 lignes par page, sans limiter le tirage aléatoire. L'âge et l'incomplétude des données sont signalés. « Actualiser le site » relit le filtre ; sans site précis, il demande l'inventaire complet.

Sous la grille, « Préparation et inventaire » regroupe les choix personnels dans « Préparation », la copie, l'export et l'actualisation dans « Inventaire », la numérotation et le service dans « Options ». Le candidat, sa vérification, son utilisation et les commandes de page restent directement accessibles.

**Capacité et conformité.** Ces analyses utilisent l'instantané chargé, sans lecture AD ni ping. Elles exploitent les combinaisons déclarées ou observées et admettent les sous-OU du site. Destination ambiguë, métadonnée absente et détails tronqués sont signalés, sans correction automatique. Des TAGS explicites stabilisent les correspondances.

# 17 Authentification et profils Windows

Le lancement normal demande un jeton administrateur par UAC. En domaine, Pesto utilise ensuite le compte Windows élevé, sans second login. Hors domaine, le compte AD est saisi explicitement.

## Compte élevé

Si l'UAC a utilisé un autre compte que celui du bureau, c'est ce compte élevé qui agit. Le technicien doit le contrôler dans l'en-tête. Pour un renommage distant, -AskCredential demande explicitement un autre compte AD (chapitre 4).

## Lire une erreur de connexion

Avec un compte AD saisi explicitement, Pesto conserve l’erreur d’origine : un échec réseau ou un refus du compte AD ne devient pas un diagnostic de compte Windows local. Sans compte explicite, vérifiez le compte choisi dans l’UAC. Si ce compte est local ou système, la connexion intégrée peut manquer des droits AD attendus ; relancez avec un compte du domaine autorisé ou choisissez « Autre compte AD ». Une identité Windows indéterminée ne prouve pas une cause locale.

Dans tous les cas, conservez le détail du message. Contrôlez le DNS, l’heure, l’accès au contrôleur et les droits avant de conclure. La découverte du contrôleur reste celle de Windows ; aucun PDC ni changement de compte n’est imposé automatiquement.

## Conservation entre deux comptes

Les fichiers des deux profils sont préservés. Deux files explicitement vides et inactives, du même PC et du même domaine, peuvent coexister. Une file active ou incompatible reste un conflit à examiner ; aucun verrou n'est supprimé pour faciliter le démarrage.

Si les historiques diffèrent, celui du compte élevé reste inchangé. L'autre est archivé à l'identique sous history-imported-<SHA256>.json, dans %LOCALAPPDATA%\GP\State\<installation>. Le journal wad\logs\Pesto-demarrage.log indique son chemin. Cette archive n'est ni fusionnée avec l'historique affiché, ni utilisée pour relancer ou valider une opération.

> [!NOTE] Un refus UAC rend 1223 et ne lance rien. Une instance déjà ouverte peut être refusée par le lanceur en 128, avant l'UAC.

# 18 Options à qualifier séparément

La coordination, la réutilisation de comptes précréés, le repli par tâche avec mot de passe et les mutations silencieuses sont désactivés par défaut. Chaque option demande une qualification dédiée. La politique Entra doit être décidée explicitement.

## Coordination entre opérateurs

Préparez un répertoire existant avec des ACL SMB et NTFS approuvées. Dans DEV, commencez par l'aperçu ci-dessous. Une fois appliqué, le script écrit un marqueur et un dossier locks ; il ne crée pas de partage et ne règle pas ses ACL.

~~~
$registre = '\\serveur\partage\Pesto'
$domaine = 'example.local'
.\tools\Initialize-Coordination.ps1 -Root $registre -Domain $domaine -WhatIf
~~~

Contrôlez le plan, puis retirez -WhatIf seulement pour le répertoire approuvé. La création exclusive lie l'engagement aux identités et aux noms. Elle ne protège pas d'un opérateur qui utilise un autre outil ou une copie non coordonnée. Un verrou ancien n'est pas réputé abandonné sur son seul âge.

## Compte ordinateur précréé

AllowPrecreatedJoin active un choix explicite dans « Ajouter au domaine ». Le fonctionnement est décrit au chapitre 3. Qualifiez les règles de réutilisation en vigueur sur votre domaine.

## Tâche avec mot de passe

AllowPasswordTaskFallback reste faux par défaut. Son activation permet un repli annoncé dans la confirmation, transmis au Planificateur par son API. Ce mode exige une revue des comptes autorisés, des tâches créées et de leur nettoyage. Il ne remplace pas le parcours normal par jeton Windows.

## Entra et jonction hors connexion

La préparation Entra avant renommage suppose un état hybride confirmé et une politique qui l'autorise (chapitre 4). Qualifiez séparément la réinscription cloud et le SSO de l'utilisateur. AllowOfflineJoin=true est accepté par la politique mais le parcours de jonction standard (Add-Computer) ne l'utilise pas. Pour la jonction hors connexion distincte, activez POLICY.AllowOfflineJoin et utilisez le parcours extension OfflineImport/OfflineApply avec un blob ODJ fourni par l'administrateur de provisionnement. Le secret est chiffré par DPAPI LocalMachine ; aucun rejeu automatique n'est effectué.

## Commandes silencieuses

Le point d'entrée wad\Invoke-Pesto.ps1 utilise le moteur importable, les mêmes contrôles d'identité et les mêmes reçus que l'interface. Il exige Windows installé, Windows PowerShell 5.1 x64 et un processus administrateur local. Il ne lance aucune fenêtre et ne s'exécute pas sous WinPE. Le script Invoke-PestoAutoJoin.ps1 fournit également le parcours de jonction.

| Action | Préparation |
|---|---|
| Inspect | Lit l'identité et les observations du poste ; -Computer choisit la cible. |
| Diagnose | Produit les diagnostics disponibles en lecture seule. |
| Join | Prépare le nom et le placement du PC local hors domaine. |
| Rename | Prépare le changement de nom d'un poste lu par son identité. |
| Move | Prépare un déplacement autorisé par les règles de site. |
| RenameMove | Prépare le changement de nom et le déplacement coordonné. |

Inspect et Diagnose ne clôturent aucun reçu. Avec Inspect, examinez aussi Observation.Errors : une observation indisponible n'est pas un état sain confirmé. -AsJson produit le résultat directement en JSON. -ConfigPath choisit un fichier complet ; le défaut est wad\cfg.json.

## Préparer les autorisations et le contexte

1. **Autoriser le parcours.** Activez POLICY.UnattendedJoinEnabled pour Join, ou POLICY.UnattendedOperationsEnabled pour Rename, Move et RenameMove. Les deux options sont désactivées par défaut. Une restriction GPO ou le mode incident peut encore bloquer la mutation.
2. **Fournir le compte en mémoire.** La séquence reçoit un PSCredential depuis son mécanisme de secrets. Aucun mot de passe ne doit figurer dans cfg.json, les arguments texte, les journaux ou les plans exportés. Le renommage distant exige le compte explicite autorisé.
3. **Garder une configuration d'exploitation.** Les drapeaux DEBUG sont false. Le moteur refuse les contextes incompatibles avant l'engagement. Une opération active, incertaine ou partielle garde ses protections.
4. **Choisir les filtres et le placement.** Pour Join, Type vaut P, S ou V, SiteCode contient deux lettres et ServiceCode trois caractères alphanumériques par défaut ; adaptez ces longueurs à la convention configurée. Avec DirectProd=false, le moteur impose le circuit PREPROD ; avec DirectProd=true, fournissez TargetOU et un code de site cohérent avec l'OU lue dans AD.
5. **Conserver les limites du parcours.** La jonction silencieuse ne prend pas en charge la coordination partagée ni la réservation AD : CoordinationRoot reste vide, CoordinationRequired et ReserveNamesInAD restent false. Elle ne réutilise pas un compte précréé choisi à la main.
6. **Vérifier le scénario administré.** Si POLICY.Scenario ou la clé REG_SZ ScenarioJson est défini, le moteur impose les champs requis, autorisés et verrouillés. Une valeur hors scénario est refusée. Les facettes sont extraites du nom réellement demandé, pas des étiquettes du formulaire.

Le contrôleur est celui découvert par Windows. Le PC à joindre doit être hors domaine et ne pas avoir de changement de nom en attente. Aucun redémarrage, basculement de contrôleur ou réessai de mutation n'est implicite.

## Préparer et exporter un plan

L'exemple utilise une variable $credentialDuCoffre déjà fournie par la séquence. Il n'enregistre aucun identifiant. Choisissez un dossier de plans existant et protégé :

~~~
$commande = 'C:\Program Files\Pesto\wad\Invoke-Pesto.ps1'
$plan = 'C:\Plans\poste-42.json'
$preparation = & $commande -Action Join `
    -Credential $credentialDuCoffre `
    -Type P -SiteCode PR -ServiceCode 765 `
    -OutPlanPath $plan
if ($preparation.ExitCode -ne 0) {
    throw $preparation.Message
}
$preparation.Plan
~~~

Sans -Execute, le moteur prépare en lecture seule. -OutPlanPath demande explicitement l'écriture d'un nouveau fichier et refuse d'en écraser un. Un plan expire après 24 heures et ne réserve aucun nom. Son empreinte détecte une altération ; elle ne constitue ni une signature ni une approbation.

## Exécuter le plan examiné

Après examen, réutilisez le même fichier. Le nom proposé est conservé ; une collision provoque un refus, sans nouveau tirage silencieux :

~~~
$resultat = & $commande -Action Join `
    -Credential $credentialDuCoffre -PlanPath $plan `
    -IdempotencyKey 'campagne42/poste42/join' -Execute
$credentialDuCoffre = $null
$resultat | ConvertTo-Json -Depth 12
exit $resultat.ExitCode
~~~

L'exécution recontrôle la machine, la configuration, l'OU, les GUID et l'état courant. Pour Rename, fournissez Computer et NewName lors de la préparation ; pour Move, Computer et TargetOU ; pour RenameMove, les trois. Les règles de changement de site restent identiques à celles du parcours graphique.

## Répéter une demande sans répéter la mutation

La clé idempotente identifie une demande sur la machine opérateur. Le registre sous %ProgramData%\GP\Automation conserve un marqueur avant l'appel au moteur, avec des droits administrateurs/SYSTEM. Une même clé et une même demande restituent le résultat conservé ; une demande différente est refusée.

Un refus avant lancement (96) est lui aussi conservé. Réutiliser sa clé restitue ce refus, sans lancer une nouvelle commande. Après correction de la cause et nouveau contrôle, fournissez une nouvelle clé explicite pour la nouvelle tentative. N’effacez pas le marqueur de la tentative précédente.

Une interruption sans résultat final retourne 97. Examinez le poste et les reçus avant toute reprise ; conservez le marqueur. Ce mécanisme ne coordonne pas plusieurs machines.

## Intégrer une séquence de déploiement

DEV\integrations\Invoke-PestoDeployment.ps1 fournit les adaptateurs ConfigMgr, PSADT, PDQ, DeployR, FirstBoot et personnalisés. Livrez l’adaptateur avec la séquence, indiquez Installation vers le pack PROD et utilisez une clé d’idempotence stable avec -Execute.

FirstBoot exige SYSTEM, Windows installé et un réseau disponible. Fournissez le PSCredential en mémoire depuis votre coffre. Le kit ne crée ni service, ni tâche, ni ouverture automatique de session.

Seules les métadonnées Campaign, Sequence, Stage, DeploymentBuild et Orchestrator sont permises (120 caractères par valeur). Les autres variables ne sont pas exportées. Qualifiez compte, réseau, interruption et codes de retour dans la version exacte de votre orchestrateur.

## Traiter le résultat

| Code | Sens et suite |
|---|---|
| 0 | Préparation valide, lecture retournée ou déplacement confirmé selon Mode et State. Ce code seul ne prouve pas une mutation. |
| 3010 | Commande acceptée ; redémarrage nécessaire. La séquence choisit le moment, sans rejouer l'action. |
| 96 | Refus avant lancement : corriger la cause puis préparer de nouveau. |
| 97 | Issue incertaine ou résultat final non conservé : examiner les preuves avant toute reprise. |
| Autre | Code métier du moteur conservé : lire EngineCode, State et Message. |

Le résultat contient Schema, Mode, State, ExitCode, MutationStarted, RestartRequired et Message, sans secret. Le contrôle après redémarrage (chapitre 6) reste facultatif si l’opération est terminée sans incertitude.

# 19 États, reçus et preuves

Pesto garde une trace durable de chaque opération : le reçu. Il distingue ce qui a été prévu, demandé, constaté et vérifié. Ces fichiers sont la preuve de l'exploitation : on ne les supprime jamais.

## Séquence d'une opération

La lecture prépare le contexte. Le contrôle compare les identités et les règles. La confirmation fige le plan. L’exécution écrit les reçus avant et pendant la demande. Une jonction ou un renommage accepté ne devient pas une vérification après redémarrage consignée. Le suivi complémentaire peut être effectué plus tard ; sa consignation exige une action explicite.

## Où sont les états

| Emplacement | Contenu à préserver |
|---|---|
| wad\cfg.json | Configuration métier opérationnelle. |
| gp.prefs.json, à côté du cfg.json choisi | Préférences de présentation lues en compatibilité ; le dossier dépend du chemin de configuration. |
| wad\logs\ | Journaux applicatifs et Pesto-demarrage.log. |
| %ProgramData%\GP\Interventions | Reçus centraux des interventions, communs à la machine opérateur. Le sous-dossier Archive conserve les reçus archivés et leur empreinte. |
| %ProgramData%\GP\Join\receipt.json | Reçu local de la jonction. |
| %ProgramData%\GP\Join\ad-reservation.json | Réservation AD conservée et éventuelle inspection à reprendre. |
| %ProgramData%\GP\Operations\direct.json | Reçu de l'action directe ; archives associées à conserver. |
| %LOCALAPPDATA%\GP\State\<installation> | Files, historiques et archives liés au profil et au chemin de configuration. |
| HKU\<SID>\Software\GP | Données du profil ; inventorier les SID concernés. Appearance contient les préférences actuelles ; Layout conserve notamment le zoom UiZoomPercent. |
| Registre de coordination, si activé | Marqueur, verrous et informations de suivi partagées. |

## Ce que contient un reçu

Un reçu distingue le plan approuvé, la photographie initiale, les observations datées et les effets confirmés ou inconnus. Renommage, déplacement, Entra et protection sont des étapes distinctes, pas un seul indicateur de réussite. Le lien parent et enfant permet de reprendre sans rejouer une étape confirmée.

Pesto 1.0 lit les schémas centraux 1, 2 et 3. Un reçu incompatible ou mal typé doit être examiné et conservé ; ne le supprimez pas pour contourner le contrôle.

## États d'une intervention

| État affiché | Sens |
|---|---|
| « Issue à vérifier » | Opération engagée dont l'issue n'est pas encore établie. |
| « Refus confirmé » | Échec de l'opération confirmé. |
| « Commande acceptée · contrôle facultatif » | Commande terminée ; redémarrage si nécessaire. Le reçu est conservé sans consignation imposée. |
| « Redémarrage puis contrôle » | Redémarrage ou cohérence du reçu à vérifier ; le suivi n’est pas classé facultatif. |
| « Effet partiel » | Une partie seulement des étapes est confirmée. |
| « Déplacement à préparer » | Renommage confirmé ; reprise du déplacement à préparer. |
| « Résultat incertain » | Demande possiblement arrivée sans résultat exploitable. |
| « Windows / AD vérifié » | Vérification consignée. |

Sur l’accueil, « Interventions à vérifier » signale les reçus à examiner, y compris les reçus illisibles. Un contrôle facultatif après une commande terminée n’alimente pas cette alerte ; le reçu reste dans la liste et dans « Acceptées · suivi facultatif ». « À vérifier avant reprise » isole les situations bloquantes ; « Tous les suivis non consignés » rassemble ces deux catégories. « Ouvrir les interventions » donne accès au suivi complet.

## Retrouver et exporter les interventions

![Les interventions conservent les résultats et les vérifications consignées.](fig:interventions)

« Historique », puis « Interventions et reprises », ouvre le suivi. Si l'accueil affiche des interventions à vérifier, « Ouvrir les interventions » mène à la même liste. Le champ de recherche se combine avec le filtre d'état ; les dates sont locales et les états sont libellés en français. « Précédent » et « Suivant » parcourent les pages de 200 lignes.

Sur l’accueil : nom et domaine Windows, heure de lecture, trois dernières interventions, activité et nom configuré en attente constatés. « Actualiser » relit Windows et les reçus locaux, sans accès AD. L’emplacement AD est une observation antérieure pour ce nom ; sa date est inconnue si elle n’a pas été conservée. Sélectionnez un reçu, puis « Ouvrir le reçu » pour le consulter. La vérification du poste établit son état présent.

« Vérifier l’état du poste » et « Compte rendu » sont directement accessibles. Sous « Détails et outils » : « Consulter » (reçu, tâches, comparaison, chronologie, dossier de support), « Entretien » (rétablissement de protection, nettoyage des tâches), « Données » (import, vues, colonnes et archives). Un reçu illisible est signalé, sans masquer les autres ni permettre de mutation.

« Compte rendu » masque poste et domaine par défaut. Décochez « Masquer poste et domaine » uniquement si leur transmission est nécessaire. « Exporter le filtre » inclut toutes les lignes filtrées, même hors page. Le CSV contient les identifiants des postes, sans le masquage du compte rendu : relisez-le avant transmission.

La lecture est bornée à 5 000 reçus. Si le catalogue est tronqué, l'export complet est bloqué ; archivez explicitement les interventions closes admissibles, sans supprimer les reçus en attente.

## Comparer et suivre un poste renommé

Dans « Détails et outils », onglet « Consulter », « Comparer deux reçus » demande de choisir exactement deux lignes avec Ctrl+clic. « Comparer ces deux reçus » montre les différences sans écrire de résultat.

« Chronologie du poste » rapproche les reçus par identité Windows ou GUID AD, jamais par le nom seul. La chronologie porte sur le catalogue consulté : reçus actifs ou archives. Un reçu sans identité fiable reste associé à sa propre opération.

## Archiver sans perdre le reçu

1. **Sélectionner.** Choisissez un reçu vérifié ou refusé, sans protection ou tâche restant à résoudre.
2. **Archiver explicitement.** Dans « Détails et outils », « Données », cliquez sur « Archiver ce reçu… », relisez le message et confirmez « Archiver ce reçu ».
3. **Retrouver.** « Consulter les archives » ouvre les reçus conservés ; « Revenir aux reçus actifs » revient au catalogue courant.

L’archivage déplace le fichier sans changer ses octets et conserve son empreinte SHA256. Il ne remplace pas un reçu existant et ne touche aucun poste ni objet AD. Les états incertains, partiels, actifs et les commandes acceptées dont le suivi reste facultatif demeurent dans les reçus actifs. Les actions de vérification et d’entretien sont désactivées dans la vue d’archives.

## Préparer un dossier de support

Sélectionnez le reçu puis, dans « Consulter », « Dossier de support… ». Le réglage « Masquer poste et domaine », coché par défaut, s’applique à l’aperçu. Relisez les données avant « Exporter ce dossier » et choisissez un dossier nouveau.

Le dossier contient le résumé de l’opération, les traces de réconciliation conservées dans le reçu, le diagnostic de la session et un manifeste SHA256. Ces traces indiquent la relecture d’une tâche, son code confirmé ou inconnu, et la reprise de protection ; elles ne certifient pas le succès global. Les 96 derniers événements du reçu bornent cette vue. Le diagnostic décrit la session de collecte, pas forcément celle de l’intervention. Aucun fichier existant n’est écrasé et aucun envoi n’est automatique.

## Conservation des journaux

POLICY.LogRetentionDays vaut 30 par défaut. Une valeur de 1 à 3650 définit la conservation des journaux ; 0 désactive leur purge. Ce réglage ne purge jamais les reçus de jonction, les interventions, les verrous ou les états de reprise. Intégrez leur sauvegarde à la procédure d'exploitation.

## Codes de résultat

| Code | Sens |
|---|---|
| 10, 20, 77 | Succès, redémarrage requis (jonction, renommage, renommage avec déplacement). |
| 11, 21 | Jonction refusée, renommage refusé. |
| 13 | Compte AD déjà existant. |
| 30, 33 | Déplacement vérifié ; déjà dans l'OU cible. |
| 31 | Déplacement refusé ou interdit. |
| 32 | Déplacement fait, protection non rétablie. |
| 40, 41 | Redémarrage demandé ; échec du redémarrage (journal seul, sans effet sur le statut AD). |
| 69, 88 | Nom déjà pris (renommage seul ; renommage avec déplacement). |
| 89 | Renommé, déplacement à reprendre. |
| 96 | Non lancé. |
| 97 | Incertain. |
| 98, 99 | Erreur technique ; 99 aussi pour un poste introuvable. |

Un résultat incertain ou tardif n'est jamais un succès. Une étape confirmée n'est jamais rejouée.

> [!ATTENTION] Le ZIP du logiciel ne sauvegarde pas ces états. Retirer une ligne de file, recopier un paquet ou changer de profil n'efface pas le besoin de résoudre les interventions encore bloquantes.

# 20 Incertitude (97) et anciens états

Un résultat 97 signifie qu'une demande a pu atteindre Windows ou l'AD sans qu'un résultat exploitable revienne. On ne relance rien à l'aveugle : on rétablit les accès, on relit, puis on décide. Les anciens états s'importent volontairement, jamais par balayage automatique.

## Traiter un résultat incertain

1. **Conserver les preuves.** Gardez le reçu, l'heure et les tâches exactes.
2. **Rétablir les accès.** Réparez le réseau, le stockage et l'accès aux sources.
3. **Relire.** Relisez Windows et l'AD avant de décider de l'étape restante (chapitre 6).

Un contrôle en échec après une étape engagée ne transforme pas l'intervention en « non lancé ». Supprimer un verrou ou un reçu, ou vider la file, n'est jamais une procédure de reprise.

## Acquitter sans valider le résultat

Un acquittement permet de préparer une nouvelle opération lorsque l'examen d'un résultat incertain ou partiel ne permet pas de consigner une réussite. Dans la fiche État ou dans Interventions, sélectionnez « Acquitter… », décrivez votre décision en 3 à 500 caractères et confirmez. Une lecture indisponible n'empêche pas cette décision ; l'absence d'observation est indiquée dans le dialogue.

Le reçu conserve sa phase, son code, ses effets Entra, renommage, déplacement et protection, ainsi que son message. L'objet Acknowledged ajoute la date, l'auteur, le motif, la phase et le code acquittés, et l'observation disponible. Il devient caduc si la phase ou le code change. Le résultat n'est jamais compté comme réussi.

L'acquittement est refusé en consultation, simulation ou démonstration, pendant une commande ou si le mutex de mutation est détenu. Une tâche Windows dont la fin n'est pas confirmée doit être relue dans « Détails et outils », « Consulter », « Relire les tâches ». Un reçu illisible ou provenant d'un autre domaine ne peut pas être acquitté comme celui du poste courant.

Pour un lot, « Acquitter le verrou… » acquitte les reçus correspondants et décoche les lignes concernées. Une ligne restée « EN COURS » devient « INCERTAIN » ; les autres résultats et identifiants sont conservés. Un échec de sauvegarde conserve le verrou. Recréez une ligne après lecture du poste pour demander une nouvelle opération ; les anciennes lignes ne sont pas rejouées.

Si dsregcmd /leave a rendu 0 mais que sa relecture a expiré, le code 97 reste incertain : le renommage peut ne pas avoir commencé. Vérifiez dsregcmd /status et AzureAdJoined sur le poste. Après acquittement, une nouvelle préparation relit cet état ; lorsque AzureAdJoined vaut NO, le retrait n'est pas répété. La réinscription hybride reste à contrôler selon votre procédure.

Les lectures dsregcmd disposent de 90 secondes avant le retrait et de deux tentatives de 120 secondes après, séparées de 5 secondes. Le retrait n'est jamais répété pour cette relecture. Ces délais ne garantissent pas que l'état pourra être obtenu : un résultat incomplet reste conservé comme tel.

## Importer un ancien état

1. **Choisir la source.** Dans « Pesto · Interventions », ouvrez « Détails et outils », puis « Données » et « Importer un ancien état ». Sélectionnez le JSON concerné. Pour un ancien reçu de jonction, la source est notamment %ProgramData%\GP\Join\receipt.json.
2. **Examiner la prévisualisation.** Vérifiez le schéma, le domaine, l'identité de la machine opérateur, les dates et les GUID. L'import n'invente pas une preuve absente et ne substitue pas une cible de même nom.
3. **Importer puis observer.** Confirmez seulement le rapprochement attendu. Le fichier d'origine est conservé et les anciennes interventions restent incertaines. L'import ne vaut pas réussite : une observation complète reste due.

## Nettoyer les tâches

Dans « Détails et outils », l’onglet « Consulter » propose « Relire les tâches » : ce bouton consulte les tâches exactes enregistrées dans le reçu et mémorise leur fin confirmée ; il ne lance ni ne supprime rien. Dans l’onglet « Entretien », « Nettoyer les tâches terminées » supprime seulement les définitions exactes terminées dont l'empreinte correspond. Il n'efface pas les tâches qui portent un préfixe semblable.

> [!ATTENTION] Escalade. Si le plan, le PC d'origine, le GUID ou la protection initiale ne peut pas être établi, conservez les preuves et faites arbitrer l'administrateur responsable. Une absence de preuve n'autorise jamais à recommencer.

# 21 Mise à jour et copie interrompue

La mise à jour se fait depuis un nouveau paquet DEV extrait à part. L'outil copie, vérifie et remplace l'EXE en dernier. Il conserve configuration, préférences, journaux et reçus.

## Mettre à jour

L'outil vérifie le manifeste de l'installation avant de préparer le remplacement. Il faut Python provisionné par l'organisation et, sous Program Files, une console administrateur. Sous Windows, le remplacement conserve les droits d’accès des fichiers existants ; si leur conservation échoue, la mise à jour refuse le remplacement.

1. **Préparer.** Terminez ou examinez les interventions actives et incertaines. Fermez Pesto normalement. Sauvegardez code, configuration et états (chapitre 22). Gardez le même chemin d'installation et de configuration.
2. **Prévisualiser.** Lancez l'aperçu et examinez le plan.
3. **Appliquer.** Appliquez depuis le même DEV. L'outil prépare des copies vérifiées de l'ancien et du nouveau code, journalise la copie et remplace l'EXE en dernier.

~~~
$destination = 'C:\Program Files\Pesto'
$outil = '.\tools\update_installation.py'
python $outil --destination $destination
python $outil --destination $destination --apply
~~~

Vérifiez séparément wad\support, hors du manifeste applicatif. La mise à jour ne modifie aucune action AD déjà réalisée. Après un aperçu ou une mise à jour réussis, l'outil signale aussi les files de l'utilisateur courant non conclues ou incertaines, sans rien bloquer.

## En cas de JSON refusé

Un manifeste, une empreinte ou un reçu avec un type JSON incorrect est refusé avec un message « Update refused ». Ne remplacez pas un reçu par un objet vide et ne le supprimez pas. Conservez les fichiers, identifiez l’élément signalé et comparez-le à une sauvegarde connue. Pour une archive source endommagée, récupérez une copie vérifiée du pack. Relancez d’abord l’aperçu après résolution.

## En présence du verrou de mise à jour

~~~
$destination = 'C:\Program Files\Pesto'
$outil = '.\tools\update_installation.py'
python $outil --destination $destination --recover
python $outil --destination $destination --recover --apply
~~~

La première commande prévisualise la reprise sans retirer le verrou. Selon le journal et les empreintes, l’application libère une préparation interrompue si le code ancien est intact, conserve une mise à jour déjà terminée si le code nouveau est confirmé, ou restaure les fichiers précédents reconnus. Une modification externe, une copie altérée ou un journal incomplet bloque la récupération.

> [!ATTENTION] Limites. Le mécanisme récupère une copie interrompue fichier par fichier. Ce n'est pas une transaction globale ni une garantie contre toute panne électrique. Ne supprimez jamais .pesto-update.lock à la main pour forcer le lancement.

# 22 Sauvegarde et retour arrière

Une sauvegarde utile contient le code, la configuration et tous les états d'exploitation. Revenir à un ancien EXE n'annule aucune action Windows ou AD. Chaque situation a sa restauration.

## Avant un changement

1. **Figer le contexte.** Fermez normalement Pesto après examen des actions engagées. Relevez la version, le SHA256 de l'EXE, le chemin de configuration, les profils opérateurs et les interventions non résolues. N'interrompez pas un traitement en cours (worker) pour simplifier la sauvegarde.
2. **Copier les données utiles.** Sauvegardez l'installation, la configuration, les préférences, les journaux, tous les répertoires GP concernés, les données des profils et les clés de registre des profils. Incluez la coordination si elle est active. Protégez ces copies avec les mêmes règles d'accès.
3. **Vérifier la copie.** Conservez un inventaire des fichiers et empreintes, l'heure, la machine d'origine et les SID concernés. Testez la lisibilité de la sauvegarde. Un ZIP du paquet neuf n'est pas une sauvegarde de l'exploitation.

## Choisir la bonne restauration

| Situation | Réponse |
|---|---|
| Copie de code interrompue | --recover en aperçu, puis --recover --apply si le journal et les empreintes sont cohérents. |
| Configuration erronée | Restaurer la configuration approuvée après sauvegarde de l'état actuel ; revalider et relancer Pesto. |
| Action Windows ou AD déjà faite | Relire l'état et préparer une intervention corrective explicite. Un ancien EXE n'annule pas cette action. |
| Reçu manquant ou incompatible | Restaurer et rapprocher seulement les données de la machine et du contexte confirmés. Ne jamais réécrire un reçu pour obtenir un état vert. |

> [!NOTE] Compatibilité. Le schéma 3 exige une version qui sait le lire. Une restauration sur un autre PC ne transfère pas l'identité Windows du PC d'origine : elle ne permet pas de vérifier sa jonction. Conservez les originaux et les archives importées.

# 23 Diagnostiquer le lancement

Pesto.exe rend ses propres codes de sortie, de 120 à 132, quand il refuse de démarrer. Les autres codes viennent de Windows PowerShell et passent tels quels. Ils sont distincts des codes de résultat 10 à 99 inscrits dans les reçus.

| Code | Cause | Action |
|---|---|---|
| 120 | Arguments invalides ou combinaison refusée. | Relire Pesto.exe --help. |
| 121 | Chemin passé en argument inutilisable. | Vérifier configuration, brouillon et chemin de rapport. |
| 122 | Chemin du lanceur inutilisable. | Installer dans un dossier au chemin plus court. |
| 123 | EXE à la racine d'un lecteur. | Placer Pesto.exe et wad dans un dossier. |
| 124 | Paquet incomplet. | Extraire tout le paquet approuvé. |
| 125 | Composant ou empreinte refusé. | Vérifier provenance, intégrité et liens ; réinstaller un paquet cohérent en préservant les états. |
| 126 | Verrou de mise à jour présent. | Suivre la récupération du chapitre 21, sans effacer le verrou. |
| 127 | Verrou invérifiable. | Lire l'erreur Windows et contrôler les droits du dossier. |
| 128 | Instance déjà ouverte. | Revenir à la fenêtre existante ; aucune UAC n'est demandée. |
| 129 | Contrôle d'instance impossible. | Lire l'erreur Windows affichée. |
| 130 | Windows PowerShell 5.1 x64 absent. | Vérifier la conformité du poste. |
| 131 | Démarrage de PowerShell refusé. | Examiner AppLocker, SRP et antivirus. |
| 132 | Code de PowerShell illisible. | Traiter le résultat comme inconnu et relire l'état. |
| 1223 | UAC annulée. | Aucune opération lancée par cette demande. |

Les codes 133 à 139 sont réservés. Le script peut aussi rendre 1 pour un refus ou une erreur après démarrage.

Pour les refus 120 à 127 et 129 à 131, la fenêtre « Pesto 1.0 | Démarrage » se termine par « Code de sortie du lanceur : N ». Le code 128 ouvre « Pesto | Déjà ouvert », sans code. Le code 132 et les erreurs de PowerShell ouvrent « Pesto 1.0 | Diagnostic ». Avec --quiet, --check-json ou --validate-plan, aucune fenêtre ne s'ouvre : seul le code reste.

> [!NOTE] En mode silencieux, fiez-vous au code et au rapport. L'absence de fenêtre ne prouve pas un succès. Les événements sont écrits pendant l’opération, puis le journal est vidé à la fin (attente maximale de deux secondes). Le message PESTO_AUDIT_INCOMPLETE sur la sortie d’erreur signale une trace incomplète ; il ne change pas un résultat de mutation en « non lancé ».

# 24 Contrôles et journaux

Trois contrôles se lancent sans UAC ni AD : --check, --check-json et --validate-plan. Ils prouvent l'intégrité du paquet ou la forme d'un brouillon, jamais les droits AD. Les journaux et les reçus servent ensuite au diagnostic d'un incident.

## Contrôle du paquet sans UAC

~~~
$exe = 'C:\Program Files\Pesto\Pesto.exe'
$p = Start-Process -FilePath $exe -ArgumentList @(
  '--check-json', 'C:\Temp\pesto-check-001.json'
) -Wait -PassThru
$p.ExitCode
~~~

Choisissez un chemin de rapport nouveau et accessible : Pesto n'écrase pas un rapport existant. Attendu sur le paquet livré : code 0, Runtime PASS, Syntax PASS et AuditWriter PASS. Les nombres de composants et de scripts doivent correspondre au manifeste du paquet contrôlé. Ce contrôle ne teste ni l'UAC ni les droits AD.

## Contrôle hors ligne d'un brouillon

~~~
Pesto.exe --validate-plan C:\Temp\brouillon.json C:\Temp\pesto-plan-001.json
~~~

Un brouillon valide donne 0 ; un brouillon invalide donne 20. Même valide, il reste Authorized=false et Configuration=NOT_VALIDATED. Ce contrôle ne lit pas l'AD et n'autorise aucune exécution.

## Lire le Journal

La page « Journal » raconte la session : contrôleur utilisé, noms écartés, résultats. « Diagnostic… » prévisualise puis exporte un diagnostic expurgé ; relisez-le avant de le partager. Le bouton « Audit » de l'en-tête rassemble les informations utiles à un incident.

La recherche filtre les messages affichés. Dépliez « Options de lecture » pour régler le suivi, le retour à la ligne et la taille du texte. Ces choix ne modifient pas le journal enregistré.

## Retrouver un outil

« Actions · Ctrl+K » ouvre « Outils et navigation » : « Postes », « Préparer », « Analyser » et « Affichage ». Le champ « Rechercher un outil » couvre toutes ces rubriques, normalise les accents et reconnaît des synonymes comme « reçu », « config » ou « libres ». Les correspondances les plus directes apparaissent en premier. Sélectionnez une commande puis « Ouvrir » ; cette sélection ne lance aucune opération sur un poste.

![Les outils sont classés par usage ; la recherche porte sur toutes les rubriques.](fig:outils-navigation)

## Collecter un incident

1. **Relever le contexte.** Notez le code, l'heure, la version, le SHA de l'EXE, le mode, la cible, l'identifiant d'intervention et le redémarrage fait ou non.
2. **Rapprocher les preuves.** Lisez le Journal, wad\logs\Pesto-demarrage.log, le reçu et les observations. « Pesto · Interventions » fournit le compte rendu et le suivi des tâches. Préservez les preuves avant toute réparation.
3. **Préparer un dossier ciblé.** Sélectionnez l’intervention, puis « Détails et outils », « Consulter », « Dossier de support… ». Relisez l’aperçu et le masquage avant « Exporter ce dossier » ; un dossier neuf est requis.
4. **Partager le nécessaire.** Relisez les exports avant transmission. Noms, domaines et comptes sont des données internes ; aucun mot de passe dans les captures, la configuration ou le compte rendu.

> [!NOTE] Performance. La palette donne les mesures locales de la session : attente, temps de travail, moyenne, P95 et maximum. Returned signifie qu'un worker a répondu ; ce n'est pas la preuve qu'une modification Windows a réussi.

# 25 Qualifier le déploiement du parc

La qualification porte sur le candidat exact à distribuer, sa configuration, les droits des opérateurs et les parcours utilisés dans l'organisation. Une compilation et un contrôle de manifeste ne prouvent pas la réussite d'une jonction ou d'un renommage sur votre réseau.

## Préparer le pilote

1. **Identifier le paquet.** Conservez les empreintes de l'EXE et des archives, le manifeste, la configuration approuvée et les paramètres de compilation.
2. **Choisir le périmètre.** Désignez des postes et OU dédiés, des comptes délégués et une fenêtre d'intervention approuvée. Sauvegardez les états utiles et définissez la reprise.
3. **Vérifier les conditions.** Contrôlez Windows PowerShell 5.1 x64, le DNS, l'heure, les flux d'administration, l'UAC et les politiques de contrôle des applications.
4. **Contrôler le paquet.** Lancez --check-json sur le candidat installé, puis faites contrôler la configuration et les OU en lecture seule.

## Couvrir les parcours utilisés

| Parcours | Points à relever |
|---|---|
| Démarrage | Compte élevé, authentification AD attendue, absence de modification des règles de sécurité, configuration chargée. |
| Jonction | PC local hors domaine, nom et OU approuvés, reçu écrit, redémarrage explicite, contrôle du canal sécurisé puis consignation. |
| Renommage | GUID stable, même site donc OU inchangée, nom configuré puis nom actif après redémarrage. |
| Changement de site | Renommage confirmé avant déplacement, OU finale et protection relues. |
| Lots | Contrôle des lignes cochées, poste pilote, progression, arrêt après l'action courante, vérification individuelle. |
| Noms | Filtre exact, tirage sur tous les candidats libres, collision détectée, nouvelle confirmation interactive. |
| Incidents | Refus de droits, lecture indisponible, résultat incomplet, persistance impossible ; aucune reprise aveugle ni suppression de verrou. |
| Présentation | Résolution et échelle du parc, clavier, thème, contraste, lecteur d'écran et RDP si utilisés. |
| Maintenance | Installation neuve, aperçu de mise à jour, conservation des ACL et des données, récupération d'une copie interrompue. |

Les scénarios qui modifient Windows ou AD demandent un périmètre et une fenêtre approuvés. Ne provoquez pas une coupure, un manque de disque ou un arrêt forcé sur une installation en service pour tester sa récupération.

## Qualifier les options séparément

La coordination, les réservations AD, les comptes précréés, le repli par tâche, la jonction silencieuse et la modification d'attributs AD (description, location, managedBy) nécessitent des scénarios adaptés aux options réellement activées. Pour plusieurs contrôleurs, observez la réplication et les créations concurrentes. Pour Entra hybride, contrôlez aussi la réinscription et le SSO ; un reçu Windows/AD ne les certifie pas. Pour les attributs, vérifiez le diff planifié et la relecture post-écriture.

> [!NOTE] Les tests de contrats sont effectués avec des doubles AD/Windows. La qualification sur VM réelle reste à la charge de l'organisation.

## Décider du déploiement

Conservez pour chaque scénario la configuration, l'heure, le poste, le contrôleur, le résultat, le reçu et la vérification après redémarrage. Faites traiter les écarts bloquants, puis étendez progressivement à un groupe pilote représentatif. La décision de généralisation appartient au responsable du parc, à partir de ces résultats et des possibilités de reprise.

> [!NOTE] Pour les scénarios administrés et les approbations de campagne, consultez le chapitre 28.

# 26 Architecture et fabrication de la distribution

Le pack DEV contient les sources, tests et outils permettant de modifier le logiciel et de reconstruire un PROD cohérent. Le pack PROD contient Pesto.exe et le dossier wad avec ses scripts, bibliothèques, ressources et configuration accessibles normalement.

## Architecture

| Composant | Rôle |
|---|---|
| Pesto.exe | Lanceur natif x64 : vérifie l'emplacement, le verrou de mise à jour et les empreintes incorporées, puis lance Windows PowerShell. |
| Pesto-Startup.ps1 | Contrôles du runtime et des scripts, UAC, identité et reprise entre profils. |
| Interface WPF | Formulaires, affichage des données et états, contrôle puis confirmation des plans. |
| Pesto-Operations.ps1 et parcours Join et Direct | Commandes Windows et AD, contrôles frais et résultats typés. |
| Safety, JoinRecovery et Recovery | Reçus, identités, observations et reprises qui conservent les effets déjà confirmés. |
| Pesto.Engine.psd1 et Pesto.Engine.psm1 | Moteur importable sans interface WPF ; runtime généré depuis les sources et dépendances des workers validées par AST. |
| Pesto-Enterprise.ps1, Pesto-Automation.ps1 et Invoke-Pesto.ps1 | Inspection, préparation et mutations silencieuses ; plans, métadonnées et idempotence. |
| Socle M4D Admin Common 0.2.0 | Bibliothèques Core, Query, IO et Diagnostics, compilées pour .NET Framework 4.7.2. |

Les bibliothèques communes sont livrées dans wad et verrouillées par common.lock.json : identité, version, taille et empreinte. Pesto vérifie l'ensemble avant chargement. Ces bibliothèques ne sont ni téléchargées ni recompilées au démarrage. Le module Wpf commun est séparé et n’est pas requis par le pack Pesto ; les helpers spécifiques du moteur peuvent encore utiliser Add-Type. Les corrections communes se font dans leur source canonique avant actualisation des consommateurs.

## Modifier les sources et fabriquer PROD

1. **Conserver le DEV neutre.** Faites une copie avant vos changements. Gardez les sources et les outils DEV avec le dossier wad complet.
2. **Modifier.** Éditez les scripts, images ou la configuration du dossier wad. Les scripts PowerShell doivent conserver leur encodage UTF-8 avec BOM et la compatibilité Windows PowerShell 5.1. Seules les DLL auxiliaires sont précompilées ; les sources PS restent en 5.1.
3. **Déclarer les composants.** Un nouveau fichier utilisé par le logiciel doit figurer dans Get-PestoRuntimeFiles de Pesto-Integrity.ps1. Un fichier non déclaré n'entre pas dans PROD. Déclarez les exports du moteur dans Pesto.Engine.exports.json ; ne modifiez pas manuellement son runtime généré.
4. **Fabriquer.** Depuis le dossier DEV, lancez .\FABRIQUER_PROD.cmd dans le terminal de compilation. Le script vérifie syntaxe et configuration, génère le module moteur, recompile le lanceur avec les nouvelles empreintes, régénère le manifeste, puis vérifie les fichiers produits.
5. **Contrôler la sortie.** Un nouveau dossier Pesto_PROD_… contient Pesto.exe et wad. Les sources et les distributions existantes ne sont pas écrasées. Les journaux, préférences, reçus, tests et outils DEV ne sont pas copiés.
6. **Qualifier puis distribuer.** Contrôlez le candidat sur votre plateforme selon le chapitre 25, puis distribuez ensemble l'EXE et le dossier wad.

Pour sélectionner un dossier wad complet et une destination neuve :

~~~
$source = 'D:\Sources\wad'
$sortie = 'D:\Livraisons\Pesto_PROD'
python .\tools\Build-PestoProduction.py $source --output $sortie
~~~

Le cfg.json fourni est inclus dans la sortie. Pour une distribution générique, utilisez le modèle neutre ; pour une distribution interne configurée, utilisez votre fichier validé. Les composants du runtime et le lanceur doivent toujours provenir de la même fabrication.

## Prérequis du poste de compilation

Sous Windows : Python 3.10 ou plus récent et Windows PowerShell 5.1 x64. Avec Visual Studio (C++ et Windows SDK), lancez .\FABRIQUER_PROD.cmd dans Developer PowerShell for VS en x64 : le double-clic n'en reprend pas l'environnement. Avec LLVM (clang et lld-link dans PATH), le double-clic convient. Sous macOS : Python 3.10 ou plus récent, PowerShell 7.4 et LLVM ; --powershell précise le chemin du moteur.

> [!NOTE] La migration vers PowerShell 7 n'est pas prévue. Le moteur cible Windows PowerShell 5.1.

Le script n'installe aucune dépendance, ne lance pas Pesto et ne contacte pas AD. La compilation depuis macOS produit les fichiers Windows mais ne constitue pas une validation Windows.

## Installation et mise à jour

| Outil DEV | Usage |
|---|---|
| docs/FABRIQUER_PROD.md | Procédure détaillée, prérequis et commandes de fabrication classique. |
| tools/Build-PestoProduction.py | Reconstruction depuis le dossier wad complet, vers une destination neuve. |
| tools/Install-Pesto.ps1 | Copie vérifiée dans un dossier neuf sous un parent existant, sans modifier ses droits. |
| tools/update_installation.py | Aperçu puis remplacement du code installé, sauvegardes et récupération après interruption. |
| tools/Build-PestoPacks.py | Assemblage des archives DEV et PROD à partir d'un runtime reconstruit cohérent. |
| tools/cfg.template.json | Configuration neutre du paquet générique. |
| tools/cfg.modele-complet.json | Exemple complet à adapter et valider. |

L'installation et la mise à jour conservent les droits et les données décrits aux chapitres 11 et 21.

**Vérifier les empreintes.** Comparez l'EXE à wad\package.json avec Get-FileHash, puis lancez Pesto.exe --check-json. Conservez le rapport de fabrication et les empreintes des archives.

## Constituer le dossier de livraison

| Outil DEV | Preuve produite |
|---|---|
| tools/check_toolchain.py | Concordance des versions du compilateur avec le profil épinglé. |
| tools/reproducible_build.py | Deux fabrications indépendantes et comparaison des artefacts. |
| tools/release_assurance.py | SBOM CycloneDX, provenance locale, versions et empreintes des packs, guides et rapports fournis. |
| tools/Sign-PestoRelease.ps1 | Signature sur une copie dédiée avec un certificat existant et horodatage approuvé (optionnel, hors périmètre livraison standard). |
| tools/Test-PestoEnvironment.ps1 | Inventaire en lecture seule de Windows, du runtime et des politiques observables. |

> [!NOTE] La signature Authenticode est optionnelle pour cette livraison. La provenance et les droits de redistribution des DLL Microsoft restent à établir.

La provenance locale est non signée tant qu'une attestation authentifiée n'a pas été produite. La signature exige un certificat de l'organisation avec clé privée ; l'outil ne crée aucune confiance et ne resigne pas les DLL Microsoft. Toute signature modifie les empreintes : constituez les packs à partir de la sortie vérifiée complète.

Les rapports doivent distinguer tests locaux avec doubles, rendu WPF, interface de l'application et opérations AD réelles. Les combinaisons Windows, langue, compte ou politique absentes de la recette restent non qualifiées. La provenance et les droits de redistribution des DLL Microsoft sont à documenter séparément de leur signature.

# 27 Mots à connaître

| Terme | En clair |
|---|---|
| AD | Active Directory local, avec ses objets ordinateurs et ses OU. |
| OU et DN | Unité d'organisation et son chemin LDAP exact. |
| GUID | Identité stable d'un objet ; le nom affiché seul ne suffit pas. |
| Reçu | État durable d'une opération, de son plan et de ses effets. |
| Observation | Lecture datée des faits Windows et AD. |
| Vérification | Résolution consignée explicitement quand les conditions sont prouvées. |
| Canal sécurisé | Lien de confiance entre le poste et le domaine, contrôlé après une jonction. |
| OU de préparation | OU de transit imposée quand la jonction directe en production n'est pas autorisée (site PREPROD). |
| Réplication | Recopie des changements d'un contrôleur de domaine vers les autres, avec un délai. |
| Banc de master | Poste de travail où plusieurs techniciens préparent des PC en même temps. |
| Lot, file | Postes préparés ensemble puis traités l'un après l'autre dans « Plusieurs postes ». |
| Poste pilote | Première ligne d'un lot, traitée seule pour valider le parcours avant le reste. |
| Lanceur | Pesto.exe : vérifie l'emplacement, le verrou et les empreintes avant de démarrer Windows PowerShell. |
| Manifeste, empreinte | wad\package.json liste les composants et leur SHA-256 ; toute différence bloque le démarrage (code 125). |
| UAC | Demande d'élévation de Windows ; un refus rend 1223 et ne lance rien. |
| POLICY | Section de cfg.json qui encadre exclusions et options ; schéma fermé. |
| Coordination | Répertoire partagé optionnel qui lie un engagement aux identités et aux noms entre opérateurs. |
| Entra hybride | Poste inscrit à la fois dans l’AD et dans l’annuaire en ligne de Microsoft ; réinscription et SSO à contrôler séparément. |
| Démonstration | Mode de formation sans AD, données fictives (-Demo, -DemoJoin ou DEBUG.GUI). |
| Simulation | Mode de test : lectures AD réelles, aucune modification (DEBUG.Simulation). |
| Consultation | Lancement Pesto.exe --consult, sans UAC ; modifications et résolution bloquées. |

# 28 Scénarios administrés, approbations et extensions

Ce chapitre détaille les fonctionnalités avancées : scénarios imposés, approbation de campagne, modification d'attributs et jonction hors connexion. Ces options sont désactivées par défaut et nécessitent une configuration explicite.

## Scénarios administrés (ScenarioJson)

Le scénario impose des valeurs pour Type, SiteCode, ServiceCode et TargetOU. Il empêche le technicien de sortir du périmètre autorisé.

**Configuration locale**

Dans cfg.json, sous POLICY, ajoutez l'objet Scenario :

~~~
"POLICY": {
  "Schema": 1,
  "Scenario": {
    "Schema": 1,
    "Name": "Portables Paris",
    "Required": ["Type", "ServiceCode"],
    "Allowed": {
      "Type": ["P"],
      "SiteCode": ["PA"]
    },
    "Locked": {
      "ServiceCode": "INF"
    }
  }
}
~~~

Les facettes sont extraites du nom réellement demandé. Le moteur ne se fie pas aux seules étiquettes du formulaire. Si une valeur est hors scénario, la préparation est refusée. Le bouton « Scénario administré… » affiche les contraintes.

**Configuration par GPO (HKLM)**

Pour imposer le scénario via la stratégie de groupe, créez la valeur REG_SZ ScenarioJson sous HKLM\SOFTWARE\Policies\M4D\Pesto. Cette valeur remplace le scénario local. Le moteur relit la politique avant toute mutation.

~~~
HKLM\SOFTWARE\Policies\M4D\Pesto
  ScenarioJson (REG_SZ) : {"Schema":1,"Name":"Portables Paris","Required":["Type","ServiceCode"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"INF"}}
~~~

## Approbation de campagne (CampaignApprovalJson)


La valeur REG_SZ CampaignApprovalJson, dans la même clé HKLM, définit les campagnes concernées et les signataires autorisés :

~~~
{"Schema":1,"Campaigns":["PARIS-2026"],"Signers":[
 {"CertificateSHA256":"empreinte-sha256-du-certificat-DER-en-64-hex-minuscules",
  "Sid":"S-1-5-21-111-222-333-1001"}]}
~~~

"*" impose une campagne et un accord pour toute opération concernée par ce moteur. La confiance vient exclusivement de HKLM, jamais du plan ou du certificat joint à l'accord. Une modification locale de cfg.json ne supprime pas cette obligation. Une suppression du certificat de cette liste révoque son autorisation.

Depuis une session Windows de l'approbateur, importer Pesto.Engine.psd1, lire les plans préparés, puis appeler :

~~~
$accord = New-PestoCampaignApproval -Plans $plans -Certificate $certificat -Minutes 60
~~~

La clé privée reste chez l'approbateur. RSA SHA-256, au moins 2048 bits, signe le payload exact ; le certificat et la signature sont publics. L'accord lie campagne, SID, échéance (24 heures maximum), domaine, machine opératrice, configuration, identités source/destination et effets demandés (y compris le diff d'attributs ou l'empreinte du blob ODJ). Les horodatages de préparation et les facettes redondantes ne remplacent pas cette identité des effets. L'exécution du plan garde sa propre validation d'intégrité et d'expiration.

Transmettre l'objet accord avec -Approval à Invoke-PestoCommand, Invoke-PestoUnattendedOperation, Invoke-PestoUnattendedJoin ou au parcours extensions. Le SID exécutant doit différer du SID signataire associé au certificat. La signature, la politique actuelle et l'expiration sont revérifiées au passage vers les effets. Ce mécanisme ne crée ni service de tickets ni serveur d'approbation.

## Modification d'attributs AD (Description, Location, ManagedBy)

Ce parcours permet de modifier les attributs description, location et managedBy d'un objet AD existant.

**Préparer le plan**

Variables :
- $wad : Chemin du dossier wad.
- $guid : GUID de l'objet AD cible.

~~~
$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action Attributes `
    -ObjectGuid $guid `
    -Attributes ([pscustomobject]@{description='Atelier';location='Paris'}) `
    -OutPlanPath C:\Plans\attributs.json
~~~

Le plan exporte un diff avant/après. Une chaîne vide efface l'attribut.

**Exécuter le plan**

Variables :
- $accord : Objet d'approbation si requis par la politique de campagne.

~~~
$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action Attributes `
    -PlanPath C:\Plans\attributs.json `
    -IdempotencyKey 'PARIS-2026/attributs-01' `
    -Approval $accord -Execute
~~~

Le moteur relit le GUID, le nom, l'emplacement et les valeurs initiales avant écriture. Une seule commande Set-ADObject est utilisée. En cas d'interruption, le résultat est incertain (97).

**Observer les effets**

La variable $id désigne l’identifiant de l’opération dans le reçu enregistré. Pour vérifier l’état après une exécution incertaine ou pour réconcilier le reçu sans nouvelle écriture :

~~~
Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action AttributeObserve -OperationId $id
~~~

## Jonction hors connexion (ODJ)


Activer explicitement POLICY.AllowOfflineJoin. La machine cible doit être un poste Windows installé, élevé, hors domaine, sans renommage en attente. WinPE, les images Windows hors ligne, la coordination réseau et les exclusions de groupes nécessitant AD ne sont pas pris en charge par ce parcours. Aucune jonction en ligne de secours n'est lancée.

L'administrateur de provisionnement fournit un fichier djoin pour **le nom actuel exact de cette machine**, ainsi que le GUID du compte et son OU. Pesto consomme ce blob opaque ; les métadonnées déclarées ne sont confirmées dans AD qu'à l'observation après redémarrage. Il ne crée pas le compte de provisionnement dans cette étape.

~~~
$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineImport `
    -BlobPath C:\Provisionnement\poste.odj -ObjectGuid $guid -TargetOU $ou -Execute
# Faire approuver $r.Plan si la politique de campagne l'exige.
Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineApply `
    -BlobId $r.BlobId -Approval $accord -Execute
# Après le redémarrage volontaire et le retour réseau :
Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineObserve -BlobId $r.BlobId
~~~

Le secret est chiffré par DPAPI LocalMachine dans ProgramData, avec une ACL limitée à SYSTEM et aux administrateurs. Il ne figure ni dans le plan ni dans l'audit. L'import ne supprime pas le fichier source : l'opérateur doit en gérer la protection et la suppression selon sa procédure. Aucun transport ou stockage cloud n'est créé. L'application expire après 24 heures ; cela **n'invalide pas le secret du compte AD**.

L'intention durable précède djoin /requestodj /localos. Un fichier plaintext éphémère est nécessaire à djoin, dans le même dossier protégé ; il est supprimé en fin de tentative avec la copie chiffrée. Après une coupure brutale, un résidu protégé peut subsister et doit être retiré par l'administrateur après examen du reçu. L'identifiant du blob empêche un nouvel import ou une nouvelle application silencieuse. Le code 3010 signifie seulement qu'un redémarrage est requis. L'observation vérifie le nouveau démarrage, la machine, le nom, le domaine, le GUID, l'OU et le canal sécurisé avant de clôturer le reçu. Aucun redémarrage ni -Repair automatique.

## Définir la convention de nommage

Le champ NamingConvention de la configuration définit l'ordre et la largeur des facettes. Il reste facultatif ; son absence conserve le format historique.

~~~
{"Schema":1,"Id":"atelier","Tokens":["Service","Number","Type","Prefix","Site"],
 "Widths":{"Prefix":3,"Site":2,"Service":2,"Number":2},"Types":"PSV"}
~~~

Avec le préfixe 123, le site AB et le service IT, le premier portable s'appelle IT01P123AB. Le numéro peut se trouver au milieu. Les largeurs sont fixes, les cinq facettes obligatoires, le total limité à 15 caractères et le numéro compris entre 1 et 10^largeur - 1. Préfixe et numéro sont numériques ; site alphabétique ; service alphanumérique. Adapter aussi CONF.Prefixe, CONF.PreprodSite, TAGS et le catalogue de sites/services aux largeurs déclarées. Importer et valider la configuration par le parcours de paramètres existant ; aucune réécriture des anciens noms n'est faite.

## Lectures, index et affichage

Le moteur réutilise un pool borné de runspaces de lecture, isolé par compte, domaine et contrôleur. Les mutations utilisent leur propre runspace. L’index compact et les helpers C# sont livrés dans Pesto.Runtime.dll ; leur chargement vérifie les empreintes. L’inventaire peut utiliser DirSync et revient au scan complet si les droits ou le curseur ne permettent pas le delta. Le registre est paginé ; les tableaux de noms et d’interventions mettent à jour les lignes modifiées en conservant tri et sélection. Ces mécanismes ne changent ni les droits AD ni le contrôleur et ne rejouent aucune mutation.
