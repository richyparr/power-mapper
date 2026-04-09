# Workflow: Incremental Audit

<required_reading>
**Read these files NOW:**
1. `references/agent-prompts.md`
2. `references/scaling-strategy.md`
</required_reading>

<process>

## Step 1: Validate Previous Audit

Check that a complete previous audit exists:

```bash
if [[ ! -f ".planning/audit/STATE.json" ]]; then
  echo "No STATE.json found. Checking for legacy audit..."
  if [[ -f ".planning/audit/inventory/all_files.tsv" ]]; then
    echo "Legacy audit found (no state tracking). Incremental mode available but resume data is limited."
  else
    echo "No previous audit found. Run a full audit first."
    exit 1
  fi
else
  STATUS=$(python3 -c "import json; print(json.load(open('.planning/audit/STATE.json'))['status'])")
  GIT_HASH=$(python3 -c "import json; print(json.load(open('.planning/audit/STATE.json'))['git_hash'])")
  echo "Previous audit: status=$STATUS, git_hash=$GIT_HASH"
  
  if [[ "$STATUS" != "complete" ]]; then
    echo "WARNING: Previous audit was not complete (status: $STATUS)."
    echo "Consider resuming the full audit instead: /power-mapper → Resume"
    echo "Continue with incremental anyway? (y/n)"
  fi
fi
```

## Step 2: Detect Changes Since Last Audit

```bash
# Use STATE.json git hash if available, otherwise find last audit commit
if [[ -n "$GIT_HASH" ]]; then
  LAST_AUDIT="$GIT_HASH"
else
  LAST_AUDIT=$(git log --oneline --all --grep="power-mapper" | head -1 | awk '{print $1}')
fi

echo "Comparing HEAD against: $LAST_AUDIT"

# Get changed, added, and deleted files
git diff --name-status "$LAST_AUDIT" HEAD > .planning/audit/incremental-changes.txt

MODIFIED=$(grep "^M" .planning/audit/incremental-changes.txt | wc -l | tr -d ' ')
ADDED=$(grep "^A" .planning/audit/incremental-changes.txt | wc -l | tr -d ' ')
DELETED=$(grep "^D" .planning/audit/incremental-changes.txt | wc -l | tr -d ' ')
RENAMED=$(grep "^R" .planning/audit/incremental-changes.txt | wc -l | tr -d ' ')

echo "Changes: $MODIFIED modified, $ADDED added, $DELETED deleted, $RENAMED renamed"
```

If no source files changed (only config, docs, etc.), report and exit:
```bash
# Filter to only source files (exclude .md, .txt, .json config, etc.)
grep -E '\.(tsx?|jsx?|css|scss|sql|py|rs|go)$' .planning/audit/incremental-changes.txt > .planning/audit/incremental-source-changes.txt
SOURCE_CHANGES=$(wc -l < .planning/audit/incremental-source-changes.txt | tr -d ' ')

if [[ "$SOURCE_CHANGES" -eq 0 ]]; then
  echo "No source files changed since last audit. Audit is up to date."
  exit 0
fi
echo "Source files changed: $SOURCE_CHANGES"
```

## Step 3: Re-run Inventory

```bash
# Back up previous inventory
cp .planning/audit/inventory/all_files.tsv .planning/audit/inventory/all_files.tsv.prev
cp .planning/audit/inventory/domain_summary.tsv .planning/audit/inventory/domain_summary.tsv.prev

# Re-run inventory
bash ~/.claude/skills/power-mapper/scripts/inventory.sh
```

## Step 4: Identify Affected Chunks and Domains

