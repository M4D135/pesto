# Qualification de Pesto 1.0

Ce protocole qualifie un build précis. Un résultat local avec doubles, un rendu WPF isolé et une opération AD réelle sont trois preuves différentes. Les scripts de préparation ne produisent jamais de résultat PASS pour une action non exécutée.

## Préparer la campagne

1. Geler les sources, construire le lanceur, régénérer puis vérifier son manifeste.
2. Relever SHA256 de Pesto.exe. Préparer `python tools/qualification.py plan --build SHA256 --output campagne.json`.
3. Renseigner Windows (édition/build), langue, .NET Framework, mode de compte, politique App Control, DPI physique, résolution, zoom Pesto, thème et identité du contrôleur découvert par Windows. Ne pas enregistrer de mot de passe.
4. Exécuter `powershell -NoProfile -File tools/Test-PestoEnvironment.ps1 -ReportPath environnement.json`. Cette lecture ne change aucune politique et ne certifie aucun droit de redistribution.
5. Conserver la configuration et les reçus avant les scénarios. Choisir des postes et objets de laboratoire autorisés ; aucune manipulation de réplication, de sécurité ou de DC partagé n'est implicite.

## Matrice minimale

| Dimension | Cas à distinguer |
| --- | --- |
| Windows | Windows 11 pris en charge et Windows Server administrateur pris en charge ; versions/builds exacts |
| Langue | Français et anglais ; messages natifs localisés |
| .NET | Version réellement présente, au moins 4.7.2 ; PowerShell Windows 5.1 x64 |
| Identité | Windows intégrée ; compte AD explicite ; SYSTEM pour les adaptateurs qualifiés |
| Politique | Politique habituelle ; App Control en audit puis imposé dans un labo autorisé ; langage contraint |
| Affichage | 100/150/200 % Windows ; zoom Pesto 80/100/150 ; clair/sombre/contraste élevé ; petite fenêtre ; deux écrans de DPI différents |
| Réseau | Disponible ; indisponible ; lecture lente ; deux postes partageant la coordination SMB ; deuxième DC seulement si le labo le permet |

Aucune combinaison absente de la campagne ne doit être déclarée prise en charge sur la seule foi d'une combinaison voisine.

## Parcours GUI de bout en bout

Pour chaque cas : capture avant, geste souris/clavier, état observé, capture après, reçu éventuel et empreinte du build. `Capture-PestoQualification.ps1` capture uniquement la fenêtre déjà au premier plan et son arbre UIA en lecture seule. Il ne clique pas et n'attribue aucun verdict. Vérifier visuellement la capture : un écran en veille ou verrouillé invalide l'observation.

- Premier lancement : importer la configuration, lire les erreurs, prévisualiser puis enregistrer ; relancer.
- Jonction : préparer, vérifier, confirmer dans le labo, constater le résultat et redémarrer explicitement. Aucune sauvegarde de travail utilisateur ne fait partie de ce parcours.
- Un seul poste : lire, préparer, comparer avant/après, annuler une confirmation puis confirmer une opération autorisée.
- Plusieurs postes : importer, corriger les lignes, modifier une sélection, annuler un changement local, préparer tout le lot, interrompre après l'action en cours.
- Noms : changer les filtres et la plage, lire la capacité, choisir un nom ; vérifier que le choix aléatoire porte sur tous les candidats éligibles.
- Paramètres : erreur de validation, modification externe du JSON, aperçu, abandon puis sauvegarde explicite.
- Interventions : filtre, détail, export, comparaison et suivi facultatif d'une opération terminée. Une opération incertaine ou partielle garde ses protections.
- Fermeture pendant lecture : aucune nouvelle écriture de nettoyage ; résultats/reçus préservés selon leur état réel.

## Visuel et accessibilité

La matrice visuelle doit vérifier les commandes essentielles et leurs pieds de page, pas uniquement la taille de fenêtre. Comparer captures de même build et même scénario ; exclure seulement les régions variables déclarées (horloge, données de laboratoire). Aucun recadrage ne doit masquer un défaut.

Avec clavier seul : Tab/Maj+Tab, F6/Maj+F6, Entrée, Échap, fermeture d'un dialogue et retour du focus. Avec Narrator réellement activé : noms des contrôles, changement de zone, erreurs associées au champ, annonces de progression regroupées et annonce finale. Le succès UIA ne remplace pas une écoute Narrator.

## Frontières de persistance et effets

Les suites `test_update.py`, `test_update_inputs.py`, `test_managed_update.py` et `test_packaging_edges.py` injectent des échecs à des frontières de copie/publication. Le banc d’installation gérée vérifie aussi la détection et la désinstallation après mise à jour, ainsi que l’ancien et le nouveau reçu de propriété lors des reprises. La suite `Run-Engine120Tests.ps1` couvre les contrats du moteur avec doubles. Pour chaque injection, vérifier l'ancien contenu, le reçu, l'absence de seconde commande et les fichiers temporaires. Une panne électrique NTFS/SMB n'est pas simulée par une exception Python : la qualifier séparément si demandée.

`test_managed_update.py` provoque également la terminaison brutale du processus à
chaque frontière de remplacement, puis une seconde terminaison pendant la reprise.
La reprise suivante doit restaurer le contenu et le reçu de propriété d’origine.
La CI exécute ces scénarios sur les disques des runners Windows 2022 et 2025. Ce banc
ne coupe ni l’alimentation ni un partage SMB et ne réalise aucune mutation AD.

