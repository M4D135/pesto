# Aperçu du nom avant jonction — 23 octobre 2026

Le formulaire attend une lecture AD complète du site sélectionné avant de calculer le nom et d’activer l’ajout. La fin de lecture remplit automatiquement l’aperçu ; une lecture lente, partielle, en erreur ou concernant un autre site ne propose aucun nom provisoire. Le nom reste stable lors des rafraîchissements tant qu’il est disponible. Le mode explicite de compte précréé conserve sa saisie.

Au clic, le contrôle porte sur le nom affiché. Une collision AD ou une réservation concurrente revient à une nouvelle proposition : la revérification automatique reste en lecture seule et un nouveau clic est nécessaire avant l’ajout. Une lecture locale annulée ou en erreur restitue également les noms arrivés pendant son exécution.

Validation : 61 contrôles de présentation (dont sept nouvelles régressions), 38 de cache du répertoire, 11 de choix des noms et 27 de réservation, tous réussis sous PowerShell 7.6.7 sur le Spark avec doubles locaux. Les rapports voisins précisent leur périmètre ; aucune nouvelle jonction réelle ni qualification WPF/Windows n’est revendiquée. Les 181 tests Python ciblés sur les noms, la jonction, le lanceur et les distributions passent également.

Le module généré a été reconstruit puis contrôlé par `Build-PestoEngineModule.ps1 -Check`. Le lanceur a été compilé avec clang/lld 23.1.2 sur macOS, sans exécution de l’EXE. Les deux archives extraites contiennent les 67 composants runtime attendus ; chaque fichier extrait a été comparé aux sources. Configuration neutre, aucune configuration privée ajoutée.

Base : `fdc30e74b5bfc349c349f90ba27c084a42c868bd`. Empreintes des sources : [sources.json](sources.json). Archives : [packs.json](packs.json). Ce correctif ne clôture aucune qualification antérieure, notamment le point 102.
