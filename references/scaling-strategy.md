# Scaling Strategy

<token_math>
## Token Budget Per Tier

**Assumptions:**
- Average 4 tokens per line of source code
- Agent useful context: ~150K tokens (leave room for prompt + output)
- Source code budget per agent: ~80K tokens ≈ 20,000 lines

**Tier 2 chunk sizing:**
- Target: 15,000 lines per chunk (safe margin below 20K limit)
- Minimum: 500 lines (merge smaller chunks together)
- Maximum: 20,000 lines (split if exceeded)
- Token estimate: 15,000 lines × 4 tokens/line = 60K tokens of source

**Tier 3 input sizing:**
- Each Tier 2 chunk produces ~200-500 lines of analysis
- Domain agent reads 3-8 chunk analyses ≈ 1,500-4,000 lines ≈ 6-16K tokens
- Well within context limits

**Tier 4 input sizing:**
- All Tier 3 domain summaries combined: 20-40 domains × 200 lines = 4,000-8,000 lines ≈ 16-32K tokens
- Plus inventory files: ~2K tokens
- Well within context limits

**Tier 5 input sizing:**
- All Tier 3 summaries: ~16-32K tokens
- All Tier 4 reports: ~5 × 4K tokens = 20K tokens
- Inventory summary: ~1K tokens
- Total: ~40-55K tokens — fits comfortably
</token_math>

<wave_execution>
## Wave Execution Strategy

**Default wave size: 4 concurrent agents**

Why 4, not 10:
- Claude Code has practical limits on concurrent background agents
- 4 agents complete in ~2-3 minutes
- Lower risk of rate limiting or API errors
- Easy to monitor and retry failures

**Wave execution pattern:**

```
Wave 1: agents 1-4   → wait → verify
Wave 2: agents 5-8   → wait → verify
Wave 3: agents 9-12  → wait → verify
...
```

**Scaling by codebase size:**

| LOC | Files (est.) | Tier 2 Chunks | Tier 2 Waves | Tier 3 Domains | Total Agents | Est. Time |
|-----|-------------|---------------|-------------|----------------|-------------|-----------|
| 10K | ~100 | 2-3 | 1 | 3-5 | ~12 | 5 min |
| 50K | ~400 | 5-8 | 2 | 6-10 | ~20 | 10 min |
| 100K | ~800 | 10-15 | 3-4 | 8-12 | ~30 | 15 min |
| 200K | ~1,500 | 15-25 | 4-7 | 10-12 | ~45 | 20 min |
| 500K | ~3,500 | 35-60 | 9-15 | 10-12 | ~80 | 30 min |
| 1M | ~6,000 | 70-125 | 18-32 | 10-12 | ~145 | 45 min |

**IMPORTANT — Tier 3 domain cap: max 12 agents.**
Each agent spawn carries ~30-50K tokens of system prompt overhead (skills list, MCP tools, CLAUDE.md, etc.) regardless of task size. With 20+ Tier 3 agents, system overhead alone can exceed 1M tokens and exhaust plan limits in minutes. Merging small domains into ≤12 composite domains cuts this overhead nearly in half with minimal quality loss — Tier 3 input is pre-digested summaries, not raw code.

**For codebases >500K LOC:**
- Increase wave size to 6-8 if API allows (test with first wave)
- Consider running Tier 2 overnight in background
- Use incremental mode for subsequent audits
- Tier 3 domains should still cap at 12 — merge aggressively
</wave_execution>

<chunking_algorithm>
## Chunking Algorithm

**Step 1: Group by domain**
Files are grouped by the domain detected in inventory (directory-based):
- `src/features/billing/*` → "billing"
- `src/pages/Billing*.tsx` → "billing" (match by prefix)
- `src/components/billing/*` → "billing"
- `src/hooks/billing/*` → "billing"
- `supabase/functions/billing-*/*` → "billing"

**Step 2: Check sizes**
For each domain group:
- If LOC < 500: mark for merging
- If LOC > 20,000: mark for splitting
- If LOC 500-20,000: keep as single chunk

**Step 3: Merge small groups**
Merge groups < 500 LOC into:
- A related domain (if imports suggest relationship)
- An "infrastructure" chunk (for config, utils, lib)
- A "misc" chunk (for truly orphan files)

**Step 4: Split large groups**
For groups > 20,000 LOC:
- Split by subdirectory (e.g., billing/services vs billing/components)
- If still too large, split alphabetically or by file size
- Name parts: "billing-services", "billing-components"

**Step 5: Assign orphans**
Files not in any domain directory:
- Root config files → "config" chunk
- Root-level source files → "core" chunk
- Test files → group with their domain or "tests" chunk

**Step 6: Verify completeness**
Sum of all chunk file counts must equal total inventory file count.
</chunking_algorithm>

<retry_strategy>
## Retry Strategy

**Agent failures:**
- If an agent produces no output file: retry once with same prompt
- If an agent produces an empty file: retry once
- If an agent produces a truncated file (missing summary section): accept and note
- If retry also fails: flag chunk as "unanalyzed" in coverage report

**Partial failures:**
- If <90% of Tier 2 chunks complete: pause and ask user
- If 90-99% complete: proceed to Tier 3, note gaps
- If 100% complete: proceed normally

**Context window exceeded:**
- If a chunk's source code doesn't fit in agent context: split the chunk in half and retry
- The inventory script already flags files > 500 LOC — use these for smarter splitting
</retry_strategy>
