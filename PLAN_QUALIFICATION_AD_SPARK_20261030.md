> Brouillon rédigé par le Spark le 30/10/2026, non relu ligne à ligne. Prérequis à valider par David avant toute mutation AD.



# Plan de recette labo — Pesto V2 (fonctions non qualifiées)

Périmètre : VM `PESTO-W11-TEST` sur hôte VirtualBox `degun`, domaine `labo.local`, DC unique `LABO-DC01` (`10.77.0.10`).  
Cible recommandée : Pesto 2.0.7 ; sinon qualifier 2.0.2 et marquer l’écart.  
Ne pas utiliser `FILPRO` ni `DOMENIA`. Ne pas arrêter/restaurer le DC.

## Règles transverses

1. **Empreinte build obligatoire**
   - Avant chaque campagne :
     ```powershell
     Get-FileHash C:\Pesto\PROD\Pesto.exe -Algorithm SHA256
     ```
   - Conserver dans `00_build.txt` : SHA-256, version, date, VM, snapshot.
   - Chaque preuve est nommée : `<build>_<recette>_<preuve>`.

2. **Instantané à froid avant mutation AD**
   - VM éteinte :
     ```powershell
     VBoxManage controlvm "PESTO-W11-TEST" poweroff
     VBoxManage snapshot "PESTO-W11-TEST" take "PRE_<recette>_<build>" --description "..."
     VBoxManage startvm "PESTO-W11-TEST" --type gui
     ```
   - À faire avant toute création/suppression d’objet AD ou opération Pesto mutante.

3. **Aucun mot de passe saisi par Claude**
   - Si une fenêtre demande un mot de passe : **David saisit**.
   - Utiliser le canal `guestcontrol` élevé avec le compte administrateur domaine déjà configuré ; ne pas afficher les identifiants.

4. **Aucune suppression AD par Claude**
   - Claude prépare, capture, vérifie.
   - **David** confirme/exécute la suppression des objets AD.

5. **Aucun redémarrage implicite**
   - Pesto CLI ne redémarre pas.
   - Si une opération annonce `PendingRestart`, on capture le reçu, puis **David autorise/exécute** le redémarrage.

6. **Preuves minimales par recette**
   - Captures écran.
   - Plan/reçu JSON si export disponible.
   - `--cli verify --receipt <ID>` pour JSON d’observation si nécessaire.
   - Journaux : `%ProgramData%\GP\V2\automation` si présent.
   - Requêtes AD en lecture seule : `dsquery computer` ou `Get-ADComputer`.

---

## Prérequis globaux

### À faire une fois avant les recettes AD

1. **Snapshot de base**
   - `PRE_BASE_<build>`.

2. **Mise à jour vers 2.0.7 si souhaitée**
   - Snapshot `PRE_UPDATE_<build>`.
   - Mise à jour par les boutons ou ZIP vérifié.
   - Relever le SHA-256 après mise à jour.
   - Si échec : restaurer le snapshot et qualifier 2.0.2.

3. **Configuration de test via `Pesto.exe --settings`**
   - Lancer avec le compte qui servira aux tests AD, via `guestcontrol` élevé.
   - Configurer :
     - Domaine : `labo.local`
     - Racine OU gérée : OU de test fournie par David
     - Sites/services : valeurs fournies par David
     - `EntraPolicy=Disabled`
     - `DsregLeaveOnMove=false`
     - `ClearProtectionOnMove=false`
     - `AllowHybridRepair=false`
     - `AuditEventLogEnabled=false` sauf si source EventLog Pesto déjà installée
     - `BlockJoinOnClockSkew=false` pour isoler les tests
     - `ExcludedGroupGuids` vide
   - Enregistrer sans mutation AD.

4. **OU de test AD**
   - David crée une OU dédiée, par exemple :
     - `OU=PestoQualif,OU=Paris,DC=labo,DC=local`
   - Snapshot VM avant création.
   - Droits : compte administrateur domaine utilisé pour les tests.

---

# R1 — Jonction avec compte ordinateur précréé

## Prérequis

### Configuration Pesto
- `POLICY.AllowPrecreatedJoin=true`
- `POLICY.ReserveNamesInAD=false`
- `POLICY.CoordinationRequired=false`
- `POLICY.CoordinationRoot` vide
- `POLICY.UnattendedJoinEnabled=false` pour garder le parcours interactif
- `POLICY.UnattendedOperationsEnabled=true` seulement si besoin de `--cli verify`

