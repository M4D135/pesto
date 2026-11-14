# Bilan de livraison GP 17.0-RC9

## Portée
Correction ciblée des traces de worker, de la supervision des mutations, et du chemin STA de l'élévation locale. Ce n'est ni une certification de production ni une preuve que l'attente RC8 avait une cause unique.

## Exécuté ici
Analyse du source RC8, comparaison des fonctions, contrôle lexical/XML, contrats de régression statiques et contrôles négatifs dans des copies en mémoire. Les résultats propres au source RC9 sont regroupés dans `tests/rc9-validation-summary.json`. Les contrôles spécifiques RC9 sont dans `tests/progress-static-report.json`.

Les anciennes empreintes de référence RC5/RC7 sont conservées. Les validateurs ont une liste explicite des fonctions intentionnellement modifiées en RC8/RC9 ; elle n'est pas un remplacement silencieux des empreintes. La comparaison dédiée RC8/RC9 figure dans `tests/rc9-preservation-report.json`.

Les rapports historiques `*-checker-selftest-report.json` peuvent dater d'une version antérieure et ne constituent pas une validation RC9. La relance du premier auto-test historique a été interrompue par la limite de temps de l'environnement ; les autres anciens auto-tests n'ont pas été relancés. Seuls les résultats listés dans le récapitulatif RC9 sont déclarés exécutés. Les contrôles négatifs intégrés aux tests de saisie, de retrait et de progression ont, eux, été exécutés sur RC9.

## Fourni, NON exécuté ici
- 21 nouveaux cas Windows PowerShell 5.1 avec parseur natif, runspaces et timers WPF isolés.
- Les suites Windows antérieures et leur lanceur TEST_TOUT.cmd.
- Le diagnostic local en lecture seule, qui nécessite Windows.
- Le workflow CI Windows et la compilation PS2EXE.

## NON validé
Rendu WPF, élévation UAC, AppLocker/WDAC/antivirus, exécution AD/Windows réelle, délais de votre réseau, droits du compte sur le poste et les OU. Aucun test de bout en bout sur domaine réel n'a eu lieu.

## Sécurité opérationnelle
Un délai expiré signale une issue à vérifier, pas une annulation. Une commande native déjà engagée et un helper externe peuvent poursuivre leur action. Le verrou, les résultats incertains et le contrôle manuel sont conservés. Aucune relance automatique et aucun redémarrage implicite ne sont ajoutés.

## Résultats du source livré

301 contrôles statiques positifs dans huit validateurs ; aucune exécution native Windows. 15 contrôles négatifs intégrés exécutés et détectés. Les totaux mesurent des contrats statiques, pas des scénarios de production.
