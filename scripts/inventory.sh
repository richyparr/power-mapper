#!/usr/bin/env bash
set -euo pipefail

# Power Mapper — Tier 1: Inventory
# Programmatically enumerate every file in the codebase.
# Zero LLM involvement. Scripts can't miss files.
#
# Output: .planning/audit/inventory/ with multiple inventory files

AUDIT_DIR=".planning/audit"
INV_DIR="$AUDIT_DIR/inventory"
mkdir -p "$INV_DIR"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

echo "=== Power Mapper: Tier 1 Inventory ==="
echo "Root: $ROOT"

# ─── Stack Detection ───────────────────────────────────────────────
echo "Detecting stack..."
STACK_FILE="$INV_DIR/stack.txt"
: > "$STACK_FILE"

# Package managers and languages
[[ -f "package.json" ]]       && echo "node" >> "$STACK_FILE"
[[ -f "package-lock.json" ]]  && echo "pm:npm" >> "$STACK_FILE"
[[ -f "yarn.lock" ]]          && echo "pm:yarn" >> "$STACK_FILE"
[[ -f "pnpm-lock.yaml" ]]     && echo "pm:pnpm" >> "$STACK_FILE"
[[ -f "bun.lockb" ]]          && echo "pm:bun" >> "$STACK_FILE"
[[ -f "requirements.txt" || -f "pyproject.toml" || -f "Pipfile" ]] && echo "python" >> "$STACK_FILE"
[[ -f "go.mod" ]]             && echo "go" >> "$STACK_FILE"
[[ -f "Cargo.toml" ]]         && echo "rust" >> "$STACK_FILE"
[[ -f "Gemfile" ]]            && echo "ruby" >> "$STACK_FILE"
[[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]] && echo "jvm" >> "$STACK_FILE"
[[ -f "Package.swift" ]]      && echo "swift" >> "$STACK_FILE"
[[ -f "composer.json" ]]      && echo "php" >> "$STACK_FILE"
[[ -f "mix.exs" ]]            && echo "elixir" >> "$STACK_FILE"
[[ -f "Makefile" ]]           && echo "make" >> "$STACK_FILE"

# Detect frameworks from package.json
if [[ -f "package.json" ]]; then
  for fw in next react vue svelte angular express fastify hono nestjs nuxt vite remix astro gatsby ember; do
    grep -q "\"${fw}\"" package.json 2>/dev/null && echo "fw:$fw" >> "$STACK_FILE"
  done
  for sdk in supabase prisma drizzle stripe @sentry/react @clerk/nextjs firebase mongoose sequelize typeorm; do
    grep -q "\"${sdk}" package.json 2>/dev/null && echo "sdk:$sdk" >> "$STACK_FILE"
  done
fi

# Detect frameworks from Python
if [[ -f "requirements.txt" ]]; then
  for fw in django fastapi flask starlette tornado; do
    grep -qi "$fw" requirements.txt 2>/dev/null && echo "fw:$fw" >> "$STACK_FILE"
  done
fi

echo "Stack: $(tr '\n' ', ' < "$STACK_FILE" | sed 's/,$//')"

# ─── File Inventory ────────────────────────────────────────────────
echo "Counting files..."

# Source extensions (broad — catch everything)
SRC_PATTERN='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|scala|swift|php|vue|svelte|astro|sql|graphql|gql|prisma|proto|css|scss|sass|less|html|hbs|ejs|pug|md|mdx|yaml|yml|toml|json|xml|sh|bash|zsh|tf|hcl|lua|r|jl|ex|exs|erl|hs|clj|dart|c|cpp|h|hpp|cs|fs|ml|nim|zig|v)$'

# Directories to exclude
EXCLUDE_ARGS=(
  -not -path "*/node_modules/*"
  -not -path "*/.git/*"
  -not -path "*/dist/*"
  -not -path "*/build/*"
  -not -path "*/.next/*"
  -not -path "*/.nuxt/*"
  -not -path "*/.svelte-kit/*"
  -not -path "*/__pycache__/*"
  -not -path "*/.planning/*"
  -not -path "*/.gsd/*"
  -not -path "*/coverage/*"
  -not -path "*/.vercel/*"
  -not -path "*/.turbo/*"
  -not -path "*/vendor/*"
  -not -path "*/target/*"
  -not -path "*/.cache/*"
  -not -path "*/playwright-report/*"
  -not -path "*/test-results/*"
  -not -path "*/.terraform/*"
  -not -path "*/venv/*"
  -not -path "*/.venv/*"
  -not -path "*/env/*"
)

# Files to exclude
EXCLUDE_FILES=(
  -not -name "*.lock"
  -not -name "package-lock.json"
  -not -name "yarn.lock"
  -not -name "pnpm-lock.yaml"
  -not -name "*.map"
  -not -name "*.min.js"
  -not -name "*.min.css"
  -not -name "*.chunk.js"
  -not -name "*.bundle.js"
)