### Objets AD à créer
- **Par David** :
  - OU de test.
  - Un compte ordinateur précréé dans l’OU de test.
  - Compte non joint, sans DNS/SPN, conforme aux règles Windows de réutilisation.
  - GUID relevé avant test.

### Poste cible
- Il faut un poste **hors domaine**.
- État actuel : VM jointe `P111301VA765662`.
- Si aucun poste hors domaine ou snapshot hors domaine n’est fourni : **R1 bloquée**.

## Étapes

1. Snapshot froid : `PRE_R1_<build>`.
2. Démarrer le poste cible hors domaine.
3. Lancer Pesto avec le compte administrateur domaine via `guestcontrol` élevé.
   - Si UAC ou login AD : David intervient.
4. Ouvrir **Ajouter ce PC**.
5. Sélectionner le mode **compte précréé**.
6. Choisir le compte ordinateur précréé.
7. Vérifier avant `Ajouter` :
   - Nom affiché
   - GUID affiché
   - OU affichée
8. Générer l’aperçu/plan.
9. Vérifier que le plan :
   - lie le GUID du compte précréé
   - cible l’OU de test
   - n’annonce pas de création de compte AD
10. Confirmer l’opération.
11. Si `PendingRestart` :
    - capturer le reçu
    - ne pas redémarrer sans accord David.
12. Après redémarrage autorisé :
    - vérifier l’appartenance au domaine
    - vérifier le nom final
    - vérifier l’OU
    - vérifier que le GUID est inchangé.
13. Récupérer le JSON :
    ```powershell
    C:\Pesto\PROD\Pesto.exe --cli verify --receipt <ID>
    ```

## Résultat attendu

- L’UI affiche le compte précréé avec nom/GUID/OU avant validation.
- Le plan ne crée pas de compte AD.
- Le GUID du compte précréé reste le même après jonction.
- Le poste est joint dans l’OU de test.
- Le reçu passe à `Verified` après observation.

## Preuves à garder

- Capture avant sélection du compte.
- Capture de l’aperçu/plan.
- Capture du reçu.
- JSON `--cli verify`.
- Sortie AD avant/après :
  ```powershell
  dsquery computer -name <NOM>
  ```
  ou `Get-ADComputer`.
- SHA-256 du build.
- Nom du snapshot.

## Nettoyage

- **David supprime** :
  - l’objet ordinateur précréé/joint de test
  - éventuellement l’OU de test si elle est dédiée
- Restaurer le snapshot `PRE_R1_<build>` si besoin.

## Ce qui exige David

- Création du compte ordinateur précréé.
- Autorisation du redémarrage.
- Saisie de mot de passe si une fenêtre le demande.
- Suppression de l’objet AD.

---

# R2 — Réservation AD des noms (`POLICY.ReserveNamesInAD`)

## Prérequis

### Configuration Pesto
- `POLICY.ReserveNamesInAD=true`
- `POLICY.AllowPrecreatedJoin=false`
- `POLICY.CoordinationRequired=false`
- `POLICY.CoordinationRoot` vide
- `POLICY.UnattendedOperationsEnabled=true` pour `--cli verify`

### Objets AD
- **Par David** :
  - OU de test.
  - Aucun compte ordinateur précréé pour le nom testé.
  - Vérifier que le nom proposé par Pesto est libre.

### Poste cible
- Poste hors domaine requis pour la jonction avec réservation AD.
- Si indisponible : qualification partielle possible sur le panneau **Réservations AD**, mais pas la création AD avant jonction.

## Étapes

1. Snapshot froid : `PRE_R2_<build>`.
2. Démarrer le poste hors domaine.
3. Lancer Pesto avec le compte administrateur domaine.
4. Ouvrir **Ajouter ce PC**.
5. Générer une proposition de nom.
6. Vérifier que le plan annonce explicitement une **réservation AD**.
7. Confirmer l’opération.
8. Avant redémarrage :
   - vérifier la création de l’objet AD réservé
   - vérifier le GUID
   - vérifier le marqueur Pesto si l’attribut est documenté
9. Ouvrir **Réservations AD**.
10. Tester :
    - **Inspecter**
    - **Préparer une reprise**
    - **Préparer un retrait**
11. Ne pas confirmer un retrait qui supprime un objet AD sans décision David.
12. Si David autorise le retrait, observer le résultat.
13. Si jonction complète :
    - redémarrage autorisé par David
    - `--cli verify --receipt <ID>`

## Résultat attendu

