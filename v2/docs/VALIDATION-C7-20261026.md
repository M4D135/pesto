# Reprise C7 — paramètres et réponses tardives, 26 octobre 2026

## Source et défauts reproduits

Branche `codex/pesto-v2-20261023`, reprise depuis le HEAD distant vérifié
`50f1c1fe727b8168eb20f77fee2719bbac42b35b`. Le checkout V2 propre a été avancé
sans réécriture ; le clone V1 et ses modifications locales ont été préservés.
Les preuves [C6](VALIDATION-C6-20261026.md) restent attachées à `51ee270`.

Sept régressions ont été exécutées dans les vrais modules de l’interface avec
un pont mémoire et des réponses volontairement retardées. Les sept échouaient
avant correction :

- Import, rollback, reprise et comparaison de configuration distribuée ouvraient
  leur confirmation après la navigation vers Aide.
- Deux clics Enregistrer avant la réponse produisaient deux préparations.
- Une relecture lente écrasait la saisie arrivée pendant la requête.
- Un rafraîchissement de configuration écrasait un brouillon déjà présent.

## Comportement corrigé

Les échanges de maintenance restent liés au montage de la page et à sa route.
Une réponse reçue après le départ ne peut plus ouvrir de dialogue ni poursuivre
le parcours vers une écriture. Une opération déjà confirmée et envoyée reste
traitée par le moteur ; ce correctif ne l’annule pas et ne la rejoue pas.

Enregistrer n’autorise qu’une préparation à la fois et affiche son état immédiatement.
Une saisie modifiée avant réception de l’aperçu impose une nouvelle préparation.
Après une application confirmée, une nouvelle saisie est conservée, avec l’empreinte
du document préparé comme base de la sauvegarde suivante. Une première création
sans sauvegarde ne prétend plus avoir produit une sauvegarde.

Les lectures portent un numéro de requête : une ancienne réponse ne peut pas
remplacer la plus récente. Une saisie modifiée pendant la lecture reste intacte.
Un rafraîchissement conserve le brouillon ; Relire demande explicitement son abandon,
y compris pour une saisie commencée avant la toute première réponse. Ce dernier cas
a été reproduit séparément : Relire remplaçait alors les champs sans confirmation.
Une commande Enregistrer prématurée n’invalide plus la première lecture attendue.
La garde de concurrence du moteur reste active et aucune configuration externe
n’est acceptée silencieusement comme base d’un brouillon.

## Validation locale exécutée

macOS arm64, SDK .NET **10.0.401**, Chromium via Chrome installé et Playwright
**1.62.1**. Les quatre suites web emploient des fixtures déclarées, sans AD/SMB/Windows.

| Contrôle | Résultat |
|---|---|
| Compilation hôte Windows croisée Release | 0 avertissement, 0 erreur |
| Compilation moteur/tests Release | 0 avertissement, 0 erreur |
| `ProfileConfigurationTests` | 28/28 |
| `ConfigurationOnlyTests` | 3/3, dont absence/création/suppression du cfg |
| `web-maintenance-check.mjs` | 33/33, dont 13 nouveaux cas de navigation/concurrence/brouillon |
| `operator-ui-check.mjs` | 32/32 |
| `demo-dom-check.mjs` | 8/8 |
| `web-check.mjs` | 149/149 ; référence externe Domenia absente, empreintes locales contrôlées |

La première exécution de `ProfileConfigurationTests` utilisait le répertoire Temp
macOS passant par le lien `/var` : 23 cas étaient refusés par la garde des chemins.
La même suite passe 28/28 avec `TMPDIR` pointant vers un dossier physique de travail.
Aucune garde contre les liens n’a été assouplie. Les logs locaux restent hors Git.

Commandes depuis `v2/` (SDK et navigateurs résolus explicitement sur le poste) :

```sh
dotnet build src/Pesto.App/Pesto.App.csproj -c Release --disable-build-servers -m:1
dotnet build tests/Pesto.Engine.Tests/Pesto.Engine.Tests.csproj -c Release --disable-build-servers -m:1
dotnet tests/Pesto.Engine.Tests/bin/Release/net10.0/Pesto.Engine.Tests.dll ProfileConfigurationTests
dotnet tests/Pesto.Engine.Tests/bin/Release/net10.0/Pesto.Engine.Tests.dll ConfigurationOnlyTests
node tools/tests/web-maintenance-check.mjs
node tools/tests/operator-ui-check.mjs
node tools/tests/demo-dom-check.mjs
node tools/tests/web-check.mjs
```

Le workflow Windows existant exécute désormais aussi ces quatre suites web.
Playwright est épinglé par version et intégrité dans `tools/tests/browser/package-lock.json` ;
`npm ci --ignore-scripts` puis l’installation explicite de Chromium ne concernent
que le banc. Aucun Node, navigateur de test ou SDK supplémentaire n’est requis
par l’application distribuée. `node_modules` est exclu du pack DEV.

## Qualification native et livraison