find . -type f "${EXCLUDE_ARGS[@]}" "${EXCLUDE_FILES[@]}" 2>/dev/null \
  | grep -iE "$SRC_PATTERN" \
  | while IFS= read -r file; do
    lines=$(wc -l < "$file" 2>/dev/null || echo "0")
    lines=$(echo "$lines" | tr -d ' ')
    printf "%s\t%s\n" "$lines" "$file"
  done | sort -t$'\t' -k1 -rn > "$INV_DIR/all_files.tsv"

TOTAL_FILES=$(wc -l < "$INV_DIR/all_files.tsv" | tr -d ' ')
TOTAL_LOC=$(awk -F'\t' '{sum+=$1} END {print sum+0}' "$INV_DIR/all_files.tsv")
echo "Total: $TOTAL_FILES files, $TOTAL_LOC lines of code"

# ─── Directory Summary ─────────────────────────────────────────────
echo "Mapping directories..."
awk -F'\t' '{
  n = split($2, parts, "/")
  if (n >= 4) dir = parts[2] "/" parts[3] "/" parts[4]
  else if (n >= 3) dir = parts[2] "/" parts[3]
  else if (n >= 2) dir = parts[2]
  else dir = "root"
  files[dir]++
  loc[dir] += $1
} END {
  for (dir in files) printf "%d\t%d\t%s\n", loc[dir], files[dir], dir
}' "$INV_DIR/all_files.tsv" | sort -t$'\t' -k1 -rn > "$INV_DIR/directories.tsv"

# ─── Domain Detection ──────────────────────────────────────────────
echo "Detecting domains..."
awk -F'\t' '{
  file = $2
  domain = "uncategorized"
  n = split(file, p, "/")

  # Match common patterns: features/, modules/, domains/, apps/
  for (i = 1; i <= n; i++) {
    if (p[i] ~ /^(features|modules|domains|apps|packages)$/ && i < n) {
      domain = p[i+1]; break
    }
  }

  # If no feature dir match, try other patterns
  if (domain == "uncategorized") {
    for (i = 1; i <= n; i++) {
      if (p[i] == "pages" && i < n) {
        # Pages: use subdirectory or filename without extension
        if (i + 2 <= n) { domain = "page:" p[i+1] }
        else { sub(/\.[^.]+$/, "", p[i+1]); domain = "page:" p[i+1] }
        break
      }
      if (p[i] == "components" && i + 1 < n) { domain = "component:" p[i+1]; break }
      if (p[i] == "hooks" && i + 1 < n) { domain = "hook:" p[i+1]; break }
      if (p[i] == "api" && i < n) { domain = "api:" p[i+1]; break }
      if (p[i] == "functions" && i < n) { domain = "function:" p[i+1]; break }
      if (p[i] == "routes" && i < n) { domain = "route:" p[i+1]; break }
      if (p[i] == "app" && i + 1 < n && p[i+1] ~ /^\(|api/) { domain = "app:" p[i+1]; break }
    }
  }

  # Fallback categories
  if (domain == "uncategorized") {
    for (i = 1; i <= n; i++) {
      if (p[i] == "services") { domain = "services"; break }
      if (p[i] == "lib") { domain = "lib"; break }
      if (p[i] == "utils") { domain = "utils"; break }
      if (p[i] == "config") { domain = "config"; break }
      if (p[i] ~ /^(test|tests|__tests__|spec|specs|e2e|cypress)$/) { domain = "tests"; break }
      if (p[i] == "migrations") { domain = "migrations"; break }
      if (p[i] == "types") { domain = "types"; break }
      if (p[i] == "contexts") { domain = "contexts"; break }
      if (p[i] == "styles") { domain = "styles"; break }
      if (p[i] == "public") { domain = "public"; break }
      if (p[i] == "scripts") { domain = "scripts"; break }
      if (p[i] == "supabase") { domain = "supabase"; break }
    }
  }

  printf "%s\t%d\t%s\n", domain, $1, $2
}' "$INV_DIR/all_files.tsv" | sort > "$INV_DIR/domains.tsv"

# Domain summary
awk -F'\t' '{
  files[$1]++
  loc[$1] += $2
} END {
  for (d in files) printf "%d\t%d\t%s\n", loc[d], files[d], d
}' "$INV_DIR/domains.tsv" | sort -t$'\t' -k1 -rn > "$INV_DIR/domain_summary.tsv"

# Grep-compatible exclude dirs
GREP_EXCLUDES="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=.nuxt --exclude-dir=.svelte-kit --exclude-dir=__pycache__ --exclude-dir=.planning --exclude-dir=coverage --exclude-dir=.vercel --exclude-dir=.turbo --exclude-dir=vendor --exclude-dir=target --exclude-dir=.cache --exclude-dir=playwright-report --exclude-dir=test-results --exclude-dir=.terraform --exclude-dir=venv --exclude-dir=.venv"