- Le plan annonce la réservation AD.
- Un objet AD est créé avec GUID et marqueur Pesto.
- Le reçu est durable.
- Aucun nettoyage automatique n’a lieu.
- La préparation de retrait affiche l’objet exact et exige une confirmation séparée.
- Après jonction, l’objet réservé devient l’objet joint avec GUID stable.

## Preuves à garder

- Capture du plan avec mention réservation AD.
- Capture du reçu.
- JSON `--cli verify`.
- Sortie AD avant/après réservation.
- Capture du panneau **Réservations AD**.
- Journaux locaux si présents.
- SHA-256 du build.

## Nettoyage

- **David supprime** :
  - l’objet AD réservé
  - l’objet joint si la recette est allée jusqu’à la jonction
  - éventuellement l’OU de test
- Restaurer le snapshot `PRE_R2_<build>`.

## Ce qui exige David

- Création de l’OU de test.
- Décision sur le retrait AD.
- Exécution ou validation de la suppression AD.
- Redémarrage.
- Saisie de mot de passe si nécessaire.

---

# R3 — Coordination partagée (dossier SMB, verrous)

## Prérequis

### Infrastructure
- **David crée** un partage dédié, par exemple :
  - `\\LABO-DC01\PestoCoordQualif`
- Droits :
  - compte administrateur domaine utilisé pour les tests
  - pas de modification des partages existants
  - pas d’arrêt/restauration du DC

### Configuration Pesto
- `POLICY.CoordinationRoot=\\LABO-DC01\PestoCoordQualif`
- `POLICY.CoordinationRequired=true`
- `POLICY.NameReservationMinutes=15`
- `POLICY.ReserveNamesInAD=false`
- `POLICY.AllowPrecreatedJoin=false`

### Limite labo
- Pas de seconde machine utilisable : `FILPRO` et `DOMENIA` sont interdites.
- Donc :
  - SMB/marqueur/verrou simple machine : qualifiable
  - concurrence intermachines : **non qualifiable**

## Étapes

1. Lancer Pesto avec le compte administrateur domaine.
2. Ouvrir **Paramètres**.
3. Enregistrer la configuration de coordination.
4. Ouvrir l’écran **Coordination**.
5. Cliquer **Inspecter la coordination**.
6. Vérifier l’affichage :
   - racine observée
   - marqueur présent/absent
   - état du partage
7. Cliquer **Préparer le dossier**.
8. Vérifier le plan :
   - lié à la configuration
   - crée seulement marqueur et sous-dossiers
   - ne crée pas de partage
   - ne modifie pas les ACL
9. Confirmer la préparation.
10. Vérifier sur le partage :
    - fichier marqueur
    - sous-dossiers attendus
11. Tester un verrou :
    - lancer un aperçu de nom ou une opération qui acquiert un verrou
    - observer l’apparition d’un fichier de verrou/bail
    - tenter une seconde action sur la même ressource
    - vérifier refus ou blocage
    - annuler/compléter proprement
    - vérifier libération seulement si résultat durable
12. Capturer l’état du dossier de coordination avant/pendant/après.

## Résultat attendu

- Le partage est accessible.
- **Préparer le dossier** crée le marqueur et les sous-dossiers sans créer le partage ni modifier les ACL.
- Un verrou exclusif apparaît pendant l’opération.
- Une seconde tentative sur la même ressource est refusée ou bloquée.
- Un résultat incertain conserve le verrou.
- Aucun verrou n’est retiré par simple ancienneté.

## Preuves à garder

- Capture de l’inspection coordination.
- Capture du plan de préparation du dossier.
- Listing du partage avant/après.
- Capture du fichier de verrou/bail.
- Capture du refus concurrent si obtenu.
- Reçu/plan JSON si disponible.
- SHA-256 du build.

## Nettoyage

- **David supprime** si souhaité :
  - le dossier de test
  - le partage de test
- Aucun objet AD à supprimer si aucune mutation AD n’a été faite.

## Ce qui exige David

- Création du partage et des ACL.
- Décision de nettoyage des verrous de test.
- Saisie de mot de passe si nécessaire.

---

# R4 — Jonction hors connexion (ODJ, blob djoin)

## Prérequis

### Poste cible
- Poste **hors domaine**.
- Compte administrateur local disponible.
- Si seul un compte domaine est disponible et que le poste hors domaine ne peut pas l’authentifier : **R4 bloquée**.

