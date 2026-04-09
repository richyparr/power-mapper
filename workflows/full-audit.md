# Workflow: Full Codebase Audit

<required_reading>
**Read these files NOW before proceeding:**
1. `references/agent-prompts.md` — Prompt templates for all agent tiers
2. `references/scaling-strategy.md` — Token math, chunk sizing, wave execution
</required_reading>

<process>

## Step 1: Initialize

```bash
rm -rf .planning/audit 2>/dev/null
mkdir -p .planning/audit/{inventory,files,domains,themes}
```

Initialize the state file for resume tracking:
```bash
cat > .planning/audit/STATE.json << 'EOF'
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_hash": "$(git rev-parse HEAD)",
  "current_tier": 1,
  "current_wave": 0,
  "completed_chunks": [],
  "completed_domains": [],
  "completed_themes": [],
  "status": "in_progress"
}
EOF
# Replace placeholders with actual values
sed -i '' "s/\$(date -u +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" .planning/audit/STATE.json
sed -i '' "s/\$(git rev-parse HEAD)/$(git rev-parse HEAD)/" .planning/audit/STATE.json
```

**If resuming an interrupted audit:** Read `.planning/audit/STATE.json` to determine where to continue. Skip to the `current_tier` and `current_wave` recorded there. Check which chunks/domains/themes are already in `completed_*` arrays and only spawn agents for the missing ones.

## Step 2: Run Tier 1 Inventory

Execute the inventory script. This is the accountability foundation — every file gets counted by bash, not by an LLM.

```bash
bash ~/.claude/skills/power-mapper/scripts/inventory.sh
```

Read the summary output:
```bash
cat .planning/audit/inventory/summary.txt
```

Present the inventory results to the user:
```
Inventory complete.

- Total files: {N}
- Total LOC: {N}
- Detected stack: {stack}
- Feature domains: {N}
- Large files (>500 LOC): {N}
- External integrations: {N}
- AI/ML files: {N}

Proceeding to chunk planning...
```

## Step 3: Create Chunk Assignments

Read the domain summary to understand the codebase shape:
```bash
cat .planning/audit/inventory/domain_summary.tsv
```

**Chunking rules:**
- Target: ~15,000 lines per chunk (≈60K tokens of source code)
- Group files by domain (files in same feature stay together)
- If a domain exceeds 15,000 lines, split it into sub-chunks
- Files not assigned to any domain go into "infrastructure" or "misc" chunks
- Each chunk must have a clear label (e.g., "billing", "messaging-part1", "config")

**Create chunk assignment files** — one file per chunk listing all files for that chunk:

```bash
# Example: create chunk assignment for the "billing" domain
grep "^billing" .planning/audit/inventory/domains.tsv | awk -F'\t' '{print $3}' > .planning/audit/chunk-assignments/billing.txt
```

Use awk/grep to split domains.tsv into chunk assignment files:

```bash
mkdir -p .planning/audit/chunk-assignments

# Group files by domain, respecting chunk size limits
awk -F'\t' '{
  domain = $1
  loc = $2
  file = $3
  # Write each domain to its own file
  print file >> ".planning/audit/chunk-assignments/" domain ".txt"
}' .planning/audit/inventory/domains.tsv
```

After creating assignments, check sizes:
```bash
for f in .planning/audit/chunk-assignments/*.txt; do
  name=$(basename "$f" .txt)
  files=$(wc -l < "$f" | tr -d ' ')
  loc=$(while IFS= read -r path; do wc -l < "$path" 2>/dev/null; done < "$f" | awk '{s+=$1} END {print s+0}')
  echo "$loc LOC | $files files | $name"
done | sort -rn
```

**Split oversized chunks:** If any chunk exceeds 20,000 LOC, split it:
```bash
# Split large chunk into parts of ~15000 lines each
split -l $(($(wc -l < chunk.txt) / 2)) chunk.txt chunk-part-
```

**Merge tiny chunks:** If any chunk has <500 LOC, merge it with a related or "misc" chunk.

Count total chunks and present execution plan:
```
Chunk plan ready.

- Total chunks: {N}
- Tier 2 agents needed: {N} (file analysis)
- Tier 3 agents needed: {N} (domain synthesis)  
- Tier 4 agents: 5 (thematic cross-cuts)
- Tier 5 agent: 1 (executive synthesis)
- Total agents: {N}
- Estimated time: ~{N} minutes (waves of 4)

Proceed?
```

Wait for user confirmation before spawning agents.

