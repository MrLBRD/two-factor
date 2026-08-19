# Fork — pourquoi et jusqu'à quand

Ce dépôt est un fork de [WordPress/two-factor](https://github.com/WordPress/two-factor).
Il existe pour une seule raison : **l'enforcement de la 2FA par rôle**, absent des
versions distribuées du plugin officiel.

## Ce que le fork ajoute

La branche `production` = `master` (miroir d'upstream) + la PR upstream
[#845](https://github.com/WordPress/two-factor/pull/845) « Add: Site-wide Two-Factor
enforcement per user role », qui répond à l'issue
[#846](https://github.com/WordPress/two-factor/issues/846).

Cette PR est ouverte depuis mars 2026, mergeable sans conflit, CI verte sur 24
combinaisons PHP/WP, et testée par un contributeur tiers. Elle attend une review.

Fonctionnellement, elle ajoute à **Réglages → Two-Factor** une section « Two-Factor
Enforcement » avec une case par rôle. Un utilisateur d'un rôle coché qui n'a pas
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

## Synchroniser avec upstream

```bash
git fetch upstream
git checkout master && git merge --ff-only upstream/master   # miroir, jamais de commit propre
git checkout production && git merge master
npm run lint && npm test
```

`master` reste un miroir strict d'upstream : ne jamais y committer. Tout ce qui est
propre au fork vit sur `production`.

## Sortie du fork

Quand l'issue `upstream-exit` apparaît :

1. Comparer notre implémentation à celle publiée — le nom des options a pu changer
   pendant la review upstream.
2. Vérifier que `two_factor_enforced_roles` déjà en base est lu par la version
   officielle, sinon prévoir une migration.
3. Repasser les sites sur le plugin de wordpress.org, archiver `production`.
