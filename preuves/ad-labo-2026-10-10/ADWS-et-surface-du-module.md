# AD du labo — ADWS hors service, surface du module inchangée (10/10/2026)

Cette note corrige une affirmation du commit `7643eb8` (« Point 3 : l'import du
module AD ne monte plus son lecteur »), qui attribuait l'impossibilité de tester
les cmdlets à WinRM arrêté dans l'invité. **Mesuré faux** : voir plus bas.

## Ce qui a été changé dans l'invité

`net start WinRM` dans `PESTO-W11-TEST` (`P111301LY765002`), sur accord de David.
Le service était `STOPPED` en `DEMAND_START` (jamais démarré, pas désactivé) ; il
est maintenant `RUNNING`, `AllowUnencrypted = false`. Réversible par
`net stop WinRM`. **Ce démarrage n'a rien réparé** : les six combinaisons testées
(`Get-ADRootDSE`, `Get-ADObject`, `Get-ADComputer`, sans `-Server` /
`dc01.labo.local` / `10.77.0.10`) échouent toutes en `ADServerDownException`,
avec et sans `ADPS_LoadDefaultDrive`.

## La panne est sur le contrôleur, pas dans l'invité

Mesuré depuis `P111301LY765002` vers `10.77.0.10` (`dc01.labo.local`) :

```
ports 88 389 636 9389 3268   OUVERTS (TcpClient, < 5 ms)
canal securise               nltest /sc_verify -> Trusted DC \\dc01.labo.local
                             Trust Verification Status = 0 NERR_Success, Kerberos
derive d'horloge             -3,8 s (tolerance Kerberos : 300 s)
GET  http://10.77.0.10:9389/     -> connexion fermée sans réponse HTTP
POST http://10.77.0.10:9389/wsman -> connexion fermée sans réponse HTTP
```

Le port est lié (HTTP.sys répond au SYN) mais l'échange HTTP meurt sans réponse :
**Active Directory Web Services ne sert pas sur `LABO-DC01`**. Les cmdlets du
module ActiveDirectory se consomment par WS-Man vers ADWS ; sans endpoint, elles
sont toutes mortes, quel que soit le client.

`LABO-DC01` n'a **aucune redirection NAT** (`VBoxManage showvminfo
--machinereadable` : « aucune redirection ») et aucun identifiant connu sur
l'hôte de labo : ni voie SSH ni `guestcontrol` possibles depuis l'extérieur.
Réparer demande la console de la VM, avec `Start-Service ADWS` (ou
`Get-Service ADWS` pour voir l'état réel).

## Ce qui reste prouvable sans ADWS, et qui couvre le risque du point 3

Le drapeau ne peut agir que sur l'import. Mesuré dans l'invité, module embarqué
`C:\PestoTest\wad\ActiveDirectory.psd1`, un runspace neuf par bras :

```
cmdlets exportees   sans drapeau = 147    avec ADPS_LoadDefaultDrive=0 = 147
version du module   sans drapeau = 1.0.1.0  avec = 1.0.1.0
liste des cmdlets   identique octet pour octet entre les deux bras
variables de session identiques  = True
lecteur AD: visible sans drapeau = False   avec =0 = False
```

Ajouté aux deux constats déjà écrits dans `7643eb8` — zéro occurrence de `AD:\`
dans tout `wad/`, et aucun lecteur `AD:` dans les runspaces qui importent le
module — la surface du module est **démontrée inchangée** par le drapeau.

## Ce qui reste ouvert

Une exécution réelle de cmdlets contre un contrôleur vivant. Elle est bloquée
par ADWS sur `LABO-DC01`, donc **elle bloque aussi tout le reste du chantier
qui touche l'AD** : bancs de noms et de collisions, phases 3-4 sur l'AD réel,
P6 configuration labo. Ce n'est pas un défaut de Pesto : l'invité était déjà
aveugle à l'AD avant le point 3.
