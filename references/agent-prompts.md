# Agent Prompt Templates

Use these templates when spawning agents for each tier. Replace `{placeholders}` with actual values.

<tier2_prompt>
## Tier 2: File-Level Analysis Agent

```
You are performing a file-level analysis for a codebase audit. Your job is to read EVERY file in your assignment and produce a structured analysis.

CRITICAL RULES:
1. Read EVERY file listed in your assignment. Do not skip any.
2. For each file, fill in the analysis template below.
3. If a file is too large to read completely, read the first 500 lines and the last 100 lines and note "partially read" in your analysis.
4. Focus on WHAT the code does (product view), not HOW it's written (architecture view).
5. Identify who uses each feature (which user roles).

YOUR ASSIGNMENT FILE: {assignment_file_path}
Read this file first to get your list of files to analyze.

OUTPUT FILE: {output_file_path}
Write your complete analysis to this file.

OUTPUT FORMAT — use this template for EACH file:

---

## {file_path} ({line_count} lines)

**Purpose:** One sentence describing what this file does from a product/user perspective.

**Type:** page | component | service | hook | context | util | config | test | edge-function | migration | type-definition | other

**User Roles:** Which roles interact with this? (admin, client, va, public, internal, system)

**Completeness:** complete | partial | stub | disabled
- If partial/stub: what's missing?

**Key Features:**
- Feature 1
- Feature 2
- ...

**External Dependencies:**
- Service/API calls (Supabase, Stripe, OpenAI, etc.)
- External URLs hit
- Environment variables used

**Imports From:** (key internal dependencies — which other features/services does this depend on?)

**Exports:** (what does this file provide to other parts of the codebase?)

**Concerns:**
- Any issues, TODOs, technical debt, or risks noticed

---

After analyzing all files, add a summary section at the top:

# Chunk Analysis: {chunk_label}

**Files analyzed:** {count}
**Total LOC:** {sum}
**Domains covered:** {list of feature areas}

Then list all file analyses below.
```
</tier2_prompt>

<tier3_prompt>
## Tier 3: Domain Synthesis Agent

```
You are synthesizing the analysis of a single feature domain in a codebase audit. Your job is to read all Tier 2 file analyses for this domain and produce a feature-level summary.

DOMAIN: {domain_name}

READ THESE TIER 2 CHUNK ANALYSES:
{list_of_chunk_files}

Look for all entries in those files that relate to the "{domain_name}" domain. This includes pages, components, services, hooks, types, and edge functions for this feature area.

OUTPUT FILE: {output_file_path}

OUTPUT FORMAT:

# Domain: {domain_name}

## What This Feature Does

Describe the feature from a PRODUCT perspective. What can users do? What problem does it solve?

## Capabilities by User Role

### Admin
- Capability 1
- Capability 2

### Client  
- Capability 1
- Capability 2

### VA (Virtual Assistant)
- Capability 1
- Capability 2

### Public (unauthenticated)
- Capability 1 (if any)

## Feature Inventory

| Component | Type | Lines | Purpose | Status |
|-----------|------|-------|---------|--------|
| file1.tsx | page | 487   | Main dashboard | complete |
| file2.ts  | service | 230 | Data access | complete |
| ...       | ...  | ...   | ...     | ...    |

## Integration Points

- **Internal:** Which other domains does this feature depend on or interact with?
- **External:** Which external services/APIs does this feature use?
- **Database:** Which tables does this feature read/write?

## Data Flow

Describe how data flows through this feature: user action → component → hook → service → database → response → UI update

## Completeness Assessment

**Overall:** complete | mostly complete | partial | early stage

**What's built:**
- Built thing 1
- Built thing 2

**What's missing or incomplete:**
- Missing thing 1
- Missing thing 2

**What's stubbed or disabled:**
- Stub 1
- Stub 2

## Concerns

- Technical debt or risks specific to this domain
- Scaling limits
- Security considerations
```
</tier3_prompt>

<tier4_prompts>
## Tier 4: Thematic Cross-Cut Agents

Each thematic agent has a specialized focus. All read from `.planning/audit/domains/` (Tier 3 outputs).

### 4a. Auth Flow Tracer

```
You are tracing authentication and authorization flows across the entire codebase.

READ: All files in .planning/audit/domains/*.md
READ: .planning/audit/inventory/env_vars.txt
ALSO GREP the source code for: "useAuth", "ProtectedRoute", "role", "permission", "RLS", "auth", "session", "jwt", "token"

OUTPUT FILE: .planning/audit/themes/auth-flow.md

ANALYZE:
1. How does authentication work? (login → session → token refresh → logout)
2. What auth providers are used? (Supabase Auth, OAuth, MFA)
3. Map every protected route and what role can access it
4. How is authorization enforced? (route-level, component-level, RLS)
5. Are there any unprotected routes that should be protected?
6. Are there any role checks that are inconsistent?
7. Session management: how are tokens stored, refreshed, expired?
8. MFA: is it enforced? Where? For which roles?

FORMAT: Structured report with route-by-role access matrix.
```

### 4b. API Surface Mapper

```
You are mapping every API endpoint and edge function in the codebase.

READ: All files in .planning/audit/domains/*.md
READ: .planning/audit/inventory/external_urls.txt
READ: .planning/audit/inventory/config_files.txt
ALSO GREP source code for: "functions/v1/", "api/", "edge function", "endpoint"

OUTPUT FILE: .planning/audit/themes/api-surface.md

ANALYZE:
1. List every API endpoint (edge functions, serverless functions, REST routes)
2. For each: HTTP method, path, auth requirements, rate limiting, input validation
3. Which endpoints are public vs authenticated?
4. Which endpoints handle webhooks? What signature verification exists?
5. Are there any endpoints without proper error handling?
6. Are there any endpoints without input validation?
7. What's the total API surface area?

FORMAT: Table of all endpoints with columns: path, method, auth, rate-limit, validation, purpose
```

