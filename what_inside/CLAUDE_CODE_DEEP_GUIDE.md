# Claude Code CLI — Deep Source Documentation

> **Based on full source mapping of `src/` (~1,900 files, 512K+ lines of TypeScript)**
> AI Engineer & Data Engineer Reference · April 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture: The Full Pipeline](#2-architecture-the-full-pipeline)
3. [Prompt Assembly System](#3-prompt-assembly-system)
4. [Tool System](#4-tool-system)
5. [BashTool — The Crown Jewel](#5-bashtool--the-crown-jewel)
6. [Feature Flags (58 Total)](#6-feature-flags-58-total)
7. [Unshipped Features — What Is Actually Built](#7-unshipped-features--what-is-actually-built)
8. [Memory System (CLAUDE.md + MEMORY.md)](#8-memory-system-claudemd--memorymd)
9. [Permission System](#9-permission-system)
10. [Multi-Agent & Coordinator System](#10-multi-agent--coordinator-system)
11. [MCP Integration](#11-mcp-integration)
12. [Skills System](#12-skills-system)
13. [Prompt Caching — How Claude Code Stays Cheap](#13-prompt-caching--how-claude-code-stays-cheap)
14. [High-Performance Usage Patterns](#14-high-performance-usage-patterns)
15. [Prompt Engineering from Source](#15-prompt-engineering-from-source)
16. [Configuration Reference](#16-configuration-reference)
17. [Slash Commands Reference](#17-slash-commands-reference)
18. [Data Engineering Patterns with Claude Code](#18-data-engineering-patterns-with-claude-code)
19. [Key File Index](#19-key-file-index)

---

## 1. Project Overview

Claude Code is Anthropic's official CLI tool for interacting with Claude from the terminal. It is not a thin wrapper around the API — it is a full agentic system with its own:

- **Prompt assembly pipeline** (12+ static sections + dynamic registry)
- **Tool permission engine** (4-layer command classification for BashTool alone)
- **Memory hierarchy** (4 scope levels, `@include` composition, frontmatter path scoping)
- **Multi-agent coordinator** (1 orchestrator + N scoped worker agents)
- **Prompt caching strategy** (cross-org static prefix, per-session dynamic suffix)
- **58 compile-time feature flags** (most stripped from public builds)

| Property | Value |
|---|---|
| Language | TypeScript (strict mode, ES modules) |
| Runtime | Bun ≥ 1.1.0 |
| Terminal UI | React 19 + Ink (React for the terminal) |
| CLI Parser | Commander.js (`@commander-js/extra-typings`) |
| Validation | Zod v4 |
| API Client | `@anthropic-ai/sdk ^0.39.0` |
| Linter | Biome |
| Analytics | GrowthBook (feature flags + A/B testing) |
| Protocol | MCP SDK `^1.12.1` |
| Scale | ~1,900 files · 512,000+ lines |

---

## 2. Architecture: The Full Pipeline

```
User types message or slash command
         │
         ▼
src/main.tsx  ←─ Commander.js CLI parser
  │  Parallel startup: MDM policy, Keychain prefetch, GrowthBook flags
  ▼
src/replLauncher.tsx  ←─ REPL session launcher
  ▼
src/QueryEngine.ts  ←─ Core engine (submitMessage)
  │  Calls fetchSystemPromptParts() → getSystemPrompt() + getUserContext() + getSystemContext()
  │  Processes user input via processUserInput()
  ▼
src/query.ts  ←─ Per-turn query loop
  │  appendSystemContext(systemPrompt, systemContext)   ← git status goes here
  │  prependUserContext(messages, userContext)          ← CLAUDE.md + date go here (message[0])
  │  Calls deps.callModel()
  ▼
src/services/api/claude.ts  ←─ Anthropic API client
  │  Prepends: attribution header + CLI prefix
  │  Applies: cache_control breakpoints (global / org / null)
  │  Calls: client.beta.messages.stream()
  ▼
Anthropic API (streaming response)
  │
  ▼  [if stop_reason === 'tool_use']
src/tools/{ToolName}/  ←─ Tool execution
  │  checkPermissions() → user prompt or auto-allow
  │  call() → execute
  │  Result fed back into message array
  │  Loop continues until stop_reason === 'end_turn'
  ▼
src/components/ + src/screens/REPL.tsx  ←─ React/Ink terminal rendering
```

### Startup Optimization (Parallel Prefetch)

`src/main.tsx` fires these in parallel **before** heavy module evaluation:

```typescript
startMdmRawRead()      // MDM policy (macOS/Windows enterprise)
startKeychainPrefetch() // API key from OS keychain
// GrowthBook flag fetch starts async
```

Heavy modules (`OpenTelemetry` ~400KB, `gRPC` ~700KB) are lazy-loaded via dynamic `import()` only when needed.

---

## 3. Prompt Assembly System

This is the most important thing to understand about Claude Code. **The prompt is assembled in the CLI, not on Anthropic's servers.** This means it is readable, reproducible, and — most importantly — overridable.

### The Full Assembly Pipeline

The final prompt reaching the model is the sum of **8 input sources**:

```
Source 1: src/constants/prompts.ts
  └─ getSystemPrompt() → 12+ static section builders

Source 2: src/context.ts
  ├─ getGitStatus()    → branch, last 5 commits, git status --short (truncated at 2000 chars)
  ├─ getSystemContext() → {gitStatus, cacheBreaker?}
  └─ getUserContext()  → {claudeMd, currentDate}

Source 3: Each tool's prompt() method
  └─ 40 tool files each contribute their own description string

Source 4: src/memdir/memdir.ts
  └─ MEMORY.md content (max 200 lines / 25KB)

Source 5: src/utils/claudemd.ts
  └─ CLAUDE.md file resolution (4-level hierarchy + @include directives)

Source 6: src/services/mcp/ (volatile)
  └─ MCP server-provided instructions (recomputed every turn when servers change)

Source 7: src/QueryEngine.ts options
  ├─ appendSystemPrompt   → additive layer on top of default
  ├─ customSystemPrompt   → REPLACES the entire default prompt
  └─ memoryMechanicsPrompt → injected only when customSystemPrompt set + memory path override

Source 8: src/services/api/claude.ts (per-call)
  ├─ Attribution header (billing)
  └─ CLI identification prefix
```

### Two-Channel Context Delivery

**Channel A — System Prompt Array:**
- Static instructions (intro, rules, task guidance, tools, tone, style)
- Git status (appended via `appendSystemContext()`)
- Tool descriptions (each tool's `prompt()` return value)
- MCP server instructions (volatile)

**Channel B — Synthetic First Message (message[0]):**

```xml
<system-reminder>
As you answer the user's questions, you can use the following context:
# claudeMd
{contents of all CLAUDE.md files}
# currentDate
Today's date is {ISO date}.

IMPORTANT: this context may or may not be relevant to your tasks.
You should not respond to this context unless it is highly relevant to your task.
</system-reminder>
```

**Why two channels?** Putting CLAUDE.md and the date into the message array (not the system prompt) means the system prompt stays stable across turns and hits the cross-org prompt cache. Volatile data never busts the cached prefix.

### Static System Prompt Sections (from `src/constants/prompts.ts`)

These are built once and cached for the session:

| Section | Content |
|---|---|
| `getSimpleIntroSection()` | Identity: "You are Claude Code..." + cyber risk warning |
| `getSimpleSystemSection()` | Output channel rules, permission modes, `<system-reminder>` tag handling, prompt injection warnings, hooks |
| `getSimpleDoingTasksSection()` | Code style, how to help users, task approach |
| `getActionsSection()` | "Executing actions with care" — reversibility, confirmation before destructive ops |
| `getUsingYourToolsSection()` | Prefer dedicated tools over Bash, parallel call guidance |
| `getSimpleToneAndStyleSection()` | No emoji, concise, file:line references, no colon before tool calls |
| `getOutputEfficiencySection()` | Prose length rules (ant-users get detailed version) |
| `getSessionSpecificGuidanceSection()` | AskUserQuestion usage, agent tool guidance, verification agent |

### Dynamic System Prompt Sections (Section Registry)

These are registered via `systemPromptSection()` / `DANGEROUS_uncachedSystemPromptSection()` and cached in `src/bootstrap/state.ts`:

```typescript
// Stable (computed once, cached until /clear or /compact):
systemPromptSection('memory', () => loadMemoryPrompt())
systemPromptSection('env_info_simple', () => computeSimpleEnvInfo())  // CWD, platform, model name
systemPromptSection('language', () => languageSection)
systemPromptSection('output_style', () => outputStyleSection)
systemPromptSection('scratchpad', () => scratchpadInstructions)

// Volatile (recomputed every turn — busts prompt cache):
DANGEROUS_uncachedSystemPromptSection('mcp_instructions', () => mcpInstructions,
  'Changes when MCP servers connect/disconnect')
```

### The Static/Dynamic Cache Boundary

`SYSTEM_PROMPT_DYNAMIC_BOUNDARY` in `src/constants/prompts.ts:114` splits the prompt into:

- **Before boundary** → `cacheScope: 'global'` — shared across **all users** from Anthropic's cache layer. All static instruction sections land here.
- **After boundary** → `cacheScope: null` — not cached. CWD, model name, git status land here.

This is why Claude Code is cheap to run at scale: every user with the same Claude Code version shares the same cached static prefix. Only the dynamic per-session suffix is billed as cache_creation_tokens.

### Overriding the System Prompt (SDK usage)

```typescript
// Option A: Replace entire default prompt
const engine = new QueryEngine({
  customSystemPrompt: "You are a specialized data pipeline assistant.",
  // getSystemContext() is skipped; git status not injected
})

// Option B: Append on top of default
const engine = new QueryEngine({
  appendSystemPrompt: "Additional constraints for this session...",
  // Appended after default prompt, before cache boundary
})
```

---

## 4. Tool System

### Standard Operation Toolset (19 always-present tools)

```
AgentTool           TaskOutputTool      BashTool
ExitPlanModeV2Tool  FileReadTool        FileEditTool
FileWriteTool       NotebookEditTool    WebFetchTool
TodoWriteTool       WebSearchTool       TaskStopTool
AskUserQuestionTool SkillTool           EnterPlanModeTool
BriefTool           ListMcpResourcesTool ReadMcpResourceTool
SendMessageTool
```

Plus conditionally: `GlobTool`, `GrepTool`, `TaskCreateTool/Get/Update/List`, `EnterWorktreeTool`, `ExitWorktreeTool`, `LSPTool`, `PowerShellTool`, `TeamCreateTool`, `TeamDeleteTool`, `ToolSearchTool`.

**The design principle: fewer tools = better results.** `CLAUDE_CODE_SIMPLE=1` strips everything down to just `[BashTool, FileReadTool, FileEditTool]`.

### Tool Anatomy (from `src/Tool.ts`)

Every tool is built with `buildTool()` and has exactly these interfaces:

```typescript
export const MyTool = buildTool({
  name: 'ToolName',                           // API-facing name
  aliases: ['tool_name'],                     // Alternative names
  description: 'What this tool does',

  inputSchema: z.object({                     // Zod v4 validation
    param: z.string().describe('description'),
    optional: z.boolean().optional(),
  }),

  // Invoked by QueryEngine during tool-call loop
  async call(input, context, canUseTool, parentMessage, onProgress) {
    return { data: result, newMessages?: [...] }
  },

  // Checked before call() — return null to allow, string to deny
  async checkPermissions(input, context): Promise<PermissionResult> { },

  // Can this instance run concurrently with other tools?
  isConcurrencySafe(input): boolean { },

  // Does this tool modify state? (affects auto-allow logic)
  isReadOnly(input): boolean { },

  // Returns string injected into system prompt as tool description
  // Called once per session, result cached in toolSchemaCache
  async prompt(options): Promise<string | null> { },

  // React/Ink components for terminal rendering
  renderToolUseMessage(input, options): ReactElement { },
  renderToolResultMessage(content, progressMessages, options): ReactElement { },
})
```

### Tool Schema Caching

Tool descriptions are cached per-session in `src/utils/toolSchemaCache.ts`. Cache key = `tool.name`. This prevents GrowthBook flag changes mid-session from altering serialized tool descriptions, which would bust the API prompt cache for the entire tool array block (expensive when there are 40+ tools).

### Tool Assembly for API Call (`assembleToolPool`)

```typescript
// src/tools.ts
export function assembleToolPool(permissionContext, mcpTools): Tools {
  const builtInTools = getTools(permissionContext)
  const allowedMcpTools = filterToolsByDenyRules(mcpTools, permissionContext)

  // CRITICAL: Both partitions sorted alphabetically for prompt-cache stability
  // Mixed sort would interleave MCP tools into built-ins → cache bust every time
  // an MCP tool's sort position changes between built-ins
  const byName = (a, b) => a.name.localeCompare(b.name)
  return uniqBy(
    [...builtInTools].sort(byName).concat(allowedMcpTools.sort(byName)),
    'name'
  )
}
```

### Complete Tool Inventory (all 58 implementations)

| Category | Tools |
|---|---|
| **Always-on** | AgentTool, BashTool, FileReadTool, FileEditTool, FileWriteTool, GlobTool\*, GrepTool\*, NotebookEditTool, WebFetchTool, WebSearchTool, TodoWriteTool, AskUserQuestionTool, SkillTool, EnterPlanModeTool, ExitPlanModeV2Tool, BriefTool, TaskOutputTool, TaskStopTool, SendMessageTool, ListMcpResourcesTool, ReadMcpResourceTool |
| **Conditional (env)** | ConfigTool†, TungstenTool†, REPLTool†, SuggestBackgroundPRTool†, TaskCreateTool, TaskGetTool, TaskUpdateTool, TaskListTool, EnterWorktreeTool, ExitWorktreeTool, LSPTool, TeamCreateTool, TeamDeleteTool, VerifyPlanExecutionTool, PowerShellTool, ToolSearchTool |
| **Feature-gated** | SleepTool, CronCreateTool, CronDeleteTool, CronListTool, RemoteTriggerTool, MonitorTool, SendUserFileTool, PushNotificationTool, SubscribePRTool, WebBrowserTool, CtxInspectTool, TerminalCaptureTool, SnipTool, ListPeersTool, WorkflowTool, OverflowTestTool |
| **Internal** | SyntheticOutputTool, MCPTool, McpAuthTool, TestingPermissionTool |

\* = not present in ant-native builds (replaced by embedded `bfs`/`ugrep`)
† = ant-only (`USER_TYPE === 'ant'`)

---

## 5. BashTool — The Crown Jewel

BashTool is where the real sub-model intelligence lives. It does not just pass commands to the shell. It runs every command through a **4-layer classification pipeline** before execution.

### Layer 1: Display Classification (`BashTool.tsx:60–172`)

`isSearchOrReadBashCommand(command)` classifies each part of a pipeline:

```typescript
// Commands classified as "Search" (collapsible in UI)
const BASH_SEARCH_COMMANDS = new Set([
  'find', 'grep', 'rg', 'ag', 'ack', 'locate', 'which', 'whereis'
])

// Commands classified as "Read" (collapsible in UI)
const BASH_READ_COMMANDS = new Set([
  'cat', 'head', 'tail', 'less', 'more',
  'wc', 'stat', 'file', 'strings',
  'jq', 'awk', 'cut', 'sort', 'uniq', 'tr'
])

// Directory listing (separate category — "Listed N directories" summary)
const BASH_LIST_COMMANDS = new Set(['ls', 'tree', 'du'])

// Semantic-neutral — skipped in pipeline classification
const BASH_SEMANTIC_NEUTRAL_COMMANDS = new Set(['echo', 'printf', 'true', 'false', ':'])

// Typically produce no stdout on success → show "Done" not "(No output)"
const BASH_SILENT_COMMANDS = new Set([
  'mv', 'cp', 'rm', 'mkdir', 'rmdir', 'chmod', 'chown', 'chgrp',
  'touch', 'ln', 'cd', 'export', 'unset', 'wait'
])
```

**Rule:** All non-neutral commands in a pipeline must be in the same category for the whole command to be collapsible. One non-read/search command → full display.

### Layer 2: Read-Only Auto-Allow (`readOnlyValidation.ts`)

`checkReadOnlyConstraints()` maintains explicit flag allowlists per tool:

```
GIT_READ_ONLY_COMMANDS:     diff, log, status, show, blame, branch, tag, describe, ...
GH_READ_ONLY_COMMANDS:      pr view, issue view, run view, release view, ...
DOCKER_READ_ONLY_COMMANDS:  ps, images, inspect, logs, stats, ...
RIPGREP_READ_ONLY_COMMANDS: all flags (rg is always read-only)
PYRIGHT_READ_ONLY_COMMANDS: all flags
EXTERNAL_READONLY_COMMANDS: cat, head, tail, ls, find, wc, ...
FD_SAFE_FLAGS:              -e, -t, -H, -I, -L, -d, ...
```

Any unknown flag → auto-escalate to `ask`. This is why `git diff` never prompts but `git push` always does.

### Layer 3: Security Analysis (`bashSecurity.ts`)

`bashCommandIsSafeAsync_DEPRECATED()` runs 23 checks before execution:

| Check | What it blocks |
|---|---|
| `COMMAND_SUBSTITUTION_PATTERNS` | `$()`, `${}`, `<()`, Zsh `=cmd` expansion |
| `ZSH_DANGEROUS_COMMANDS` | `zmodload`, `emulate`, `sysopen`, `ztcp`, `zpty` |
| Unicode whitespace | Commands with invisible whitespace characters |
| Brace expansion | `{a,b}` patterns that could expand unexpectedly |
| Mid-word `#` | Comment injection inside commands |
| Backslash operators | `\|`, `\;`, `\&` escaped in non-obvious positions |
| Obfuscated flags | Flags that look like shell operators |
| Control characters | Non-printable chars in command strings |

`extractQuotedContent()` strips single/double quoted content before pattern matching to avoid false positives on content inside strings.

### Layer 4: Exit Code Semantics (`commandSemantics.ts`)

```typescript
// grep / rg: exit 1 = "no matches" (informational, not an error)
['grep', exitCode => ({ isError: exitCode >= 2, message: exitCode === 1 ? 'No matches found' : undefined })]
['rg',   exitCode => ({ isError: exitCode >= 2, message: exitCode === 1 ? 'No matches found' : undefined })]

// find: exit 1 = partial (some dirs inaccessible)
['find', exitCode => ({ isError: exitCode >= 2, message: exitCode === 1 ? 'Some directories were inaccessible' : undefined })]

// diff: exit 1 = "files differ" (informational)
['diff', exitCode => ({ isError: exitCode >= 2, message: exitCode === 1 ? 'Files differ' : undefined })]

// test / [: exit 1 = condition false
['test', exitCode => ({ isError: exitCode >= 2 })]
['[',    exitCode => ({ isError: exitCode >= 2 })]
```

Exit code is extracted from the **last command in the pipeline** (since pipes pass through last command's exit code).

### Permission Decision Tree (`bashPermissions.ts`)

```
Input: command string
  │
  ├─1─ Exact match in deny/ask/allow rules? → return immediately
  │
  ├─2─ Prefix/wildcard match?
  │     deny rules: strip all env vars (FOO=bar cmd → cmd, iterative fixed-point)
  │     allow rules: strip safe wrappers (timeout/nohup/nice/sudo/env)
  │
  ├─3─ Path constraint check: file paths within project directory?
  │     (uses AST-derived argv when TREE_SITTER_BASH available)
  │
  ├─4─ sed constraint check: safe sed operations only?
  │
  ├─5─ Mode check: plan-mode, auto-mode, read-only mode?
  │
  ├─6─ Read-only auto-allow: checkReadOnlyConstraints() → auto-approve?
  │
  ├─7─ [BASH_CLASSIFIER flag] NLP classifier: Claude-based command classifier
  │
  └─8─ Generate user permission prompt + rule suggestion
        Suggestion prefers 2-word prefix ("git commit:*") over exact match
        Falls back to first word for complex pipelines
        Blocks: bare shell prefixes (bash, sh, sudo, env) as suggestion prefixes
```

### BashTool Input Schema

```typescript
z.strictObject({
  command: z.string(),
  timeout: z.number().optional(),               // ms, max 600000 (10 min), default 120000 (2 min)
  description: z.string().optional(),           // Human-readable description (5–10 words for simple)
  run_in_background: z.boolean().optional(),    // Don't block — get notified on completion
  dangerouslyDisableSandbox: z.boolean().optional(), // Override sandbox (requires explicit user permission)
})
```

### BashTool System Prompt (what the model sees)

Key constraints injected by `getSimplePrompt()` in `src/tools/BashTool/prompt.ts`:

```
IMPORTANT: Avoid using this tool to run find, grep, cat, head, tail, sed, awk, or echo
commands, unless explicitly instructed. Instead:
 - File search: Use Glob (NOT find or ls)
 - Content search: Use Grep (NOT grep or rg)
 - Read files: Use Read (NOT cat/head/tail)
 - Edit files: Use Edit (NOT sed/awk)
 - Write files: Use Write (NOT echo >/cat <<EOF)

# Instructions
 - If your command will create new directories or files, first use this tool to run
   `ls` to verify the parent directory exists
 - Always quote file paths that contain spaces
 - Try to maintain CWD throughout session using absolute paths
 - Timeout: up to 10 minutes (600000ms), default 2 minutes
 - For multiple independent commands: make multiple tool calls in parallel
 - For dependent commands: use && to chain them
 - For git commands: prefer new commits over amending; never skip hooks
 - Avoid unnecessary sleep commands — use run_in_background instead
```

---

## 6. Feature Flags (58 Total)

All flags are Bun compile-time dead-code elimination gates. In external builds, most compile to `false` and their code paths are physically absent from the binary.

Declared in: `src/types/bun-bundle.d.ts`
Usage: `import { feature } from 'bun:bundle'`

### MAJOR — Ready for Release

| Flag | What is built |
|---|---|
| `KAIROS` | Always-on background assistant — channels, push notifications, GitHub webhooks, `--session-id` CLI arg, session continuation. Sub-flags: `KAIROS_BRIEF`, `KAIROS_CHANNELS`, `KAIROS_DREAM`, `KAIROS_GITHUB_WEBHOOKS`, `KAIROS_PUSH_NOTIFICATION` |
| `COORDINATOR_MODE` | One Claude orchestrating N workers with scoped tool sets. Activated via `CLAUDE_CODE_COORDINATOR_MODE=1`. Files: `src/coordinator/` |
| `AGENT_TRIGGERS` | `CronCreateTool`, `CronDeleteTool`, `CronListTool`. Cron scheduling with durable jobs in `.claude/scheduled_tasks.json`. Sub-flag: `AGENT_TRIGGERS_REMOTE` → `RemoteTriggerTool` |
| `VOICE_MODE` | Full voice interface. Files: `src/voice/`, `src/services/voiceStreamSTT.ts`. Keybinding: `space: 'voice:pushToTalk'` |
| `PROACTIVE` | `SleepTool` — agents that pause and self-resume. Combined with `KAIROS` for full autonomous mode |
| `BRIDGE_MODE` | IDE extension communication layer (VS Code, JetBrains). Files: `src/bridge/` |
| `TRANSCRIPT_CLASSIFIER` | Auto-infer permission mode from session history. ML classifier → `auto` mode. Files: `src/utils/permissions/autoModeState.ts` |
| `ULTRAPLAN` | Enhanced planning with verification step. Command: `/ultraplan` |

### IN-FLIGHT — Partially Built

| Flag | What is built |
|---|---|
| `WEB_BROWSER_TOOL` | `WebBrowserTool` — `src/tools/WebBrowserTool/` — real browser automation via CDP |
| `CONTEXT_COLLAPSE` | `CtxInspectTool` + 3 compaction strategies: `REACTIVE_COMPACT`, `CACHED_MICROCOMPACT`, context inspection |
| `HISTORY_SNIP` | `SnipTool` — surgically remove specific conversation history segments |
| `AGENT_MEMORY_SNAPSHOT` | `src/tools/AgentTool/agentMemorySnapshot.ts` — persist agent memory across sessions |
| `WORKFLOW_SCRIPTS` | `WorkflowTool` — pre-defined multi-step automation scripts |
| `MONITOR_TOOL` | `MonitorTool` — watch MCP resources and trigger on state changes |
| `BASH_CLASSIFIER` | NLP classifier for bash permission decisions using Claude itself |
| `TREE_SITTER_BASH` | Proper AST-based command parsing (shadow mode: `TREE_SITTER_BASH_SHADOW`) |

### INFRASTRUCTURE

| Flag | What is built |
|---|---|
| `TEAMMEM` | Team memory synchronization — `src/services/teamMemorySync/` |
| `MCP_SKILLS` | MCP-hosted skill libraries — discoverable like packages |
| `EXPERIMENTAL_SKILL_SEARCH` | Local skill index + MCP skill prefetch |
| `TOKEN_BUDGET` | Per-session token spend cap — `src/query/tokenBudget.ts` |
| `CHICAGO_MCP` | macOS Spotlight/Accessibility/Notifications via MCP — `src/services/mcp/config.ts:641` |
| `UPLOAD_USER_SETTINGS` / `DOWNLOAD_USER_SETTINGS` | Sync settings across machines |
| `COMMIT_ATTRIBUTION` | Tag git commits with Claude session metadata |
| `EXTRACT_MEMORIES` | Auto-extract memories from conversations — `src/services/extractMemories/` |
| `SSH_REMOTE` | SSH remote sessions — `src/main.tsx:577` |
| `FORK_SUBAGENT` | Fork subagent command |

### UNKNOWN / INTERNAL

| Flag | Notes |
|---|---|
| `BUDDY` | Companion sprite / `src/buddy/CompanionSprite.tsx` |
| `LODESTONE` | Referenced in `src/interactiveHelpers.tsx:176` — no tool wired yet |
| `TORCH` | `src/commands.ts:107` — command present, purpose undocumented |
| `ABLATION_BASELINE` | Research/testing flag |

---

## 7. Unshipped Features — What Is Actually Built

### KAIROS — Background Assistant

**Files:** `src/assistant/`, `src/services/mcp/channelNotification.ts`
**Tools built:** `SubscribePRTool`, `PushNotificationTool`, `SendUserFileTool`

Architecture: KAIROS is a persistent Claude session that runs in the background. It connects via the bridge layer, subscribes to GitHub webhooks (`KAIROS_GITHUB_WEBHOOKS`), and sends push notifications (`KAIROS_PUSH_NOTIFICATION`). Session continuation uses `--session-id` and `--continue` CLI args parsed in `src/bridge/bridgeMain.ts:1787`.

### Coordinator Mode — Multi-Agent Orchestration

**Files:** `src/coordinator/coordinatorMode.ts`
**Activation:** `CLAUDE_CODE_COORDINATOR_MODE=1` env + `feature('COORDINATOR_MODE')`

The coordinator gets the full tool set. Workers get `COORDINATOR_MODE_ALLOWED_TOOLS` — a restricted subset defined in `src/constants/tools.ts`. `TeamCreateTool`/`TeamDeleteTool` manage worker lifetimes. `SendMessageTool` handles inter-agent messaging. Each worker is a sub-agent with scoped permissions.

### AGENT_TRIGGERS — Cron + Webhooks

**Tools:** `CronCreateTool`, `CronDeleteTool`, `CronListTool` (`src/tools/ScheduleCronTool/`)

Durable jobs persist to `.claude/scheduled_tasks.json` and survive restarts. Non-durable jobs are session-only. The scheduler adds jitter (up to 10% of period) to avoid fleet-level thundering herd.

```typescript
// CronCreateTool input schema
z.object({
  cron: z.string(),        // "*/5 * * * *" standard 5-field cron
  prompt: z.string(),      // Prompt to enqueue at each fire time
  recurring: z.boolean(),  // true = repeat; false = one-shot then delete
  durable: z.boolean(),    // true = persist to disk; false = session-only
})
```

### WEB_BROWSER_TOOL — Real Browser Automation

**Files:** `src/tools/WebBrowserTool/`
**Status:** Implementation present in source, stripped from external builds

This is not `WebFetchTool`. It is full browser control via CDP/Playwright: navigate, click, fill forms, scrape rendered SPAs, interact with JavaScript-heavy pages.

### CONTEXT_COLLAPSE — Surgical Compaction

Three strategies built:
1. **Reactive compact** (`REACTIVE_COMPACT`) — `src/services/compact/reactiveCompact.ts`
2. **Micro compact with caching** (`CACHED_MICROCOMPACT`) — surgical removal with cache preservation
3. **CtxInspectTool** (`CONTEXT_COLLAPSE`) — inspection tool for context contents

Current `/compact` is a blunt full-history summary. These three are surgical alternatives.

### AGENT_MEMORY_SNAPSHOT — Cross-Session Memory

**File:** `src/tools/AgentTool/agentMemorySnapshot.ts`

This is what turns Claude Code from a session-based tool into a persistent one. The agent remembers what it learned about your codebase without you building a memory layer on top.

---

## 8. Memory System (CLAUDE.md + MEMORY.md)

### CLAUDE.md Hierarchy (4 Levels)

Files are loaded in **reverse priority order** — higher priority files are loaded later and the model attends to them more:

```
Priority (low → high):
1. Managed:  /etc/claude-code/CLAUDE.md           ← all users on this machine
2. User:     ~/.claude/CLAUDE.md                   ← your personal global rules
3. Project:  CLAUDE.md, .claude/CLAUDE.md,
             .claude/rules/*.md                    ← project-specific rules
4. Local:    CLAUDE.local.md                       ← your local overrides (gitignored)
```

**Loading in `src/utils/claudemd.ts`:**
- `@include ./other-file.md` — include another file by reference
- Frontmatter `paths:` — scope rules to specific file globs

```markdown
---
paths:
  - "src/data/**/*.py"
  - "pipelines/**"
---
# Data Pipeline Rules
These rules only apply to files matching the paths above.
```

### CLAUDE.md Delivery

CLAUDE.md content is delivered as the **synthetic first message** (`<system-reminder>`) — NOT as part of the system prompt array. This preserves the cached system prompt prefix. CLAUDE.md changes do not bust the prompt cache.

### MEMORY.md

- **Path:** `~/.claude/MEMORY.md` (user-scoped) or project `.claude/MEMORY.md`
- **Max:** 200 lines / 25KB (content truncated beyond this with a warning)
- **Channel:** Loaded as a stable section in the system prompt (via `loadMemoryPrompt()`)
- **Commands:** `/memory` — view/edit. `remember` skill — persist information programmatically.
- **Auto-extraction:** `EXTRACT_MEMORIES` feature flag → `src/services/extractMemories/` auto-extracts important facts from conversations

### Writing Effective CLAUDE.md

Based on the source, what works:

```markdown
# Project: [Name]

## Architecture
[Brief overview — what the system does, main components]

## Code Conventions
[Language, frameworks, naming, patterns]

## Commands
- Build: `bun run build`
- Test: `bun test`
- Lint: `bun run lint`

## Key Files
- src/main.ts: Entry point
- src/config.ts: Configuration

## Do Not
- Do not modify X without updating Y
- Never commit directly to main
- Always run lint before committing
```

**Tips from source:**
- Keep under 200 lines (hard truncation at that point)
- Use `@include` for large rule sets split across files
- Use `paths:` frontmatter to scope rules to directories
- Project CLAUDE.md takes precedence over user global CLAUDE.md
- CLAUDE.local.md for personal local overrides (add to .gitignore)

---

## 9. Permission System

### Permission Modes

| Mode | Source | Behavior |
|---|---|---|
| `default` | `src/hooks/toolPermission/` | Prompts user for each potentially destructive operation |
| `plan` | `src/hooks/toolPermission/` | Shows full execution plan, user approves once for all |
| `bypassPermissions` | — | Auto-approves everything. **Dangerous — for CI/trusted environments only** |
| `auto` | `TRANSCRIPT_CLASSIFIER` flag | ML classifier reads session history and infers appropriate permission level |

### Permission Rules (Wildcard Patterns)

```
Bash(git *)          # Allow all git commands
Bash(git log)        # Allow only 'git log' specifically
Bash(npm test)       # Allow 'npm test' specifically
FileEdit(/src/*)     # Allow edits to anything under src/
FileRead(*)          # Allow reading any file
FileWrite(/tmp/*)    # Allow writes only to /tmp
```

Rules are stored in `.claude/settings.json` under `permissions.allow` and `permissions.deny`.

### How BashTool Permission Suggestions Work

When a new command needs a rule, the system suggests the **minimal reusable rule**:

- `git commit -m "message"` → suggests `git commit:*` (2-word prefix)
- `cat /etc/hosts` → suggests `cat` (first word)
- Complex pipeline → suggests first command prefix

Shell wrappers (`bash`, `sh`, `sudo`, `env`, etc.) are **blocked from being permission prefixes** to prevent bypass via `sudo denied_cmd`.

---

## 10. Multi-Agent & Coordinator System

### Agent Types

| Type | File | Purpose |
|---|---|---|
| `LocalShellTask` | `src/tasks/LocalShellTask/` | Background shell command |
| `LocalAgentTask` | `src/tasks/LocalAgentTask/` | Sub-agent running locally |
| `RemoteAgentTask` | `src/tasks/RemoteAgentTask/` | Agent on remote machine |
| `InProcessTeammateTask` | `src/tasks/InProcessTeammateTask/` | Parallel teammate in same process |
| `DreamTask` | `src/tasks/DreamTask/` | Background ideation/consolidation |

### AgentTool (Sub-Agent Spawning)

```typescript
// AgentTool input schema
z.object({
  description: z.string(),      // What this agent will do
  prompt: z.string(),           // Full task prompt
  subagent_type: z.string().optional(), // Specific agent type to use
  run_in_background: z.boolean().optional(),
  isolation: z.enum(['worktree']).optional(), // Run in git worktree isolation
})
```

Agent definitions are loaded from `.claude/agents/` directory (YAML files) via `src/tools/AgentTool/loadAgentsDir.ts`. Each definition specifies:
- `agentType`: identifier
- `whenToUse`: description for the orchestrator
- `tools`: allowlist (or empty = all tools)
- `disallowedTools`: denylist

### Coordinator Mode

When `COORDINATOR_MODE` is active:
- **Coordinator** gets full tool set + `AgentTool` + `SendMessageTool`
- **Workers** get `COORDINATOR_MODE_ALLOWED_TOOLS` only (restricted subset)
- Workers communicate via `SendMessageTool`
- `TeamCreateTool` spawns parallel worker teams
- `TaskCreateTool/UpdateTool/ListTool/GetTool` track work across agents

### Agent Prompt Injection

`AgentTool/prompt.ts` dynamically lists available agent types in the tool description:

```
When to use the Agent tool:
- general-purpose: For researching complex questions... (Tools: All tools)
- feature-dev:code-reviewer: Reviews code for bugs... (Tools: Glob, Grep, Read, ...)
- Explore: Fast agent for exploring codebases... (Tools: All tools except Agent, Edit, Write)
```

This listing is injected as an **attachment message** (not system prompt) when `shouldInjectAgentListInMessages()` is true — this prevents MCP connection/disconnection from busting the tool schema cache.

---

## 11. MCP Integration

Claude Code is both an **MCP client** and can run as an **MCP server**.

### As MCP Client

```bash
# Add an MCP server
claude mcp add my-server -- node /path/to/server.js

# With environment variables
claude mcp add my-server -e API_KEY=xxx -- node /path/to/server.js

# Remove
claude mcp remove my-server
```

MCP tool discovery uses `ToolSearchTool` for deferred loading — tools are discovered at runtime rather than all loaded upfront. This keeps the tool count low until a specific MCP tool is needed.

**Tools for MCP:**

| Tool | Purpose |
|---|---|
| `MCPTool` | Invoke tools on connected MCP servers |
| `ListMcpResourcesTool` | List resources exposed by MCP servers |
| `ReadMcpResourceTool` | Read a specific MCP resource |
| `McpAuthTool` | Handle MCP server authentication |
| `ToolSearchTool` | Discover deferred MCP tools |

### As MCP Server

```bash
# Launch Claude Code as an MCP server
# Entrypoint: src/entrypoints/mcp.ts
```

This exposes Claude Code's own tools and resources to other AI agents via the MCP protocol.

### MCP Instructions (Volatile System Prompt Section)

MCP servers can inject instructions into Claude's system prompt via the MCP protocol. These are the **only truly volatile** section — they recompute every turn and are marked `DANGEROUS_uncachedSystemPromptSection` because they change whenever a server connects or disconnects.

---

## 12. Skills System

Skills are reusable, named workflows bundled with prompts and tool configurations.

### Bundled Skills (`src/skills/bundled/`)

| Skill | Purpose |
|---|---|
| `batch` | Batch operations across multiple files |
| `claudeApi` | Direct Anthropic API interaction |
| `debug` | Debugging workflows |
| `keybindings` | Keybinding configuration |
| `loop` | Iterative refinement loops |
| `remember` | Persist information to memory |
| `scheduleRemoteAgents` | Schedule agents for remote execution |
| `simplify` | Simplify complex code |
| `skillify` | Create new skills from workflows |
| `stuck` | Get unstuck when blocked |
| `updateConfig` | Modify configuration programmatically |
| `verify` / `verifyContent` | Verify code correctness |

### Creating Custom Skills

Skills are YAML files in `.claude/skills/` or the global `~/.claude/skills/` directory:

```yaml
---
name: my-pipeline-skill
description: Run the full data pipeline validation
---

# Pipeline Validation Skill

Run these steps in sequence:

1. Validate schema: `python validate_schema.py`
2. Check row counts: `python check_counts.py`
3. Run integration tests: `pytest tests/integration/`
4. Generate report: `python generate_report.py`

Report any failures with their error output.
```

Invoke with `/my-pipeline-skill` in the REPL, or via `SkillTool` in agent mode.

---

## 13. Prompt Caching — How Claude Code Stays Cheap

This is the most impactful optimization in Claude Code's architecture. Understanding it lets you build equally efficient agent systems.

### Cache Scope Hierarchy

```
Attribution header           → cacheScope: null   (never cached)
CLI identification prefix    → cacheScope: 'org'  (per-org cache)
Static instruction sections  → cacheScope: 'global' (cross-org cache ← the big win)
  [SYSTEM_PROMPT_DYNAMIC_BOUNDARY]
Dynamic per-session sections → cacheScope: null   (not cached)
```

The **global** scope means the static sections (identity, system rules, task guidance, tool rules, tone, style) are shared across **all Claude Code users** from Anthropic's cache layer. Every user benefits from every other user's cache warm-up.

### What This Means for Builders

1. **Keep your system prompt prefix stable.** Anything that changes between turns must come after the cache boundary or in the message array.
2. **CLAUDE.md goes in the message array** (synthetic first message) — not the system prompt — for exactly this reason.
3. **MCP instructions are volatile** — connecting/disconnecting MCP servers busts the suffix cache.
4. **Tool schemas are session-cached** — GrowthBook flag changes mid-session don't re-serialize tool descriptions.
5. **Build your own cache boundary** — in custom systems, put stable instructions first, volatile last.

### Token Cost Breakdown (from `src/services/api/logging.ts`)

```
cache_creation_input_tokens  → charged at 1.25× input rate (written to cache)
cache_read_input_tokens      → charged at 0.1× input rate  (read from cache)
input_tokens                 → full rate (new uncached content)
output_tokens                → full rate
```

After first turn: most tokens are `cache_read_input_tokens` (90% cheaper). The static system prompt prefix is read from cache every turn.

---

## 14. High-Performance Usage Patterns

### Pattern 1: Minimal Tool Surface

```bash
# Strip down to minimum for focused tasks
CLAUDE_CODE_SIMPLE=1 claude

# Only [BashTool, FileReadTool, FileEditTool] are active
# Smaller tool array = more context for reasoning
```

### Pattern 2: CLAUDE.md for Persistent Context

Never repeat project context in every prompt. Put it in CLAUDE.md:

```markdown
# Project: DataPipeline v2
## Stack: Python 3.12, Pandas 2.0, DuckDB 0.10, Airflow 2.9
## Test: pytest tests/ -x --tb=short
## Lint: ruff check src/ && mypy src/
## Never modify: src/schema_registry.py (auto-generated)
## Data locations:
- Raw: s3://data-lake/raw/ (read-only)
- Processed: s3://data-lake/processed/ (write OK)
- Local dev: ~/data/
```

### Pattern 3: Parallel Tool Calls

Claude Code's system prompt explicitly instructs Claude to run independent tool calls in parallel. Write prompts that make this possible:

```
Good:  "Check git status, read config.py, and list the tests directory"
       → 3 parallel tool calls

Bad:   "First check git status. Then read config.py. Then list tests."
       → 3 sequential tool calls (unnecessarily slow)
```

### Pattern 4: Permission Rules for CI/Automation

```json
// .claude/settings.json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(bun *)",
      "Bash(python *)",
      "Bash(pytest *)",
      "FileRead(*)",
      "FileEdit(src/*)",
      "FileWrite(output/*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf*)"
    ]
  }
}
```

### Pattern 5: Background Tasks for Long Operations

```
"Run the full test suite in the background while you also check for lint errors"
→ BashTool with run_in_background: true
→ Claude gets notified when done
→ Can do other work in parallel
```

### Pattern 6: Worktree Isolation for Safe Experimentation

```
"Enter a worktree to try refactoring the pipeline without affecting main"
→ EnterWorktreeTool creates isolated git worktree
→ All edits isolated from main branch
→ ExitWorktreeTool to keep or discard changes
```

### Pattern 7: Plan Mode for Complex Multi-Step Tasks

```
"Enter plan mode and design the migration from Postgres to DuckDB"
→ EnterPlanModeTool: Claude plans without executing
→ You review and approve
→ ExitPlanModeTool: Execute approved plan
→ Mistakes caught before they happen
```

### Pattern 8: Scoped Agent for Dangerous Tasks

```typescript
// In agent definition (.claude/agents/data-validator.yaml)
---
agentType: data-validator
whenToUse: Validate data integrity and schema compliance
tools:
  - Read
  - Bash
disallowedTools:
  - Write
  - FileEdit
---
// Agent can read and run validation scripts but cannot modify files
```

---

## 15. Prompt Engineering from Source

The actual behavioral instructions Claude Code uses on itself — extracted from `src/constants/prompts.ts`:

### Core Task Approach (from `getSimpleDoingTasksSection()`)

What Claude Code tells itself about task execution:
- Read existing code before writing new code
- Make minimal targeted edits — don't refactor unnecessarily
- Always run tests/lint after changes
- If you're unsure, ask rather than guess
- Confirm before destructive operations
- Prefer existing patterns in the codebase

### Tool Priority Rules (from `getUsingYourToolsSection()`)

```
Priority order:
1. Dedicated tool (FileRead, Glob, Grep, FileEdit)
2. BashTool (when no dedicated tool can do it)

Never use Bash for:
- Reading files → use FileReadTool
- Finding files → use GlobTool
- Searching content → use GrepTool
- Editing files → use FileEditTool
- Writing files → use FileWriteTool
```

### Output Efficiency Rules (from `getOutputEfficiencySection()`)

- No preamble ("I'll help you...", "Certainly!")
- No postamble ("Let me know if...")
- Answer directly, then stop
- Reference files as `file:line` format
- No emoji unless user uses them first
- Concise bullet points over flowing prose

### Git Safety Protocol (from `src/tools/BashTool/prompt.ts`)

These are the exact rules injected into the system prompt:

```
NEVER update the git config
NEVER run: push --force, reset --hard, checkout ., restore ., clean -f, branch -D
  (unless user explicitly requests — taking unauthorized destructive actions is unhelpful)
NEVER skip hooks (--no-verify, --no-gpg-sign)
NEVER force push to main/master — warn the user
CRITICAL: Always create NEW commits (not --amend) unless user explicitly asks for amend
  When a pre-commit hook fails, the commit did NOT happen — so --amend would modify
  the PREVIOUS commit, potentially losing work
NEVER commit unless user explicitly asks
Stage specific files by name, not git add -A (avoids committing .env, credentials)
```

### Designing Your Own High-Quality Prompts

Based on how Claude Code's own prompts are structured:

```markdown
# [Section Name]
[Concise statement of purpose]

## [Subsection]
[Specific rules as bullets]
- Do X when Y
- Never do Z because [reason — this matters]
- If unclear, [specific fallback behavior]

## Examples
[Concrete examples for ambiguous rules]
```

Key principles extracted from the source:
1. **Give the reason, not just the rule** — "Never use --amend because when a pre-commit hook fails..." (agents reason better with causality)
2. **Define the fallback explicitly** — "If you're unsure, ask rather than guess"
3. **Use explicit negative constraints** — "NEVER" and "CRITICAL:" get more model attention
4. **Section structure with `#` headers** — the model attends to headers more than inline text

---

## 16. Configuration Reference

### Settings Files

| Location | Scope | Format |
|---|---|---|
| `~/.claude/settings.json` | Global user | JSON |
| `.claude/settings.json` | Project | JSON |
| `.claude/settings.local.json` | Project local (gitignored) | JSON |
| `/etc/claude-code/` | Machine-wide (enterprise) | JSON |

### Key Settings (`src/schemas/`)

```json
{
  "model": "claude-opus-4-5",
  "permissions": {
    "allow": ["Bash(git *)", "FileRead(*)"],
    "deny": ["Bash(rm -rf*)"]
  },
  "env": {
    "ANTHROPIC_API_KEY": "sk-...",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "16000"
  },
  "spinnerVerbs": {
    "mode": "append",
    "verbs": ["Analyzing", "Processing"]
  },
  "outputStyle": "default",
  "theme": "dark",
  "vim": false
}
```

### Environment Variables

| Variable | Effect |
|---|---|
| `CLAUDE_CODE_SIMPLE=1` | Strip to [BashTool, FileReadTool, FileEditTool] only |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` | Disable `run_in_background` feature |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` | Skip all CLAUDE.md file loading |
| `CLAUDE_CODE_COORDINATOR_MODE=1` | Enable multi-agent coordinator (+ `COORDINATOR_MODE` flag) |
| `CLAUDE_CODE_VERIFY_PLAN=true` | Enable plan verification tool |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Override max output tokens |
| `ENABLE_LSP_TOOL=1` | Enable Language Server Protocol tool |
| `ANTHROPIC_API_KEY` | API key (also readable from macOS Keychain) |
| `ANTHROPIC_BASE_URL` | Custom API endpoint (Bedrock, Vertex, proxies) |

---

## 17. Slash Commands Reference

### Most Useful Commands

```bash
/commit              # AI-generated git commit message
/commit-push-pr      # Commit + push + create PR in one step
/review              # Code review of staged/unstaged changes
/security-review     # Security-focused code review
/compact             # Compress conversation context (saves tokens)
/memory              # View/edit CLAUDE.md memory files
/plan                # Enter planning mode (no execution)
/ultraplan           # Enhanced planning with verification step
/cost                # Token usage and estimated cost
/doctor              # Environment diagnostics
/mcp                 # Manage MCP server connections
/skills              # View/manage skills
/model               # Switch active model
/effort              # Adjust response effort level
/context             # Visualize current context
/resume              # Restore a previous session
```

### Task Management (when TodoV2 enabled)

```bash
/tasks               # List background tasks
/agents              # Manage sub-agents
```

### Debug Commands

```bash
/doctor              # Environment check — API, auth, tools, MCP
/status              # System and session status
/stats               # Session statistics
/cost                # Token usage breakdown
/context             # Context visualization (files, memory, etc.)
```

### Hidden/Internal Commands

```bash
/break-cache         # Invalidate prompt cache (debug)
/heapdump            # Memory heap dump
/ctx_viz             # Context visualization (debug mode)
/mock-limits         # Mock rate limits for testing
/ant-trace           # Internal tracing (ant-only)
```

---

## 18. Data Engineering Patterns with Claude Code

### Pipeline Development

```markdown
# CLAUDE.md for data pipeline projects

## Pipeline Architecture
- Ingestion: src/ingestion/ (Airflow DAGs)
- Transform: src/transform/ (Pandas/DuckDB)
- Validation: src/validation/ (Great Expectations)
- Output: src/output/ (Parquet, S3)

## Data Contracts
- All schemas in: src/schemas/
- Never modify schemas without versioning
- Backward compatibility required

## Testing
- Unit: pytest tests/unit/ -x
- Integration: pytest tests/integration/ (needs DB connection)
- Data quality: python run_expectations.py

## Commands
- Run pipeline: airflow dags trigger my_pipeline
- Check status: airflow dags state my_pipeline
- Local dev: python dev_runner.py --date 2026-01-01
```

### Effective Prompts for Data Work

```
"Read the schema in src/schemas/events.py, check how it's used in 
src/transform/events_transform.py, then write a new validation 
function that checks for null primary keys and duplicate records. 
Add tests in tests/unit/test_events_validation.py."
```

```
"Run the full pipeline in the background while you review the 
schema changes in the last 3 commits and check if any downstream 
transforms need updating."
```

```
"Enter plan mode and design a migration from the current Pandas 
pipeline to DuckDB, listing every file that needs changing and 
estimating the risk of each change."
```

### Agentic Data Pipeline Validation

```yaml
# .claude/agents/pipeline-validator.yaml
---
agentType: pipeline-validator
whenToUse: Validate data pipeline output quality and schema compliance
tools:
  - Read
  - Glob
  - Grep
  - Bash
disallowedTools:
  - Write
  - FileEdit
  - FileWrite
---
Validate data integrity:
1. Check row counts match expectations
2. Validate null rates per column
3. Check date ranges are within bounds
4. Verify foreign key integrity
5. Run schema validation against registered schema
Report failures with specific row samples.
```

---

## 19. Key File Index

| File | Lines | Purpose |
|---|---|---|
| `src/main.tsx` | — | CLI entrypoint, Commander.js parser, parallel startup prefetch |
| `src/QueryEngine.ts` | ~46K | Core LLM API engine — streaming, tool loops, thinking mode, retries |
| `src/Tool.ts` | ~29K | `buildTool()` factory, `ToolDef` interface, permission result types |
| `src/commands.ts` | ~25K | Command registry, conditional loading, feature-gated commands |
| `src/tools.ts` | — | Tool registry: `getAllBaseTools()`, `getTools()`, `assembleToolPool()` |
| `src/context.ts` | — | `getGitStatus()`, `getUserContext()`, `getSystemContext()` |
| `src/constants/prompts.ts` | — | `getSystemPrompt()` and all 12+ static section builders |
| `src/constants/systemPromptSections.ts` | — | Section registry, memoization, `clearSystemPromptSections()` |
| `src/constants/spinnerVerbs.ts` | — | 188 spinner verbs (`getSpinnerVerbs()`, custom verb config) |
| `src/utils/queryContext.ts` | — | `fetchSystemPromptParts()` — central prompt assembly coordinator |
| `src/utils/api.ts` | — | `appendSystemContext()`, `prependUserContext()`, `toolToAPISchema()` |
| `src/services/api/claude.ts` | — | Final API call: attribution header, cache_control, streaming |
| `src/utils/claudemd.ts` | — | CLAUDE.md discovery, `@include` resolution, frontmatter path filtering |
| `src/memdir/memdir.ts` | — | MEMORY.md loading, 200-line/25KB truncation |
| `src/tools/BashTool/BashTool.tsx` | — | Command classification, input schema, `isSearchOrReadBashCommand()` |
| `src/tools/BashTool/bashPermissions.ts` | — | Full permission decision tree, rule matching, suggestion logic |
| `src/tools/BashTool/bashSecurity.ts` | — | 23 security validators, Zsh dangerous command blocklist |
| `src/tools/BashTool/commandSemantics.ts` | — | Exit code interpretation per command |
| `src/tools/BashTool/readOnlyValidation.ts` | — | Read-only auto-allow, per-tool flag allowlists |
| `src/tools/BashTool/prompt.ts` | — | BashTool system prompt: git safety rules, tool preference rules |
| `src/tools/AgentTool/AgentTool.tsx` | — | Sub-agent spawning, agent type resolution |
| `src/tools/AgentTool/prompt.ts` | — | Dynamic agent listing injected into tool description |
| `src/tools/AgentTool/runAgent.ts` | — | Agent execution engine |
| `src/tools/AgentTool/loadAgentsDir.ts` | — | Agent YAML definition loader |
| `src/coordinator/coordinatorMode.ts` | — | Multi-agent coordinator lifecycle |
| `src/services/mcp/config.ts` | — | MCP server configuration and registration |
| `src/hooks/toolPermission/` | — | Permission check pipeline, mode handling |
| `src/utils/permissions/autoModeState.ts` | — | Transcript classifier auto-mode state |
| `src/skills/bundled/` | — | 14 bundled skills |
| `src/skills/loadSkillsDir.ts` | — | Skill discovery from disk |
| `src/tasks/LocalShellTask/` | — | Background shell task implementation |
| `src/tasks/LocalAgentTask/` | — | Local agent task implementation |
| `src/state/AppStateStore.ts` | — | Global mutable `AppState` object |
| `src/bridge/bridgeMain.ts` | — | IDE bridge main loop (KAIROS session args at line 1787) |
| `src/types/bun-bundle.d.ts` | — | Declaration of `feature()` from `'bun:bundle'` |
| `src/utils/toolSchemaCache.ts` | — | Session-scoped tool schema cache (prevents mid-session cache busts) |
| `src/query/tokenBudget.ts` | — | Token budget tracking (`TOKEN_BUDGET` flag) |
| `src/services/compact/` | — | Context compression: reactive, micro, cached variants |
| `src/services/extractMemories/` | — | Auto-memory extraction from conversations |
| `src/schemas/` | — | Zod v4 schemas for all settings and configuration |
| `src/voice/` | — | Voice input system (STT, keybindings, `VOICE_MODE` flag) |

---

## Appendix: The 188 Spinner Verbs

*Stored in `src/constants/spinnerVerbs.ts`. Customizable via `settings.spinnerVerbs`.*

```
Accomplishing, Actioning, Actualizing, Architecting, Baking, Beaming,
Beboppin', Befuddling, Billowing, Blanching, Bloviating, Boogieing,
Boondoggling, Booping, Bootstrapping, Brewing, Bunning, Burrowing,
Calculating, Canoodling, Caramelizing, Cascading, Catapulting, Cerebrating,
Channeling, Channelling, Choreographing, Churning, Clauding, Coalescing,
Cogitating, Combobulating, Composing, Computing, Concocting, Considering,
Contemplating, Cooking, Crafting, Creating, Crunching, Crystallizing,
Cultivating, Deciphering, Deliberating, Determining, Dilly-dallying,
Discombobulating, Doing, Doodling, Drizzling, Ebbing, Effecting,
Elucidating, Embellishing, Enchanting, Envisioning, Evaporating, Fermenting,
Fiddle-faddling, Finagling, Flambéing, Flibbertigibbeting, Flowing,
Flummoxing, Fluttering, Forging, Forming, Frolicking, Frosting, Gallivanting,
Galloping, Garnishing, Generating, Gesticulating, Germinating, Gitifying,
Grooving, Gusting, Harmonizing, Hashing, Hatching, Herding, Honking,
Hullaballooing, Hyperspacing, Ideating, Imagining, Improvising, Incubating,
Inferring, Infusing, Ionizing, Jitterbugging, Julienning, Kneading,
Leavening, Levitating, Lollygagging, Manifesting, Marinating, Meandering,
Metamorphosing, Misting, Moonwalking, Moseying, Mulling, Mustering, Musing,
Nebulizing, Nesting, Newspapering, Noodling, Nucleating, Orbiting,
Orchestrating, Osmosing, Perambulating, Percolating, Perusing, Philosophising,
Photosynthesizing, Pollinating, Pondering, Pontificating, Pouncing,
Precipitating, Prestidigitating, Processing, Proofing, Propagating, Puttering,
Puzzling, Quantumizing, Razzle-dazzling, Razzmatazzing, Recombobulating,
Reticulating, Roosting, Ruminating, Sautéing, Scampering, Schlepping,
Scurrying, Seasoning, Shenaniganing, Shimmying, Simmering, Skedaddling,
Sketching, Slithering, Smooshing, Sock-hopping, Spelunking, Spinning,
Sprouting, Stewing, Sublimating, Swirling, Swooping, Symbioting, Synthesizing,
Tempering, Thinking, Thundering, Tinkering, Tomfoolering, Topsy-turvying,
Transfiguring, Transmuting, Twisting, Undulating, Unfurling, Unravelling,
Vibing, Waddling, Wandering, Warping, Whatchamacalliting, Whirlpooling,
Whirring, Whisking, Wibbling, Working, Wrangling, Zesting, Zigzagging
```

---

*Source mapping completed: April 1, 2026*
*Based on: `git clone https://github.com/TaGoat/claude_code_cli`*
*Branch: `main` (documentation layer over unmodified source snapshot)*

# 2 CHANNEL:
Channel A — appendSystemContext()
"
Definition: src/utils/api.ts lines 437–447
function appendSystemContext(systemPrompt: PromptBlock[], systemContext: Record<string, string>) {
  for (const [key, value] of Object.entries(systemContext)) {
    systemPrompt.push({
      type: 'text',
      text: `${key}: ${value}\n`,
      cacheScope: null,  // volatile — never cached
    })
  }
}
"

Called from: src/query.ts lines 449–451
appendSystemContext(systemPrompt, systemContext)
// → appends git status, branch name, last commits to END of system prompt array

Data source: src/context.ts → getSystemContext() (lines 116–150)
- Runs 5 parallel git commands: branch, main-branch detection, git user, git status, last 5 commits
- Result: { gitStatus, cacheBreaker? } dict passed into Channel A

---
Channel B — prependUserContext() / <system-reminder>

Definition: src/utils/api.ts lines 449–474
function prependUserContext(messages: Message[], userContext: Record<string, string>) {
  const text = `<system-reminder>\nAs you answer the user's questions, you can use the following context:\n`
    + Object.entries(userContext).map(([k, v]) => `# ${k}\n${v}`).join('\n')
    + `\n\nIMPORTANT: this context may or may not be relevant...`
    + `\n</system-reminder>`

  messages.unshift({ role: 'user', content: text, isMeta: true })
  // → inserted at position 0 of the messages array every single turn
}

Called from: src/query.ts lines 659–661
prependUserContext(messagesForQuery, userContext)
// → prepends <system-reminder> block as messages[0] before every API call

Data source: src/context.ts → getUserContext() (lines 155–189)
- Reads all CLAUDE.md files (managed → user → project → local hierarchy)
- Appends currentDate: Today's date is {ISO date}.
- Result: { claudeMd, currentDate } dict passed into Channel B

---
Why the Split?

The architectural reason is prompt cache stability:

- Channel A (system prompt) = cached with cacheScope: 'global' for static sections. Git status is appended at the end as volatile (cacheScope: null) so it doesn't bust
  the cached prefix.
- Channel B (messages[0]) = CLAUDE.md lives here because if it were in the system prompt, any edit to your CLAUDE.md would invalidate the entire cached system prompt,
costing you the cache hit every turn. As message[0] it's outside the cached system prompt entirely.

The <system-reminder> wrapper you see right now in this conversation — that's literally the output of prependUserContext() running in real-time on top of this session.