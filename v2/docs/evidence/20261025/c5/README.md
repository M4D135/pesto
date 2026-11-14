# Validation portable C5 — synthèse publiable

Moteur **590/590**, pont **15/15**, banc de transaction **10/10**. Builds moteur/pont/hôte Windows/banc : zéro erreur et zéro avertissement. Les **231 sources C#/projets** restent identiques avant et après la campagne finale, puis ont été revérifiées avant le commit. `summary.json` contient uniquement ces résultats, sans chemin d’environnement, identité opérateur, poste réel ou données de domaine.

Les huit suites web terminent à **50/50, 32/32, 29/29, 18/18, 23/23, 21/21, 11/11 et 149/149**. Le passage de parité 50/50 conserve un résumé explicite et ne prétend pas à un transcript intégral. Les contrôles de régression vérifient 78 sources web inchangées pendant leurs exécutions.

Les journaux bruts de développement restent dans l’espace de travail : ils ne sont pas recopiés dans ce commit. Les preuves Windows natives sont publiées directement par les workflows GitHub ; leurs liens et leurs résultats sont consignés dans le rapport daté.

Échecs initiaux résolus avant la campagne finale : diagnostics CA1416 dans un lambda ACL Windows, fixture de finalisation d’attributs reconstruisant à tort un nouveau reçu, listes statiques web ignorant les nouvelles API et le contexte local. Aucun garde métier n’a été supprimé.

Cette campagne emploie des fixtures et Chromium loopback. Elle n’exécute ni opération AD, ni SMB externe, ni djoin, ni redémarrage réel. La compilation croisée ne constitue pas un démarrage Windows.