### 4c. Integration Auditor

```
You are auditing every external service integration in the codebase.

READ: All files in .planning/audit/domains/*.md  
READ: .planning/audit/inventory/external_urls.txt
READ: .planning/audit/inventory/ai_files.txt
READ: .planning/audit/inventory/env_vars.txt

OUTPUT FILE: .planning/audit/themes/integrations.md

ANALYZE for each external service:
1. What service is it? (Stripe, Supabase, OpenAI, etc.)
2. How is it authenticated? (API key, OAuth, webhook signature)
3. Where are credentials stored? (env vars, secrets)
4. What operations are performed? (read, write, webhook)
5. Is there error handling for API failures?
6. Is there retry logic?
7. Are there timeout configurations?
8. Is there a fallback if the service is down?
9. Are webhook signatures verified?
10. What data flows to/from this service?

FORMAT: One section per integration with all 10 points addressed.
```

### 4d. Automation Mapper

```
You are mapping every automated, scheduled, or background process in the codebase.

READ: All files in .planning/audit/domains/*.md
READ: .planning/audit/inventory/config_files.txt
ALSO GREP source code for: "cron", "schedule", "interval", "queue", "webhook", "background", "worker", "pg_cron", "setInterval"

OUTPUT FILE: .planning/audit/themes/automation.md

ANALYZE:
1. Cron jobs / scheduled tasks: what runs, when, what it does
2. Webhook receivers: what events trigger what actions
3. Background processes: any workers, queues, or async processing
4. Realtime subscriptions: what listens for what changes
5. Email automation: scheduled sends, drip campaigns, reminders
6. Content scheduling: auto-publish, expiry
7. Cleanup tasks: data retention, garbage collection

FORMAT: Table of all automated processes with: trigger, frequency, action, monitoring
```

### 4e. Dead Code Detector

```
You are finding unused, orphaned, and dead code in the codebase.

READ: All files in .planning/audit/domains/*.md
READ: .planning/audit/inventory/all_files.tsv
READ: .planning/audit/inventory/large_files.tsv
ALSO GREP source code for: imports and exports to check connectivity

OUTPUT FILE: .planning/audit/themes/dead-code.md

ANALYZE:
1. Files that exist but are never imported by any other file
2. Exports that are never imported anywhere
3. Routes defined but not linked from any navigation
4. Components that exist but aren't rendered anywhere
5. Services with functions that are never called
6. Feature directories that appear abandoned (no recent git activity)
7. Configuration for features that don't exist
8. Disabled or commented-out features
9. Placeholder/stub pages or components

FORMAT: Categorized list with file paths and evidence for each finding.
```
</tier4_prompts>

<tier5_prompt>
## Tier 5: Executive Synthesis Agent

```
You are producing the final deliverables of a comprehensive codebase audit. You have access to domain-level summaries and thematic cross-cutting reports — NOT raw source code.

READ ALL FILES IN:
- .planning/audit/domains/*.md (feature domain summaries)
- .planning/audit/themes/*.md (cross-cutting analysis reports)
- .planning/audit/inventory/summary.txt (inventory stats)
- .planning/audit/inventory/large_files.tsv (largest files for reference)
- .planning/audit/inventory/stack.txt (detected stack)

WRITE THREE FILES:

### 1. .planning/audit/FEATURES.md

Complete product capability map organized by USER ROLE. For each role, list every action they can take in the product.

Format:
# Product Feature Map

## Stats
- Total features: N
- User roles: [list]
- External integrations: N

## By User Role

### Admin
#### [Feature Area]
- Action 1 — what they can do, where (page/route)
- Action 2
...

### Client
#### [Feature Area]
- Action 1
...

### VA (Virtual Assistant)
...

### Public (Unauthenticated)
...

## By Feature Domain
[For each domain: one-paragraph summary of what it does + completeness rating]

## Integration Map
[Every external service and what it enables]

## AI/ML Capabilities
[Every AI-powered feature and what model/service it uses]


### 2. .planning/audit/GAPS.md

Every incomplete, missing, stub, or disabled feature found across all domain and thematic analyses.

Format:
# Codebase Gaps

## Stubs & Disabled Features
[Features that exist as code but don't work]

## Incomplete Implementations  
[Features that partially work but have missing pieces]

## Missing Features
[Features referenced in UI/routes but not implemented]

## Dead Code
[Summary from dead-code thematic report]

## Technical Debt
[Patterns that will cause problems at scale]

## Security Gaps
[From auth-flow and api-surface thematic reports]


### 3. .planning/audit/AUDIT-SUMMARY.md

Executive overview of the codebase.

Format:
# Codebase Audit Summary

## Overview
- Project: [name/description]  
- Stack: [detected stack]
- Size: [files, LOC]
- Feature domains: [count]
- External integrations: [count]
- API endpoints: [count]

## Architecture
[Brief architectural pattern description]

## Health Score
Rate 1-10 on each dimension:
- Feature completeness: X/10
- Code quality: X/10
- Test coverage: X/10
- Security posture: X/10
- Documentation: X/10
- Overall: X/10

## Key Strengths
[Top 5 things done well]

## Key Risks
[Top 5 things that need attention]

## Recommendations
[Top 5 actionable next steps, prioritized]
```
</tier5_prompt>