## Step 4: Execute Tier 2 — File-Level Analysis

For each chunk, spawn an Agent. Read the prompt template from `references/agent-prompts.md` (TIER 2 section).

**Wave execution:** Launch agents in waves. Default wave size: 4 concurrent agents.

```
For each wave:
  1. Spawn up to 4 agents with run_in_background=true
  2. Each agent gets:
     - Its chunk assignment file path
     - The output path: .planning/audit/files/chunk-{label}.md
     - The Tier 2 prompt template (from references/agent-prompts.md)
  3. Wait for all agents in this wave to complete
  4. Verify each agent wrote its output file
  5. If any agent failed, note it for retry
  6. Move to next wave
```

**Agent spawn pattern:**

```
Agent(
  description="Audit chunk: {label}",
  model="sonnet",
  run_in_background=true,
  prompt="[Tier 2 prompt from references/agent-prompts.md]
  
  YOUR ASSIGNMENT: Read the files listed in .planning/audit/chunk-assignments/{label}.txt
  Write your analysis to: .planning/audit/files/chunk-{label}.md
  
  [Include full Tier 2 prompt template here]"
)
```

**IMPORTANT:** Each agent prompt MUST include:
- The full file list (or path to the assignment file)
- The exact output path
- The output format template
- Instructions to read EVERY file, not just the interesting ones

After all Tier 2 waves complete, verify:
```bash
echo "=== Tier 2 Completeness ===" 
total_chunks=$(ls .planning/audit/chunk-assignments/*.txt | wc -l | tr -d ' ')
completed=$(ls .planning/audit/files/chunk-*.md 2>/dev/null | wc -l | tr -d ' ')
echo "Chunks: $total_chunks | Completed: $completed"
for f in .planning/audit/chunk-assignments/*.txt; do
  label=$(basename "$f" .txt)
  if [[ ! -f ".planning/audit/files/chunk-${label}.md" ]]; then
    echo "MISSING: chunk-${label}"
  fi
done
```

**Retry failed chunks:** Re-spawn agents for any missing chunk outputs.

**After each wave completes**, update state:
```bash
# Update STATE.json with completed chunks (run after each wave)
completed=$(ls .planning/audit/files/chunk-*.md 2>/dev/null | sed 's/.*chunk-//' | sed 's/\.md//' | paste -sd',' -)
python3 -c "
import json
with open('.planning/audit/STATE.json','r') as f: s=json.load(f)
s['current_tier']=2
s['completed_chunks']='$completed'.split(',')
with open('.planning/audit/STATE.json','w') as f: json.dump(s,f,indent=2)
"
```

### Step 4b: Validate Tier 2 Quality

Shallow analyses waste downstream tokens. Check that each chunk output has sufficient depth:

```bash
echo "=== Tier 2 Quality Check ==="
for f in .planning/audit/files/chunk-*.md; do
  label=$(basename "$f" .md)
  lines=$(wc -l < "$f" | tr -d ' ')
  files_expected=$(wc -l < ".planning/audit/chunk-assignments/${label#chunk-}.txt" 2>/dev/null | tr -d ' ')
  files_analyzed=$(grep -c "^## " "$f" 2>/dev/null || echo 0)
  
  # Flag if analysis is suspiciously thin
  if [[ $lines -lt 20 ]]; then
    echo "SHALLOW: $label — only $lines lines (expected analysis of $files_expected files)"
  elif [[ $files_analyzed -lt $files_expected ]]; then
    echo "INCOMPLETE: $label — analyzed $files_analyzed/$files_expected files"
  else
    echo "OK: $label — $lines lines, $files_analyzed/$files_expected files"
  fi
done
```

**Re-run shallow or incomplete chunks.** If a chunk has <20 lines of output or analyzed fewer files than assigned, re-spawn that agent. This catches agents that silently skipped files or produced one-line summaries.

## Step 5: Execute Tier 3 — Domain Synthesis

**Target: max 12 Tier 3 agents.** Each agent spawn costs ~30-50K tokens in system overhead regardless of task complexity. Reducing agent count is the single most effective way to control token usage.

### Step 5a: Identify domains and their sizes

```bash
# List domains with LOC totals
awk -F'\t' '{
  domain = $1
  gsub(/^(page|component|hook|function|api):/, "", domain)
  gsub(/^[A-Z]/, tolower(substr(domain,1,1)), domain)
  loc = $2
  domains[domain] += loc
} END {
  for (d in domains) print domains[d] "\t" d
}' .planning/audit/inventory/domain_summary.tsv | sort -rn
```

