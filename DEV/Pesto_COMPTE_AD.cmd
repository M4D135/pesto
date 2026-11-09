@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Connexion explicite optionnelle. Aucun mot de passe en argument.
rem Sans call : call referait une passe sur les pourcentages et doublerait les circonflexes du chemin.
"%~dp0Pesto.cmd" -AskCredential %*
