# Lot politiques métier — contrôles portables

Moteur **431/431**, pont **8/8**, panneaux de politiques **17/17**, maintenance **18/18**, contrats web **132/132**, cycle du pont **13/13**, démo navigateur **11/11**, auto-test du banc **10/10**. Les builds moteur/tests, hôte Windows et banc réussissent avec zéro erreur et zéro avertissement. **178 fichiers sources/tests du périmètre C# sont identiques avant/après** cette vérification intégrée.

Les parcours métier passent 25/25 avant le dernier ajout de divulgation de réservation, puis 2/2 ciblés après celui-ci ; ce ne sont pas 27 cas indépendants ni une invocation unique de toute la suite modifiée. Les preuves ne s’additionnent pas. Les tests emploient des doubles déclarés et Chromium ; ils ne prouvent aucune opération AD/SMB, aucune commande PowerShell native ni le démarrage WebView2 Windows du nouveau binaire. Le rapport courant décrit les campagnes Windows attachées à leurs commits exacts.

Les journaux et les instantanés ci-dessous conservent leurs octets originaux.

| Fichier | SHA-256 original |
|---|---|
| [build-engine-policies-final.txt](build-engine-policies-final.txt) | `05bec09c9959ab783a74549e72b7e6af016df76df5e2d7a5afd299ec64f95cd9` |
| [engine-policies-final.txt](engine-policies-final.txt) | `5b1045441ecf29236ff3dd8e437350d04abf7beddf5dfbb17220439a50fe14e4` |
| [build-app-policies-final.txt](build-app-policies-final.txt) | `2f6682555f98b22170123f3a342d7ae5a783d09fb341ded725f0595b4bfc7cb0` |
| [build-harness-policies-final.txt](build-harness-policies-final.txt) | `14decc038d1f124781a4d325dfbd0341d6d0587fc9c2789f89bff34112e555d6` |
| [harness-policies-final.txt](harness-policies-final.txt) | `8f0e73ab05e7f9f18137c0f8bc5727a7860cc68c18156c7ea0aee9051daacf39` |
| [build-bridge-policies.txt](build-bridge-policies.txt) | `17fa800e6be56143ad34321a3682f2b8d4566337283bdf03dc004a08dd7b33de` |
| [bridge-policies.txt](bridge-policies.txt) | `904ffe0ac29a49043139210acb5b1ae25696b6928e2395193af2b3ad762b862b` |
| [policy-ui-final.txt](policy-ui-final.txt) | `4b9c4ddbd8f51a43fcbfbd9a94855bd3dc62f9d42f42ba71706902b8a98d8c92` |
| [web-maintenance-check-policies.txt](web-maintenance-check-policies.txt) | `c825946ddc4048e80550a84485dd3d3b2794aacf5ae763d7a9136de23fcc7474` |
| [web-business-check-policies.txt](web-business-check-policies.txt) | `26fed231a4a75a0d83578e09081bb177f18b9c78379ed7ab619adb1bd8874333` |
| [business-reservation-final.txt](business-reservation-final.txt) | `9e32f810d676774f936f40bd9b26b8bf5d923c1f9b0bd995d7c3a10dd9aa15fd` |
| [web-check-policies-final.txt](web-check-policies-final.txt) | `db963bc377c0b818a51f7a827e53f93779e06599b16826cd84b6bf75ddd22191` |
| [bridge-lifecycle-check-policies-final.txt](bridge-lifecycle-check-policies-final.txt) | `70a43a953b6192eea9a67773623b7cc6d18f22e07837b8c2cd7624cd1840ffe8` |
| [demo-check-policies-final.txt](demo-check-policies-final.txt) | `e0debd8e5f0cb2997d80d425b95201fae9e7bdf6c9d01fec7007d4d807f4b5e9` |
| [sources-before.json.txt](sources-before.json.txt) | `d9f37a9009ef0c410832776ade7f6f9ab0b633f653d61008b3761729d3dbc3d8` |
| [sources-after.json.txt](sources-after.json.txt) | `d9f37a9009ef0c410832776ade7f6f9ab0b633f653d61008b3761729d3dbc3d8` |
