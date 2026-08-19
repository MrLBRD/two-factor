#!/usr/bin/env bash
#
# Veille sur WordPress/two-factor pour ce fork.
#
# Le critère qui compte est la RELEASE, pas le merge de PR : un correctif mergé
# sur master mais jamais publié n'est distribué à personne, tout en étant
# lisible publiquement par un attaquant. On alerte donc sur les releases, et on
# signale en second lieu les commits de master non encore intégrés ici.
#
# Variables attendues : GH_TOKEN, GITHUB_REPOSITORY.
# Usage local : GITHUB_REPOSITORY=MrLBRD/two-factor ./.github/scripts/upstream-watch.sh [--dry-run]

set -euo pipefail

UPSTREAM="${UPSTREAM:-WordPress/two-factor}"
FORK_BRANCH="${FORK_BRANCH:-production}"
# Marqueur prouvant que l'enforcement par rôle est présent dans un tag donné.
FEATURE_MARKER="${FEATURE_MARKER:-two_factor_enforced_roles}"
UPSTREAM_PR="${UPSTREAM_PR:-845}"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# --- 1. Dernière release upstream -------------------------------------------
release_json="$(gh api "repos/${UPSTREAM}/releases?per_page=1")"
tag="$(jq -r '.[0].tag_name // empty' <<<"$release_json")"
published="$(jq -r '.[0].published_at // empty' <<<"$release_json")"

if [ -z "$tag" ]; then
	echo "Aucune release trouvée sur ${UPSTREAM}, rien à faire."
	exit 0
fi

# date -d est GNU (runner Ubuntu) ; -j -f est BSD (macOS, pour les tests locaux).
if date -u -d "$published" +%s >/dev/null 2>&1; then
	published_ts="$(date -u -d "$published" +%s)"
else
	published_ts="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$published" +%s)"
fi
days_old=$(( ( $(date -u +%s) - published_ts ) / 86400 ))

echo "Dernière release upstream : ${tag} (${published:0:10}, il y a ${days_old} j)"

# --- 2. Cette release contient-elle l'enforcement par rôle ? -----------------
# On lit le fichier AU TAG PUBLIÉ : seule preuve que le code est réellement
# distribué, et non simplement mergé sur master.
feature_shipped=false
if gh api "repos/${UPSTREAM}/contents/two-factor.php?ref=${tag}" --jq '.content' 2>/dev/null \
	| base64 -d 2>/dev/null | grep -q "${FEATURE_MARKER}"; then
	feature_shipped=true
fi
echo "Enforcement par rôle distribué dans ${tag} : ${feature_shipped}"