### Blob djoin
- **Par David** :
  - générer un blob `djoin` valide pour le nom actuel du poste cible.
  - exemple de commande côté poste joint/administré :
    ```cmd
    djoin /provision /domain labo.local /machine <NOM_CIBLE> /savefile C:\Temp\<NOM_CIBLE>.txt
    ```
  - si possible avec l’OU de test.
  - fournir le fichier blob de façon contrôlée.
  - ne pas laisser le blob sur des chemins exposés.

### Configuration Pesto
- `POLICY.AllowOfflineJoin=true`
- `POLICY.CoordinationRoot` vide
- `POLICY.CoordinationRequired=false`
- `POLICY.ExcludedGroupGuids` vide
- `POLICY.BlockJoinOnClockSkew=false` ou au moins sans mesure DC avant ODJ
- `EntraPolicy=Disabled`

## Étapes

1. Snapshot froid : `PRE_R4_<build>`.
2. Démarrer le poste hors domaine.
3. Ouvrir la configuration si nécessaire :
   ```powershell
   C:\Pesto\PROD\Pesto.exe --settings
   ```
4. Activer `POLICY.AllowOfflineJoin`.
5. Lancer le parcours ODJ :
   ```powershell
   C:\Pesto\PROD\Pesto.exe --offline-join
   ```
6. Importer le blob djoin via le dialogue natif.
7. Vérifier :
   - le nom actuel est conservé
   - aucun backend AD ordinaire n’est sollicité avant application
   - le plan est unique
8. Préparer l’opération.
9. Confirmer l’application.
10. Vérifier qu’un journal est écrit avant `djoin`.
11. Ne pas redémarrer sans accord David.
12. Après redémarrage autorisé :
    - vérifier l’appartenance au domaine
    - vérifier le nom
    - vérifier l’OU
    - utiliser **Observer après redémarrage — accès AD**
13. Récupérer le JSON :
    ```powershell
    C:\Pesto\PROD\Pesto.exe --cli verify --receipt <ID>
    ```

## Résultat attendu

- La fenêtre ODJ s’ouvre sans découverte de DC ni backend AD ordinaire.
- Le blob est importé et validé.
- Le nom actuel est conservé.
- L’application est unique.
- Le journal est écrit avant `djoin`.
- Après redémarrage, le poste est joint.
- L’observation après boot lit l’AD.

## Preuves à garder

- Capture de la fenêtre ODJ.
- Capture de l’import du blob.
- Capture du plan ODJ.
- Capture du reçu.
- JSON `--cli verify`.
- Journaux locaux.
- Logs Windows liés à `djoin` si accessibles.
- Sortie AD après jonction.
- SHA-256 du build.

## Nettoyage

- **David supprime** :
  - l’objet ordinateur créé/joint par ODJ
  - le fichier blob
  - éventuellement l’OU de test
- Restaurer le snapshot `PRE_R4_<build>`.

## Ce qui exige David

- Génération du blob djoin.
- Placement sécurisé du blob.
- Accès administrateur local sur le poste hors domaine.
- Autorisation du redémarrage.
- Suppression de l’objet AD.
- Saisie de mot de passe si nécessaire.

---

# R5 — DPI / accessibilité

## Prérequis

- Aucune mutation AD.
- Build identifié par SHA-256.
- Pesto installé dans `C:\Pesto\PROD`.
- Session locale possible.
- Utiliser `--settings` pour éviter toute connexion AD :
  ```powershell
  C:\Pesto\PROD\Pesto.exe --settings
  ```

## Étapes

### 1. Échelles 125 %, 150 %, 200 %

Pour chaque échelle :

1. Ouvrir **Paramètres Windows > Système > Écran**.
2. Régler la mise à l’échelle sur :
   - 125 %
   - 150 %
   - 200 %
3. Lancer :
   ```powershell
   C:\Pesto\PROD\Pesto.exe --settings
   ```
4. Naviguer :
   - Paramètres
   - Aide
   - Démonstration si accessible
   - dialogues natifs
5. Vérifier :
   - pas de texte tronqué
   - pas de bouton inaccessible
   - focus clavier visible
   - Tab/Shift+Tab fonctionnels
   - Entrée/Échap fonctionnels
   - captures lisibles

### 2. Narrateur

1. Lancer Narrateur :
   - `Ctrl+Win+Entrée`
   - ou via `guestcontrol` : `Narrator.exe`
2. Naviguer dans Pesto `--settings`.
3. Vérifier que Narrateur annonce :
   - titres
   - boutons
   - champs
   - cases à cocher
   - messages de confirmation
