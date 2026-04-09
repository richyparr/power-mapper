# Power Mapper

**100% codebase coverage auditing for Claude Code.** Maps every file, feature, integration, and gap across codebases of any size — from 10K to 1M+ lines of code.

> "I asked Claude to map my codebase. It missed 40% of the files and hallucinated features that didn't exist. So I built a system where bash scripts find every file and LLMs just analyze what's there. Power Mapper has never missed a file."

---

## The Problem

When you point an AI at a large codebase and ask "what does this do?", it explores a few files, reads some imports, and gives you a confident-sounding summary that's missing half the picture. It doesn't know what it doesn't know.

This matters when you're:
- **Picking up a codebase you didn't write** and need the real feature inventory, not a guess
- **Planning a major refactor** and need to know what actually depends on what
- **Running a security audit** and can't afford to miss an unprotected endpoint
- **Onboarding AI tools** (GSD, Cursor, Copilot) and want them to understand the full project, not a sample
- **Inheriting a project** and need to know what's built, what's broken, and what's dead

## How It Works

Power Mapper uses a hierarchical MapReduce architecture. Bash scripts enumerate files (no LLM can miss what a script finds), then waves of parallel agents analyze, synthesize, and compress the results up through 6 tiers:

```
Tier 1: INVENTORY         bash scripts count every file          (~30 seconds)
    |
Tier 2: FILE ANALYSIS     parallel agents analyze source code    (~5-15 min)
    |
Tier 3: DOMAIN SYNTHESIS  agents merge into feature domains      (~3-5 min)
    |
Tier 4: THEMATIC CUTS     5 agents trace cross-cutting concerns  (~3 min)
    |
Tier 5: EXECUTIVE         single agent produces final reports    (~2 min)
    |
Tier 6: VERIFICATION      bash confirms 100% file coverage       (~10 seconds)
```

**The key insight:** each tier compresses ~4x. Raw source code becomes file analyses, file analyses become domain summaries, domain summaries become product-level features. No single agent ever needs to hold the entire codebase in context.

At the end, a verification script cross-references every file in the inventory against every analysis output. If coverage is below 100%, it flags the gaps and re-runs analysis for missed files. You get a guarantee, not a guess.

## What You Get

### Core Analysis

| File | What's in it |
|------|-------------|
| **FEATURES.md** | Complete product capability map organized by user role. Every action every user type can take, and where. |
| **GAPS.md** | Every stub, TODO, disabled feature, incomplete implementation, and dead route. Prioritized. |
| **AUDIT-SUMMARY.md** | Architecture overview, tech stack, health score (1-10 across 5 dimensions), top strengths, top risks, recommendations. |

### Derivative Outputs

These are generated automatically from the core analysis — zero extra agent cost:

| File | Who uses it | What it does |
|------|------------|-------------|
| **CODEBASE-CONTEXT.md** | Every future AI session | Condensed project overview that makes Claude/Cursor/Copilot instantly smarter about your project |
| **DEPENDENCIES.md** | Refactoring, phase planning | Domain dependency graph (with Mermaid diagram) + "what breaks if I change X?" impact analysis |
| **SECURITY-BASELINE.md** | Security audits | Auth flows, API surface, unprotected routes, rate limiting gaps |
| **TEST-MAP.md** | E2E test planning | Every testable feature mapped by user role |
| **CLEANUP.md** | Tech debt sprints | Dead code, orphan files, unused exports — actionable removal targets |
| **CHANGES-SINCE-LAST-AUDIT.md** | Progress tracking | What's new, what's fixed, what's regressed (incremental mode only) |

## Use Cases

### Picking up someone else's project
Run a full audit. In 15 minutes you'll know every feature, every gap, every integration, and every piece of dead code. No more "I think this endpoint does X" — you'll have a verified inventory.

### Planning a major refactor
The dependency graph tells you exactly which domains depend on which. Change the auth system? DEPENDENCIES.md shows every domain that imports from it and what they use. No surprises.

### Security audit baseline
SECURITY-BASELINE.md gives you every auth flow, every API endpoint, every unprotected route, and every endpoint missing rate limiting — extracted from a 100% file coverage analysis, not a sample.

### Onboarding AI coding tools
The CLAUDE.md integration means every future Claude Code session automatically reads the audit. Your AI assistant knows the full picture from the first message. Works with GSD, and the CODEBASE-CONTEXT.md file is useful for any AI tool that reads project files.

### Tracking codebase health over time
Run incremental audits after each milestone. CHANGES-SINCE-LAST-AUDIT.md shows features added, gaps closed, new debt introduced, and an overall health trajectory. Are you shipping faster or accumulating debt?

### Due diligence on an acquisition
Need to evaluate a codebase quickly? Power Mapper gives you a complete feature inventory, health score, integration map, and gap analysis in under an hour — for codebases up to 1M LOC.

## Installation

```bash
# Clone the repo
git clone https://github.com/richyparr/power-mapper.git

# Copy to your Claude Code skills directory
cp -r power-mapper/ ~/.claude/skills/power-mapper/
```

## Quick Start

```bash
# In any git repository, open Claude Code and run:
/power-mapper
```

Choose **Full audit** for your first run. You'll see:

```
Inventory complete.
- Total files: 847
- Total LOC: 94,231
- Detected stack: React, TypeScript, Supabase, Tailwind
- Feature domains: 18

Chunk plan ready.
- Tier 2 agents: 12 (file analysis)
- Tier 3 agents: 10 (domain synthesis)
- Tier 4 agents: 5 (thematic cross-cuts)
- Tier 5 agent: 1 (executive synthesis)
- Total agents: 28
- Estimated time: ~15 minutes

Proceed?
```

After completion, start with:
```bash
cat .planning/CODEBASE-CONTEXT.md    # Project overview
cat .planning/audit/FEATURES.md      # Full feature map
cat .planning/audit/GAPS.md          # What's missing
```

## How It Scales

| Codebase | Tier 2 Agents | Tier 3 Agents | Total Agents | Est. Time |
|----------|--------------|---------------|-------------|-----------|
| 10K LOC  | 2-3          | 3-5           | ~12         | 5 min     |
| 50K LOC  | 5-8          | 6-10          | ~20         | 10 min    |
| 100K LOC | 10-15        | 8-12          | ~30         | 15 min    |
| 200K LOC | 15-25        | 10-12         | ~45         | 20 min    |
| 500K LOC | 35-60        | 10-12         | ~80         | 30 min    |
| 1M LOC   | 70-125       | 10-12         | ~145        | 45 min    |

Tier 3 is capped at **max 12 agents** regardless of codebase size. Small domains are automatically merged. This is the single most important optimization — each spawned agent carries ~25-30K tokens of system overhead.

## Token Cost Tips

Power Mapper is token-intensive. These optimizations are built in:

- **Domain merging** — Tier 3 auto-merges small domains to stay under 12 agents
- **Quality validation** — Catches shallow Tier 2 analyses before they waste downstream tokens
- **Incremental mode** — After the first audit, only re-analyze what git says changed
- **Resume tracking** — `STATE.json` lets interrupted audits resume mid-wave, not from scratch
- **Model selection** — Sonnet for Tiers 2-4 (bulk analysis), Opus only for Tier 5 (executive synthesis)

**Before running**, set Claude Code effort to **low or medium** (`/effort`). The agents do structured summarization, not complex reasoning.

**Session overhead matters.** Every agent inherits your session's system prompt. To minimize cost:
- Keep `~/.claude/CLAUDE.md` concise
- Disconnect unused MCP servers before running
- Fewer installed skills = less overhead per agent

## Incremental Mode

After the first full audit, use incremental mode to stay current:

```
/power-mapper
> Choose: 2 (Incremental audit)
```

It diffs against the git hash stored in `STATE.json`, re-analyzes only changed chunks, and produces a `CHANGES-SINCE-LAST-AUDIT.md` showing what's different. Token cost scales with how much changed, not total codebase size.

## Integration

### Claude Code / CLAUDE.md

After the audit completes, Power Mapper adds a section to your project's `CLAUDE.md` pointing to the audit files. Every future Claude Code session automatically knows the full project context.

### GSD (Get Shit Done)

If you use the [GSD plugin](https://github.com/glittercowboy/get-shit-done), Power Mapper replaces `gsd-map-codebase` with strictly more comprehensive output. The CLAUDE.md directive tells GSD to use the audit data instead of running its own exploration.

### Any AI tool

`CODEBASE-CONTEXT.md` is a self-contained ~200-line project summary designed for AI consumption. Point any tool at it — Cursor, Copilot, Windsurf, or your own agents.

## Architecture

For a comprehensive technical deep-dive into every tier, every agent, wave execution, the compression pyramid, and what makes this approach powerful, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

```
power-mapper/
+-- SKILL.md                        # Skill entry point
+-- README.md                       # This file
+-- workflows/
|   +-- full-audit.md               # Complete Tier 1-6 audit workflow
|   +-- incremental-audit.md        # Git-diff based incremental audit
+-- references/
|   +-- agent-prompts.md            # Prompt templates for Tier 2/3/4/5 agents
|   +-- scaling-strategy.md         # Token math, chunk sizing, wave execution
+-- scripts/
    +-- inventory.sh                # Tier 1 file enumeration (bash)
    +-- verify-coverage.sh          # Tier 6 coverage verification (bash)
```

### Design Principles

1. **Scripts enumerate, LLMs understand.** File discovery is bash, not AI. Scripts can't miss files. LLMs can and will.

2. **Filesystem is shared memory.** Agents never pass context to each other. Every agent reads from disk and writes to disk. The orchestrator passes file paths, never source code.

3. **Hierarchical compression.** Each tier compresses ~4x. No agent ever exceeds 200K tokens of meaningful input, regardless of codebase size.

4. **100% verifiable coverage.** A verification script cross-references inventory against analysis. Every file must appear. No exceptions.

5. **The orchestrator never reads source code.** Your main Claude Code session coordinates — it never reads source files directly, keeping its context window free.

## Requirements

- [Claude Code](https://claude.ai/download) CLI
- Git repository
- bash, awk, grep, wc (standard Unix tools)
- python3 (for STATE.json management)

## Contributing

Issues and PRs welcome. The main areas for improvement:

- **More language-aware chunking** — Currently groups by directory. Could use import graphs for smarter grouping.
- **Configurable wave size** — Currently hardcoded at 4. Could be adjusted per-tier.
- **Output format options** — JSON export, Notion integration, etc.
- **Non-Claude support** — Adapt prompts for other AI coding tools.

## License

MIT