# --- 3. Retard de notre branche sur master upstream -------------------------
# Comparaison faite DEPUIS notre fork : base = notre branche, head = master
# upstream. ahead_by donne donc les commits upstream qui nous manquent.
if compare_json="$(gh api "repos/${GITHUB_REPOSITORY}/compare/${FORK_BRANCH}...${UPSTREAM%%/*}:master" 2>/dev/null)"; then
	behind="$(jq -r '.ahead_by // "inconnu"' <<<"$compare_json")"
else
	# Branche absente du fork (pas encore poussée) ou refs incomparables.
	behind="inconnu"
fi
echo "Commits upstream master non intégrés dans ${FORK_BRANCH} : ${behind}"

# --- 4. État de la PR amont (informatif) ------------------------------------
pr_state="$(gh api "repos/${UPSTREAM}/pulls/${UPSTREAM_PR}" --jq 'if .merged then "mergée" else .state end' 2>/dev/null || echo 'inconnu')"

# --- 4b. Correctifs de sécurité coincés sur master --------------------------
# C'est le vrai risque : upstream merge des fix puis ne publie pas. Le diff est
# alors public alors que les sites tournent encore sur la version vulnérable.
sec_commits=""
if [ -n "${compare_json:-}" ]; then
	sec_commits="$(jq -r '.commits[]?.commit.message | split("\n")[0]' <<<"$compare_json" 2>/dev/null \
		| grep -iE 'fail.closed|securit|vulnerab|\bxss\b|csrf|nonce|sanitiz|escap|bypass|injection|hardening' \
		| grep -viE 'dependabot|^bump |^merge ' | head -15 || true)"
fi
sec_count="$(printf '%s' "$sec_commits" | grep -c . || true)"
echo "Correctifs de sécurité non intégrés détectés : ${sec_count}"
echo "PR #${UPSTREAM_PR} : ${pr_state}"

# --- 5. Alertes : une issue par tag, idempotent -----------------------------
# Le corps passe par un fichier : une apostrophe dans du texte français suffit
# à casser le parsing d'un heredoc imbriqué dans $( ), et gh gère --body-file.
open_issue() { # $1 titre, $2 label, $3 chemin du fichier de corps
	local title="$1" label="$2" body_file="$3" existing

	existing="$(gh issue list --repo "${GITHUB_REPOSITORY}" --state open \
		--search "\"${title}\" in:title" --json title --jq 'length' 2>/dev/null || echo 0)"
	if [ "${existing:-0}" -gt 0 ]; then
		echo "Issue déjà ouverte pour « ${title} », pas de doublon."
		return
	fi

	if [ "$DRY_RUN" = true ]; then
		echo "--- DRY RUN : issue qui serait créée ---"
		echo "Titre : ${title}"
		echo "Label : ${label}"
		cat "${body_file}"
		echo "--- fin ---"
		return
	fi

	gh label create "$label" --repo "${GITHUB_REPOSITORY}" --color 0E8A16 --force >/dev/null 2>&1 || true
	gh issue create --repo "${GITHUB_REPOSITORY}" --title "$title" --label "$label" --body-file "$body_file"
}

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

# Seuil de commits non intégrés au-delà duquel on alerte même sans release.
DRIFT_THRESHOLD="${DRIFT_THRESHOLD:-25}"

if [ "$feature_shipped" = true ]; then
	cat > "$body_file" <<EOF
La release upstream **${tag}** (${published:0:10}) contient \`${FEATURE_MARKER}\` :
l'enforcement 2FA par rôle est désormais **distribué** dans la version officielle.
Le fork n'a plus de raison d'être pour cette fonctionnalité.

**Procédure de sortie**

1. Comparer notre implémentation à celle publiée — le nom des options a pu changer
   pendant la review upstream.
2. Vérifier que l'option \`${FEATURE_MARKER}\` déjà enregistrée en base est bien lue
   par la version officielle. Sinon, prévoir une migration avant de basculer.
3. Repasser les sites sur le plugin de wordpress.org, puis archiver \`${FORK_BRANCH}\`.

PR d'origine : ${UPSTREAM}#${UPSTREAM_PR} (${pr_state})
EOF
	open_issue \
		"Retour possible sur le plugin officiel — ${tag} embarque l'enforcement par rôle" \
		"upstream-exit" \
		"$body_file"
	exit 0
fi

# --- Alerte drift : indépendante des releases -------------------------------
# Sans ce bloc, une absence prolongée de release upstream (le cas actuel) ne
# déclencherait aucune alerte alors que les correctifs s'accumulent sur master.
if [ "$behind" != "inconnu" ] && [ "${behind:-0}" -gt 0 ] \
	&& { [ "${sec_count:-0}" -gt 0 ] || [ "${behind}" -ge "${DRIFT_THRESHOLD}" ]; }; then

	{
		echo "\`${FORK_BRANCH}\` a **${behind}** commits de retard sur \`${UPSTREAM}@master\`."
		echo
		echo "Dernière release upstream : **${tag}** (${published:0:10}, il y a ${days_old} j) —"
		echo "ces commits ne sont donc distribués dans **aucune version publiée**."
		echo
		if [ "${sec_count:-0}" -gt 0 ]; then
			echo "**${sec_count} correctif(s) touchant à la sécurité** non intégrés ici :"
			echo
			printf '%s\n' "$sec_commits" | sed 's/^/- /'
			echo
		fi
		echo "**À faire** — reporter les correctifs :"
		echo
		echo '```bash'
		echo "git fetch upstream"
		echo "git checkout ${FORK_BRANCH}"
		echo "git merge upstream/master"
		echo "npm run lint && npm test"
		echo '```'
	} > "$body_file"

	open_issue \
		"Correctifs upstream non intégrés dans ${FORK_BRANCH}" \
		"upstream-drift" \
		"$body_file"

elif [ "$behind" != "inconnu" ] && [ "${behind:-0}" -gt 0 ]; then
	cat > "$body_file" <<EOF
Release upstream **${tag}** publiée le ${published:0:10}.

Elle **ne contient pas** l'enforcement par rôle : le fork reste nécessaire.

- Commits de \`master\` non intégrés ici : **${behind}**
- PR #${UPSTREAM_PR} : ${pr_state}
EOF
	open_issue \
		"Upstream ${tag} publiée — à intégrer dans ${FORK_BRANCH}" \
		"upstream-release" \
		"$body_file"
else
	echo "Rien à signaler."
fi