La détection d’une installation gérée abîmée retourne un état non sain ; elle ne
déduit aucun droit de suppression d’un reçu illisible. Le reçu initial est publié
par remplacement atomique. Le rapport de reprise reste `Recovered=false` tant que
le verrou n’a pas été retiré. Si seul l’enregistrement final échoue après la reprise
confirmée, `ResultReportWritten=false` le signale sans rejouer les effets.

Une désinstallation interrompue conserve son verrou et ses fichiers restants pour
inspection manuelle. Son journal ne permet pas d’adopter des fichiers non possédés
ni d’effacer la configuration. Les sauvegardes de préparation sont conservées.

## Deux opérateurs et SMB

Employer deux processus sur deux machines distinctes, même partage et mêmes filtres. Démarrer simultanément la réservation d'un même candidat : un seul propriétaire doit être accepté. Puis tester deux candidats distincts, arrêt du propriétaire, perte du partage, réponse tardive. Vérifier les identités/opérations et les fichiers du partage. Aucun fichier de verrou n'est effacé pour faire réussir le test. Réservation AD et coordination restent désactivées dans la distribution neutre.

## Réplication AD

Consigner le DC réellement choisi, les identités GUID et les heures de lecture. Si deux DC existent dans le labo, comparer leurs observations après une opération autorisée, en restant attaché au DC Windows pour l'exécution. Ne pas changer la topologie, forcer la réplication ou basculer vers le PDC. L'absence sur un autre DC n'autorise ni réemploi ni rejeu. Sans deuxième DC, marquer le scénario BLOCKED, avec raison.

## Longues sessions et secrets

`Measure-PestoSession.ps1 -TargetProcessId ID -Samples 120 -IntervalSeconds 5 -ReportPath session.json` mesure mémoire privée, working set, handles, threads et CPU. Répéter une charge identique après échauffement ; une hausse ponctuelle n'est pas une fuite. Les abonnements doivent aussi être examinés par les tests du composant concerné.

Le rapport conserve les échantillons acquis si le processus s’arrête ou devient
inaccessible. Il distingue ces cas et refuse de mélanger deux processus réutilisant
le même PID. Le fichier de sortie doit être nouveau : un rapport concurrent reste
intact. `Run-SessionMeasureTests.ps1` vérifie ces comportements avec de vrais processus.

Pour un contrôle WPF reproductible sans AD, exécuter sous Windows PowerShell 5.1,
en STA :

```powershell
powershell -NoProfile -STA -File tests/Run-WpfSessionTests.ps1 -MinimumDurationSeconds 120 -ReportPath session-wpf.json
```

Le banc charge le véritable XAML, crée et ferme des fenêtres, parcourt huit pages et
relève les références faibles, la mémoire, les handles et les threads après
échauffement. Son verdict `MEASURED_ONLY` concerne cette charge isolée ; il ne clôture
pas la mesure prolongée de l’application complète avec ses workers et ses accès AD.

`Run-UxTests.ps1` conserve les mesures d’un arbre XAML disposé à 1460, 1100 puis
1460 DIP ainsi que 200 cycles de navigation. Les dimensions DIP de cet arbre ne sont
pas une preuve de résolution physique, de DPI Windows ou de comportement sur deux écrans.

Injecter uniquement des secrets factices dans les chemins d'erreur, adaptateurs et exports. `scan_evidence.py dossier --canary-file fichier-hors-dossier.txt` détecte ces marqueurs dans les textes UTF-8/UTF-16 sans les afficher. Les images et fichiers non textuels restent signalés non examinés ; compléter par OCR/relecture visuelle. Aucun vrai secret de laboratoire ne doit être committé.

`Run-SecretOutputsTests.ps1 -EvidenceDirectory dossier-neuf -ReportPath secrets.json`
produit des sorties réelles avec un marqueur synthétique : journal asynchrone,
erreurs, HTML, diagnostic, compte rendu et dossier de support. Le contrôle couvre aussi
les exports internes conservant les noms de postes : cette option n’autorise pas
l’export de mots de passe ou de jetons. Le scanner vérifie ensuite ces fichiers,
indépendamment du verdict de la suite. Il ne garantit pas l’absence de tout secret
inconnu et n’analyse pas les pixels des captures.

## Composants Microsoft

La procédure détaillée est dans [MICROSOFT_COMPONENTS.md](MICROSOFT_COMPONENTS.md).
`release_assurance.py create` publie un inventaire lié aux empreintes du manifeste ;
`Test-PestoEnvironment.ps1` relève en lecture seule les versions et les signatures
effectivement observées sur Windows. Les justificatifs du paquet d’origine et des
droits de redistribution restent nécessaires, indépendamment de la validité d’une
signature Authenticode.

## Enregistrer une observation

`python tools/qualification.py record --input campagne.json --output campagne-01.json --case gui/first-run-import --status PASS --observed "Résultat concrètement observé" --attachment capture.json --attachment window.png`

Le rapport précédent est conservé. Un cas déjà renseigné ne peut pas être réécrit. Une nouvelle tentative conserve son propre rapport et le lien vers l'échec initial.

Pour relier ces observations aux 120 exigences et aux fichiers distribués, suivre
la [procédure de clôture](CLOTURE_120.md). Une procédure prête ou une capture seule
ne clôture pas une qualification non exécutée.
