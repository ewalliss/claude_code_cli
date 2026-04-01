# Claude Code Mastery Guide
## High-Quality Prompts · CLAUDE.md Setup · Tool Usage · Ultrathink Patterns

> **Source-grounded.** Every pattern in this guide is derived from the actual Claude Code
> source at `src/`. References point to exact files and line numbers.
> AI Engineer & Data Engineer Reference · April 2026

---

## Table of Contents

1. [How the Model Thinks — Source Evidence](#1-how-the-model-thinks--source-evidence)
2. [Ultrathink — What It Actually Does](#2-ultrathink--what-it-actually-does)
3. [The Optimal CLAUDE.md Setup](#3-the-optimal-claudemd-setup)
4. [High-Quality Prompt Patterns](#4-high-quality-prompt-patterns)
5. [Tool Usage for Best Results](#5-tool-usage-for-best-results)
6. [Permission Rules That Unlock Speed](#6-permission-rules-that-unlock-speed)
7. [The Agent/Fork System](#7-the-agentfork-system)
8. [Memory Architecture for Long Sessions](#8-memory-architecture-for-long-sessions)
9. [Anti-Patterns — What Kills Quality](#9-anti-patterns--what-kills-quality)
10. [Full Example: Production-Grade CLAUDE.md](#10-full-example-production-grade-claudemd)
11. [Full Example: High-Performance Prompts](#11-full-example-high-performance-prompts)
12. [Source Reference Index](#12-source-reference-index)

---

## 1. How the Model Thinks — Source Evidence

Understanding what the model is *actually told* is the foundation for engineering quality.
These are verbatim excerpts from `src/constants/prompts.ts`.

### Identity First

The very first line the model receives:

```
You are an interactive agent that helps users with software engineering tasks.
```
*`src/constants/prompts.ts:175`*

**Implication:** The model self-identifies as an *agent*, not a chatbot. It expects
to act — read files, run commands, make decisions. Prompts that describe a task
rather than ask a question get better results.

### The Six Core Doctrines Taught to the Model

These are the actual instructions the model receives every session:

#### Doctrine 1 — Code Minimalism (`prompts.ts:200–213`)
```
Don't add features, refactor code, or make "improvements" beyond what was asked.
Don't add error handling for scenarios that can't happen.
Don't create helpers for one-time operations.
Three similar lines of code is better than a premature abstraction.
```

**Implication:** The model will resist over-engineering by default.
If you want thoroughness, ask for it explicitly.

#### Doctrine 2 — Read Before Modifying (`prompts.ts:230`)
```
In general, do not propose changes to code you haven't read.
If a user asks about or wants you to modify a file, read it first.
```

**Implication:** The model will always read first. Don't fight this. Give it
permission to explore with phrases like "take what you need to understand the
full picture before starting."

#### Doctrine 3 — Diagnosis Before Retry (`prompts.ts:233`)
```
If an approach fails, diagnose why before switching tactics — read the error,
check your assumptions, try a focused fix. Don't retry the identical action blindly,
but don't abandon a viable approach after a single failure either.
```

**Implication:** The model has a built-in retry budget. If you want it to persist
through complexity, say "do not give up until you have exhausted all diagnostic paths."

#### Doctrine 4 — Honest Outcome Reporting (`prompts.ts:240`)
```
Report outcomes faithfully: if tests fail, say so with the relevant output.
Never claim "all tests pass" when output shows failures.
Equally, when a check did pass, state it plainly — do not hedge confirmed results.
```

**Implication:** The model is trained to be honest in both directions.
If it says "tests pass", trust it. If you need verification evidence, ask it to
"show me the output of every verification step."

#### Doctrine 5 — Reversibility-First (`prompts.ts:258`)
```
Carefully consider the reversibility and blast radius of actions.
The cost of pausing to confirm is low, while the cost of an unwanted action is high.
A user approving an action once does NOT mean they approve it in all contexts.
```

**Implication:** The model will pause before destructive operations. To speed this
up, use permission rules (see Section 6) or explicitly authorize specific actions
in CLAUDE.md: `"You are authorized to push to feature/* branches without asking."`

#### Doctrine 6 — Verification Mandate (`prompts.ts:211`)
```
Before reporting a task complete, verify it actually works: run the test,
execute the script, check the output. If you can't verify, say so explicitly
rather than claiming success.
```

**Implication:** The model will run verification steps. Reinforce this in your
CLAUDE.md: "Always run `npm test` and show me the output before declaring done."

---

## 2. Ultrathink — What It Actually Does

### Source Evidence

```typescript
// src/utils/thinking.ts:19–24
export function isUltrathinkEnabled(): boolean {
  if (!feature('ULTRATHINK')) { return false }
  return getFeatureValue_CACHED_MAY_BE_STALE('tengu_turtle_carbon', true)
}

// src/utils/thinking.ts:29–31
export function hasUltrathinkKeyword(text: string): boolean {
  return /\bultrathink\b/i.test(text)
}
```

```typescript
// src/utils/thinking.ts:113–144
export function modelSupportsAdaptiveThinking(model: string): boolean {
  // Only claude-opus-4-6 and claude-sonnet-4-6 support adaptive thinking
  if (canonical.includes('opus-4-6') || canonical.includes('sonnet-4-6')) {
    return true
  }
  // All other named models: false
}
```

### What Adaptive Thinking Is

The model has two modes:
- **Normal**: Generates output token-by-token without extended reasoning
- **Adaptive thinking**: The model decides *how much* to think based on the complexity
  of the task. Simple tasks get no thinking budget. Hard problems get a large one.

The word `ultrathink` in your prompt is detected by `hasUltrathinkKeyword()` and
signals to the engine to allocate maximum extended thinking budget.

### When to Use Ultrathink

| Situation | Use ultrathink? | Why |
|---|---|---|
| Multi-file architecture decisions | YES | Requires holding many constraints simultaneously |
| Root cause diagnosis of subtle bugs | YES | Needs systematic hypothesis elimination |
| Complex SQL or data pipeline design | YES | State-heavy, dependency-rich reasoning |
| Security analysis of code | YES | Adversarial reasoning benefits from extended thinking |
| Simple file edit | NO | Adds latency with no benefit |
| Single-function implementation | NO | Model handles this fine in normal mode |
| Summarizing a file | NO | No complex reasoning required |

### The Correct Way to Trigger Ultrathink

The keyword is detected with a word boundary regex: `\bultrathink\b`.
It must appear as a **standalone word**, not embedded in another word.

```
# Works:
"ultrathink about the architecture of this system"
"I need you to ultrathink the migration strategy"

# Does NOT work:
"superultrathink"   ← word boundary fails
"ultra-think"       ← hyphen breaks boundary match
```

**Best practice:** Put `ultrathink` at the start of the request so it's read
before any context that might constrain thinking:

```
ultrathink: given the entire src/payments/ module, design a migration from
Stripe v2 to Stripe v3 that handles all existing webhook types, preserves
idempotency, and requires zero downtime. Read all relevant files first.
```

### The Thinking Budget

Adaptive thinking budgets scale with model and context. On `claude-opus-4-6`:
- Normal prompt: 0 thinking tokens (thinking hidden)
- Regular prompt with thinking enabled: 1k–8k tokens (model decides)
- `ultrathink` keyword: maximum budget (model decides to max out)
- `MAX_THINKING_TOKENS=0` env var: **disables all thinking**

Do not set `MAX_THINKING_TOKENS=0` in production. The model on Opus 4.6 performs
significantly better with adaptive thinking enabled.

---

## 3. The Optimal CLAUDE.md Setup

### Architecture: The 4-Level Hierarchy

```
src/utils/claudemd.ts:1–26

Priority order (later = higher priority):
  1. /etc/claude-code/CLAUDE.md     ← MDM-managed enterprise policy
  2. ~/.claude/CLAUDE.md            ← Your personal global instructions
  3. {project}/CLAUDE.md            ← Project-specific instructions
  4. {project}/CLAUDE.local.md      ← Private, gitignored overrides
```

**Key rules from source (`claudemd.ts:254–279`):**
- Files inside `.claude/rules/*.md` can have a `paths:` frontmatter that restricts
  them to only load when you're working on matching files
- `@include` directives compose knowledge from other files
- Max 40,000 characters total across all loaded files
- Later files in the hierarchy override earlier ones

### What to Put at Each Level

#### `~/.claude/CLAUDE.md` — Your Global Identity

This is loaded for **every project**. Keep it about *you*, not any specific codebase.

```markdown
## My Role
I am a senior full-stack engineer focused on correctness over speed.

## Communication Style
- Always show me the output of verification steps
- Do not hedge confirmed results — if tests pass, say so plainly
- When you find something unexpected, say so before fixing it

## Git Conventions
- Commit format: `<type>: <scope> - <short summary>`
- Types: feat, fix, docs, refactor, test, chore
- Always create new commits, never amend without asking

## Behavior I want
- Read files before modifying them (you already do this, keep it)
- When a task has multiple independent parts, do them in parallel
- After any significant change, run the test suite and show me output
- If you're about to do something irreversible, tell me what it is first

## Behavior I don't want
- Don't add unsolicited comments, docstrings, or type annotations
- Don't over-engineer. Three similar lines beat a premature abstraction
- Don't add error handling for things that can't happen
- Don't summarize what you just did — I can read the diff
```

#### `{project}/CLAUDE.md` — Project Context

This is loaded for everyone on the project (checked in to git). Write for any
new team member using Claude Code on this codebase.

```markdown
## Project: [Name]

## Tech Stack
- Runtime: Node.js 22, TypeScript 5.4
- Framework: Next.js 15 App Router
- Database: PostgreSQL 16 via Prisma ORM
- Testing: Vitest + Playwright for E2E
- CI: GitHub Actions

## Architecture
- `src/app/` — Next.js app router pages/layouts
- `src/server/` — tRPC routers (all business logic lives here)
- `src/db/` — Prisma schema + migrations
- `src/lib/` — Shared utilities

## Development Commands
```bash
pnpm dev          # Start dev server (port 3000)
pnpm test         # Run unit tests
pnpm test:e2e     # Run Playwright tests
pnpm db:push      # Push schema changes (dev only)
pnpm db:migrate   # Create + apply migration (production)
```

## Code Conventions
- All database access goes through Prisma, never raw SQL
- All API endpoints use tRPC, never `app/api/` routes
- Error handling: throw `TRPCError` in server code, let tRPC handle serialization
- Tests colocated with source: `src/server/users.ts` → `src/server/users.test.ts`

## What Requires My Approval
- Any change to `src/db/schema.prisma`
- Any change to `src/server/auth.ts`
- Creating new database migrations
- Changing any environment variable names
```

#### `{project}/CLAUDE.local.md` — Private Overrides

Gitignored. For personal preferences on this project.

```markdown
## My Local Setup
- I run postgres locally on port 5433 (not 5432)
- My test user: test@local.dev / password123

## Permissions for This Session
- You may push to feature/* branches without asking me
- You may run `pnpm test` and `pnpm build` without asking
- You may create/delete files under src/ without asking

## Active Task Context
- We are migrating from tRPC v10 to v11
- Do not use the `router` from tRPC v10 patterns
- Use `createTRPCRouter` from `@trpc/server` v11
```

### The @include Pattern for Shared Rules

```markdown
<!-- In CLAUDE.md -->
@.claude/rules/testing.md
@.claude/rules/security.md
@~/.claude/snippets/git-conventions.md
```

```markdown
<!-- .claude/rules/testing.md -->
---
paths:
  - src/**/*.test.ts
  - tests/**/*.spec.ts
---

## Test File Rules
- Use `describe` + `it` blocks, not top-level `test()`
- Mock only at system boundaries (HTTP, DB, filesystem)
- Never mock internal modules
- Each test must be fully independent — no shared mutable state
```

### The 200-Line / 25KB MEMORY.md Limit

The auto-memory system (`src/memdir/memdir.ts:35–38`) enforces:
- Max 200 lines in `MEMORY.md` (the entrypoint index)
- Max 25,000 bytes

Beyond these limits, the memory system appends a warning:
```
WARNING: MEMORY.md is too long. Only part of it was loaded.
Keep index entries to one line under ~200 chars; move detail into topic files.
```

**Design pattern:** Use `MEMORY.md` as an index only. Put detail in topic files
that are `@include`'d or linked:

```markdown
<!-- MEMORY.md — index only, one line per entry -->
- [User profile](memory/user.md) — senior FE engineer, prefers TS, dislikes over-abstraction
- [Feedback: no trailing summaries](memory/feedback.md) — confirmed preference 2026-03-15
- [Project: payment migration](memory/project_stripe.md) — v2→v3, deadline 2026-05-01
```

---

## 4. High-Quality Prompt Patterns

### Pattern 1 — Scope-First, Then Task

The model is trained to "read first" (`prompts.ts:230`). Help it by declaring scope upfront:

```
# Weak
Fix the bug in the payment flow

# Strong
The bug is in src/server/payments/checkout.ts — specifically in the
`createPaymentIntent` function (around line 87). When the user has a
saved card and applies a coupon, the final amount is calculated before
the coupon discount is applied. Fix it. Read the full function and the
related `applyCoupon` util in src/lib/coupon.ts before changing anything.
```

### Pattern 2 — Task + Verification Instruction

The model's verification mandate (`prompts.ts:211`) means it will verify. Help it
verify the right thing:

```
# Weak
Implement the user search endpoint

# Strong
Implement the user search endpoint at POST /api/users/search.
Requirements:
- Accepts { query: string, page: number, limit: number }
- Returns { users: User[], total: number, hasMore: boolean }
- Query matches on name OR email (case-insensitive)
- Limit capped at 100

When done:
1. Run `pnpm test src/server/users` and show me the output
2. Check for TypeScript errors with `pnpm tsc --noEmit`
3. Tell me if either step fails
```

### Pattern 3 — Ultrathink for Architecture

Use ultrathink when the answer requires holding many constraints simultaneously:

```
ultrathink:

We have a monolithic Express app (src/) that serves 50k req/day. I need to
extract the notifications system (src/notifications/) into a separate service
that communicates via Redis pub/sub. The main app must continue working during
and after the migration.

Constraints:
- Zero downtime — must be feature-flagged
- The notifications service must be independently deployable
- Existing notification types: email, SMS, push (3 separate providers)
- The main app currently calls notifications inline in request handlers

Read src/notifications/ fully, then design the migration strategy including:
1. The new service interface (what Redis channels/schemas)
2. The feature flag strategy for gradual rollout
3. The order of operations for extraction
4. What breaks if the notifications service is down
```

### Pattern 4 — Parallel Exploration

The model is explicitly trained to parallelize (`prompts.ts:310`). You can ask for it:

```
Explore the authentication system. In parallel:
1. Read all files in src/auth/ and summarize what each does
2. Find all places in the codebase that call `verifyToken()` 
3. Find all tests in tests/ that cover authentication

Report findings from all three before proposing any changes.
```

### Pattern 5 — Diagnosis Mode

For bug investigations, trigger the diagnosis doctrine (`prompts.ts:233`):

```
The checkout flow throws "Cannot read property 'price' of undefined" in
production. This only happens for users with saved payment methods (not guests).

Do a root cause investigation:
1. Read the checkout flow starting from src/pages/checkout.tsx
2. Trace the data flow to find where `price` could be undefined
3. Check if there's a difference in how saved-card vs guest checkouts
   construct the order object
4. Do NOT fix anything yet — just tell me what you found and your theory
```

### Pattern 6 — Constrained Implementation

When you want the model to stay in strict scope:

```
Add a `deletedAt` soft-delete column to the users table.

Scope:
- Only change src/db/schema.prisma and the auto-generated migration
- Only update src/server/users.ts to exclude soft-deleted users from queries
- Do NOT change any other files

Do NOT:
- Add audit logging
- Add a restore endpoint (I'll do that separately)
- Modify the auth system
```

### Pattern 7 — Data Engineering Prompts

For data work, context about types and volumes matters more than code style:

```
ultrathink:

I need a data pipeline to ingest Stripe webhook events into our analytics
warehouse (BigQuery). 

Current state:
- Webhooks arrive at POST /webhooks/stripe (src/webhooks/stripe.ts)
- We currently only log them (console.log)
- BigQuery project: analytics-prod, dataset: events

Events to handle:
- payment_intent.succeeded
- payment_intent.payment_failed
- customer.subscription.updated
- customer.subscription.deleted

Requirements:
- Idempotent (Stripe retries webhooks on failure)
- Schema evolution safe (new Stripe fields shouldn't break ingestion)
- Latency: < 30s from webhook to BigQuery
- Must not block the HTTP response (fire-and-forget is fine)

Read src/webhooks/stripe.ts first. Then design the ingestion schema
(BigQuery table definitions) and the transformation logic.
Show me the BigQuery schema DDL before writing any TypeScript.
```

---

## 5. Tool Usage for Best Results

### The Tool Preference Hierarchy

The model is explicitly taught this hierarchy (`prompts.ts:291–301`):

```
Dedicated tools > Bash
  Read     > cat / head / tail / sed
  Edit     > sed / awk
  Write    > echo > file / heredoc
  Glob     > find / ls
  Grep     > grep / rg
  Bash     > only for shell commands that have no dedicated tool
```

**Why this matters for quality:** Dedicated tools have structured output that the
model can reason about more reliably than raw terminal output. `FileRead` returns
content with line numbers. `Grep` returns structured match results. `Bash(grep ...)`
returns raw text that the model must parse.

### Making Parallel Tool Calls Explicit

The model will parallelize when it can figure out independence. Help it:

```
# Weak (model must infer parallelizability)
"Read the auth files and the payment files"

# Strong (model knows immediately)
"In parallel: read src/auth/jwt.ts and src/payments/stripe.ts"
```

### The TodoWrite Tool — Task Tracking

`TodoWriteTool` enables structured task tracking that shows in the UI.
Trigger it for multi-step tasks by structuring your request as a list:

```
Here are the tasks for the auth refactor:
1. Migrate JWT secret from env var to AWS Secrets Manager
2. Update all token verification calls to use the new client
3. Add rotation support
4. Write tests for rotation

Start on task 1. Use the task tracking tool to show progress.
```

The model is explicitly told (`prompts.ts:308`):
```
Break down and manage your work with the TaskCreate tool.
Mark each task as completed as soon as you are done with the task.
Do not batch up multiple tasks before marking them as completed.
```

### FileRead — Getting the Most Out of It

The model knows about line-range reads. You can direct it:

```
# Tell the model exactly what you want it to read
Read src/auth/jwt.ts lines 80-150 (the token refresh logic)
```

For large files, the model will paginate automatically. If you need it to
read the whole file:
```
Read the entire src/payments/checkout.ts — all of it, not just the first section
```

### Bash — When to Use It

Use Bash explicitly when:
- Running the test suite: `run "pnpm test" and show me the full output`
- Checking types: `run "pnpm tsc --noEmit" and paste the errors`
- Database operations: `run the migration with "pnpm db:migrate"`
- Process inspection: `run "ps aux | grep node" to see what's running`

Do **not** use Bash for file reading, searching, or editing — it pollutes the
context with ANSI codes and raw output the model has to strip.

### WebSearch and WebFetch

```
# Effective WebSearch usage
"Search for 'Stripe webhook idempotency best practices 2025' and summarize the
key points relevant to our checkout flow"

# Effective WebFetch — be specific about what to extract
"Fetch https://stripe.com/docs/webhooks/best-practices and extract only the
section on idempotency keys"
```

---

## 6. Permission Rules That Unlock Speed

### How Rules Work

Rules are stored in `~/.claude/settings.json` or `.claude/settings.json` and
matched before the permission prompt. From `src/hooks/toolPermission/`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(npm test)",
      "Bash(pnpm test *)",
      "Bash(pnpm tsc *)",
      "FileRead(*)",
      "FileEdit(src/*)",
      "Glob(*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf *)",
      "Bash(DROP TABLE*)"
    ]
  }
}
```

### The Rule Precedence

```
DENY → always blocks (checked first)
ALLOW → auto-approves if not in deny
no match → prompt user
```

### High-Performance Permission Set

For a typical development project, these rules eliminate almost all permission
prompts without sacrificing safety:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git add*)",
      "Bash(git checkout*)",
      "Bash(git branch*)",
      "Bash(git stash*)",
      "Bash(npm run*)",
      "Bash(pnpm run*)",
      "Bash(pnpm test*)",
      "Bash(pnpm build*)",
      "Bash(pnpm tsc*)",
      "Bash(npx tsc*)",
      "Bash(npx vitest*)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(ls *)",
      "Bash(find . *)",
      "Bash(rg *)",
      "Bash(grep *)",
      "FileRead(*)",
      "FileEdit(src/*)",
      "FileEdit(tests/*)",
      "FileEdit(*.md)",
      "FileWrite(src/*)",
      "FileWrite(tests/*)",
      "Glob(*)",
      "WebSearch(*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(git reset --hard*)",
      "Bash(git clean -f*)",
      "Bash(rm -rf*)",
      "Bash(sudo *)",
      "Bash(DROP *)",
      "Bash(DELETE FROM *)"
    ]
  }
}
```

### Embedding Authorization in CLAUDE.md

For project-wide authorizations that the model reads as part of context:

```markdown
## Authorized Actions (no confirmation needed)
- Run the test suite: `pnpm test` and `pnpm test:e2e`
- Run type checks: `pnpm tsc --noEmit`
- Create/edit files under src/ and tests/
- Create new git branches and commits
- Run database migrations in development (not production)

## Always Confirm
- Pushing to any remote branch
- Changes to prisma/schema.prisma
- Any operation on the production database
- Deleting files (not creating)
```

---

## 7. The Agent/Fork System

### Source Evidence: When to Fork vs Spawn

```
src/tools/AgentTool/prompt.ts:81–95

Fork yourself (omit subagent_type) when the intermediate tool output isn't
worth keeping in your context. The criterion is qualitative — "will I need
this output again" — not task size.

- Research: fork open-ended questions.
- Implementation: prefer to fork implementation work that requires more than
  a couple of edits.

Forks are cheap because they share your prompt cache.
Don't set model on a fork — a different model can't reuse the parent's cache.
```

### Fork vs Subagent Decision

| Situation | Use | Why |
|---|---|---|
| "Explore this directory and summarize" | Fork (no subagent_type) | Output won't be needed again; keeps parent context clean |
| "Find all uses of X and tell me" | Fork | Research output; parent only needs the summary |
| Code review of a PR | Specialized subagent (`code-reviewer`) | Specialized agent has tuned prompts |
| Explore a large codebase | Specialized subagent (`Explore`) | Has dedicated search patterns |
| Multi-step refactor | Fork or direct | Depends on whether you need the intermediate outputs |

### Writing Agent Prompts — Source Doctrine

From `src/tools/AgentTool/prompt.ts:99–112`:

```
Brief the agent like a smart colleague who just walked into the room —
it hasn't seen this conversation, doesn't know what you've tried,
doesn't understand why this task matters.

Never delegate understanding. Don't write "based on your findings,
fix the bug" or "based on the research, implement it." Those phrases
push synthesis onto the agent instead of doing it yourself. Write
prompts that prove you understood: include file paths, line numbers,
what specifically to change.
```

**Template for a good agent prompt:**

```
Agent task: Review the checkout flow for security vulnerabilities

Context you need:
- This is a Next.js/tRPC app
- The checkout flow is in src/server/payments/checkout.ts
- We handle payments via Stripe (using their webhook verification)
- The vulnerability report mentioned "insufficient input validation on
  line-item amounts"

Your job:
1. Read src/server/payments/checkout.ts fully
2. Read src/server/payments/validation.ts
3. Find all places where user-supplied amounts are used without validation
4. Check if a user could manipulate the final charge amount

Report in under 300 words. List each finding with file:line and severity.
Do NOT fix anything — just find and report.
```

### When NOT to Use Agents

From `src/tools/AgentTool/prompt.ts:232–240` (verbatim model instruction):

```
When NOT to use the Agent tool:
- If you want to read a specific file path, use FileRead instead
- If you are searching for a specific class definition, use Glob/Grep instead
- If you are searching code within 2-3 files, use Read instead
- Other tasks that are not related to the agent descriptions
```

Agents have overhead. Use them for tasks that genuinely need parallelism or
specialized behavior, not as a default for every subtask.

---

## 8. Memory Architecture for Long Sessions

### The Four Memory Types

From `src/memdir/memdir.ts:199–265`:

| Type | File | What to store |
|---|---|---|
| `user` | `~/.claude/MEMORY.md` | Role, preferences, expertise, working style |
| `feedback` | Individual files | Corrections, confirmed approaches, anti-patterns |
| `project` | Individual files | Architecture decisions, deadlines, stakeholder context |
| `reference` | Individual files | Where things live in external systems |

**What NOT to store** (from source):
- Code patterns (read the code)
- Git history (use `git log`)
- Debugging solutions (in the commit message)
- Anything already in CLAUDE.md

### Triggering Auto-Memory

Use the `/remember` skill to organize memory explicitly:

```
/remember that we decided to use Redis for the session store because
PostgreSQL was showing lock contention at >500 concurrent sessions.
This is a project-level architecture decision, not a user preference.
```

The `remember` skill (`src/skills/bundled/remember.ts:57–62`):
1. Reads all memory layers
2. Classifies each entry
3. **Presents ALL proposals before making any changes**
4. Does NOT modify files without explicit approval

### MEMORY.md Index Pattern

Keep `MEMORY.md` as a one-line-per-entry index. Use 150 chars max per line:

```markdown
---
name: Project Memory Index
description: Pointers to all memory files for this project
type: user
---

- [User profile](memory/user.md) — senior BE engineer, Go expert, new to React
- [Feedback: concise responses](memory/feedback_terse.md) — no trailing summaries
- [Project: auth rewrite](memory/project_auth.md) — JWT→OAuth2, deadline 2026-06-01
- [Reference: Linear project](memory/ref_linear.md) — AUTH board for all auth tickets
```

---

## 9. Anti-Patterns — What Kills Quality

### Anti-Pattern 1 — Vague Task Descriptions

```
# Kills quality
"Clean up the auth code"
"Make the tests better"
"Fix the performance issue"

# Better
"The auth code in src/auth/ has duplicate token verification logic in
jwt.ts and middleware.ts. Consolidate them. Read both files first."
```

### Anti-Pattern 2 — Asking for Too Much in One Prompt

The model is a single conversation thread. Overloaded prompts produce shallow work:

```
# Too much (model will skim)
"Refactor the entire payments module, add comprehensive tests, update
the docs, fix the three open bugs, and add the new Stripe v3 support"

# Better — break it up
Turn 1: "ultrathink: design the refactor plan for payments module"
Turn 2: "Implement phase 1 from the plan: [specific items]"
Turn 3: "Add tests for the changes just made"
```

### Anti-Pattern 3 — Fighting the Read-First Doctrine

The model reads before modifying. Don't add prompts that tell it to skip this:

```
# Counterproductive
"Don't read all the files, just make the change to add the field"
(Model will read anyway, but now it's confused about your intent)

# Better
"Add the `updatedAt` field to User in src/db/schema.prisma only.
Read that file first to see the current schema format."
```

### Anti-Pattern 4 — Suppressing Verification

The model is trained to verify. Telling it to skip verification kills quality:

```
# Bad
"Don't bother running the tests, just implement it"

# Good
"Implement it, then run pnpm test and show me the output"
```

### Anti-Pattern 5 — Ultrathink on Simple Tasks

Ultrathink adds latency (model generates extended thinking tokens). On simple tasks:

```
# Wastes time
"ultrathink: add a console.log to debug this function"
"ultrathink: rename this variable"

# Just ask directly
"Add console.log(userId) before line 47 in src/server/auth.ts"
```

### Anti-Pattern 6 — Context Window Pollution

Long sessions accumulate tool output. Use `/compact` proactively:

```
# After a long exploration session, before starting implementation:
/compact
"Now implement [the thing we designed]"
```

The auto-compact threshold is `13,000 tokens reserve` (`src/services/compact/autoCompact.ts`).
Don't wait for auto-compact — it runs a full summarization API call that costs tokens.
Use `/compact` yourself at natural transition points.

### Anti-Pattern 7 — Ambiguous Authorization

The model's authorization is **scoped** (`prompts.ts:258`):
```
Authorization stands for the scope specified, not beyond.
A user approving an action once does NOT mean they approve it in all contexts.
```

```
# Creates repeated prompts
"You can push code"
(Model will still ask for every push because scope is unclear)

# Better — explicit scope
"You may push to feature/* branches without asking me.
You must always ask before pushing to main or staging."
```

---

## 10. Full Example: Production-Grade CLAUDE.md

This is a complete CLAUDE.md for a TypeScript/Next.js project.
Based on the source patterns above, it's structured to maximize quality and minimize friction.

```markdown
# Project: Acme Platform

## Stack
- Next.js 15 App Router (TypeScript 5.4, strict mode)
- tRPC v11 for all API routes
- Prisma ORM + PostgreSQL 16
- Vitest (unit) + Playwright (E2E)
- Deployed to Vercel + Railway

## Directory Map
- `src/app/`         — Pages, layouts (no business logic)
- `src/server/`      — tRPC routers (all business logic lives here)
- `src/db/`          — Prisma schema + seed data
- `src/lib/`         — Pure utilities (no side effects, no DB)
- `src/components/`  — React components (no server code)
- `tests/e2e/`       — Playwright tests

## Development Commands
```bash
pnpm dev             # Dev server (localhost:3000)
pnpm test            # Unit tests (Vitest)
pnpm test:e2e        # E2E tests (Playwright, requires pnpm dev)
pnpm tsc --noEmit    # Type check (no compilation)
pnpm db:push         # Apply schema changes (dev only — no migration file)
pnpm db:migrate dev  # Create + apply migration (staging/prod use deploy)
pnpm lint            # Biome linter
```

## Code Conventions

### TypeScript
- Never use `any`. Use `unknown` + type guard, or a specific type.
- Prefer `type` over `interface` for object shapes (except when extending)
- All async functions must have explicit return types

### tRPC
- All input validated with Zod. All output typed.
- Errors via `throw new TRPCError({ code: 'BAD_REQUEST', message: '...' })`
- No raw HTTP responses — everything goes through tRPC

### Database
- All queries through Prisma — no raw SQL
- Migrations via `pnpm db:migrate dev` — never `db:push` on staging/prod
- Every new table needs a `createdAt DateTime @default(now())` and `updatedAt DateTime @updatedAt`

### Testing
- Unit tests colocated: `src/server/users.ts` → `src/server/users.test.ts`
- Mock only external boundaries (HTTP calls, email service) — never mock internal modules
- Every bug fix needs a regression test

## What Always Requires My Approval
- Pushing to any remote branch
- Any change to `src/db/schema.prisma`
- Any change to `src/server/auth/`
- Running database migrations in non-local environments

## What You May Do Without Asking
- Read any file
- Edit files under `src/` and `tests/`
- Create/delete files under `src/` and `tests/`
- Create git commits and local branches
- Run `pnpm test`, `pnpm build`, `pnpm tsc --noEmit`, `pnpm lint`

## Verification Requirements
After ANY code change:
1. Run `pnpm tsc --noEmit` — show me the output
2. Run `pnpm test` — show me the output
3. If either fails, fix it before declaring done

After a database schema change:
1. Run `pnpm db:push` to test locally
2. Tell me what migration command would be needed for staging

## Active Context
- Migrating from tRPC v10 to v11 (do not use the old `router()` pattern)
- Stripe webhook handling is being rewritten (don't touch `src/server/payments/webhooks.ts`)
```

---

## 11. Full Example: High-Performance Prompts

### Prompt Template: Feature Implementation

```
[Feature name]: [one-line description]

Context:
- [Where it fits in the system]
- [Related existing code to read first: file paths]
- [What it connects to]

Requirements:
1. [Specific requirement]
2. [Specific requirement]
3. [Specific requirement]

Constraints:
- [What NOT to change]
- [Performance/security requirements]

Verification:
- Run pnpm test [path] and show me the output
- Run pnpm tsc --noEmit and show me any errors
```

### Prompt Template: Bug Investigation

```
Bug: [one-line description]

Symptoms:
- [What happens]
- [When it happens]
- [What doesn't happen (if relevant)]

Reproduction:
- [Steps to reproduce, or "not reproducible locally"]

Relevant files (start here):
- [file:line range where the bug likely is]

Investigation approach:
1. Read [specific files] first
2. Trace the data flow from [entry point] to [error point]
3. Identify what condition causes [symptom]
4. Do NOT fix yet — tell me what you found and your theory

If the root cause is in a different file than expected, tell me before digging in.
```

### Prompt Template: Data Pipeline Design

```
ultrathink:

Pipeline: [name and purpose]

Data source: [where data comes from, format, volume]
Data destination: [where it goes, format, SLAs]

Inputs:
- [Schema/structure of input data]
- [Volume: N records/hour or N GB/day]
- [Frequency: real-time / batch / triggered]

Requirements:
- [Correctness requirement: idempotency, ordering, etc.]
- [Latency requirement]
- [Error handling requirement]
- [Monitoring requirement]

Read [relevant existing files] first.

Deliver in this order:
1. Schema design (input, output, intermediate if any)
2. Transformation logic with edge cases
3. Error handling strategy
4. Monitoring approach

Show me the schema before writing any code.
```

### Prompt Template: Security Review

```
ultrathink:

Security review of: [component name]
Files to review: [list of files]

Known risks to check:
- [Specific concern 1, e.g., SQL injection in search queries]
- [Specific concern 2, e.g., SSRF in URL fetch]
- [Specific concern 3, e.g., mass assignment]

Also check for OWASP Top 10 issues relevant to this component.

For each finding:
- File:line reference
- Severity: Critical / High / Medium / Low
- Description of the vulnerability
- Example exploit scenario
- Recommended fix (but don't implement yet)

Report format: numbered list, highest severity first.
```

---

## 12. Source Reference Index

| Topic | Source File | Lines |
|---|---|---|
| Model identity instruction | `src/constants/prompts.ts` | 175–184 |
| Code minimalism doctrine | `src/constants/prompts.ts` | 200–213 |
| Read-before-modify doctrine | `src/constants/prompts.ts` | 230 |
| Diagnosis-before-retry | `src/constants/prompts.ts` | 233 |
| Honest outcome reporting | `src/constants/prompts.ts` | 240 |
| Reversibility-first doctrine | `src/constants/prompts.ts` | 255–267 |
| Verification mandate | `src/constants/prompts.ts` | 211 |
| Tool preference hierarchy | `src/constants/prompts.ts` | 291–301 |
| Parallel tool calls | `src/constants/prompts.ts` | 310 |
| TodoWrite guidance | `src/constants/prompts.ts` | 308 |
| Ultrathink feature gate | `src/utils/thinking.ts` | 19–24 |
| Ultrathink keyword detection | `src/utils/thinking.ts` | 29–31 |
| Adaptive thinking model support | `src/utils/thinking.ts` | 113–144 |
| Thinking enabled by default | `src/utils/thinking.ts` | 146–162 |
| CLAUDE.md hierarchy | `src/utils/claudemd.ts` | 1–26 |
| @include directive | `src/utils/claudemd.ts` | 18–25 |
| Conditional rules (paths:) | `src/utils/claudemd.ts` | 254–279 |
| MEMORY.md size limits | `src/memdir/memdir.ts` | 35–38 |
| Memory type taxonomy | `src/memdir/memdir.ts` | 199–265 |
| Memory not for code patterns | `src/memdir/memdir.ts` | 241 |
| Fork semantics | `src/tools/AgentTool/prompt.ts` | 81–96 |
| Agent prompt writing doctrine | `src/tools/AgentTool/prompt.ts` | 99–113 |
| When NOT to use agents | `src/tools/AgentTool/prompt.ts` | 232–240 |
| Agent list cache optimization | `src/tools/AgentTool/prompt.ts` | 55–64 |
| Permission rule precedence | `src/hooks/toolPermission/` | — |
| Auto-compact threshold | `src/services/compact/autoCompact.ts` | 28–91 |
| System prompt cache boundary | `src/constants/prompts.ts` | 114–115 |
| Channel A: git context | `src/context.ts` | 116–150 |
| Channel B: CLAUDE.md injection | `src/context.ts` | 155–189 |

---

*Based on full source analysis of `/Users/dangnguyen/claude_code_cli/src/` · April 2026*
*Every recommendation in this guide has a source citation. No guessing.*
