# Fork — pourquoi et jusqu'à quand

Ce dépôt est un fork de [WordPress/two-factor](https://github.com/WordPress/two-factor).
Il existe pour une seule raison : **l'enforcement de la 2FA par rôle**, absent des
versions distribuées du plugin officiel.

## Ce que le fork ajoute

La branche `production` = `master` (miroir d'upstream) + quatre PR upstream ouvertes,
toutes avec une CI verte sur les 27 checks et mergées ici sans conflit :

| PR | Apport | Pourquoi |
|---|---|---|
| [#845](https://github.com/WordPress/two-factor/pull/845) | Enforcement 2FA par rôle | La raison d'être du fork ([#846](https://github.com/WordPress/two-factor/issues/846)) |
| [#927](https://github.com/WordPress/two-factor/pull/927) | Rework du fail-safe des providers | Corrige une régression **de la 0.16.0** ([#871](https://github.com/WordPress/two-factor/issues/871)) |
| [#917](https://github.com/WordPress/two-factor/pull/917) | Rate-limit avant le pre-processing | Durcissement anti-bruteforce |
| [#958](https://github.com/WordPress/two-factor/pull/958) | Code de secours vide | Correctif de bug |

Deux PR ont été écartées volontairement :

- **#882** traite la même issue #871 que #927 par une approche concurrente, née d'une
  review de #882. Les cumuler produit un conflit : il faut choisir, et #927 est
  l'approche retenue en amont.
- **#916 (Passkeys)** ajoute la dépendance composer `lbuchs/webauthn`, ce qui rendrait
  `vendor/` nécessaire au runtime alors qu'il est exclu de la distribution — le build
  du zip serait à refondre.

**Validation locale de la combinaison** (19/08/2026, wp-env / PHP 7.4.33) :
PHPUnit **209 tests, 690 assertions, OK** — dont les 10 tests du groupe
`enforcement` qui passent avec le rework de #927, ce qui confirme que les deux
n'entrent pas en conflit. PHPCS 23/23 et PHPStan 0 erreur.

Deux violations PHPCS de la PR #917 ont dû être corrigées ici : sa branche a été
rebasée le 9 juillet, avant le bump PHP_CodeSniffer 3.13.6 arrivé sur master le
8 août, si bien que sa CI ne les voit pas.

### L'enforcement par rôle en pratique

#845 ajoute à **Réglages → Two-Factor** une section « Two-Factor Enforcement » avec
une case par rôle. Un utilisateur d'un rôle coché qui n'a pas
configuré de 2FA se voit injecter le provider Email au login. Le comportement est
volontairement *fail-closed* : si le provider Email est désactivé au niveau du site,
l'enforcement ne s'applique pas plutôt que d'injecter un provider (TOTP) qui exigerait
une configuration préalable et échouerait en silence.

Options créées en base : `two_factor_enforced_roles`, `two_factor_enabled_providers`.

## Pourquoi un fork plutôt que d'attendre

Au 19/08/2026, la dernière release officielle est la **0.16.0 du 27/03/2026**, soit
145 jours, avec **128 commits non distribués** sur `master`. Parmi eux, des correctifs
touchant à la sécurité — dont « Fail closed when CSPRNG is unavailable during nonce
generation » (PR #877) et deux autres sur la vérification de nonce.

Conséquence contre-intuitive mais décisive : suivre `master` via ce fork rend **plus à
jour** en sécurité que rester sur la 0.16.0 de wordpress.org. Un correctif mergé mais
non publié est lisible par tout le monde et appliqué chez personne.

C'est pour cette raison que la veille se déclenche sur les **releases** et sur le
**drift de `master`**, jamais sur le simple merge d'une PR.

## Veille automatique

`.github/workflows/upstream-watch.yml` exécute quotidiennement
`.github/scripts/upstream-watch.sh`, qui ouvre une issue dans ce dépôt selon trois cas :

| Label | Déclencheur | Action attendue |
|---|---|---|
| `upstream-exit` | Une release officielle contient `two_factor_enforced_roles` | Le fork n'a plus de raison d'être → repasser sur le plugin officiel |
| `upstream-drift` | Des correctifs de sécurité, ou ≥ 25 commits, non intégrés dans `production` | Reporter les correctifs |
| `upstream-release` | Nouvelle release sans la feature | Intégrer la release |

Le critère de sortie est la présence du marqueur **dans le fichier au tag publié** —
donc dans du code réellement distribué, pas simplement mergé.

Test à blanc, sans rien créer :

```bash
GITHUB_REPOSITORY=MrLBRD/two-factor ./.github/scripts/upstream-watch.sh --dry-run
```

> **À faire une fois après le premier push :** activer les Actions sur le fork
> (onglet *Actions* → *I understand my workflows, go ahead and enable them*). GitHub
> les désactive par défaut sur les forks, et suspend les workflows planifiés après
> 60 jours sans activité sur le dépôt.

## Gestionnaire de paquets : pnpm

Ce fork utilise **pnpm**, pas npm. `pnpm-lock.yaml` a été généré par `pnpm import`
depuis le `package-lock.json` d'upstream, donc avec les mêmes versions résolues.

> **Après chaque synchronisation qui modifie `package-lock.json`** (Dependabot est
> très actif en amont), régénérer le lockfile pnpm :
>
> ```bash
> pnpm import && pnpm install
> ```

Les scripts internes de `package.json` appellent encore `npm run` : ce fichier n'est
volontairement **pas** modifié, parce que les workflows CI d'upstream (`test.yml`,
`deploy.yml`) reposent dessus et que Dependabot y touche à chaque bump. Nos propres
points d'entrée — `bin/build-zip.sh` et les tâches VS Code — contournent ces scripts
et appellent `pnpm exec` directement.

## Tâches VS Code

`Cmd+Shift+B` lance le build du zip. Les autres via **Terminal → Exécuter la tâche** :

| Tâche | Effet |
|---|---|
| Plugin : builder le ZIP | *(défaut)* archive installable |
| Plugin : builder le ZIP et l'ouvrir dans le Finder | idem + Finder |
| Tests : suite complète | PHPUnit dans le conteneur |
| Tests : enforcement par rôle | uniquement le groupe `enforcement` |
| Lint : PHPCS | WordPress + VIP-Go |
| Env : démarrer / arrêter | conteneurs wp-env |
| Veille upstream : test à blanc | vérifie sans créer d'issue |

## Construire le zip à installer

En ligne de commande :

```bash
./bin/build-zip.sh
```

Produit `build/two-factor-<version>.zip` (~3 s, 80 Ko), contenant un unique dossier
racine `two-factor/` comme l'exige l'installeur WordPress. Le contenu suit
`.distignore` : ni `tests/`, ni `node_modules/`, ni `vendor/`, ni fichiers de dev, ni
fichiers propres au fork.

Le script échoue plutôt que de produire une archive silencieusement cassée dans deux
cas : si `includes/qrcode-generator/qrcode.js` manque — dépendance runtime copiée
depuis `node_modules` au build, sans laquelle le QR code TOTP ne s'affiche pas — ou si
un fichier de développement s'est glissé dans `dist/`. Ce second garde-fou a déjà
servi : `.distignore` ne connaissait pas `pnpm-lock.yaml`, qui partait dans l'archive.

Installation : **Extensions → Ajouter → Téléverser une extension**.

## Synchroniser avec upstream

```bash
git fetch upstream
git checkout master && git merge --ff-only upstream/master   # miroir, jamais de commit propre
git checkout production && git merge master
pnpm import && pnpm install                                  # si package-lock.json a bougé
pnpm exec wp-env start
pnpm exec wp-env run tests-cli --env-cwd=wp-content/plugins/two-factor composer -- test
```

Les quatre PR intégrées sont autant de merges à re-résoudre si upstream touche les
mêmes zones. Quand l'une d'elles est mergée en amont, son merge local devient un
no-op : elle disparaît naturellement à la synchronisation suivante.

`master` reste un miroir strict d'upstream : ne jamais y committer. Tout ce qui est
propre au fork vit sur `production`.

## Sortie du fork

Quand l'issue `upstream-exit` apparaît :

1. Comparer notre implémentation à celle publiée — le nom des options a pu changer
   pendant la review upstream.
2. Vérifier que `two_factor_enforced_roles` déjà en base est lu par la version
   officielle, sinon prévoir une migration.
3. Repasser les sites sur le plugin de wordpress.org, archiver `production`.
