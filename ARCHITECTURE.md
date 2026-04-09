# Power Mapper: Architecture Deep Dive

This document explains exactly how Power Mapper works — every tier, every agent, every wave, and the design decisions that make it possible to audit a million-line codebase without any single agent needing to see the whole thing.

---

## The Core Problem: LLMs Can't Count

Ask an LLM to "map this codebase" and it will:
1. Read a few entry points
2. Follow some imports
3. Explore directories that look interesting
4. Produce a confident summary

The problem? It explored maybe 30% of the files. It doesn't know about the edge function buried in `supabase/functions/billing-webhook/index.ts`. It missed the admin panel at `src/pages/AdminOps.tsx`. It has no idea that `src/features/leave/` exists because nothing in the files it read imports from it.

**LLMs don't know what they don't know.** They can't enumerate a filesystem reliably. They explore breadth-first from whatever file they start at, and they stop when they feel like they've seen enough.

Power Mapper solves this with a simple rule: **bash scripts enumerate, LLMs understand.**

A bash script will never miss a file. `find . -name "*.tsx"` returns every `.tsx` file, period. So we let bash do what it's good at (counting things) and LLMs do what they're good at (understanding things).

---

## The Six Tiers

### Tier 1: Inventory (Bash)

**What:** A bash script (`scripts/inventory.sh`) runs `find`, `grep`, `wc`, and `awk` across the entire repository.

**Produces:**
- `all_files.tsv` — Every source file with its line count
- `directories.tsv` — LOC by directory
- `domains.tsv` — Files grouped by detected domain (based on directory structure)
- `domain_summary.tsv` — Domain totals
- `large_files.tsv` — Files over 500 LOC (these need extra attention)
- `external_urls.txt` — Every external API URL found via grep
- `env_vars.txt` — Every environment variable referenced
- `ai_files.txt` — Files that reference AI/ML libraries
- `db_files.txt` — Database schemas and migrations
- `config_files.txt` — Configuration files
- `stack.txt` — Detected frameworks and languages
- `summary.txt` — Quick stats

**Time:** ~30 seconds for a 200K LOC codebase.

**Why bash, not an agent?** Because this is the accountability foundation. Every file that exists in the repo gets counted here. At the end of the entire audit (Tier 6), a verification script checks that every file in this inventory appeared in at least one analysis. If bash says 847 files exist, then 847 files must be analyzed. No exceptions.

### Tier 2: File-Level Analysis (Parallel Agents)

**What:** The orchestrator groups files into "chunks" of ~15,000 lines each (based on domain affinity), then spawns one Sonnet agent per chunk. Each agent reads every file in its assignment and produces a structured analysis.

**Per-file analysis template:**
```
## src/features/billing/BillingManager.tsx (487 lines)

Purpose: Admin page for managing client billing, invoices, and payment methods
Type: page
User Roles: admin
Completeness: complete

Key Features:
- View/filter all invoices by client, status, date
- Generate manual invoices
- Process refunds
- Export billing reports to CSV

External Dependencies:
- Supabase: billing tables (invoices, payments, subscriptions)
- Stripe: payment processing, refund API

Imports From: useAuth, useBilling, InvoiceTable component
Exports: BillingManager page component

Concerns:
- No rate limiting on refund endpoint
- CSV export loads all records into memory
```

**How chunks are created:**

The orchestrator reads `domain_summary.tsv` and groups files by domain:
- `src/features/billing/*`, `src/hooks/billing/*`, `supabase/functions/billing-*/*` → all go in the "billing" chunk
- Target: ~15,000 lines per chunk
- If a domain exceeds 20,000 lines, it's split (`billing-services`, `billing-components`)
- If a domain is under 500 lines, it's merged with a related domain or an "infrastructure" chunk
- Every file must end up in exactly one chunk

**Wave execution:**

Agents are launched in waves of 4 concurrent background agents:

```
Wave 1: [billing] [messaging] [recruitment] [tasks]     → wait → verify
Wave 2: [crm] [time-tracking] [leave] [support]         → wait → verify
Wave 3: [admin] [training] [analytics] [infrastructure]  → wait → verify
```

Each wave takes ~2-3 minutes. After each wave, the orchestrator checks that every agent wrote its output file and that the output isn't suspiciously thin.

**Quality validation (Step 4b):**

After all Tier 2 waves complete, a quality check runs:
```bash
for each chunk output:
  - Count lines of output
  - Count ## headers (one per file analyzed)
  - Compare against files assigned
  - Flag if: output < 20 lines, or analyzed fewer files than assigned
```

Shallow or incomplete chunks get re-run. This catches agents that silently skipped files or produced one-line summaries — a problem that compounds through every later tier if not caught here.

