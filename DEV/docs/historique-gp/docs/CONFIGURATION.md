# Configuration et migration

**RC2 :** la configuration active est désormais `wad/cfg.json`. Les exemples et la copie originale sont également dans `wad`. L’option `-ConfigPath` du lanceur permet toujours de fournir un autre fichier.

## Configuration fournie : anomalie bloquante à corriger

`CONF[0].Domaine` vaut `o.LOCAL`. Les suffixes des entrées `OUBase`, `OUSite` et de `OUScanNoms` sont `DC=labo,DC=local`, soit `labo.local`. GP 17 refuse ce contexte incohérent avant une connexion réelle. Il n’existe pas assez d’information dans l’archive pour décider lequel de ces domaines est le bon. Les libellés d’OU paraissent également altérés ; ils restent conservés.

Dans l’écran de correction, renseigner le domaine réel et les DistinguishedName exacts obtenus dans l’annuaire. Le contrôle local valide leur forme et leur cohérence ; il ne peut pas prouver que l’OU existe sans connexion. Une sauvegarde `.bak` accompagne le remplacement atomique. L’annulation de la correction ferme le démarrage au lieu de charger une configuration fictive.

## Champs principaux

| Champ | Règle et effet |
|---|---|
| `CONF[0].Domaine` | Domaine DNS cohérent avec tous les DN configurés |
| `CONF[0].ADM` | Identifiant de connexion prérempli, pas un mot de passe |
| `CONF[0].Prefixe` | 6 caractères de la convention de nommage |
| `CONF[0].PreprodSite` | Code de 3 caractères utilisé pour les règles de préproduction |
| `CONF[0].DirectProd` | false : OU PREPROD requise ; true : jonction directe selon le choix métier |
| `CONF[0].OUScanNoms` | Racine OU de lecture des noms ; vide accepté selon le repli existant |
| `CONF[0].Buffer` | Entier 0 à 999, pas une limite de parallélisme des écritures |
| `CONF[0].DarkMode` | 0, 1 ou 2 selon les modes historiques de l’interface |
| `CONF[0].AllowHybridRepair` | **false par défaut** ; autorisation sensible de réparation Entra après refus de renommage |
| `CONF[0].ClearProtectionOnMove` | Autorise la levée temporaire puis le rétablissement de la protection anti-suppression pour un déplacement |
| `OUBase` | Entrée ROOT obligatoire, PREPROD obligatoire sauf DirectProd=true |
| `OUSite` | Organismes/sites racines ; chaque entrée a Nom et OU |
| `TAGS` | Motifs de site et tags de 2 lettres ; couverture PREPROD requise si nécessaire |

La convention de nom généré est `T` + préfixe 6 caractères + site 2 lettres + service 3 caractères/chiffres selon le validateur existant + numéro 001–999. Exemple synthétique : `S111301MA123001`. Le choix du type et des codes d’organisation doit rester conforme aux règles métier réelles, pas à cet exemple.

Les booléens historiques sous forme de chaînes sont conservés. Le parseur accepte ses représentations documentées par les tests, mais refuse une valeur inconnue en validation stricte. Préférer `"true"` / `"false"` pour rester homogène au fichier existant.

## Modes et clés historiques

`DEBUG.GUI=true` désigne une maquette sans appels AD ; `DEBUG.Simulation=true` et GUI=false désignent une simulation connectée avec lectures réelles. Hors simulation, `HorsDomaine` et `MauvaiseOU` ne doivent pas forcer de faux états : GP détecte l’état réel du poste. `ForceADM` et `BPVerifNomAD` restent des clés historiques sans effet métier sensible.

`DsregLeaveOnMove` est conservé pour compatibilité du fichier, mais ne commande plus un retrait Entra à chaque déplacement. Ne pas l’utiliser comme substitution à `AllowHybridRepair`. Une configuration 16.x peut être rejetée si elle contenait une incohérence auparavant tolérée : la compatibilité n’est donc pas inconditionnelle.

Les changements de domaine, GUI, simulation ou contexte hors domaine demandent un redémarrage pour éviter de mélanger un ancien credential, un ancien DC et de nouveaux réglages. Vider/exporter la file avant de modifier la configuration.

## Périmètre des OU

Les mutations contrôlent l’appartenance aux racines configurées par composants de DN, sans simple recherche de suffixe textuel. Le profil accepté concerne les OU : un conteneur `CN=Computers` n’est pas une OU prise en charge ; les RDN multivalués sont rejetés. Les virgules échappées sont traitées, mais il ne s’agit pas d’un validateur général de toutes les formes possibles de DN LDAP.

Cette limite logicielle n’est pas un remplacement des délégations AD. Configurer les racines au plus étroit et les droits du compte en conséquence. Un programme exécuté par un utilisateur capable de modifier lui-même son code/configuration ne constitue pas une frontière d’autorisation indépendante.

## Fichiers sensibles

Le JSON ne doit jamais contenir le mot de passe. La configuration contient néanmoins la structure interne du domaine. Ne pas la déposer dans un dépôt public. L’exemple et la démo ne contiennent que des chemins fictifs. Le `.gitignore` fourni ne supprime pas un secret ou un fichier déjà commité : effectuer une revue avant toute publication.
