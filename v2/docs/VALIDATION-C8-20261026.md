# Reprise C8 — fichiers natifs et réponses opérateur, 26 octobre 2026

**Campagne finale réussie : [40323591018](https://github.com/M4D135/pesto/actions/runs/40323591018), source `483a8a3a4a02914e77db611f8d1cf83fb7979c6f`.**
Les [preuves et téléchargements](evidence/20261026/windows-483a8a3/README.md) identifient les ZIP
testés. Les rapports [C7](VALIDATION-C7-20261026.md) et [C6](VALIDATION-C6-20261026.md)
restent attachés à leurs sources historiques.

## Corrections et développement du banc

Reprise de la branche codex/pesto-v2-20261023 depuis 0523c1df9357de06d301a9508ae7d3b646cb03ec.

Corrections produit :

- Import natif : lecture bornée d’un instantané avec décodage strict UTF-8/16/32 selon BOM ; refus des octets invalides. Le dialogue reste sur le fil UI, la lecture et l’écriture de fichiers passent hors de ce fil.
- Export natif : fichier temporaire, flush, contrôle d’annulation puis déplacement atomique ; nettoyage du temporaire.
- Un poste / Plusieurs postes : numéro de requête pour la recherche ; ancienne réponse ou ancienne erreur ignorée après nouvelle recherche ou saisie. Les suites asynchrones s’arrêtent après navigation.
- File : retrait sérialisé, plan préparé invalidé immédiatement, anciennes listes ignorées. Un ajout déjà envoyé conserve son résultat moteur mais ne déclenche pas la lecture du poste suivant après navigation.

Contrôles locaux exécutés : compilation croisée de l’hôte et compilation tests Release sans avertissement ni erreur, 29 tests ProfileConfiguration, 3 ConfigurationOnly, 41 contrôles opérateur Chromium, 149 contrôles statiques. Les doubles d’annuaire sont déclarés ; ils ne prouvent pas une mutation AD réelle.

Développement du banc Windows : même Pesto.exe, nouveau dossier Temp obligatoire, profil temporaire, aucun adaptateur AD. Dialogues natifs de fichier, annulations, comparaison du contenu, import dans un second profil et construction d’un pack personnalisé complet. Ce banc ne couvre pas la sélection positive du dossier de destination, UAC sous un autre compte, les ACL réelles ni AD.

Campagnes intermédiaires conservées :

- 40311076581 / 0b7fd982afa9049e10e2cfe65cbf849017fddc3a : échec du banc sur l’attente de l’indicateur InterfaceReady réservé au contrôle santé. Aucun dialogue atteint. Profil temporaire supprimé. Corrigé en observant le véritable shell local via les étapes fermées du banc existant.
- 40312774476 / 08849841bf441115d7f0b2ee5ad2f0101deb605d : parent prêt, assertion d’export échouée. La preuve ne contenait pas le chemin retourné et ne permet pas d’en attribuer précisément la cause. Le scénario a ensuite fourni un nom initial absolu dans son dossier temporaire et ajouté les observations du chemin et du contenu.
- 40314345999 / 95f901becd9694141cd0666591636ddb7883f3ed : export exact confirmé, puis arrêt du pilote à l’import. L’arbre natif prouve Edit/1148 pour l’import, alors que l’export exposait Edit/1001. Le pilote accepte ces deux identifiants et exclut la barre d’adresse 41477.

Ces campagnes ont passé leurs contrôles moteur/pont/web et de coexistence natifs précédents, mais ne valident pas une livraison complète. Aucune archive candidate réussie n’a été publiée par ces trois runs.

Premier passage VM e70692c : console session 1, identité Windows de domaine non élevée, EXE exact contrôlé. Démonstration réussie : 44 refus directs, six transitions fraîches, trois profils/deux instances/trois reçus, brouillon/route/préférences conservés, fermeture et suppression des profils. Export natif exact ensuite confirmé ; le banc configuration échoue à `noExportTemporaryFile`. Son assertion cherchait `*.tmp` dans tout le sous-arbre incluant le profil WebView2 actif, alors que SaveExportAsync écrit seulement `export.json.<GUID>.tmp` à côté de la destination. Le commit 483a8a3 limite le contrôle à ces fichiers frères et consigne leur nombre. Les fichiers observés au premier échec n’ont pas été inventoriés avant nettoyage : leur origine exacte n’est pas prouvée.

Chronologie VM : identité BIOS et membre de domaine relues ; snapshot à froid C7 conservé. Après blocage avec heartbeat absent, David autorise le redémarrage de la seule VM. La tentative de reset trouve la VM arrêtée ; état aborted relu, puis startvm du même UUID réussi. Aucun snapshot restauré et aucune VM voisine touchée. Guest Control est accessible avec redirection des sorties VBox vers des fichiers ordinaires sur l’hôte. Après les bancs natifs, la console se reverrouille ; inspection AD préparée séparément, en lecture seule et avec configuration de laboratoire créée sans lecture du cfg privé.

Diagnostic console hôte : VBox.log associe la seule VM à VirtualBoxVM PID3268, dont SessionId=0 ; le bureau interactif du PC est en session2. La GUI/Qt était donc lancée dans la session SSH non interactive. Le démarrage GUI de l’orchestrateur était inadapté à la saisie native par David. L’inspection AD a atteint CredUI sous élévation (PID3132, session invitée1) mais aucun identifiant n’a été saisi ; seuls la demande et l’identité locale ont été produits.


## Campagne Windows finale

La campagne finale passe 201 tests moteur ciblés sur fixtures, 15 du pont et 30 du compagnon,
le parsing PS5.1 des 18 variantes métier et du script du banc, puis les quatre suites web
33/41/8/149. Les compilations sont sans avertissement ni erreur.

Le vrai EXE et WebView2 fixe passent démarrage, coexistence locale/démo et fermeture dans les
deux canaux, puis les 14 contrôles natifs de configuration et les quatre transactions entre
compilations distinctes. Huit reçus santé et sept lancements du helper sont recoupés. Le détail,
les empreintes et les limites figurent dans la synthèse liée ci-dessus.

La campagne intermédiaire [40315650487](https://github.com/M4D135/pesto/actions/runs/40315650487)
avait déjà passé ces essais sur `e70692c`. Son premier passage VM a ensuite révélé l’assertion
de nettoyage trop large du banc. Les preuves de cette campagne restent distinctes du candidat
final `483a8a3`, qui limite cette assertion aux temporaires de l’export.

## Laboratoire et reste à qualifier

Le pack PROD exact de `483a8a3` a été installé sur la seule VM autorisée : SHA du ZIP et de l’EXE vérifiés dans l’invité, 500 entrées de l’inventaire conformes. L’identité BIOS, l’appartenance au domaine et la session console ont été relues. Le banc a tourné en session interactive 1, sans élévation et sans adaptateur AD.

La **démo du candidat final réussit** (code 0, reçu SHA-256 `1e278e1f9f2c584d221837c262cd7719c966d89ca05431f647b630b32e192453`). Le banc de configuration échoue ensuite avec `qualification.configuration.dialog-path`, au stade export : seul `parentReady` est acquis. Ce refus constate un écart entre le chemin envoyé et la relecture immédiate du contrôle natif ; sa cause précise n’a pas été déterminée. Les 14 contrôles CI réussis ne remplacent pas cet échec VM. Le reçu d’échec porte le SHA-256 `f3816b8784c9089fdd5832786372d00708245f91ccea635085965bf9179fdffd`.

À **13:11:04 UTC**, VirtualBox passe cette VM à **aborted**. Le journal du processus `VBoxHeadless.exe` associé à cette VM contient une exception dans `VBoxC.dll`, offset `0x00030c46`. Le déclencheur précis reste inconnu. Le reçu du banc et les deux hashes avaient été relus à 13:10:48 UTC ; la collecte complète des preuves invitées est ensuite refusée parce que la VM est arrêtée. Aucun nouvel essai ni redémarrage en boucle n’a suivi ce crash.

Le premier passage sur `e70692c` avait validé la démo et l’export exact, puis révélé le contrôle trop large des temporaires, corrigé par `483a8a3`. Ses quatre captures et sa preuve complète sont conservées séparément. Il ne vaut pas réussite de la configuration sur le candidat final.

Un problème distinct d’affichage a été corrigé : la GUI lancée depuis SSH appartenait à la session 0 de l’hôte. Après arrêt forcé de la seule VM, autorisé par David, le démarrage headless avec VRDE toujours désactivé lui a permis de confirmer l’ouverture de la console par Afficher. L’instantané à froid reste conservé ; aucune restauration ni intervention sur les VM voisines.

L’inspection AD préparée utilise un harnais distinct compilé depuis les sources courantes et une configuration de laboratoire créée sans lire le cfg privé. La première tentative atteint la saisie native sous élévation, sans identifiant saisi, et ne produit que la demande et l’identité locale ; la tentative suivante ne produit pas de nouvelle preuve. Aucun appel AD métier ni mutation n’est qualifié. Les essais AD restent bloqués par l’instabilité de la VM. Reprise : stabiliser cet environnement, relire son identité et les reçus, reproduire le dialogue d’export puis reprendre l’inspection et le canari réversible, sans restauration de DC ni sortie de domaine improvisée.


La coexistence avec session AD connectée, les mutations AD, UNC, acquisition officielle GitHub,
UAC sous une autre identité, Program Files, ACL/DPAPI réels, ODJ, CLI et Entra demandent leurs
preuves propres. Le protocole de sortie/jonction positive ne dispose pas encore d’un retour
démontré vers l’objet AD d’origine ; aucune sortie de domaine n’est utilisée pour forcer un essai.

## Livraison

Les deux packs ont été téléchargés, leurs enveloppes, ZIP internes, manifestes et EXE contrôlés.
Ils restent candidats et ne remplacent pas la V1. Ce bilan est poussé séparément des sources
binaires ; les ZIP exécutés ne sont pas réassemblés après modification de la documentation.
