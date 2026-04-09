---
name: power-mapper
description: Enterprise-scale codebase auditing with hierarchical MapReduce. Handles 1M+ LOC with 100% file coverage verification. Use when you need a complete feature inventory of any codebase without missing a single file, page, API endpoint, or integration.
---

<essential_principles>

**1. Scripts Enumerate, LLMs Understand**
Never rely on an LLM to "find" files. Use bash scripts to programmatically list every file, route, endpoint, and integration. Scripts can't miss files. LLMs can and will.

**2. Filesystem Is Shared Memory**
Agents never pass context to each other. Every agent reads input from disk and writes output to disk. The orchestrator (you) passes file paths, never source code.

**3. Hierarchical Compression**
Source code (Tier 2) compresses into file analyses. File analyses (Tier 3) compress into domain summaries. Domain summaries (Tier 4-5) compress into product-level features. Each tier compresses ~4x. No agent ever exceeds 200K tokens of meaningful input.

**4. 100% Verifiable Coverage**
After every audit, a verification script cross-references inventory against analysis outputs. Every file in the inventory must appear in at least one analysis. Coverage < 100% triggers a re-analysis loop for missed files.

**5. The Orchestrator Never Reads Source Code**
You (the orchestrator) manage the process. You read inventory summaries, create chunk assignments, spawn agents, and verify coverage. You NEVER read source files directly. This keeps your context window free for coordination.

</essential_principles>

<architecture>

```
Tier 1: INVENTORY        bash scripts → .planning/audit/inventory/
    ↓
Tier 2: FILE ANALYSIS    parallel agents → .planning/audit/files/chunk-{N}.md
    ↓
Tier 3: DOMAIN SYNTHESIS  parallel agents → .planning/audit/domains/{name}.md
    ↓
Tier 4: THEMATIC CROSS-CUTS  parallel agents → .planning/audit/themes/{name}.md
    ↓
Tier 5: EXECUTIVE SYNTHESIS  single agent → .planning/audit/FEATURES.md + GAPS.md + AUDIT-SUMMARY.md
    ↓
Tier 6: VERIFICATION     bash script → .planning/audit/COVERAGE.txt
```

**Scaling math (approximate):**

| Codebase Size | Tier 2 Agents | Tier 3 Agents | Total Agents | Wall Time |
|--------------|---------------|---------------|-------------|-----------|
| 50K LOC      | 4-8           | 5-10          | ~20         | ~8 min    |
| 200K LOC     | 15-25         | 10-20         | ~55         | ~15 min   |
| 500K LOC     | 40-60         | 20-30         | ~100        | ~25 min   |
| 1M LOC       | 80-125        | 30-40         | ~170        | ~40 min   |

Agents run in waves of 4 (default, configurable). Each wave takes ~2-3 minutes.

</architecture>

<output_structure>

After a complete audit, `.planning/audit/` contains:

```
.planning/
├── CODEBASE-CONTEXT.md         # START HERE — condensed context for GSD/Claude Code
└── audit/
    ├── STATE.json              # Audit state for resume/incremental tracking
    ├── inventory/              # Tier 1 — script-generated file inventory
    │   ├── all_files.tsv       # Every source file with LOC
    │   ├── directories.tsv     # LOC by directory
    │   ├── domains.tsv         # Files grouped by detected domain
    │   ├── domain_summary.tsv  # Domain totals (LOC, file count)
    │   ├── large_files.tsv     # Files >500 LOC
    │   ├── external_urls.txt   # External API calls found
    │   ├── env_vars.txt        # Environment variables found
    │   ├── ai_files.txt        # AI/ML related files
    │   ├── db_files.txt        # Database schemas/migrations
    │   ├── config_files.txt    # Configuration files
    │   ├── stack.txt           # Detected stack/frameworks
    │   └── summary.txt         # Quick stats
    ├── files/                  # Tier 2 — per-chunk file analyses
    │   ├── chunk-001.md
    │   ├── chunk-002.md
    │   └── ...
    ├── domains/                # Tier 3 — per-domain feature summaries (max 12)
    │   ├── messaging.md
    │   ├── billing.md
    │   └── ...
    ├── themes/                 # Tier 4 — cross-cutting concern reports
    │   ├── auth-flow.md
    │   ├── api-surface.md
    │   ├── integrations.md
    │   ├── automation.md
    │   └── dead-code.md
    ├── FEATURES.md             # Tier 5 — complete product capability map
    ├── GAPS.md                 # Tier 5 — stubs, TODOs, incomplete features
    ├── AUDIT-SUMMARY.md        # Tier 5 — health score, stats, architecture
    ├── COVERAGE.txt            # Tier 6 — verification results
    ├── DEPENDENCIES.md         # Derivative — domain dependency graph + impact analysis
    ├── SECURITY-BASELINE.md    # Derivative — auth flows + API surface for hardening
    ├── TEST-MAP.md             # Derivative — testable features for E2E planning
    ├── CLEANUP.md              # Derivative — dead code removal targets
    └── CHANGES-SINCE-LAST-AUDIT.md  # Incremental only — what changed between audits
```