4. Tester les dialogues :
   - import/export
   - confirmation
   - annulation
5. Conserver un transcript ou une capture avec les annonces visibles.

### 3. Contraste élevé

1. Ouvrir **Paramètres Windows > Accessibilité > Thèmes de contraste**.
2. Activer un thème contraste élevé.
3. Relancer `Pesto.exe --settings`.
4. Vérifier :
   - lisibilité du texte
   - visibilité du focus
   - visibilité des bordures
   - lisibilité des boutons désactivés
   - lisibilité des messages d’erreur
5. Désactiver le thème après test.

## Résultat attendu

- L’UI reste utilisable à 125 %, 150 %, 200 %.
- Narrateur annonce les contrôles principaux.
- Le contraste élevé ne masque pas les éléments critiques.
- Aucun mot de passe n’est requis pour cette recette.

## Preuves à garder

- Captures par échelle.
- Captures Narrateur ou transcript.
- Captures contraste élevé.
- SHA-256 du build.
- Version de Pesto.
- Date/heure.

## Nettoyage

- Remettre l’échelle Windows à 100 %.
- Désactiver Narrateur.
- Désactiver le thème contraste élevé.

## Ce qui exige David

- Rien en principe.
- Si une fenêtre demande un mot de passe : David saisit.

---

# R6 — Plusieurs DC

## Verdict

**Non qualifiable dans le labo actuel.**

## Preuve de limitation

Exécuter en lecture seule :

```cmd
nltest /dclist:labo.local
```

ou :

```powershell
Get-ADDomainController -Filter *
```

Résultat attendu :

- Un seul DC : `LABO-DC01`
- Pas de second DC
- Pas de bascule DC testable
- Pas de test de latence multi-DC
- Pas de test de sélection de DC alternatif
- Pas de test de redondance AD

## Ce qui serait nécessaire

- Un second DC dans le labo.
- Ou une maquette AD isolée avec deux DC.
- Sans toucher `LABO-DC01` partagé.

---

# Ordre recommandé

1. **R5 — DPI/accessibilité**
   - Aucun risque AD.
   - Valide l’UI et le build.

2. **R3 — Coordination partagée**
   - SMB uniquement si partage disponible.
   - Pas de mutation AD.

3. **R1 — Jonction avec compte précréé**
   - Mutation AD.
   - Snapshot obligatoire.

4. **R2 — Réservation AD des noms**
   - Mutation AD.
   - Snapshot obligatoire.

5. **R4 — ODJ / blob djoin**
   - Mutation AD + blob externe.
   - Snapshot obligatoire.

6. **R6 — Plusieurs DC**
   - À clôturer comme non qualifiable.

---

# Estimation grossière

| Recette | Estimation | Dépendances David |
|---|---:|---|
| R5 DPI/accessibilité | 2 à 4 h | Aucune |
| R3 Coordination SMB | 2 à 4 h | Partage/ACL |
| R1 Jonction précréée | 3 à 6 h | Objet AD, reboot, suppression |
| R2 Réservation AD | 3 à 6 h | OU, décision retrait, suppression |
| R4 ODJ | 4 à 8 h | Blob, admin local, reboot, suppression |
| R6 Multi-DC | 0,5 h | Constat non qualifiable |

Total labo : **14 à 28 heures**, hors délais David.

---

# Points bloquants / informations manquantes

À clarifier avant exécution complète :

1. **Poste hors domaine**
   - Non fourni.
   - Nécessaire pour R1, R2 complet, R4.
   - À défaut : R1/R4 non qualifiables, R2 partiel.

2. **Blob djoin**
   - Non fourni.
   - À générer par David.

3. **Partage de coordination**
   - Non fourni.
   - À créer par David sur le DC ou un serveur membre autorisé.

4. **Seconde machine pour concurrence coordination**
   - Non disponible.
   - `FILPRO` et `DOMENIA` interdites.
   - Concurrence intermachines non qualifiable.

5. **Attribut marqueur AD de réservation**
   - Non documenté dans les éléments fournis.
   - À fournir pour vérifier complètement R2.

6. **Compte administrateur local sur poste hors domaine**
   - Non confirmé.
   - Nécessaire pour R4.

7. **Export reçu JSON depuis l’UI**
   - Non documenté.
   - Solution de repli : `--cli verify --receipt <ID>`.

8. **Deuxième DC**
   - Absent.
   - R6 non qualifiable.