**Model:** Sonnet. These agents read raw source code and need to accurately identify purpose, user roles, completeness, and dependencies. Sonnet handles this well. Haiku would miss nuance. Opus would be overkill.

### Tier 3: Domain Synthesis (Parallel Agents)

**What:** Agents read the Tier 2 chunk analyses (not source code) and synthesize them into feature-level domain summaries.

**The domain merging problem:**

A codebase with 20 feature areas would naively need 20 Tier 3 agents. But each agent spawn carries ~25-30K tokens of system overhead (Claude Code's system prompt, CLAUDE.md, MCP tool definitions, skills list). With 20 agents, that's 500-600K tokens just in overhead — before they even start reading.

**Solution: cap at 12 agents.** Small domains (≤3,000 LOC) are merged using affinity groupings:
- `leave` + `time-tracking` + `attendance` → `time-attendance`
- `announcements` + `approvals` + `support` → `comms-workflow`
- `training` + `knowledge-hub` + `filehub` → `knowledge`
- Config/scripts/lib/core → `infrastructure`

This cuts overhead nearly in half with minimal quality loss — the agents are summarizing pre-digested analyses, not reading raw code.

**Per-domain output:**

Each domain summary includes:
- **Product description** — What this feature does from a user's perspective
- **Capabilities by role** — What each user type (admin, client, VA, public) can do
- **Feature inventory** — Table of every file with type, LOC, purpose, and status
- **Integration points** — Internal domain dependencies, external services, database tables
- **Data flow** — How data moves through the feature
- **Completeness assessment** — What's built, what's missing, what's stubbed
- **Concerns** — Technical debt, scaling limits, security issues

**Model:** Sonnet. Synthesis from pre-digested summaries — doesn't need Opus-level reasoning.

### Tier 4: Thematic Cross-Cuts (5 Parallel Agents)

This is where Power Mapper gets really interesting. Tiers 2-3 analyze the codebase vertically (by feature domain). Tier 4 cuts horizontally — tracing concerns that cross every domain.

**All 5 agents run in a single wave (parallel).** Each reads all Tier 3 domain summaries plus relevant inventory files. They never read source code.

#### Agent 4a: Auth Flow Tracer

Traces authentication and authorization from login through every protected route.

**Analyzes:**
- How authentication works end-to-end (login → session → refresh → logout)
- What auth providers are used (Supabase Auth, OAuth, MFA)
- Every protected route and which role can access it
- How authorization is enforced (route-level, component-level, RLS)
- Unprotected routes that should be protected
- Inconsistent role checks
- Session management (token storage, refresh, expiry)
- MFA enforcement

**Output:** Structured report with a **route-by-role access matrix** — a table showing every route and which roles can access it. This is invaluable for security audits.

#### Agent 4b: API Surface Mapper

Maps every API endpoint and edge function.

**Analyzes:**
- Every endpoint: HTTP method, path, auth requirements, rate limiting, input validation
- Public vs authenticated endpoints
- Webhook handlers and signature verification
- Endpoints missing error handling
- Endpoints missing input validation
- Total API surface area

**Output:** A complete API table with columns for path, method, auth, rate-limit, validation, and purpose. This is what security auditors ask for first.

#### Agent 4c: Integration Auditor

Audits every external service the codebase talks to.

**For each integration, analyzes 10 dimensions:**
1. What service (Stripe, Supabase, OpenAI, etc.)
2. Authentication method (API key, OAuth, webhook signature)
3. Credential storage (env vars, secrets)
4. Operations performed (read, write, webhook)
5. Error handling for API failures
6. Retry logic
7. Timeout configurations
8. Fallback behavior
9. Webhook signature verification
10. Data flow to/from the service

**Output:** One section per integration with all 10 points addressed. This catches integrations that are partially wired up, missing error handling, or storing credentials insecurely.

#### Agent 4d: Automation Mapper

Maps every automated, scheduled, or background process.

**Analyzes:**
- Cron jobs / scheduled tasks
- Webhook receivers and what they trigger
- Background workers, queues, async processing
- Realtime subscriptions
- Email automation (scheduled sends, drip campaigns)
- Content scheduling (auto-publish, expiry)
- Cleanup tasks (data retention, garbage collection)

**Output:** Table of all automated processes with trigger, frequency, action, and monitoring status. This surfaces the "invisible" parts of the system that break silently.

#### Agent 4e: Dead Code Detector

Finds unused, orphaned, and abandoned code.

**Analyzes:**
- Files never imported by any other file
- Exports never imported anywhere
- Routes defined but not linked from navigation
- Components that exist but aren't rendered
- Services with functions never called
- Abandoned feature directories (no recent git activity)
- Configuration for features that don't exist
- Disabled or commented-out features
- Placeholder/stub pages

**Output:** Categorized list with file paths and evidence for each finding. This is the input for tech debt cleanup sprints.

**Model for all Tier 4 agents:** Sonnet. These agents do the most analytical work — tracing flows across domains, finding inconsistencies, spotting gaps. Sonnet handles this well.

### Tier 5: Executive Synthesis (Single Agent)

**What:** A single Opus agent reads all Tier 3 domain summaries and all Tier 4 thematic reports, then produces three executive deliverables.

**Why Opus?** This is the one tier where reasoning quality matters most. The agent needs to:
- Synthesize 20-40K tokens of domain summaries into a coherent product feature map
- Cross-reference thematic findings to identify systemic patterns
- Make judgment calls about health scores
- Prioritize recommendations based on risk and impact

**Produces three files:**

**FEATURES.md** — Complete product capability map organized by user role:
```
### Admin
#### Billing
- View/filter all invoices by client, status, date — /admin/billing
- Generate manual invoices — /admin/billing/new
- Process refunds — /admin/billing/:id/refund
- Export billing reports to CSV — /admin/billing/export
```

Every action, every role, every route. If it's in the codebase, it's in this map.

**GAPS.md** — Everything that's incomplete, missing, stubbed, or dead:
- Stubs & disabled features
- Incomplete implementations
- Missing features (referenced in UI but not built)
- Dead code summary
- Technical debt patterns
- Security gaps

**AUDIT-SUMMARY.md** — Executive overview with health scores:
- Architecture overview
- Health score (1-10) across 5 dimensions: feature completeness, code quality, test coverage, security posture, documentation
- Top 5 strengths
- Top 5 risks
- Top 5 recommendations (prioritized)

### Tier 6: Verification (Bash)

**What:** A verification script (`scripts/verify-coverage.sh`) cross-references the Tier 1 inventory against all Tier 2 outputs.

**Logic:**
```
For every file in all_files.tsv:
  Search all chunk-*.md files for this filename
  If found in at least one: ✓ covered
  If found in none: ✗ MISSED

Coverage = covered / total × 100%
```

**If coverage < 100%:** The orchestrator creates a new chunk with the missed files, re-runs Tier 2 for that chunk, then re-runs Tiers 3-5 for affected domains. The audit doesn't complete until every file is accounted for.

**If coverage = 100%:** The audit is verified. Every file that exists in the repository has been analyzed.

---

## Derivative Outputs (Step 10)

After the 6-tier core audit, Power Mapper generates additional outputs by extracting and recombining data from the core analysis. These cost very little extra — one Sonnet agent for CODEBASE-CONTEXT.md, one for DEPENDENCIES.md, and bash scripts for the rest.

### CODEBASE-CONTEXT.md (1 Sonnet agent)

A condensed ~200-line project summary designed for AI consumption. This is the single most impactful output — it gets referenced in the project's CLAUDE.md so every future AI session starts with full project context.

Contains: project overview, architecture, feature domains table (with status and LOC), user roles, external integrations, top gaps, key metrics.

### DEPENDENCIES.md (1 Sonnet agent)

Domain-level dependency graph extracted from the "Integration Points → Internal" sections of each domain summary.

Contains:
- **Dependency matrix** — Which domains depend on which, sorted by coupling
- **Mermaid diagram** — Visual flowchart of domain-to-domain dependencies
- **Impact analysis** — For each domain: "if this changes, these domains are affected"
- **Coupling risks** — Domains that are highly coupled, central bottlenecks, circular dependencies

This is the "what breaks if I change X?" tool.

### SECURITY-BASELINE.md (bash script)

Combines the auth-flow and api-surface thematic reports into a single security starting point. Extracts unprotected routes and endpoints missing rate limiting into dedicated sections.

### TEST-MAP.md (bash script)

Extracts user-facing actions from FEATURES.md and incomplete features from GAPS.md into a test planning document.

### CLEANUP.md (bash script)

Copies the dead-code thematic report into a standalone cleanup target list.

### CHANGES-SINCE-LAST-AUDIT.md (incremental only, 1 Sonnet agent)

Compares current and previous domain summaries to show: new features added, features removed, gaps closed, new gaps introduced, and an overall health trajectory assessment.

---

## Wave Execution In Detail

### Why waves of 4?

Claude Code has practical limits on concurrent background agents. Running more than 4-6 simultaneously risks:
- API rate limiting
- Agent failures from context pressure
- Difficulty monitoring and retrying

4 agents per wave is the sweet spot: fast enough (~2-3 minutes per wave), reliable enough (easy to verify and retry).

### Wave pattern across the full audit

For a typical 100K LOC codebase with 12 Tier 2 chunks and 10 Tier 3 domains:

```
TIER 2 (file analysis):
  Wave 1: [chunk-1] [chunk-2] [chunk-3] [chunk-4]          ~3 min
  Wave 2: [chunk-5] [chunk-6] [chunk-7] [chunk-8]          ~3 min
  Wave 3: [chunk-9] [chunk-10] [chunk-11] [chunk-12]       ~3 min
  Quality validation                                         ~30 sec

TIER 3 (domain synthesis):
  Wave 4: [domain-1] [domain-2] [domain-3] [domain-4]      ~2 min
  Wave 5: [domain-5] [domain-6] [domain-7] [domain-8]      ~2 min
  Wave 6: [domain-9] [domain-10]                            ~2 min

TIER 4 (thematic cross-cuts):
  Wave 7: [auth] [api] [integrations] [automation] [dead]   ~3 min

TIER 5 (executive synthesis):
  Wave 8: [executive]                                        ~2 min

DERIVATIVE OUTPUTS:
  Wave 9: [codebase-context] [dependencies]                  ~2 min
  Bash scripts: security-baseline, test-map, cleanup          ~10 sec

VERIFICATION:
  Bash script                                                 ~10 sec
```

**Total: ~22 minutes, 30 agents, 9 waves.**

### State tracking between waves

`STATE.json` records progress after every wave:
```json
{
  "started_at": "2025-04-09T10:00:00Z",
  "git_hash": "abc123",
  "current_tier": 2,
  "current_wave": 3,
  "completed_chunks": ["billing", "messaging", "recruitment", "tasks", "crm", "time-tracking", "leave", "support"],
  "completed_domains": [],
  "completed_themes": [],
  "status": "in_progress"
}
```

If the audit is interrupted (rate limit, session timeout, crash), resume reads this file and skips straight to the first incomplete wave. It doesn't re-run chunks that already have output files.

---

## The Compression Pyramid

This is the mathematical insight that makes Power Mapper scale.

```
Tier 1:  100,000 lines of source code        (400K tokens)
           ↓ 4x compression
Tier 2:   25,000 lines of file analyses       (100K tokens)
           ↓ 4x compression
Tier 3:    6,000 lines of domain summaries    (24K tokens)
           ↓ 4x compression
Tier 4:    1,500 lines of thematic reports    (6K tokens)
           ↓ 3x compression
Tier 5:      500 lines of executive output    (2K tokens)
```

**No agent ever sees more than ~80K tokens of meaningful input.** A Tier 2 agent reads ~15,000 lines of source code (~60K tokens). A Tier 3 agent reads 3-8 chunk analyses (~6-16K tokens). Tier 4-5 agents read domain summaries + thematic reports (~20-50K tokens).

This means Power Mapper works the same way on a 50K LOC codebase as a 1M LOC codebase. The only thing that changes is the number of Tier 2 agents (more chunks). Tiers 3-5 stay roughly the same size because compression keeps the input manageable.

A 1M LOC codebase just means more Tier 2 waves — the information still compresses down to ~500 lines of executive output.

---

## Why This Is Powerful

### 1. It can't miss files

Every other AI codebase mapping tool relies on the LLM to explore the filesystem. Power Mapper uses bash. The verification step proves 100% coverage mathematically — not "we're pretty confident" but "every file in the inventory appears in at least one analysis, here's the proof."

### 2. It scales without context limits

A 1M LOC codebase has ~4M tokens of source code. No AI model can hold that in context. Power Mapper never tries. Through hierarchical compression, no single agent ever sees more than 80K tokens. You can audit a codebase 10x larger than any model's context window.

### 3. It produces actionable outputs, not summaries

FEATURES.md isn't a paragraph about what the app does. It's a table of every action every user role can take, with the route where they do it. GAPS.md isn't "there's some technical debt." It's a categorized list of every stub, every TODO, every disabled feature, with file paths.

### 4. It's verifiable and reproducible

Run it twice, get the same structure. The output is deterministic in structure (the inventory is identical, the chunks are identical). The content varies slightly between runs (LLMs aren't deterministic), but the coverage guarantee holds every time.

### 5. Incremental mode makes it sustainable

The first audit is expensive. Every audit after that is cheap. Git diff tells you what changed, and you only re-analyze those chunks. A 5% code change means ~5% of the token cost, not another full audit.

### 6. It feeds everything downstream

The audit isn't a dead document. CODEBASE-CONTEXT.md makes every future AI session smarter. DEPENDENCIES.md feeds refactoring decisions. SECURITY-BASELINE.md feeds security audits. TEST-MAP.md feeds test planning. CLEANUP.md feeds tech debt sprints. One expensive audit powers months of downstream work.