**Who consumes what:**

| File | Consumed by | Purpose |
|------|-------------|---------|
| CODEBASE-CONTEXT.md | GSD planning agents, Claude Code, new sessions | Project understanding |
| FEATURES.md | Product planning, roadmap creation | What exists |
| GAPS.md | GSD phase planning, backlog creation | What's missing |
| DEPENDENCIES.md | `/gsd-analyze-dependencies`, refactoring | Impact analysis |
| SECURITY-BASELINE.md | Security hardening skill | Audit starting point |
| TEST-MAP.md | E2E testing skill | Test planning |
| CLEANUP.md | Tech debt sprints | Removal targets |
| CHANGES-SINCE-LAST-AUDIT.md | Team reviews, progress tracking | Health trajectory |

</output_structure>

<audit_modes>

| Mode | Tiers | What you get | Token cost | Best for |
|------|-------|-------------|------------|----------|
| **Full** | 1-6 + all derivatives | Everything: domain summaries, 5 thematic reports, dependency graph, security baseline, test map, cleanup targets | High | First audit, security review, due diligence, large codebases |
| **Standard** | 1-3, 5-6 + limited derivatives | FEATURES.md, GAPS.md, AUDIT-SUMMARY.md, CODEBASE-CONTEXT.md, DEPENDENCIES.md. No thematic cross-cuts. | Medium | Regular audits, incremental updates, most use cases |
| **Quick** | 1-2, 5-6 + CODEBASE-CONTEXT only | FEATURES.md, GAPS.md, AUDIT-SUMMARY.md, CODEBASE-CONTEXT.md. No domain summaries, no themes. | Low | Small codebases (<100K LOC), quick overview |

</audit_modes>

<intake>
Checking for previous audit...

**If `.planning/audit/inventory/all_files.tsv` exists:**

A previous audit exists. What would you like to do?

1. **Full audit** — All tiers, all derivatives (max insight, max tokens)
2. **Standard audit** — Skip thematic cross-cuts, fewer derivatives (balanced)
3. **Quick audit** — File analysis → executive summary (fast, small codebases only)
4. **Incremental audit** — Only re-analyze files changed since last audit
5. **Resume** — Continue an interrupted audit from where it stopped

**If no previous audit exists:**

What level of audit would you like?

1. **Full** — All tiers, all derivatives (max insight, max tokens)
2. **Standard** — Skip thematic cross-cuts, fewer derivatives (balanced)
3. **Quick** — File analysis → executive summary (fast, small codebases only)

</intake>

<routing>

| Response | Workflow | Mode flag |
|----------|----------|-----------|
| 1, "full", "complete" | `workflows/full-audit.md` | `mode=full` |
| 2, "standard", "balanced" | `workflows/full-audit.md` | `mode=standard` |
| 3, "quick", "fast", "light" | `workflows/full-audit.md` | `mode=quick` |
| 4, "incremental", "update", "diff", "changed" | `workflows/incremental-audit.md` | (inherits mode from previous audit) |
| 5, "resume", "continue" | `workflows/full-audit.md` | (resume flag + previous mode) |

**After reading the workflow, follow it exactly. Pass the mode flag to control which tiers execute.**

</routing>

<reference_index>

**Agent Prompts:** `references/agent-prompts.md` — Prompt templates for Tier 2/3/4/5 agents
**Scaling Strategy:** `references/scaling-strategy.md` — Token math, chunk sizing, wave execution

</reference_index>

<workflows_index>

| Workflow | Purpose |
|----------|---------|
| full-audit.md | Complete audit (supports full/standard/quick modes) |
| incremental-audit.md | Re-audit only files changed since last audit |

</workflows_index>