```bash
# Find which chunks contain changed files
> .planning/audit/affected_chunks.txt
while IFS=$'\t' read -r status file; do
  # Skip non-source files
  echo "$file" | grep -qE '\.(tsx?|jsx?|css|scss|sql|py|rs|go)$' || continue
  # Find which chunk assignment contains this file
  grep -rl "$file" .planning/audit/chunk-assignments/ 2>/dev/null >> .planning/audit/affected_chunks.txt
done < .planning/audit/incremental-changes.txt

sort -u .planning/audit/affected_chunks.txt -o .planning/audit/affected_chunks.txt
AFFECTED_CHUNKS=$(wc -l < .planning/audit/affected_chunks.txt | tr -d ' ')

# Map affected chunks to domains
> .planning/audit/affected_domains.txt
if [[ -f ".planning/audit/domain-mapping.tsv" ]]; then
  # Use the Tier 3 domain mapping from the full audit
  for chunk_file in $(cat .planning/audit/affected_chunks.txt); do
    label=$(basename "$chunk_file" .txt)
    grep "^${label}" .planning/audit/domain-mapping.tsv | awk -F'\t' '{print $2}' >> .planning/audit/affected_domains.txt
  done
else
  # Fall back to chunk label as domain name
  for chunk_file in $(cat .planning/audit/affected_chunks.txt); do
    basename "$chunk_file" .txt >> .planning/audit/affected_domains.txt
  done
fi
sort -u .planning/audit/affected_domains.txt -o .planning/audit/affected_domains.txt
AFFECTED_DOMAINS=$(wc -l < .planning/audit/affected_domains.txt | tr -d ' ')

echo "Affected: $AFFECTED_CHUNKS chunks, $AFFECTED_DOMAINS domains"
```

Present the incremental plan:
```
Incremental audit plan:

Source files changed: {N} ({M} modified, {A} added, {D} deleted)
Chunks to re-analyze: {N} (out of {total} total)
Domains to re-synthesize: {N} (out of {total} total)
Tier 4-5: always re-run (they read summaries, fast)

Token savings vs full audit: ~{percent}% (skipping {skipped} Tier 2 chunks)

Proceed?
```

Wait for user confirmation.

## Step 5: Handle New and Deleted Files

**New files** (added since last audit) need to be assigned to chunks:
```bash
# Files in current inventory but not in any chunk assignment
comm -23 \
  <(awk -F'\t' '{print $2}' .planning/audit/inventory/all_files.tsv | sort) \
  <(cat .planning/audit/chunk-assignments/*.txt 2>/dev/null | sort) \
  > .planning/audit/new_unassigned_files.txt

NEW_COUNT=$(wc -l < .planning/audit/new_unassigned_files.txt | tr -d ' ')
if [[ "$NEW_COUNT" -gt 0 ]]; then
  echo "$NEW_COUNT new files need chunk assignment"
  # Assign new files to existing chunks by domain, or create new chunk
fi
```

**Deleted files**: Remove from chunk assignments and note in analysis:
```bash
grep "^D" .planning/audit/incremental-changes.txt | awk '{print $2}' | while read -r file; do
  # Remove from chunk assignments
  sed -i '' "\|${file}|d" .planning/audit/chunk-assignments/*.txt 2>/dev/null
done
```

## Step 6: Re-run Affected Tier 2 Chunks

Back up previous chunk outputs, then re-run only affected chunks:

```bash
for chunk_file in $(cat .planning/audit/affected_chunks.txt); do
  label=$(basename "$chunk_file" .txt)
  mv ".planning/audit/files/chunk-${label}.md" ".planning/audit/files/chunk-${label}.md.prev" 2>/dev/null
done
```

Spawn Tier 2 agents for affected chunks only. Use same prompt from `references/agent-prompts.md`.

Run quality validation (Step 4b from full-audit) on re-analyzed chunks.

## Step 7: Re-run Affected Tier 3 Domains

Re-spawn Tier 3 agents only for domains in `.planning/audit/affected_domains.txt`.

Each agent reads ALL chunk files for its domain (not just the re-analyzed ones) to produce a complete domain summary.

## Step 8: Re-run Tier 4-5

Always re-run all 5 Tier 4 thematic agents and the Tier 5 executive synthesis — they read summaries and should reflect the current state of the entire codebase.

Follow full-audit Steps 6-7.

## Step 9: Generate Changes Report

This is unique to incremental audits — shows what changed between audits:

```
Agent(
  description="Generate changes report",
  model="sonnet",
  prompt="Compare the current audit outputs against the previous versions to produce a changes report.

  For each affected domain, read both current and previous (.prev) versions:
  - Current: .planning/audit/domains/{domain}.md
  - Previous: .planning/audit/domains/{domain}.md.prev (if exists)

  Also read:
  - .planning/audit/FEATURES.md (current)
  - .planning/audit/GAPS.md (current)
  - .planning/audit/incremental-changes.txt (git diff summary)

  WRITE TO: .planning/audit/CHANGES-SINCE-LAST-AUDIT.md

  FORMAT:

  # Changes Since Last Audit
  <!-- Previous audit: {git_hash} | Current: {HEAD} -->
  <!-- Date: {date} -->

  ## Summary
  - Files changed: {N} modified, {N} added, {N} deleted
  - Domains affected: {list}
  - Domains unchanged: {list}

  ## New Features Added
  Capabilities that exist now but didn't in the previous audit.

  ## Features Removed or Disabled
  Capabilities that were present before but are now gone.

  ## Gaps Closed
  Items from the previous GAPS.md that have been resolved.

  ## New Gaps Introduced
  New incomplete features, stubs, or technical debt since last audit.

  ## Health Trajectory
  Is the codebase getting healthier or accumulating debt? Brief assessment.

  ## Domain-by-Domain Changes
  For each affected domain, 2-3 sentences on what changed."
)
```

## Step 10: Regenerate Derivative Outputs

Re-run all derivative outputs from full-audit Step 10 (CODEBASE-CONTEXT.md, DEPENDENCIES.md, SECURITY-BASELINE.md, TEST-MAP.md, CLEANUP.md) so they reflect current state.

## Step 11: Update State

```bash
python3 -c "
import json
with open('.planning/audit/STATE.json','r') as f: s=json.load(f)
s['status']='complete'
s['git_hash']='$(git rev-parse HEAD)'
s['completed_at']='$(date -u +%Y-%m-%dT%H:%M:%SZ)'
s['last_incremental']={
  'files_changed': $SOURCE_CHANGES,
  'chunks_reanalyzed': $AFFECTED_CHUNKS,
  'domains_refreshed': $AFFECTED_DOMAINS
}
with open('.planning/audit/STATE.json','w') as f: json.dump(s,f,indent=2)
"
```

Verify coverage:
```bash
bash ~/.claude/skills/power-mapper/scripts/verify-coverage.sh
```

## Step 12: Register with CLAUDE.md

Ensure the project CLAUDE.md has a pointer to the audit (same as full-audit — idempotent):

```bash
CLAUDE_MD="./CLAUDE.md"
if ! grep -q "CODEBASE-CONTEXT.md" "$CLAUDE_MD" 2>/dev/null; then
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

## Step 13: Commit

```bash
git add .planning/audit/ .planning/CODEBASE-CONTEXT.md CLAUDE.md
git commit -m "docs: power-mapper incremental audit

$SOURCE_CHANGES files changed ($MODIFIED modified, $ADDED added, $DELETED deleted)
$AFFECTED_CHUNKS chunks re-analyzed, $AFFECTED_DOMAINS domains refreshed
Coverage: $(grep coverage_percent .planning/audit/COVERAGE.txt | cut -d= -f2)%

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

## Step 14: Present Results

```
=== Power Mapper: Incremental Audit Complete ===

Changes: {N} source files ({M} modified, {A} added, {D} deleted)
Re-analyzed: {N} chunks, {N} domains
Skipped: {N} unchanged chunks (token savings: ~{percent}%)
Coverage: {coverage}%

New deliverable:
  cat .planning/audit/CHANGES-SINCE-LAST-AUDIT.md  # What changed

All other deliverables updated:
  cat .planning/CODEBASE-CONTEXT.md
  cat .planning/audit/FEATURES.md
  cat .planning/audit/GAPS.md
  cat .planning/audit/AUDIT-SUMMARY.md
  cat .planning/audit/DEPENDENCIES.md
  cat .planning/audit/SECURITY-BASELINE.md
  cat .planning/audit/TEST-MAP.md
  cat .planning/audit/CLEANUP.md
```

</process>

<success_criteria>
- [ ] Previous audit validated (STATE.json or legacy)
- [ ] Changes detected via git diff against last audit hash
- [ ] Inventory refreshed
- [ ] Only affected chunks re-analyzed (not entire codebase)
- [ ] New/deleted files handled (assigned/removed from chunks)
- [ ] Tier 2 quality validation passed on re-analyzed chunks
- [ ] Affected domains re-synthesized
- [ ] Tier 4-5 refreshed with current data
- [ ] CHANGES-SINCE-LAST-AUDIT.md generated
- [ ] All derivative outputs regenerated
- [ ] STATE.json updated with new git hash
- [ ] Coverage still 100%
- [ ] CLAUDE.md pointer registered
- [ ] Results committed
</success_criteria>
