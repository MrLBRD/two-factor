#!/usr/bin/env bash
#
# Construit le zip du plugin, prêt à installer dans WordPress.
#
# Produit build/two-factor-<version>.zip, contenant un unique dossier racine
# two-factor/ (exigence de l'installeur WordPress). Le contenu suit .distignore :
# ni tests, ni node_modules, ni vendor, ni fichiers de dev.
#
# Usage : ./bin/build-zip.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
SLUG="two-factor"
BUILD_DIR="${ROOT}/build"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

version="$(sed -n 's/^ \* Version:[[:space:]]*\(.*\)$/\1/p' two-factor.php | head -1 | tr -d '[:space:]')"
[ -n "$version" ] || die "Version introuvable dans two-factor.php"

bold "Build ${SLUG} ${version}"

# --- 1. Dépendances npm -----------------------------------------------------
# qrcode-generator est une dépendance RUNTIME : le Gruntfile copie
# node_modules/qrcode-generator/qrcode.js dans includes/. Sans elle, le plugin
# est cassé côté navigateur.
if [ ! -d node_modules/qrcode-generator ]; then
	echo "  Installation des dépendances npm…"
	# --ignore-scripts évite le hook preinstall « composer install » : vendor/
	# n'est pas distribué, composer n'est donc pas nécessaire pour le zip.
	npm install --ignore-scripts --no-audit --no-fund --silent
fi
ok "dépendances npm présentes"

# --- 2. Build Grunt ---------------------------------------------------------
npx --no-install grunt build >/dev/null 2>&1 || npx grunt build >/dev/null
[ -d dist ] || die "grunt build n'a pas produit dist/"
ok "dist/ généré"

# --- 3. Garde-fous ----------------------------------------------------------
# Chemin exact chargé par providers/class-two-factor-totp.php:175 — l'absence de
# ce fichier casse l'affichage du QR code TOTP sans erreur PHP.
QRCODE_PATH="dist/includes/qrcode-generator/qrcode.js"
[ -f "$QRCODE_PATH" ] || die "${QRCODE_PATH} manquant (dépendance runtime du TOTP)"
ok "qrcode.js embarqué"

for unwanted in node_modules vendor tests .git .github FORK.md package.json composer.json; do
	[ -e "dist/${unwanted}" ] && die "dist/ contient ${unwanted}, qui ne doit pas être distribué"
done
ok "aucun fichier de développement dans dist/"

# --- 4. Mise en forme de l'archive ------------------------------------------
# Le dossier racine doit porter le slug du plugin, sinon WordPress l'installe
# dans un répertoire au mauvais nom.
rm -rf "${BUILD_DIR}/stage"
mkdir -p "${BUILD_DIR}/stage"
cp -R dist "${BUILD_DIR}/stage/${SLUG}"

zip_path="${BUILD_DIR}/${SLUG}-${version}.zip"
rm -f "$zip_path"
( cd "${BUILD_DIR}/stage" && zip -rq "$zip_path" "$SLUG" -x '*.DS_Store' )
rm -rf "${BUILD_DIR}/stage"

# --- 5. Rapport -------------------------------------------------------------
file_count="$(unzip -l "$zip_path" | tail -1 | awk '{print $2}')"
size="$(du -h "$zip_path" | cut -f1 | tr -d '[:space:]')"

echo
bold "→ ${zip_path#"${ROOT}/"}"
echo "  ${file_count} fichiers, ${size}"
echo
echo "  Installation : Extensions → Ajouter → Téléverser une extension"