### Step 5b: Merge small domains to stay under 12 agents

**Rules (apply in order):**

1. Domains with **>3,000 LOC** keep their own agent (these are substantial features)
2. Domains with **≤3,000 LOC** must be merged into a related larger domain or grouped together
3. **Total Tier 3 agents must not exceed 12**

**Merge affinity guide** — when merging small domains, prefer these groupings:
- Time/attendance/leave/scheduling → `time-attendance`
- Announcements/approvals/support → `comms-workflow`
- Training/knowledge/filehub → `knowledge`
- Public pages/legal/misc → `public-misc`
- Config/scripts/lib/core → `infrastructure`
- Any remaining small domains (<1,000 LOC each) → `misc`

**Create a domain mapping file** that maps each inventory domain to its Tier 3 synthesis domain:

```bash
# After deciding on groupings, create the mapping
# Format: original_domain<TAB>tier3_domain
cat > .planning/audit/domain-mapping.tsv << 'MAPPING'
billing	billing
recruitment	recruitment
messaging	messaging
leave	time-attendance
attendance	time-attendance
time-tracking	time-attendance
...
MAPPING
```

Adjust the mapping based on the actual domains and LOC from Step 5a. The goal is ≤12 Tier 3 domains.

### Step 5c: Create Tier 3 assignment lists

For each Tier 3 domain, list which Tier 2 chunk files it should read:

```bash
# For each tier3 domain, find which chunk analyses contain relevant files
for domain in $(awk -F'\t' '{print $2}' .planning/audit/domain-mapping.tsv | sort -u); do
  echo "=== $domain ==="
  # Get all original domains that map to this tier3 domain
  originals=$(awk -F'\t' -v d="$domain" '$2==d {print $1}' .planning/audit/domain-mapping.tsv)
  # Find chunk files that contain analysis for these domains
  for orig in $originals; do
    grep -l "$orig" .planning/audit/files/chunk-*.md 2>/dev/null
  done | sort -u
done
```

Present the merged domain plan to the user:
```
Tier 3 domain plan:

- {domain1}: {N} LOC, reads chunks: {list} (merged from: {originals})
- {domain2}: {N} LOC, reads chunks: {list}
...

Total Tier 3 agents: {N} (target: ≤12)

Proceed?
```

### Step 5d: Spawn Tier 3 agents

For each merged domain, spawn a Tier 3 agent. Read the prompt template from `references/agent-prompts.md` (TIER 3 section).

**Agent spawn pattern:**

```
Agent(
  description="Synthesize domain: {domain}",
  model="sonnet",
  run_in_background=true,
  prompt="[Tier 3 prompt from references/agent-prompts.md]
  
  DOMAIN: {domain}
  This domain covers these feature areas: {list of original domains merged into this one}
  READ THESE TIER 2 ANALYSES: [list of chunk-*.md files relevant to this domain]
  WRITE TO: .planning/audit/domains/{domain}.md"
)
```

Run in waves of 4. After completion, verify all domain files exist.

## Step 6: Execute Tier 4 — Thematic Cross-Cuts

Spawn 5 thematic agents IN PARALLEL (single wave). Read prompts from `references/agent-prompts.md` (TIER 4 section).

**Agents:**
1. **auth-flow** — Traces authentication from login through every protected route
2. **api-surface** — Maps every public/internal API endpoint with auth and rate limits
3. **integrations** — Audits every external service: how used, error handling, completeness
4. **automation** — Maps every cron, webhook, queue, scheduled job, background task
5. **dead-code** — Finds exports never imported, routes never linked, orphan files

Each reads the Tier 3 domain summaries (NOT source code) plus the inventory files.

```
Agent(
  description="Thematic: {theme}",
  model="sonnet",
  run_in_background=true,
  prompt="[Tier 4 prompt for {theme} from references/agent-prompts.md]
  
  READ: All files in .planning/audit/domains/
  READ: .planning/audit/inventory/external_urls.txt (for integrations theme)
  READ: .planning/audit/inventory/ai_files.txt (for integrations theme)
  WRITE TO: .planning/audit/themes/{theme}.md"
)
```

Wait for all 5 to complete.

## Step 7: Execute Tier 5 — Executive Synthesis

Spawn a SINGLE opus-level agent that reads all Tier 3 domain summaries and Tier 4 thematic reports.

