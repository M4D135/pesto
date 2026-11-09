# Campagne Windows 41b7722

[Workflow et artefacts natifs originaux](https://github.com/M4D135/pesto/actions/runs/40228437180) — conclusion : **failure**.

Le parseur valide 13/13 sources sous Windows PowerShell 5.1. PROD atteint prêt/fermé et 34 API refusées, mais la preuve globale reste success:false à cause du compteur final resté à 29. DEV et les transactions ne sont pas exécutés. Le correctif ultérieur 8b9f143 possède sa propre campagne.

Les journaux et preuves JSON restent dans leurs artefacts GitHub d’origine ; ils ne sont pas recopiés dans ce commit. La campagne reste attachée à ce binaire et ne qualifie pas automatiquement le lot C5 ultérieur.