La campagne initiale [40302129647](https://github.com/M4D135/pesto/actions/runs/40302129647)
sur `0a691d0` échoue au contrôle des empreintes du kit web : les trente fichiers
suivis par `provenance.json` ont été convertis en CRLF au checkout Windows.
Les compilations, tests moteur/pont/compagnon et trois suites Chromium précédentes
réussissent ; les packs et essais natifs suivants ne sont pas exécutés.
Le contrôle ne doit pas normaliser les octets ni recalculer les empreintes attendues.

La conversion est reproduite localement avec `core.autocrlf=true` : 145 et 253
fins de ligne converties sur les deux fichiers témoins. `.gitattributes` préserve
désormais les octets de `v2/web/**`, comme les composants V1 déjà protégés.
Un nouveau checkout avec la même option passe les **30/30 empreintes** originales.
Le workflow est aussi déclenché par les changements de `.gitattributes`.

Les campagnes [40302711621](https://github.com/M4D135/pesto/actions/runs/40302711621)
sur `fc43a7a` et [40303224314](https://github.com/M4D135/pesto/actions/runs/40303224314)
sur `d3af22b` sont **annulées par les pushes suivants**. La seconde avait validé
les quatre suites web, la coexistence native et les trois transactions PROD, avant
annulation pendant DEV. Elle ne reçoit pas le verdict de la campagne finale.

**Campagne finale entièrement réussie : [40304895510](https://github.com/M4D135/pesto/actions/runs/40304895510)**,
source **`95f8ce0b1f9605dcaddfdc97c0b7b017762567be`**. Windows 2025, SDK **10.0.302**,
WebView2 fixe **156.0.4314.42**. Les compilations sont sans avertissement ni erreur.
Le workflow exécute 200 tests moteur ciblés sur fixtures, 15 du pont, 30 du compagnon,
18 variantes métier analysées par PowerShell 5.1 et le parsing de son script d’entrée.
Les quatre suites web passent également sous Windows : **33, 32, 8 et 149 contrôles**.

Les deux packs passent démarrage, coexistence locale/démo et fermeture avec le vrai
EXE et WebView2 embarqué : 44 refus directs par canal, six transitions de page,
profils et identifiants distincts, contexte parent conservé. Les huit captures ont
été relues. Le parent reste en configuration locale sans adaptateur AD.

Les trois transactions PROD et la transaction normale DEV réussissent entre deux
compilations distinctes, avec acquisition du ZIP pour les cas normaux. Quatre
transactions, huit reçus de santé et sept lancements du helper ont été recoupés.
Les états finaux sont `rolledBack`, les sources A/B, le ZIP et le cfg sentinelle
restent inchangés. La santé négative et la reprise native après interruption à
`checking` sont couvertes en PROD, sans étendre ces résultats à DEV ou à l’AD réel.
Cette campagne enregistre un inventaire de descendants refusé (`descendant-image-outside-case`),
puis un inventaire complet accepté avant l’arrêt. La branche de refus et nouvelle observation
est ainsi exercée, alors que C6 n’avait pas rencontré ce cas.

La [synthèse des preuves](evidence/20261026/windows-95f8ce0/README.md) contient les
liens PROD/DEV, les hashes de l’EXE, des ZIP et de leurs enveloppes Actions, ainsi
que la baseline reconstruite dans cette campagne. L’archive de preuves a été
téléchargée et vérifiée par SHA-256 ; les deux gros packs n’ont pas été retéléchargés.
Aucune release V1 n’a été modifiée. Les statuts restent `official=false`,
`distribution=candidate`, `qualification=unqualified`. Le commit documentaire
suivant ne reconstruit ni ne modifie les binaires et ZIP testés.

## Commits du lot

- `0a691d0faa30f156064afae48498a85925eb4e34` : réponses tardives, brouillons, sauvegarde sérialisée et banc Chromium Windows.
- `fc43a7a06c7d0bbd6e5197718b64167a3c78b98d` : commande Enregistrer avant la première lecture.
- `d3af22bf1b73802c2cc7998c677bae9617f89169` : octets du kit web préservés au checkout Windows.
- `95f8ce0b1f9605dcaddfdc97c0b7b017762567be` : confirmation d’abandon du brouillon saisi avant la première réponse ; source des packs finaux.

## Laboratoire et limites

Le contrôle en lecture seule du 26 octobre a cette fois obtenu une réponse SSH
du bastion. L’inventaire VirtualBox de l’UUID autorisé retrouve **PESTO-W11-TEST**
dans l’état **poweroff**. Cela actualise l’observation de refus de connexion C6.
L’état à froid a été conservé dans l’instantané **C7-avant-verification-20261026**
avant le démarrage de cette seule VM. Sa relecture confirme l’état **running** ;
la VM reste démarrée et l’instantané est conservé. Aucune restauration ou fermeture
forcée n’a été utilisée pour débloquer le diagnostic.

L’identité invitée n’a pas pu être obtenue : les commandes Guest Control donnent
`VERR_NOT_IMPLEMENTED` (le test hostname termine au code 33), la capture VirtualBox
échoue avec `E_FAIL`, et le canal SSH existant refuse la vérification de clé.
Aucun contournement de clé n’a été appliqué. Une tentative de copie de preuve a
expiré ; le contrôle final ne trouve aucun processus de cette copie encore en cours.
Le snapshot ancien ne suffit pas à reprendre les identités historiques du client
ou des objets AD. **Aucune opération AD n’a été engagée.** Les données de laboratoire
et ses journaux bruts restent hors Git.

La qualification AD, l’authentification réelle, la coexistence avec une session AD,
UAC avec autre compte, les dialogues natifs d’import/export/pack personnalisé,
ACL/DPAPI, UNC, acquisition HTTP officielle, Program Files, ODJ, CLI et Entra restent
distincts des contrôles isolés. Recette courte : sur le seul client autorisé,
établir le retour à froid et l’identité actuelle, utiliser le pack exact de cette
campagne, vérifier le nom affiché puis effectuer le canari réversible et sa relecture
par GUID. Suivre [QUALIFICATION-WINDOWS.md](QUALIFICATION-WINDOWS.md) ; aucun secret
ni configuration privée historique ne doit devenir une fixture publique.