**Token budget check:** Before spawning, verify total input size:
```bash
wc -l .planning/audit/domains/*.md .planning/audit/themes/*.md 2>/dev/null | tail -1
```

If total exceeds 4000 lines (~16K tokens), the synthesis agent can handle it — domain summaries + thematic reports compress well. If it exceeds 10,000 lines, consider splitting into two synthesis passes.

```
Agent(
  description="Executive synthesis",
  model="opus",
  prompt="[Tier 5 prompt from references/agent-prompts.md]
  
  READ: All .planning/audit/domains/*.md files
  READ: All .planning/audit/themes/*.md files
  READ: .planning/audit/inventory/summary.txt
  READ: .planning/audit/inventory/large_files.tsv
  
  WRITE:
  - .planning/audit/FEATURES.md — Complete product capability map by user role
  - .planning/audit/GAPS.md — Stubs, TODOs, incomplete features, dead routes
  - .planning/audit/AUDIT-SUMMARY.md — Health score, stats, key findings"
)
```

Wait for completion. Verify all 3 output files exist and are non-empty.

## Step 8: Run Tier 6 — Coverage Verification

```bash
bash ~/.claude/skills/power-mapper/scripts/verify-coverage.sh
```

Read and present results:
```bash
cat .planning/audit/COVERAGE.txt
```

**If coverage < 100%:**
```
Coverage: {N}%
{M} files were not analyzed. 

These files were in the inventory but not mentioned in any Tier 2 output:
[list from missed_files.txt]

Re-analyzing missed files...
```

Create a new chunk assignment with the missed files and re-run Tier 2 for that chunk. Then re-run Tiers 3-5 for affected domains.

**If coverage = 100%:**
```
Coverage: 100% — Every file in the inventory was analyzed.
```

## Step 9: Scan for Secrets

```bash
grep -rE '(sk-[a-zA-Z0-9]{20,}|sk_live_|sk_test_|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|xox[baprs]-|-----BEGIN.*PRIVATE KEY)' .planning/audit/ 2>/dev/null && echo "SECRETS_FOUND=true" || echo "SECRETS_FOUND=false"
```

If secrets found, warn user and pause before committing.

## Step 10: Generate Derivative Outputs

The audit data is expensive to produce. Extract maximum value by generating files that other tools consume automatically.

### 10a: CODEBASE-CONTEXT.md (for GSD + Claude Code)

Generate a condensed context file that GSD planning agents and Claude Code (`claude init`) naturally discover. This single file makes every future session smarter about the project.

Spawn a single agent:

```
Agent(
  description="Generate codebase context",
  model="sonnet",
  prompt="Read the following audit outputs and produce a single condensed context file.

  READ:
  - .planning/audit/AUDIT-SUMMARY.md
  - .planning/audit/FEATURES.md
  - .planning/audit/GAPS.md
  - .planning/audit/inventory/summary.txt
  - .planning/audit/inventory/stack.txt

  WRITE TO: .planning/CODEBASE-CONTEXT.md

  FORMAT — keep this under 200 lines total:

  # Codebase Context
  <!-- Auto-generated by power-mapper audit. Do not edit manually. -->
  <!-- Last updated: {date} -->

  ## Project Overview
  One paragraph: what this product does, who uses it, what stack it runs on.

  ## Architecture
  3-5 sentences: how the codebase is structured, key patterns, runtime topology.

  ## Feature Domains
  Table with columns: Domain | Status (complete/partial/stub) | Key Capabilities | LOC
  One row per domain from the audit.

  ## User Roles & Permissions
  For each role: one line summary of what they can do.

  ## External Integrations
  Table: Service | Purpose | Auth Method | Status

  ## Known Gaps
  Bulleted list of the top 10-15 most important gaps from GAPS.md.
  Prioritize: broken features > stubs > missing features > tech debt.

  ## Key Metrics
  - Total files / LOC
  - Feature domains: N
  - External integrations: N
  - API endpoints: N
  - Health score: N/10
  - Coverage: N%

  IMPORTANT: This file will be read by AI agents in future sessions to understand the project.
  Be factual, specific, and concise. No filler. Every line should convey information."
)
```

### 10b: Security Baseline (for security-hardening skill)

Extract security-relevant findings into a standalone file that the security-hardening skill can consume:

