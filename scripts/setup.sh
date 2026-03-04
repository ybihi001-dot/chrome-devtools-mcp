#!/bin/bash
# ============================================================
# MarocCommercantHub - Script Setup GitHub + Vercel
# Version : 2.0
# Usage   : chmod +x scripts/setup.sh && ./scripts/setup.sh
# ============================================================

set -e

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "
${BOLD}${CYAN}==> $*${NC}"; }

check_cmd() { command -v "$1" >/dev/null 2>&1; }

banner() {
  echo -e "${BOLD}${GREEN}"
  echo "  +------------------------------------------+"
  echo "  |   MarocCommercantHub - Setup v2.0        |"
  echo "  |   GitHub + Supabase + Vercel Deploy      |"
  echo "  +------------------------------------------+"
  echo -e "${NC}"
}

banner
info "Date : $(date +%Y-%m-%d\ %H:%M:%S)"
info "Repertoire : $(pwd)"

# ETAPE 1 - Verification dependances
step "Verification des dependances"

MISSING=()
for cmd in git node npm; do
  if check_cmd "$cmd"; then
    ok "$cmd : $(command -v $cmd)"
  else
    MISSING+=("$cmd")
    warn "$cmd INTROUVABLE"
  fi
done

[ ${#MISSING[@]} -gt 0 ] && err "Dependances manquantes : ${MISSING[*]}"

if check_cmd vercel; then
  VERCEL_OK=true
  ok "Vercel CLI : $(vercel --version 2>/dev/null | head -1)"
else
  VERCEL_OK=false
  warn "Vercel CLI absent. Installez : npm i -g vercel"
fi

if check_cmd gh; then
  ok "GitHub CLI : $(gh --version | head -1)"
else
  warn "GitHub CLI absent (optionnel)"
fi

# ETAPE 2 - Configuration Git
step "Configuration Git"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init && ok "Depot git initialise."
else
  ok "Depot git existant detecte."
fi

if git remote get-url origin >/dev/null 2>&1; then
  ok "Remote origin : $(git remote get-url origin)"
else
  read -p "URL de votre depot GitHub: " REPO_URL
  [ -n "$REPO_URL" ] && git remote add origin "$REPO_URL" && ok "Remote configure : $REPO_URL"
fi

[ -z "$(git config user.name)" ]  && read -p "Votre nom Git: "   N && git config user.name "$N"
[ -z "$(git config user.email)" ] && read -p "Votre email Git: " E && git config user.email "$E"
ok "Git : $(git config user.name) <$(git config user.email)>"

# ETAPE 3 - npm install
step "Installation dependances Node.js"
if [ -f package.json ]; then
  npm install && ok "npm install termine."
else
  warn "Pas de package.json - etape ignoree."
fi

# ETAPE 4 - Build
step "Build du projet"
if [ -f package.json ] && grep -q '"build"' package.json; then
  npm run build && ok "Build reussi."
else
  warn "Pas de script build - etape ignoree."
fi

# ETAPE 5 - Verification schema SQL
step "Verification schema Supabase"
SQL="sql/maroc_commercant_hub_schema.sql"
if [ -f "$SQL" ]; then
  LC=$(wc -l < "$SQL")
  ok "Schema SQL : $LC lignes"
  for s in "CREATE TABLE" "CREATE INDEX" "CREATE POLICY" "CREATE FUNCTION" "CREATE TRIGGER"; do
    C=$(grep -c "$s" "$SQL" 2>/dev/null || true)
    [ "$C" -gt 0 ] && ok "$s : $C" || warn "$s : absent"
  done
else
  warn "Schema SQL introuvable !"
fi

# ETAPE 6 - Commit & Push
step "Commit et Push GitHub"
if git diff --quiet && git diff --staged --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  ok "Depot propre - rien a committer."
else
  git add -A
  MSG="feat: MarocCommercantHub - SQL schema + setup scripts [$(date +%Y-%m-%d)]"
  git commit -m "$MSG" && ok "Commit cree."
  if git remote get-url origin >/dev/null 2>&1; then
    B=$(git rev-parse --abbrev-ref HEAD)
    git push origin "$B" && ok "Push reussi sur origin/$B"
  else
    warn "Pas de remote - push ignore."
  fi
fi

# ETAPE 7 - Deploiement Vercel
step "Deploiement Vercel"
if [ "$VERCEL_OK" = true ]; then
  read -p "Deployer sur Vercel maintenant ? [o/N] " D
  if [[ "$D" =~ ^[oOyY]$ ]]; then
    if [ -f ".vercel/project.json" ]; then
      vercel --prod && ok "Deploiement prod termine !"
    else
      vercel && ok "Deploiement initial termine !"
    fi
  else
    info "Deploiement ignore. Lancez manuellement : vercel --prod"
  fi
else
  warn "Pour deployer :
  1. npm i -g vercel
  2. vercel login
  3. vercel --prod"
fi

# RESUME
echo ""
echo -e "${BOLD}${GREEN}+------------------------------------------+"
echo -e "| Setup MarocCommercantHub TERMINE !       |"
echo -e "+------------------------------------------+${NC}"
echo ""
cat << NEXTSTEPS
Prochaines etapes :
  1. Supabase  -> Importez sql/maroc_commercant_hub_schema.sql
               -> Copiez SUPABASE_URL et SUPABASE_ANON_KEY
  2. GitHub    -> Verifiez votre depot en ligne
  3. Vercel    -> Ajoutez les variables d env :
               -> NEXT_PUBLIC_SUPABASE_URL
               -> NEXT_PUBLIC_SUPABASE_ANON_KEY
  4. Local     -> npm run dev
NEXTSTEPS
echo ""
ok "MarocCommercantHub est pret ! Bonne continuation."
