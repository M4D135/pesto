# Revue externe, brouillon à vérifier

OpenCode CLI 1.19.1, modèle `opencode/deepseek-v4.1-flash-free`. Revue en lecture seule de la version intermédiaire, avant les correctifs ci-dessous ; aucune exécution des reproductions par le modèle.

Revue ciblée — réponses uniquement sur les correctifs récents, sans réécriture d'architecture.

# 1. `Protect-PestoLogText` — `DEV/wad/Pesto-Journal.ps1:9-23`

### 1.1 Fuite : clés collées à d'autres caractères de mot (ligne 20, lookbehind `(?<![\w])`)
Le lookbehind exige que le caractère **immédiatement** avant le nom de clé soit non-`\w`. Toute clé où le mot-clé est soudé à un préfixe/suffixe de mot n'est donc pas vue, et la valeur part en clair.

- Repro : `Protect-PestoLogText 'sa_password=CANARY123'` → renvoie la chaîne **inchangée** (souligné = `\w`).
- Idem : `dbpassword=…`, `userpassword=…`, `accesstoken=CANARY` (pas d'underscore → `access_token` ne matche pas, et `token` est précédé de `s`).
- Idem pour des clés hors liste : `secret_key=CANARY`, `secretkey=…`, `pin=…`, `connectionstring=…` (la liste de la ligne 20 est figée et `secret` exige `[:=]` juste après, or `_key` suit).

Les PASS (`access_token=`, `client_secret=`, `api-key=`) ne couvrent que les formes exactes de la liste, d'où l'illusion de vert.

### 1.2 Fuite : schémas `Authorization` autres que Bearer/Basic (ligne 20)
L'alternative `(?:bearer|basic)\s+\S+` ne connaît que ces deux schémas ; sinon on retombe sur `\S+`, qui ne masque que le **premier jeton** de la valeur.

- Repro : `Protect-PestoLogText 'Authorization: Negotiate TlRMTVNTUAACAAAA'` → masque `Negotiate`, mais `TlRMTVNTUAACAAAA` reste en clair.
- Idem `Authorization: Digest username=…, response=…` et SigV4 `Authorization: AWS4-HMAC-SHA256 Credential=…/Signature=…`.
- Idem valeur multi-jetons sur une clé quelconque : `token=Bearer ABC DEF` ne masque que `Bearer ABC`, `DEF` fuit.

### 1.3 Fuite : valeur JSON imbriquée contenant une espace (ligne 20, alternative `\S+`)
Quand la valeur n'est pas une chaîne quotée, `\S+` s'arrête à la première espace.

- Repro : `Protect-PestoLogText '{"secret": {"nested": "CANARY1234"}}'` → seul `{"nested":` est masqué ; `CANARY1234` ressort (et aucun mot-clé ne suit pour le rattraper).
- Les cas testés (valeur chaîne simple, `Basic …`, `Bearer …`) ne déclenchent jamais ce chemin.

### 1.4 Fuite : userinfo d'URL sans mot de passe (ligne 19)
`(https?://)[^/\s:@]+:[^/\s@]+@` **exige** `user:pass@`. Un jeton placé seul en userinfo n'est pas masqué.

- Repro : `Protect-PestoLogText 'https://CANARYTOKEN@host/path'` → inchangé.

À l'inverse, 1.1→1.4 sont des fuites ; le garde-fou `catch` (ligne 22, y compris timeout 250 ms) et le plafond 65536 (ligne 15) restent, eux, sûrs (masquage total). Point correct mais aveugle : une ligne légitime > 65536 est *entièrement* remplacée.

# 2. `Invoke-PestoDeployment.ps1` — `DEV/integrations/Invoke-PestoDeployment.ps1`

### 2.1 `Uncertain 97` émis alors que le moteur n'a jamais démarré (lignes 388, 406-407)
`$mutationPossible` est fixé **avant** l'appel (ligne 388). Toute exception de la phase `Command` — y compris un échec qui n'écrit rien : commande `Invoke-PestoCommand` introuvable, module importé mais fonction non exportée, liaison d'arguments invalide — produit `MutationStarted=$true` et `ExitCode=97/Uncertain`.

- Repro : module `Pesto.Engine.psd1` valide mais sans `Invoke-PestoCommand` exportée, appel `-Action Rename -Execute -IdempotencyKey k` → résultat `Uncertain/97` alors qu'aucune mutation n'a eu lieu.
- C'est conservateur (sens sûr), mais c'est une imprécision reproductible : le test `test_execution_exception_remains_uncertain_not_safe_to_retry` ne distingue pas « moteur a écrit puis a échoué » de « moteur jamais atteint ».

### 2.2 `exit` dérivé d'une propriété d'`ExitCode` absente (ligne 415)
`exit ([int]$result.ExitCode)` : sur le chemin normal, si le moteur renvoie un objet sans `ExitCode` (ex. `@{State='Failed';MutationStarted=$true}`), `[int]$null` vaut **0** → l'adaptateur sort en succès malgré un `State` d'échec.

- Repro : `Fixture.psm1` renvoyant l'objet ci-dessus → code de sortie 0.
- Le test `test_normal_result_is_not_reclassified` fournit toujours `ExitCode=20` et ne couvre pas l'absence.

Les messages fermés (catch 392-408) sont, eux, corrects : aucun texte d'exception ni chemin n'est réinjecté (`test_failure_loading_host_does_not_echo_secret_path`), et l'échappement ASCII `MatchEvaluator` (413) est bien compatible 5.1.

# 3. `scan_evidence.py` — `DEV/tools/scan_evidence.py`

### 3.1 Exception non capturée → chemin (portant le canari) dans la trace (lignes 659-661)
Seul `UnicodeError` est capturé (661). Toute `OSError` sur `path.stat()` (657) ou `path.read_bytes()` (659) remonte hors de `scan()` puis hors de `__main__` (non protégé) : la trace Python affiche le chemin complet du fichier.

- Repro : fichier `leak_PESTO_CANARY_abcdef.txt` en mode `000` dans la racine → `PermissionError` dont le message contient le chemin → le canari apparaît sur **stderr**, alors que `_masked_path` ne sert qu'au rapport.
- Même effet pour un fichier disparu entre `rglob` et `stat` (TOCTOU).

### 3.2 Fichier de canaris avec BOM → faux négatif (lignes 671-674 → 660)
`read_text(encoding='utf-8')` conserve le BOM sur la première ligne. Comme `splitlines()` ne l'enlève pas, le premier canari vaut `'\ufeffCANARY…'` ; `len ≥ 8` passe, donc aucun `ValueError`, mais `text.count('\ufeffCANARY…')` = 0.

- Repro : canari UTF-8 **avec BOM** ; le fichier examiné contient réellement le canari → rapport `NO_CANARY_FOUND_IN_EXAMINED_TEXT` (faux négatif silencieux). `utf-8-sig` est déjà utilisé pour les fichiers analysés (660) mais pas pour la liste d'entrée.

Le reste est sain : refus des liens avant `resolve` (648), racine non-liée (654), `\x00` (664) et seuil 16 Mo (657) renvoyés en `unexamined`, et la boucle `_masked_path` (639-642) est correcte (elle ne peut pas être infinie, les canaris faisant ≥ 8 caractères). Limites non couvertes : UTF-32 et encodages BOM-less non UTF-16 restent `unexamined` (comportement voulu, pas un bug).

# Conclusion

Les trois correctifs atteignent leur cible nominale (masquage des formes testées, messages fermés sans secret, refus des liens et des encodages ambigus), mais ils présentent des **fuites et imprécisions reproductibles** non couvertes par les suites vertes locales :

- **Fuite de secrets** : clés collées (`sa_password`, `accesstoken`, `secret_key`) et schémas `Authorization` non Bearer/Basic (`Negotiate`, `Digest`, SigV4) — §1.1-1.2 ; valeurs JSON imbriquées espacées et userinfo d'URL sans mot de passe — §1.3-1.4.
- **État/exit trompeurs** : `Uncertain/97` alors que le moteur n'a jamais été atteint (§2.1) ; sortie `0` si `ExitCode` manque (§2.2).
- **Scanner** : canari visible dans la trace en cas d'`OSError` (§3.1) et faux négatif si la liste de canaris a un BOM (§3.2).

Ces points sont des limites/comportements observables ; aucune recette Windows/AD réelle n'a été exécutée ici — seuls les cas synthétiques ci-dessus sont décrits.