```bash
# Combine auth-flow and api-surface themes into a security baseline
{
  echo "# Security Baseline"
  echo "<!-- Auto-generated by power-mapper audit -->"
  echo ""
  echo "## Auth Flow Summary"
  echo ""
  sed -n '/^#/,$p' .planning/audit/themes/auth-flow.md 2>/dev/null | tail -n +2
  echo ""
  echo "## API Surface Summary"
  echo ""
  sed -n '/^#/,$p' .planning/audit/themes/api-surface.md 2>/dev/null | tail -n +2
  echo ""
  echo "## Unprotected Routes"
  echo ""
  grep -i "unprotected\|no auth\|public.*should\|missing.*auth" .planning/audit/themes/auth-flow.md 2>/dev/null || echo "None identified"
  echo ""
  echo "## Endpoints Without Rate Limiting"
  echo ""
  grep -i "no rate\|missing rate\|rate limit" .planning/audit/themes/api-surface.md 2>/dev/null || echo "None identified"
} > .planning/audit/SECURITY-BASELINE.md
```

### 10c: Test Coverage Map (for E2E testing)

Extract testable features and their status for the E2E testing skill:

```bash
{
  echo "# Test Coverage Map"
  echo "<!-- Auto-generated by power-mapper audit -->"
  echo ""
  echo "## Features Requiring E2E Tests"
  echo ""
  echo "Derived from FEATURES.md — every user-facing capability listed by role."
  echo ""
  # Extract user-facing actions from FEATURES.md
  grep -E "^- .+—" .planning/audit/FEATURES.md 2>/dev/null || echo "See FEATURES.md for full list"
  echo ""
  echo "## Incomplete Features (skip for now)"
  echo ""
  grep -E "stub|disabled|partial" .planning/audit/GAPS.md 2>/dev/null | head -20 || echo "See GAPS.md"
  echo ""
  echo "## Critical User Flows"
  echo ""
  echo "Derive from the feature map above. Prioritize flows that cross multiple domains."
} > .planning/audit/TEST-MAP.md
```

### 10d: Dead Code Cleanup List

Extract actionable cleanup targets:

```bash
{
  echo "# Dead Code Cleanup"
  echo "<!-- Auto-generated by power-mapper audit -->"
  echo ""
  cat .planning/audit/themes/dead-code.md 2>/dev/null || echo "No dead code analysis available"
} > .planning/audit/CLEANUP.md
```

### 10e: Dependency Graph (for GSD phase ordering + impact analysis)

Generate a domain-level dependency graph from the "Integration Points → Internal" sections of each domain summary. This feeds `/gsd-analyze-dependencies` and answers "what breaks if I change X?"

```
Agent(
  description="Generate dependency graph",
  model="sonnet",
  prompt="Read all domain summaries and extract the inter-domain dependency graph.

  READ: All files in .planning/audit/domains/*.md

  WRITE TO: .planning/audit/DEPENDENCIES.md

  FORMAT:

  # Domain Dependency Graph
  <!-- Auto-generated by power-mapper audit -->

  ## Dependency Matrix

  Table with domains as rows. Columns: Domain | Depends On | Depended On By | External Services
  Sort by 'Depended On By' count descending (most-depended-on domains first).

  ## Mermaid Diagram

  Generate a Mermaid flowchart showing domain-to-domain dependencies:
  - Nodes = domains
  - Edges = dependency direction (A depends on B = A --> B)
  - Color high-dependency nodes (depended on by 3+ domains) differently
  - Keep it readable — group tightly coupled domains

  ## Impact Analysis

  For each domain, list:
  ### {domain}
  **If this domain changes, these domains are affected:**
  - {list of domains that depend on it, with what they depend on}
  
  **This domain depends on:**
  - {list of domains it imports from, with what it uses}

  ## Coupling Risks
  
  Flag any domains that are:
  - Highly coupled (depends on 5+ other domains)
  - Central bottlenecks (depended on by 5+ domains)
  - Circular dependencies (A→B→A)
  
  These are refactoring priorities and high-risk change areas."
)
```

### 10f: Finalize State

```bash
python3 -c "
import json
with open('.planning/audit/STATE.json','r') as f: s=json.load(f)
s['status']='complete'
s['completed_at']='$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('.planning/audit/STATE.json','w') as f: json.dump(s,f,indent=2)
"
```

## Step 11: Register with CLAUDE.md

Add a pointer to the project's CLAUDE.md so Claude Code and GSD discover the audit automatically. Only add if not already present:

