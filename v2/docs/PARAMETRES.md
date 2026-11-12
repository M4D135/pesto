# Écran Paramètres — contrat (2.0.15)

Depuis 2.0.15, l’écran **Paramètres** reprend la page Paramètres de Domenia 2 (commit `044f61fe`) : bandeau d’état, rail de sections avec pastille glissante, une section visible à la fois, recherche de réglage par la touche `/` et adresse `#/parametres?section=…`. Décision de David du 12/11/2026, limitée à cet écran : le reste de l’interface, du kit et des animations est inchangé.

Le comportement métier ne change pas : même brouillon, mêmes validations, mêmes appels au moteur, mêmes confirmations, mêmes textes, même garde de sortie et mêmes refus des réponses tardives. Changer de section n’appelle jamais le moteur.

| Fichier | Rôle |
|---|---|
| `web/js/pages/parametres.js` | Lecture (`configuration.settings` ou `settings.get`), enregistrement, brouillon, tuiles, carte d’état, répartition des cartes de maintenance |
| `web/js/pages/parametres/shell.js` | Coque : bandeau, rail, recherche, tuiles, pastilles, éclat du réglage trouvé ; aucun appel moteur |
| `web/js/pages/parametres/sections.js` | Registre pur (sans DOM, importable sous Node) : sections, alias d’adresse, index de recherche |
| `web/css/pages/parametres.css` | Feuille de l’écran, liée dans `index.html` après `css/kit.css` ([UI-KIT.md](UI-KIT.md)) |
| `web/js/router.js` | `ctx.isCurrent()` et `ctx.replaceParams(params)` |

## 1. Disposition

- **Bandeau** : sourcil « Réglages de Pesto », titre « Paramètres » (seul `h1` de l’écran), texte d’introduction, pastilles de mode (`[data-zone="mode"]`), champ « Rechercher un réglage… », groupe de quatre tuiles « État des paramètres », alerte « Configuration invalide ».
- **Colonne gauche** : rail « Sections des paramètres », puis panneau « Brouillon des paramètres » : statut (`[data-settings-status]`, `role="status"`), **Relire**, **Enregistrer** et l’avertissement d’invalidation des aperçus, plans et file.
- **Contenu** : un seul formulaire `form[data-form="settings"]` enveloppe les panneaux Annuaire et Politiques ; les panneaux Configuration, Mises à jour et Interface le suivent. Chaque panneau commence par un en-tête (icône, titre `h2`, phrase d’introduction).

Tous les panneaux sont rendus au montage. Celui qui n’est pas affiché porte `hidden`. Les champs, les cartes de maintenance et le registre de coordination restent donc présents dans le DOM quelle que soit la section affichée.

## 2. Sections

Ordre du rail :

| `id` | Rail | Contenu |
|---|---|---|
| `annuaire` | Annuaire — Domaine, préfixe, convention et sites | Carte « Annuaire et nommage » : `domain`, `dc`, `prefix`, `namingPattern`, puis en session réelle `rootOu`, `preprodOu`, `preprodSite`, puis `production`, `randomNames`. Carte « Sites » : `textarea[name="sites"]`, ses deux indications et le message de refus (`[data-slot="sites-msg"]`). **Section par défaut.** |
| `politiques` | Politiques — Coordination, jonction, CLI et audit | Session réelle seulement. Carte « Politiques des opérations » : `coordinationRoot`, `coordinationRequired`, `reserveNamesInAd`, `allowPrecreatedJoin`, `allowOfflineJoin`, `unattendedJoinEnabled`, `unattendedOperationsEnabled`, `entraPolicy`, `auditEventLogEnabled`, `blockJoinOnClockSkew`, `excludedGroupGuids`. Carte « Registre de coordination », masquée hors session `live` comme auparavant. |
| `configuration` | Configuration — Export, import, défaut et référentiels | Carte « Configuration en vigueur » (lecture seule, § 4), carte « Configuration à partager » (`configurationVersion`, Exporter, Importer, Définir comme configuration par défaut, Comparer la configuration distribuée, Reconnecter Pesto), carte « Référentiels sites et services ». |
| `mises-a-jour` | Mises à jour — ZIP, dossier ou partage UNC | Carte « Mises à jour de Pesto » : ZIP, dossier, `updateSource`, Inspecter ce chemin, État et reprise, Revenir à la version précédente, candidats et pack préparé. |
| `interface` | Interface — Animations et démonstration | Carte « Interface et démonstration » : champ **Animations** (`interfaceMotion`), bouton de démonstration (`.demo-trigger`), indication `[data-demo-hint]`, et une note : le thème se choisit dans la barre supérieure. |