# ─── External URLs / API Calls ─────────────────────────────────────
echo "Scanning for external integrations..."
grep -rn "https\?://" . \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --include="*.py" --include="*.go" --include="*.rs" --include="*.rb" \
  --include="*.java" --include="*.php" \
  $GREP_EXCLUDES 2>/dev/null \
  | grep -v "//.*http" \
  > "$INV_DIR/external_urls.txt" 2>/dev/null || true

# ─── Environment Variables ─────────────────────────────────────────
echo "Finding environment variables..."
grep -rn 'VITE_\|NEXT_PUBLIC_\|REACT_APP_\|NUXT_\|process\.env\.\|import\.meta\.env\.\|os\.environ\|os\.getenv\|env::var\|Deno\.env' . \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --include="*.py" --include="*.go" --include="*.rs" --include="*.env*" \
  $GREP_EXCLUDES 2>/dev/null \
  > "$INV_DIR/env_vars.txt" 2>/dev/null || true

# ─── AI/ML Imports ─────────────────────────────────────────────────
echo "Detecting AI/ML usage..."
grep -rln 'openai\|anthropic\|@google/generative\|langchain\|huggingface\|deepgram\|whisper\|tensorflow\|torch\|sklearn\|transformers\|@ai-sdk\|replicate\|cohere\|mistral' . \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --include="*.py" --include="*.go" \
  $GREP_EXCLUDES 2>/dev/null \
  > "$INV_DIR/ai_files.txt" 2>/dev/null || true

# ─── Database Files ────────────────────────────────────────────────
echo "Finding database schemas..."
find . \( -name "*.sql" -o -name "*.prisma" -o -name "schema.*" -o -name "*.migration.*" -o -name "drizzle.config.*" \) \
  "${EXCLUDE_ARGS[@]}" 2>/dev/null \
  > "$INV_DIR/db_files.txt" 2>/dev/null || true

# ─── Config Files ──────────────────────────────────────────────────
echo "Finding config files..."
find . -maxdepth 3 -type f \( \
  -name "*.config.*" -o -name ".env*" -o -name "tsconfig*" -o \
  -name "vite.config.*" -o -name "next.config.*" -o -name "nuxt.config.*" -o \
  -name "tailwind.config.*" -o -name "postcss.config.*" -o \
  -name "playwright.config.*" -o -name "vitest.config.*" -o \
  -name "jest.config.*" -o -name "webpack.config.*" -o \
  -name "docker-compose*" -o -name "Dockerfile*" -o \
  -name "vercel.json" -o -name "vercel.ts" -o \
  -name ".eslintrc*" -o -name "eslint.config.*" -o \
  -name ".prettierrc*" -o -name "prettier.config.*" -o \
  -name "Makefile" -o -name "Procfile" -o -name "fly.toml" \
  \) "${EXCLUDE_ARGS[@]}" 2>/dev/null \
  > "$INV_DIR/config_files.txt" 2>/dev/null || true

# ─── Large Files ───────────────────────────────────────────────────
echo "Identifying large files..."
awk -F'\t' '$1 > 500 { print }' "$INV_DIR/all_files.tsv" > "$INV_DIR/large_files.tsv"

# ─── Summary ───────────────────────────────────────────────────────
DOMAIN_COUNT=$(wc -l < "$INV_DIR/domain_summary.tsv" | tr -d ' ')
LARGE_COUNT=$(wc -l < "$INV_DIR/large_files.tsv" | tr -d ' ')
URL_COUNT=$(wc -l < "$INV_DIR/external_urls.txt" | tr -d ' ')
AI_COUNT=$(wc -l < "$INV_DIR/ai_files.txt" | tr -d ' ')
DB_COUNT=$(wc -l < "$INV_DIR/db_files.txt" | tr -d ' ')
CONFIG_COUNT=$(wc -l < "$INV_DIR/config_files.txt" | tr -d ' ')
STACK_INFO=$(tr '\n' ',' < "$INV_DIR/stack.txt" | sed 's/,$//')

cat > "$INV_DIR/summary.txt" << EOF
total_files=$TOTAL_FILES
total_loc=$TOTAL_LOC
domains=$DOMAIN_COUNT
large_files=$LARGE_COUNT
external_urls=$URL_COUNT
ai_files=$AI_COUNT
db_files=$DB_COUNT
config_files=$CONFIG_COUNT
stack=$STACK_INFO
EOF

echo ""
echo "=== INVENTORY COMPLETE ==="
echo "Total files: $TOTAL_FILES"
echo "Total LOC:   $TOTAL_LOC"
echo "Stack:       $STACK_INFO"
echo "Domains:     $DOMAIN_COUNT"
echo "Large (>500 LOC): $LARGE_COUNT"
echo "External URLs:    $URL_COUNT"
echo "AI/ML files:      $AI_COUNT"
echo "DB files:         $DB_COUNT"
echo "Config files:     $CONFIG_COUNT"
echo ""
echo "Output: $INV_DIR/"