```bash
CLAUDE_MD="./CLAUDE.md"

# Check if pointer already exists
if ! grep -q "CODEBASE-CONTEXT.md" "$CLAUDE_MD" 2>/dev/null; then
  # Append the pointer section
  cat >> "$CLAUDE_MD" << 'EOF'

## Codebase Context
A power-mapper audit has been completed with 100% file coverage. Before exploring the codebase or running `gsd-map-codebase`, read these files first:
- `.planning/CODEBASE-CONTEXT.md` — Project overview, architecture, feature domains, integrations, gaps
- `.planning/audit/FEATURES.md` — Complete product capability map by user role
- `.planning/audit/GAPS.md` — Missing features, stubs, incomplete work
- `.planning/audit/DEPENDENCIES.md` — Domain dependency graph and impact analysis
Do NOT run `gsd-map-codebase` — the power-mapper audit is more comprehensive and replaces it.
EOF
  echo "Added codebase context pointer to CLAUDE.md"
else
  echo "CLAUDE.md already references CODEBASE-CONTEXT.md — skipping"
fi
```

## Step 12: Commit Results

```bash
git add .planning/audit/ .planning/CODEBASE-CONTEXT.md CLAUDE.md
git commit -m "docs: power-mapper full codebase audit

Tier 1: $(cat .planning/audit/inventory/summary.txt | head -2 | tr '\n' ', ')
Tier 2: $(ls .planning/audit/files/ | wc -l | tr -d ' ') chunk analyses
Tier 3: $(ls .planning/audit/domains/ | wc -l | tr -d ' ') domain summaries
Coverage: $(grep coverage_percent .planning/audit/COVERAGE.txt | cut -d= -f2)%

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

## Step 13: Present Results

```bash
wc -l .planning/audit/FEATURES.md .planning/audit/GAPS.md .planning/audit/AUDIT-SUMMARY.md .planning/CODEBASE-CONTEXT.md
```

```
=== Power Mapper: Audit Complete ===

Inventory: {N} files, {N} LOC across {N} domains
Analysis: {N} Tier 2 chunks → {N} domain summaries → {N} thematic reports
Coverage: {coverage}%

Deliverables:

  Core Analysis:
  - FEATURES.md ({N} lines) — Complete product capability map by user role
  - GAPS.md ({N} lines) — Missing features, stubs, incomplete work
  - AUDIT-SUMMARY.md ({N} lines) — Architecture, health score, key findings
  - {N} domain summaries in domains/
  - 5 thematic reports in themes/

  Derivative Outputs:
  - CODEBASE-CONTEXT.md — Condensed context for GSD/Claude Code (start here)
  - DEPENDENCIES.md — Domain dependency graph with impact analysis
  - SECURITY-BASELINE.md — Auth flows + API surface for security hardening
  - TEST-MAP.md — Testable features mapped for E2E planning
  - CLEANUP.md — Dead code removal targets

Quick access:
  cat .planning/CODEBASE-CONTEXT.md          # Start here — project overview
  cat .planning/audit/FEATURES.md             # Full feature map by role
  cat .planning/audit/GAPS.md                 # What's missing or broken
  cat .planning/audit/AUDIT-SUMMARY.md        # Health score and architecture
  cat .planning/audit/DEPENDENCIES.md         # What breaks if I change X?
  cat .planning/audit/SECURITY-BASELINE.md    # Security audit starting point
  cat .planning/audit/TEST-MAP.md             # E2E test planning
  cat .planning/audit/CLEANUP.md              # Dead code to remove
```

</process>

<success_criteria>
This workflow is complete when:
- [ ] Tier 1 inventory script ran successfully
- [ ] All chunk assignments created (every file assigned to exactly one chunk)
- [ ] All Tier 2 agents completed (one per chunk)
- [ ] Tier 2 quality validation passed (no shallow/incomplete chunks)
- [ ] All Tier 3 domain agents completed (max 12 merged domains)
- [ ] All 5 Tier 4 thematic agents completed
- [ ] Tier 5 synthesis produced FEATURES.md, GAPS.md, AUDIT-SUMMARY.md
- [ ] Tier 6 verification shows 100% coverage (or re-analysis ran for missed files)
- [ ] No secrets leaked in output files
- [ ] Derivative outputs generated (CODEBASE-CONTEXT.md, DEPENDENCIES.md, SECURITY-BASELINE.md, TEST-MAP.md, CLEANUP.md)
- [ ] STATE.json finalized with status: complete
- [ ] CLAUDE.md pointer registered
- [ ] Results committed to git
- [ ] User presented with summary and access paths
</success_criteria>