En démonstration (session `simulation`), le rail compte quatre sections : Politiques n’est pas rendue. En configuration locale (`Pesto.exe --settings`, `?configuration=local`), la session est réelle et les cinq sections sont présentes ; les refus de cette session sont ceux de [CONFIGURATION.md](CONFIGURATION.md#ouvrir-les-paramètres-sans-connexion-ad).

Les textes des cartes de `maintenance.js` et de `coordination-panel.js` sont inchangés. `parametres.js` place chaque carte de maintenance dans sa section avant leur raccordement : `configuration` et `references` dans Configuration, `updates` dans Mises à jour ; une carte inconnue tombe dans Configuration.

## 3. Adresse

| Adresse reçue | Section affichée | Adresse réécrite |
|---|---|---|
| `#/parametres` | Annuaire | inchangée |
| `#/parametres?section=<id>` (section présente) | `<id>` | inchangée ; `#/parametres` pour Annuaire |
| `#/parametres?section=politiques` en démonstration | Annuaire | `#/parametres` |
| `#/parametres?section=<alias>` | section canonique | `?section=<id>` canonique, ou `#/parametres` pour Annuaire |
| `#/parametres?section=<inconnu>` | Annuaire | `#/parametres` |
| `#/parametres?ouvrir=<nom>` | section du champ `[name="<nom>"]` ou du bouton `[data-maint="<nom>"]` | `?section=` de cette section, sans `ouvrir` |
| `#/parametres?section=X&ouvrir=Y` | section de Y si Y existe, sinon X | idem |
| autres paramètres | ignorés | retirés |

Alias acceptés, comparés sans accents ni casse :

| Section | Alias |
|---|---|
| `annuaire` | `nommage`, `domaine`, `sites` |
| `politiques` | `politique`, `coordination` |
| `configuration` | `import`, `export`, `defaut`, `referentiels` |
| `mises-a-jour` | `mise-a-jour`, `maj`, `updates` |
| `interface` | `apparence`, `animations`, `demonstration`, `demo` |

- `ouvrir=` est lu une seule fois, au montage. Sa valeur doit vérifier `^[A-Za-z][A-Za-z0-9-]{0,63}$`, sinon elle est ignorée. La cible est éclairée et reçoit le focus si elle est focalisable et active. **Aucune action n’est lancée** : ni clic, ni dialogue, ni appel.
- Un changement de section fait dans l’écran (rail, tuile, recherche, alerte, refus d’enregistrement) réécrit l’adresse par `ctx.replaceParams`. L’écriture passe par `history.replaceState` : pas de `hashchange`, pas de remontage, pas de garde de sortie.
- Une navigation **externe** vers une autre section (lien, saisie de l’adresse, `ctx.navigate('parametres', { section })`) produit un `hashchange` et un rendu normal du routeur. Avec un brouillon modifié, la garde « Quitter les paramètres » demande d’abord ; si l’opérateur accepte, l’écran est remonté sur la section demandée.
- Exception : un clic simple sur un lien vers l’adresse nue `#/parametres`, comme l’entrée **Paramètres** du menu, affiche Annuaire sur place quand l’écran est courant. Il n’y a ni remontage, ni garde, ni appel, et le brouillon reste intact, comme en 2.0.14 où ce lien visait l’adresse affichée. Un clic avec Ctrl, Maj, Alt ou Cmd et le raccourci Alt+chiffre gardent la navigation du routeur.
- Le retour de la fenêtre de démonstration rouvre `#/parametres?section=interface`, ou l’écran qu’elle désigne.
- La partie `?configuration=local` de `location.search` n’est jamais touchée.

## 4. Bandeau : tuiles, alerte, carte d’état

Les tuiles sont de vrais boutons. Un clic affiche la section indiquée et lui donne le focus. Leur source unique est la dernière lecture réussie du moteur (`loaded`) : aucune tuile ne déclenche d’appel.

| Tuile | Section ouverte | Valeur · sous-texte |
|---|---|---|
| Configuration | Configuration | « Valide » · « Profil Windows » ; « Absente » · « À créer ou importer » ; « Invalide » · « Import requis » ; en démonstration « Démonstration » · « Monde fictif » |
| Nommage | Annuaire | préfixe lu ou « — » · convention lue ou « Convention non définie » |
| Politiques (session réelle) | Politiques | « n sur 8 » · « options activées » (cases `coordinationRequired`, `reserveNamesInAd`, `auditEventLogEnabled`, `blockJoinOnClockSkew`, `allowPrecreatedJoin`, `allowOfflineJoin`, `unattendedJoinEnabled`, `unattendedOperationsEnabled` à `true`) |
| Démonstration (démonstration) | Interface | « Active » · « Aucun effet réel » |
| Brouillon | première section modifiée, sinon Annuaire | « Enregistré » · « Aucune modification en attente » ; « Modifié » · « Enregistrer pour appliquer » |

Avant la première lecture, les tuiles affichent « Lecture… ». Si la première lecture échoue, elles affichent « Non lue ». Si une relecture échoue, elles gardent les dernières valeurs lues, comme le formulaire. Les tuiles ne portent jamais `aria-busy` ni `.skeleton` : `data-ready="parametres"` n’attend pas après elles.

**Alerte** (`[data-configuration-invalid]`, `role="alert"`) : visible quand la configuration du profil est invalide. Elle donne le diagnostic exact et le bouton **Aller à l’import**, qui affiche Configuration, éclaire **Importer** et lui donne le focus. La section par défaut reste Annuaire, même dans ce cas : l’adresse reste stable. `main.dataset.configurationState`, `main.dataset.configurationDiagnostic` et l’événement `pesto-configuration-state` sont inchangés.

**Carte « Configuration en vigueur »**, en lecture seule et sans appel. Verdict : « Configuration valide », « Aucune configuration enregistrée », « Configuration invalide » (avec le diagnostic), « Configuration de démonstration », « Lecture… » ou « Non lue » (avec l’erreur). Faits : domaine, préfixe, nombre de sites et empreinte (12 premiers caractères, valeur complète en infobulle). Toutes les valeurs passent par `textContent`.

**Pastilles du rail** :

- `•` sur Annuaire ou Politiques quand un champ de la section diffère de la dernière version lue ou enregistrée (texte lu : « modifications non enregistrées ») ;
- `!` sur Configuration quand la configuration est invalide (texte lu : « configuration invalide ») ;
- `•` sur Configuration ou Mises à jour quand un statut de maintenance (`[data-maint-status]`) change alors que sa section est masquée, par exemple une écriture de la configuration par défaut terminée après un changement de section (texte lu : « nouveau résultat »). La pastille disparaît quand la section est affichée. Sur Configuration, `!` reste prioritaire.

## 5. Recherche

- Le champ suit le motif combobox et listbox : `aria-expanded`, `aria-activedescendant`, `aria-selected`, `aria-keyshortcuts="/"`.
- `/` place le focus dans le champ. La touche est ignorée dans un champ de saisie, quand un dialogue est ouvert, et avec Ctrl, Cmd ou Alt. Maj n’est pas exclu : sur AZERTY, `/` s’obtient avec Maj.
- Chaque mot de la requête, sans accents ni casse, doit figurer dans le libellé ou les mots-clés de l’entrée. La liste montre au plus 8 résultats, ou « Aucun réglage ne correspond. ».
- ↓ et ↑ parcourent les résultats en boucle, Entrée choisit, Échap vide le champ, un clic choisit.
- Choisir un résultat vide le champ, affiche la section, éclaire le réglage pendant 1,7 s et lui donne le focus. Si le réglage n’a rien de focalisable et d’actif (action désactivée, note, carte d’état), le focus va au bloc éclairé, qui reçoit `tabindex="-1"` jusqu’à ce qu’il perde le focus : le focus suit toujours la vue.
- L’index compte 40 entrées (`INDEX` de `sections.js`) : les champs d’Annuaire et de Politiques, les deux actions du registre de coordination, la carte d’état, `configurationVersion` et les boutons de maintenance, `updateSource`, Animations, Démonstration et le thème.
- Au montage, l’écran ne garde que les entrées dont la section est présente et dont la cible existe hors d’un élément masqué par son propre gabarit : hors session `live`, les actions du registre ne sont pas proposées.

## 6. Brouillon unique et enregistrement

Le brouillon couvre tous les champs `.k-field[data-name]` du formulaire et `textarea[name="sites"]`, qu’ils soient affichés ou non. Changer de section ne le modifie pas, ne demande rien et n’appelle pas le moteur. **Relire**, **Enregistrer**, la garde de sortie, la conservation d’un brouillon modifié pendant une lecture et les commandes d’écran `parametres-reload` et `parametres-save` sont inchangés.

Un refus ouvre la section de la cause, sans annonce de section supplémentaire :

| Refus | Section ouverte | Effet |
|---|---|---|
| Format des sites | Annuaire | Message sous la carte Sites, annoncé une fois, ramené à l’écran ; focus dans la zone des sites |
| Champ requis ou au mauvais format | section du premier champ en erreur | Focus sur ce champ ; annonce du kit « N champs à corriger. » une fois |
| GUID de groupes exclus | Politiques | Message du champ, focus dans le champ ; aucun aperçu demandé |
| Refus du moteur | Annuaire | Message sous la carte Sites, annoncé une fois |

## 7. Garanties

- **Aucun nouvel appel moteur.** Le montage lit les paramètres comme en 2.0.14. Tuiles, carte d’état, pastilles, rail et recherche ne lisent que ce qui a déjà été lu.
- **Écran courant.** `ctx.isCurrent()` vaut `true` tant qu’aucun rendu plus récent n’a commencé et que l’adresse est celle de l’écran : l’adresse du montage, puis celle réécrite par `ctx.replaceParams`. Elle devient `false` dès que l’adresse quitte l’écran, même avant le traitement du `hashchange`. `ctx.replaceParams` refuse d’écrire quand l’écran n’est plus courant. Les réponses tardives restent donc acceptées après un changement de section et refusées après un départ.
- **Maintenance.** `mountMaintenance` utilise `ctx.isCurrent()` : un changement de section ne bloque aucune action de maintenance, et un départ les refuse comme avant.
- **Avis de démarrage.** `showConfigurationNotice` compare le seul chemin de l’adresse : il reste valable quand l’opérateur change de section.
- **Garde de sortie.** Après un refus de quitter, le routeur rétablit l’adresse de l’écran telle qu’elle est à ce moment, avec la section éventuellement réécrite pendant le dialogue.
- **Rendu.** Aucun attribut `style` dans les gabarits (CSP `style-src 'self'`) : les variables `--y`, `--h`, `--j` et `--tone` passent par le CSSOM.
- **Navigation de l’application.** La page n’utilise ni `.nav-item`, ni `.nav-pill`, ni `aria-current="page"`, réservés au menu de l’application. Le rail utilise `aria-current="true"`.

## 8. Accessibilité

- **Rail** : `nav[aria-label="Sections des paramètres"]`, liste de boutons `aria-controls` et `aria-current`. ↑ et ↓ déplacent le focus en boucle, Début et Fin vont aux extrémités, Entrée et Espace affichent la section. Le focus reste sur le rail. La pastille glissante est `aria-hidden`.
- **Panneaux** : `section[aria-labelledby][tabindex="-1"]`. Ce ne sont pas des `tabpanel`, car le rail n’est pas un `tablist`.
- **Annonce** : « Section … » quand l’opérateur change de section (rail, tuile, recherche, alerte). Aucune annonce au premier rendu ni après un refus d’enregistrement.
- **Focus** : au premier rendu, le routeur focalise `main`. Recherche, tuile et alerte donnent le focus au réglage visé ou au panneau. Si l’en-tête du panneau focalisé est hors de la vue (fenêtre étroite, rail et brouillon au-dessus), le panneau est d’abord ramené à l’écran. Au clavier, le panneau focalisé porte le contour du kit.
- **Animations réduites** (`data-motion="reduced"`, ou « Suivre Windows » avec `prefers-reduced-motion`) : pas d’animation d’entrée de section, défilement immédiat vers le réglage, pas de rebond des tuiles. L’éclat et l’alerte ne s’animent pas.
- Il n’y a pas d’animation de sortie entre sections : l’affichage est synchrone.
- **Fenêtre inactive** : la page n’ajoute aucune animation en boucle. L’anneau et les orbes du bandeau gardent la pause du kit.
- **Contraste élevé** : rail, tuiles et brouillon sont encadrés de 2 px sans halo, et l’élément courant du rail porte un contour. Son focus clavier s’en distingue : 3 px, couleur `--accent-hover`, décalé. La liste de recherche est opaque et le résultat actif est encadré. Anneau et orbes sont masqués.
- **`forced-colors`** : pastille masquée, contours `Highlight` et `CanvasText`. Le focus de l’élément courant du rail est en `CanvasText` sur 3 px. Le résultat actif de la recherche est en `Highlight` / `HighlightText`, sur une liste `Canvas`. Les icônes sur dégradé (élément courant, en-tête de section) passent en `Highlight` / `HighlightText`.
- **Contraste du texte** : l’alerte « Configuration invalide » a un fond opaque, que les orbes du bandeau ne traversent pas. La clé des tuiles est en `--text-muted`.
- **Largeur** : la mise en page suit la largeur de l’écran, pas celle de la fenêtre.
  - sous 1120 px, les tuiles passent sous le titre ;
  - sous 980 px, le rail et le brouillon passent au-dessus du contenu, ne collent plus, et le rail s’affiche en grille sans pastille ;
  - sous 560 px, une tuile par ligne ;
  - aucun défilement horizontal : les panneaux sont une grille à une colonne `minmax(0, 1fr)`, que l’exemple insécable des sites n’élargit pas.

## 9. Bancs natifs

Les scripts `Input` et `Click` des bancs refusent un élément masqué. Les bancs ouvrent donc la section avant d’agir, par des étapes **fermées** : une valeur d’énumération, sans texte fourni par la page, la CLI ou le pont.

| Étape | Banc | Effet |
|---|---|---|
| `ShowDirectory`, `ShowConfiguration`, `ShowUpdates` | `--qualify-configuration` (`ConfigurationQualificationScripts`) | Clic sur l’élément du rail, puis contrôle dans la même évaluation : panneau visible, `aria-current="true"` et adresse écrite par la page (`#/parametres` pour Annuaire) |
| `ShowUpdates` | `--qualify-update-ui` (`UpdateUiQualificationScripts`) | Idem, avant le choix du ZIP |
| `ShowInterface` | `--qualify-demo`, coexistence (`DemoQualificationScripts`) | Idem, refusé si la coque est inerte ; avant chaque **Ouvrir la démonstration** |

- L’attente d’inactivité accepte `#/parametres` et `#/parametres?section=<id>` (`IsSettingsRoute`).
- La vérification de l’installation isolée du banc de mise à jour exige toujours `#/parametres`, adresse nue de la section par défaut.
- La route attendue du parent de coexistence devient `#/parametres?section=interface`.
- Coexistence, après la fermeture du premier enfant : `ShowDirectory` (`DemoQualificationScripts`, même script que l’étape du banc de configuration) rouvre Annuaire. La capture `parent-preserved.png` montre donc le brouillon conservé, comme en 2.0.14 (route `#/parametres`, brouillon identique). `ShowInterface` est ensuite rejouée avant le second enfant.
- Aucun contrôle, aucune capture ni aucun dialogue n’est ajouté : 44 contrôles, 6 captures et 7 dialogues de configuration, 6 transitions de démonstration.
- Le banc « mise à jour par l’interface » exécute le programme de la base A (`962f3ba`) avec son interface et ses propres scripts compilés : l’étape `ShowUpdates` n’y est pas exécutée tant que cette base ne change pas. Le validateur `Pesto.UpdateQualification` (`UiSuite.cs`) accepte dès maintenant les `uiSteps` avec ou sans `ShowUpdates` en tête. Sans ce changement, il refuserait la preuve dès que la base passerait à 2.0.15 ou après.

Ces étapes n’ont tourné sur aucun runner Windows à la date de 2.0.15 ([QUALIFICATION-WINDOWS.md](QUALIFICATION-WINDOWS.md)).

## 10. Contrôles et limites

Suites navigateur de l’écran (Chromium et pont de test, [EVIDENCE.md](EVIDENCE.md)) :

- `web-check.mjs` : pureté de `sections.js`, alias, borne de 8 résultats, cibles et icônes de l’index ;
- `web-settings-rail-check.mjs` : rail, adresse, recherche, clavier, animations, contraste et largeur en démonstration ;
- `web-maintenance-check.mjs` : cas de la session réelle (même montage, appels inchangés, réponses tardives, refus qui ouvrent leur section, garde de sortie, alerte, tuiles) ;
- `web-dom-check.mjs`, `demo-dom-check.mjs` et `gui-follow-check.mjs`.

Non qualifié par ces suites : WebView2 natif, UI Automation, lecteur d’écran et échelles d’affichage Windows. Ces points relèvent des bancs natifs et de la [checklist Windows](QUALIFICATION-WINDOWS.md).
