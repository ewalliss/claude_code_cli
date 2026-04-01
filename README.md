<div align="center">

# Claude Code CLI

[![TypeScript](https://img.shields.io/badge/TypeScript-512K%2B_lines-3178C6?logo=typescript&logoColor=white)](#tech-stack)
[![Bun](https://img.shields.io/badge/Runtime-Bun-f472b6?logo=bun&logoColor=white)](#tech-stack)
[![Files](https://img.shields.io/badge/~1,900_files-source_only-grey)](#directory-structure)
[![MCP Server](https://img.shields.io/badge/MCP-Explorer_Server-blueviolet)](#-explore-with-mcp-server)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

</div>

> The raw imported snapshot is preserved in this repository's [`backup` branch](https://github.com/TaGoat/claude_code_cli/tree/backup). The `main` branch contains added documentation, tooling, and repository metadata.

---

## Table of Contents

- [What Is Claude Code?](#what-is-claude-code)
- [Documentation](#-documentation)
- [Explore with MCP Server](#-explore-with-mcp-server)
- [Directory Structure](#directory-structure)
- [Architecture](#architecture)
  - [Tool System](#1-tool-system)
  - [Command System](#2-command-system)
  - [Service Layer](#3-service-layer)
  - [Bridge System](#4-bridge-system)
  - [Permission System](#5-permission-system)
  - [Feature Flags](#6-feature-flags)
- [Key Files](#key-files)
- [Tech Stack](#tech-stack)
- [Design Patterns](#design-patterns)
- [GitPretty Setup](#gitpretty-setup)
- [The Optimal CLAUDE.md Setup](#the-optimal-CLAUDE.md-setup)
- [High-Quality Prompt Patterns](#high-quality-prompt-patterns)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)

---

## What Is Claude Code?

Claude Code is an official CLI tool for interacting with Claude directly from the terminal: editing files, running commands, searching codebases, managing git workflows, and more.

| | |
|---|---|
| **Language** | TypeScript (strict) |
| **Runtime** | [Bun](https://bun.sh) |
| **Terminal UI** | [React](https://react.dev) + [Ink](https://github.com/vadimdemedes/ink) |
| **Scale** | ~1,900 files · 512,000+ lines of code |

---

## Documentation

For in-depth guides, see the [`docs/`](docs/) directory:

| Guide | Description |
|-------|-------------|
| **[Architecture](docs/architecture.md)** | Core pipeline, startup sequence, state management, rendering, data flow |
| **[Tools Reference](docs/tools.md)** | Complete catalog of all ~40 agent tools with categories and permission model |
| **[Commands Reference](docs/commands.md)** | All ~85 slash commands organized by category |
| **[Subsystems Guide](docs/subsystems.md)** | Deep dives into Bridge, MCP, Permissions, Plugins, Skills, Tasks, Memory, Voice |
| **[Exploration Guide](docs/exploration-guide.md)** | How to navigate the codebase — study paths, grep patterns, key files |

Also see: [CONTRIBUTING.md](CONTRIBUTING.md) · [MCP Server README](mcp-server/README.md)

---

## Explore with MCP Server

This repo also ships an [MCP server](https://modelcontextprotocol.io/) that lets any MCP-compatible client (Claude Code, Claude Desktop, VS Code Copilot, Cursor) explore the codebase interactively.

### Install from npm

The MCP server is published as [`claude-code-explorer-mcp`](https://www.npmjs.com/package/claude-code-explorer-mcp) on npm — no need to clone the repo:

```bash
# Claude Code
claude mcp add claude-code-explorer -- npx -y claude-code-explorer-mcp
```

### One-liner setup (from source)

```bash
git clone https://github.com/TaGoat/claude_code_cli.git ~/claude_code_cli \
  && cd ~/claude_code_cli/mcp-server \
  && npm install && npm run build \
  && claude mcp add claude-code-explorer -- node ~/claude_code_cli/mcp-server/dist/index.js
```

<details>
<summary><strong>Step-by-step setup</strong></summary>

```bash
# 1. Clone the repo
git clone https://github.com/TaGoat/claude_code_cli.git
cd claude_code_cli/mcp-server

# 2. Install & build
npm install && npm run build

# 3. Register with Claude Code
claude mcp add claude-code-explorer -- node /absolute/path/to/claude-code-source-code/mcp-server/dist/index.js
```

Replace `/absolute/path/to/claude-code-source-code` with your actual clone path.

</details>

<details>
<summary><strong>VS Code / Cursor / Claude Desktop config</strong></summary>

**VS Code** — add to `.vscode/mcp.json`:
```json
{
  "servers": {
    "claude-code-explorer": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/mcp-server/dist/index.js"],
      "env": { "CLAUDE_CODE_SRC_ROOT": "${workspaceFolder}/src" }
    }
  }
}
```

**Claude Desktop** — add to your config file:
```json
{
  "mcpServers": {
    "claude-code-explorer": {
      "command": "node",
      "args": ["/absolute/path/to/claude-code-source-code/mcp-server/dist/index.js"],
      "env": { "CLAUDE_CODE_SRC_ROOT": "/absolute/path/to/claude-code-source-code/src" }
    }
  }
}
```

**Cursor** — add to `~/.cursor/mcp.json` (same format as Claude Desktop).

</details>

### Available tools & prompts

| Tool | Description |
|------|-------------|
| `list_tools` | List all ~40 agent tools with source files |
| `list_commands` | List all ~50 slash commands with source files |
| `get_tool_source` | Read full source of any tool (e.g. BashTool, FileEditTool) |
| `get_command_source` | Read source of any slash command (e.g. review, mcp) |
| `read_source_file` | Read any file from `src/` by path |
| `search_source` | Grep across the entire source tree |
| `list_directory` | Browse `src/` directories |
| `get_architecture` | High-level architecture overview |

| Prompt | Description |
|--------|-------------|
| `explain_tool` | Deep-dive into how a specific tool works |
| `explain_command` | Understand a slash command's implementation |
| `architecture_overview` | Guided tour of the full architecture |
| `how_does_it_work` | Explain any subsystem (permissions, MCP, bridge, etc.) |
| `compare_tools` | Side-by-side comparison of two tools |

**Try asking:** *"How does the BashTool work?"* · *"Search for where permissions are checked"* · *"Show me the /review command source"*

### Custom source path / Remove

```bash
# Custom source location
claude mcp add claude-code-explorer -e CLAUDE_CODE_SRC_ROOT=/path/to/src -- node /path/to/mcp-server/dist/index.js

# Remove
claude mcp remove claude-code-explorer
```

---

## Directory Structure

```
src/
├── main.tsx                 # Entrypoint — Commander.js CLI parser + React/Ink renderer
├── QueryEngine.ts           # Core LLM API caller (~46K lines)
├── Tool.ts                  # Tool type definitions (~29K lines)
├── commands.ts              # Command registry (~25K lines)
├── tools.ts                 # Tool registry
├── context.ts               # System/user context collection
├── cost-tracker.ts          # Token cost tracking
│
├── tools/                   # Agent tool implementations (~40)
├── commands/                # Slash command implementations (~50)
├── components/              # Ink UI components (~140)
├── services/                # External service integrations
├── hooks/                   # React hooks (incl. permission checks)
├── types/                   # TypeScript type definitions
├── utils/                   # Utility functions
├── screens/                 # Full-screen UIs (Doctor, REPL, Resume)
│
├── bridge/                  # IDE integration (VS Code, JetBrains)
├── coordinator/             # Multi-agent orchestration
├── plugins/                 # Plugin system
├── skills/                  # Skill system
├── server/                  # Server mode
├── remote/                  # Remote sessions
├── memdir/                  # Persistent memory directory
├── tasks/                   # Task management
├── state/                   # State management
│
├── voice/                   # Voice input
├── vim/                     # Vim mode
├── keybindings/             # Keybinding configuration
├── schemas/                 # Config schemas (Zod)
├── migrations/              # Config migrations
├── entrypoints/             # Initialization logic
├── query/                   # Query pipeline
├── ink/                     # Ink renderer wrapper
├── buddy/                   # Companion sprite (Easter egg 🐣)
├── native-ts/               # Native TypeScript utils
├── outputStyles/            # Output styling
└── upstreamproxy/           # Proxy configuration
```

---

## Architecture

### 1. Tool System

> `src/tools/` — Every tool Claude can invoke is a self-contained module with its own input schema, permission model, and execution logic.

| Tool | Description |
|---|---|
| **File I/O** | |
| `FileReadTool` | Read files (images, PDFs, notebooks) |
| `FileWriteTool` | Create / overwrite files |
| `FileEditTool` | Partial modification (string replacement) |
| `NotebookEditTool` | Jupyter notebook editing |
| **Search** | |
| `GlobTool` | File pattern matching |
| `GrepTool` | ripgrep-based content search |
| `WebSearchTool` | Web search |
| `WebFetchTool` | Fetch URL content |
| **Execution** | |
| `BashTool` | Shell command execution |
| `SkillTool` | Skill execution |
| `MCPTool` | MCP server tool invocation |
| `LSPTool` | Language Server Protocol integration |
| **Agents & Teams** | |
| `AgentTool` | Sub-agent spawning |
| `SendMessageTool` | Inter-agent messaging |
| `TeamCreateTool` / `TeamDeleteTool` | Team management |
| `TaskCreateTool` / `TaskUpdateTool` | Task management |
| **Mode & State** | |
| `EnterPlanModeTool` / `ExitPlanModeTool` | Plan mode toggle |
| `EnterWorktreeTool` / `ExitWorktreeTool` | Git worktree isolation |
| `ToolSearchTool` | Deferred tool discovery |
| `SleepTool` | Proactive mode wait |
| `CronCreateTool` | Scheduled triggers |
| `RemoteTriggerTool` | Remote trigger |
| `SyntheticOutputTool` | Structured output generation |

### 2. Command System

> `src/commands/` — User-facing slash commands invoked with `/` in the REPL.

| Command | Description | | Command | Description |
|---|---|---|---|---|
| `/commit` | Git commit | | `/memory` | Persistent memory |
| `/review` | Code review | | `/skills` | Skill management |
| `/compact` | Context compression | | `/tasks` | Task management |
| `/mcp` | MCP server management | | `/vim` | Vim mode toggle |
| `/config` | Settings | | `/diff` | View changes |
| `/doctor` | Environment diagnostics | | `/cost` | Check usage cost |
| `/login` / `/logout` | Auth | | `/theme` | Change theme |
| `/context` | Context visualization | | `/share` | Share session |
| `/pr_comments` | PR comments | | `/resume` | Restore session |
| `/desktop` | Desktop handoff | | `/mobile` | Mobile handoff |

### 3. Service Layer

> `src/services/` — External integrations and core infrastructure.

| Service | Description |
|---|---|
| `api/` | Anthropic API client, file API, bootstrap |
| `mcp/` | Model Context Protocol connection & management |
| `oauth/` | OAuth 2.0 authentication |
| `lsp/` | Language Server Protocol manager |
| `analytics/` | GrowthBook feature flags & analytics |
| `plugins/` | Plugin loader |
| `compact/` | Conversation context compression |
| `extractMemories/` | Automatic memory extraction |
| `teamMemorySync/` | Team memory synchronization |
| `tokenEstimation.ts` | Token count estimation |
| `policyLimits/` | Organization policy limits |
| `remoteManagedSettings/` | Remote managed settings |

### 4. Bridge System

> `src/bridge/` — Bidirectional communication layer connecting IDE extensions (VS Code, JetBrains) with the CLI.

Key files: `bridgeMain.ts` (main loop) · `bridgeMessaging.ts` (protocol) · `bridgePermissionCallbacks.ts` (permission callbacks) · `replBridge.ts` (REPL session) · `jwtUtils.ts` (JWT auth) · `sessionRunner.ts` (session execution)

### 5. Permission System

> `src/hooks/toolPermission/` — Checks permissions on every tool invocation.

Prompts the user for approval/denial or auto-resolves based on the configured permission mode: `default`, `plan`, `bypassPermissions`, `auto`, etc.

### 6. Feature Flags

Dead code elimination at build time via Bun's `bun:bundle`:

```typescript
import { feature } from 'bun:bundle'

const voiceCommand = feature('VOICE_MODE')
  ? require('./commands/voice/index.js').default
  : null
```

Notable flags: `PROACTIVE` · `KAIROS` · `BRIDGE_MODE` · `DAEMON` · `VOICE_MODE` · `AGENT_TRIGGERS` · `MONITOR_TOOL`

---

## Key Files

| File | Lines | Purpose |
|------|------:|---------|
| `QueryEngine.ts` | ~46K | Core LLM API engine — streaming, tool loops, thinking mode, retries, token counting |
| `Tool.ts` | ~29K | Base types/interfaces for all tools — input schemas, permissions, progress state |
| `commands.ts` | ~25K | Command registration & execution with conditional per-environment imports |
| `main.tsx` | — | CLI parser + React/Ink renderer; parallelizes MDM, keychain, and GrowthBook on startup |

---

## Tech Stack

| Category | Technology |
|---|---|
| Runtime | [Bun](https://bun.sh) |
| Language | TypeScript (strict) |
| Terminal UI | [React](https://react.dev) + [Ink](https://github.com/vadimdemedes/ink) |
| CLI Parsing | [Commander.js](https://github.com/tj/commander.js) (extra-typings) |
| Schema Validation | [Zod v4](https://zod.dev) |
| Code Search | [ripgrep](https://github.com/BurntSushi/ripgrep) (via GrepTool) |
| Protocols | [MCP SDK](https://modelcontextprotocol.io) · LSP |
| API | [Anthropic SDK](https://docs.anthropic.com) |
| Telemetry | OpenTelemetry + gRPC |
| Feature Flags | GrowthBook |
| Auth | OAuth 2.0 · JWT · macOS Keychain |

---

## Design Patterns

<details>
<summary><strong>Parallel Prefetch</strong> — Startup optimization</summary>

MDM settings, keychain reads, and API preconnect fire in parallel as side-effects before heavy module evaluation:

```typescript
// main.tsx
startMdmRawRead()
startKeychainPrefetch()
```

</details>

<details>
<summary><strong>Lazy Loading</strong> — Deferred heavy modules</summary>

OpenTelemetry (~400KB) and gRPC (~700KB) are loaded via dynamic `import()` only when needed.

</details>

<details>
<summary><strong>Agent Swarms</strong> — Multi-agent orchestration</summary>

Sub-agents spawn via `AgentTool`, with `coordinator/` handling orchestration. `TeamCreateTool` enables team-level parallel work.

</details>

<details>
<summary><strong>Skill System</strong> — Reusable workflows</summary>

Defined in `skills/` and executed through `SkillTool`. Users can add custom skills.

</details>

<details>
<summary><strong>Plugin Architecture</strong> — Extensibility</summary>

Built-in and third-party plugins loaded through the `plugins/` subsystem.

</details>

---

## GitPretty Setup

<details>
<summary>Show per-file emoji commit messages in GitHub's file UI</summary>

```bash
# Apply emoji commits
bash ./gitpretty-apply.sh .

# Optional: install hooks for future commits
bash ./gitpretty-apply.sh . --hooks

# Push as usual
git push origin main
```

</details>

---
## The Optimal CLAUDE.md Setup

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

## High-Quality Prompt Patterns

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

## Contributing

Contributions to Claude Code, the MCP server, and exploration tooling are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
