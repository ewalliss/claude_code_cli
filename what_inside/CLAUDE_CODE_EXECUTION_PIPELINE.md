# Claude Code CLI — Full Execution Pipeline

> **Source-grounded documentation of what happens between Enter and response**
> Based on full source mapping of `src/` (~1,900 files, 512K+ lines TypeScript)
> AI Engineer & Data Engineer Reference · April 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Stage 0 — Input Capture (REPL)](#2-stage-0--input-capture-repl)
3. [Stage 1 — Input Processing & Command Detection](#3-stage-1--input-processing--command-detection)
4. [Stage 2 — Message Construction](#4-stage-2--message-construction)
5. [Stage 3 — QueryGuard: Serialize or Enqueue](#5-stage-3--queryguard-serialize-or-enqueue)
6. [Stage 4 — QueryEngine.submitMessage()](#6-stage-4--queryenginesubmitmessage)
7. [Stage 5 — query() Inner Loop](#7-stage-5--query-inner-loop)
8. [Stage 6 — API Call Construction](#8-stage-6--api-call-construction)
9. [Stage 7 — SSE Stream Processing](#9-stage-7--sse-stream-processing)
10. [Stage 8 — Tool Execution Loop](#10-stage-8--tool-execution-loop)
11. [Stage 9 — Loop Continuation](#11-stage-9--loop-continuation)
12. [Stage 10 — Stop Hooks & Termination](#12-stage-10--stop-hooks--termination)
13. [Stage 11 — UI Rendering (Throughout)](#13-stage-11--ui-rendering-throughout)
14. [Stage 12 — Session Cleanup](#14-stage-12--session-cleanup)
15. [Complete Data Flow Diagram](#15-complete-data-flow-diagram)
16. [Timing Reference](#16-timing-reference)
17. [Key Architectural Decisions Explained](#17-key-architectural-decisions-explained)
18. [Source File Index](#18-source-file-index)

---

## 1. Overview

When a user types a message and presses **Enter** in Claude Code, the following high-level sequence occurs:

```
Enter keypress
  → Input validation & slash command detection
  → Message object construction (UUID, metadata, attachments)
  → QueryGuard: serialize concurrent turns
  → QueryEngine.submitMessage(): context assembly (parallel)
  → query() loop: pre-flight message processing
  → API request construction (cache headers, two-channel context)
  → HTTP streaming to Anthropic API
  → SSE stream parsed: text deltas → UI, tool_use blocks → executor
  → Tool execution (permission check → run → result)
  → Results fed back into messages → loop continues
  → end_turn → stop hooks → session persisted
  → REPL resets to input prompt
```

This entire cycle is an **async generator pipeline**. Every yielded value is a typed `SDKMessage` that flows to the REPL's React state, triggering real-time UI re-renders via Ink.

---

## 2. Stage 0 — Input Capture (REPL)

**Primary file:** `src/screens/REPL.tsx`

The REPL is a **React component** rendered by [Ink](https://github.com/vadimdemedes/ink) — React for terminal UIs. It is the outermost container of the entire interactive session.

### Keystroke handling

```typescript
// src/screens/REPL.tsx line 12
import { useInput } from '../ink.js'
```

Ink's `useInput()` hook registers a raw keypress listener on stdin. The actual text editing experience is delegated to `<PromptInput>` (`src/components/PromptInput/PromptInput.js`), which:

- Maintains a mutable string buffer of the in-progress input
- Handles cursor movement, Vim mode (`useVimMode`), history navigation (↑↓ arrows)
- On **Enter** keypress → fires the submit callback with the finalized input string

### Special global keys (always active)

| Key | Behavior | Source |
|---|---|---|
| `Ctrl+C` | Cancel current request / exit | `CancelRequestHandler` |
| `Ctrl+Z` | Suspend process | OS-level SIGTSTP |
| `Ctrl+R` | Reverse history search | `useSearchInput` |
| `Esc` | Cancel streaming response | abort controller |
| `/` prefix | Slash command mode | `parseSlashCommand()` |

### Voice input (feature-gated)

```typescript
// src/screens/REPL.tsx line 98 — dead code elimination
const useVoiceIntegration = feature('VOICE_MODE')
  ? require('../hooks/useVoiceIntegration.js').useVoiceIntegration
  : () => ({ stripTrailing: () => 0, handleKeyEvent: () => {} })
```

Voice input is compiled out of public builds. When enabled, speech-to-text is streamed via `src/services/voiceStreamSTT.ts`.

---

## 3. Stage 1 — Input Processing & Command Detection

**Primary file:** `src/utils/processUserInput/processUserInput.ts`

The submit callback calls `processUserInput()` — the **first real decision tree** in the pipeline.

### Function signature

```typescript
export async function processUserInput({
  input,              // string | ContentBlockParam[]
  preExpansionInput,  // input before [Pasted text #N] expansion
  mode,               // 'normal' | 'voice' | 'vim'
  context,            // ToolUseContext (full session state)
  messages,           // current conversation history
  pastedContents,     // pasted image/text blobs
  ideSelection,       // cursor selection from IDE bridge
  uuid,               // pre-assigned UUID for this message
  querySource,        // 'repl_main_thread' | 'agent:...' | etc.
  isMeta,             // is this a synthetic system message?
  skipSlashCommands,  // skip command parsing (bridge mode)
  ...
})
```

### Decision tree

```
input received
     │
     ├─ hasUltraplanKeyword(input)?
     │    └─ YES → replaceUltraplanKeyword() → rewrite to /ultraplan prompt
     │
     ├─ parseSlashCommand(input) matches?
     │    │
     │    ├─ findCommand() → LocalCommand
     │    │    └─ run in-process → return text → shouldQuery: false
     │    │
     │    ├─ findCommand() → LocalJSXCommand
     │    │    └─ render JSX (e.g. /doctor, /install) → shouldQuery: false
     │    │
     │    └─ findCommand() → PromptCommand
     │         └─ getPromptForCommand(args, context)
     │              → returns ContentBlockParam[] (the prompt)
     │              → shouldQuery: true → continue as normal query
     │
     └─ normal text prompt
          └─ processTextPrompt() → shouldQuery: true
```

### User-prompt-submit hooks

Before anything reaches the API:

```typescript
// src/utils/processUserInput/processUserInput.ts
await executeUserPromptSubmitHooks(input, context)
const blockingMessage = getUserPromptSubmitHookBlockingMessage()
if (blockingMessage) {
  return { messages: [blockingMessage], shouldQuery: false }
}
```

If a `<user-prompt-submit-hook>` script returns a blocking response, **the query is aborted entirely** — no API call is made. This is how pre-flight validators work (lint checks, format validators, etc.).

### Attachment resolution

```typescript
// src/utils/attachments.ts
const attachments = await getAttachmentMessages(input, context)
```

Resolves:
- `@filename` references → reads file → inlines content or creates attachment message
- Pasted images → resizes/downsamples via `src/utils/imageResizer.ts` → base64 image blocks
- IDE selections → appended as context blocks
- Agent mentions (`@AgentName`) → routes to multi-agent coordinator

---

## 4. Stage 2 — Message Construction

**Primary file:** `src/utils/messages.ts`

### createUserMessage()

```typescript
export function createUserMessage({
  content,           // ContentBlockParam[]
  toolUseResult?,    // string (if this is a tool result)
  uuid?,             // pre-assigned UUID
  isMeta?,           // true = synthetic, not shown in UI
  ...
}): UserMessage {
  return {
    type: 'user',
    uuid: uuid ?? randomUUID(),
    message: {
      role: 'user',
      content,
    },
    isMeta: isMeta ?? false,
    timestamp: Date.now(),
  }
}
```

The `uuid` is critical — it links tool_use blocks to their results across turns, and is used for session replay via `/resume`.

### Message types in the system

| Type | Role | Purpose |
|---|---|---|
| `UserMessage` | user | Human input, tool results |
| `AssistantMessage` | assistant | Model output, tool_use blocks |
| `AttachmentMessage` | user | File/image attachments |
| `SystemMessage` | — | Internal notifications (not sent to API) |
| `ProgressMessage` | — | Real-time tool progress UI |
| `TombstoneMessage` | — | Marks messages to remove from UI (fallback recovery) |
| `ToolUseSummaryMessage` | — | Compressed summary of tool calls |

---

## 5. Stage 3 — QueryGuard: Serialize or Enqueue

**Primary file:** `src/utils/QueryGuard.ts`

```typescript
// src/screens/REPL.tsx line 35
import { QueryGuard } from '../utils/QueryGuard.js'
```

The `QueryGuard` ensures only one query runs at a time per session. This matters because:

1. The `while (true)` query loop mutates the `messages` array in-place
2. Running two queries concurrently would interleave tool results with wrong turn contexts
3. Users can type while a response streams — those messages queue up

```
queryGuard.isActive?
├─ YES → message pushed to pending queue
│         when current query ends → dequeue → start next
└─ NO  → acquire guard → begin query
```

The queued commands are visible in the `<PromptInputQueuedCommands>` component shown at the bottom of the input area while a query is running.

---

## 6. Stage 4 — QueryEngine.submitMessage()

**Primary file:** `src/QueryEngine.ts` line 209

This is the main conversation manager. One `QueryEngine` instance lives for the lifetime of a session. `submitMessage()` is an **async generator** — it `yield`s `SDKMessage` objects consumed by the REPL's render loop.

### Class state (persists across turns)

```typescript
class QueryEngine {
  private mutableMessages: Message[]        // full conversation history
  private abortController: AbortController  // Ctrl+C handling
  private permissionDenials: SDKPermissionDenial[]
  private totalUsage: NonNullableUsage       // cumulative token costs
  private readFileState: FileStateCache      // tracks which file versions were read
  private discoveredSkillNames: Set<string>  // per-turn skill discovery cache
  private loadedNestedMemoryPaths: Set<string>
}
```

### Context assembly — PARALLEL fetch

The very first action inside `submitMessage()` is a parallel fetch of all context needed for the system prompt:

```typescript
// src/utils/queryContext.ts line 44
const { defaultSystemPrompt, userContext, systemContext }
  = await fetchSystemPromptParts({
      tools,
      mainLoopModel,
      additionalWorkingDirectories,
      mcpClients,
      customSystemPrompt,
    })
```

Which internally runs three things **concurrently**:

```typescript
// src/utils/queryContext.ts line 61
const [defaultSystemPrompt, userContext, systemContext] = await Promise.all([

  // CHANNEL A (static): 12+ section builders, cached globally
  getSystemPrompt(tools, mainLoopModel, additionalDirs, mcpClients),

  // CHANNEL B data: reads all CLAUDE.md files + appends today's date
  getUserContext(),   // src/context.ts line 155

  // CHANNEL A (dynamic): runs 5 git shell commands in parallel
  getSystemContext(), // src/context.ts line 116
])
```

### What getSystemContext() does (Channel A dynamic data)

`src/context.ts` lines 116–150 runs these **5 git commands in parallel** via `Promise.all`:

```bash
git rev-parse --abbrev-ref HEAD      # current branch name
git rev-parse --abbrev-ref origin/HEAD  # main/master detection
git config user.name                 # git author name
git status --short                   # file changes (truncated at 2000 chars)
git log --oneline -5                 # last 5 commit messages
```

All results are combined into `{ gitStatus: string }` and appended to the system prompt as volatile blocks.

### What getUserContext() does (Channel B data)

`src/context.ts` lines 155–189 reads:

1. All CLAUDE.md files (managed → user → project → local hierarchy via `src/utils/claudemd.ts`)
2. Appends `currentDate: Today's date is {ISO-8601 date}.`

Returns: `{ claudeMd: string, currentDate: string }`

This dict is **not** appended to the system prompt. It becomes the `<system-reminder>` block at `messages[0]`.

### System prompt object assembly

```typescript
// src/QueryEngine.ts lines 321–325
const systemPrompt = asSystemPrompt([
  ...(customPrompt !== undefined ? [customPrompt] : defaultSystemPrompt),
  ...(memoryMechanicsPrompt ? [memoryMechanicsPrompt] : []),
  ...(appendSystemPrompt ? [appendSystemPrompt] : []),
])
```

If the caller provides `customSystemPrompt`, the entire default system prompt is **replaced**. `appendSystemPrompt` is always additive on top.

---

## 7. Stage 5 — query() Inner Loop

**Primary file:** `src/query.ts` line 219 → `queryLoop()` line 241

This is the **agentic engine** — the `while (true)` loop that drives each tool-use round-trip.

```typescript
export async function* query(params: QueryParams): AsyncGenerator<...> {
  const terminal = yield* queryLoop(params, consumedCommandUuids)
  return terminal
}

async function* queryLoop(params, consumedCommandUuids) {
  let state: State = { messages, toolUseContext, turnCount: 1, ... }

  while (true) {
    // ... per-iteration logic
    // If needsFollowUp === true  → continue
    // If needsFollowUp === false → return { reason: 'end_turn' }
  }
}
```

### Per-iteration pre-flight processing (in order)

Every iteration of the loop applies these transformations to `messagesForQuery` before making the API call:

| Step | Function | Purpose |
|---|---|---|
| 1 | `getMessagesAfterCompactBoundary()` | Slice history after last `/compact` |
| 2 | `applyToolResultBudget()` | Truncate oversized tool results |
| 3 | `snipCompactIfNeeded()` | `HISTORY_SNIP`: remove old messages |
| 4 | `microcompact()` | Compress redundant tool result pairs |
| 5 | `applyCollapsesIfNeeded()` | `CONTEXT_COLLAPSE`: fold old sections |
| 6 | `autocompact()` | Full summary compaction near context limit |
| 7 | token blocking check | Yield error + return if at hard limit |

### Channel A finalized (line 449)

```typescript
// src/query.ts line 449
const fullSystemPrompt = asSystemPrompt(
  appendSystemContext(systemPrompt, systemContext)
)
```

`appendSystemContext()` (`src/utils/api.ts` line 437) appends git status etc. as **volatile** (`cacheScope: null`) blocks at the END of the system prompt array. These never receive `cache_control` and are recomputed every turn.

### Channel B injected (line 660)

```typescript
// src/query.ts line 660
messages: prependUserContext(messagesForQuery, userContext),
```

`prependUserContext()` (`src/utils/api.ts` line 449) inserts the `<system-reminder>` block as `messages[0]` — a synthetic user message with `isMeta: true`. This happens **every single turn**, right before the API call, and is not persisted to the conversation history.

The resulting `<system-reminder>` block looks exactly like this (you can see it in any Claude Code session):

```xml
<system-reminder>
As you answer the user's questions, you can use the following context:
# claudeMd
{contents of all CLAUDE.md files in hierarchy}
# currentDate
Today's date is 2026-04-01.

IMPORTANT: this context may or may not be relevant to your tasks.
You should not respond to this context unless it is highly relevant to your task.
</system-reminder>
```

---

## 8. Stage 6 — API Call Construction

**Primary file:** `src/services/api/claude.ts`

`deps.callModel()` routes to `streamDangerousMessageStream()` in `claude.ts`, which constructs the final `BetaMessageStreamParams`.

### Message normalization

```typescript
// src/utils/messages.ts
normalizeMessagesForAPI(messages, tools)
```

Strips all internal Claude Code metadata that the Anthropic API rejects:
- `uuid` fields
- `timestamp` fields
- `isMeta` flags
- Internal tool result metadata
- `ProgressMessage` and `SystemMessage` types (never sent to API)

Converts `Message[]` → `MessageParam[]` (Anthropic SDK types).

### Prompt cache control applied

```typescript
// src/utils/api.ts
splitSysPromptPrefix(systemPrompt)
```

The system prompt array is split at `SYSTEM_PROMPT_DYNAMIC_BOUNDARY`. Everything before the boundary gets `cache_control: { type: "ephemeral" }` — telling Anthropic's servers to cache this prefix for 5 minutes across requests from the same API key.

The cache structure:

```
System prompt array:
  [0] intro section          ← cacheScope: 'global'   (stable, cached)
  [1] rules section          ← cacheScope: 'global'   (stable, cached)
  [2] tool descriptions      ← cacheScope: 'global'   (stable, cached)
  ...
  [N] SYSTEM_PROMPT_DYNAMIC_BOUNDARY ← cache_control breakpoint here
  [N+1] MCP instructions     ← cacheScope: null       (volatile, not cached)
  [N+2] git status           ← cacheScope: null       (volatile, not cached)
```

### Tool schema serialization

```typescript
// src/utils/api.ts line 170
toolToAPISchema(tool) → BetaToolUnion
```

Each tool's Zod `inputSchema` is converted to JSON Schema format for the API. Tools are sorted **alphabetically by name** in `assembleToolPool()` (`src/tools.ts`) — this ensures adding a new MCP tool doesn't change the position of existing tools in the array, preserving cache hits on the tool list.

### Final BetaMessageStreamParams

```typescript
{
  model: currentModel,                  // e.g. 'claude-opus-4-5'
  max_tokens: computedMaxTokens,
  system: fullSystemPrompt,             // array of {type, text, cache_control?}
  messages: [
    { role: 'user',      content: '<system-reminder>...</system-reminder>' }, // isMeta
    { role: 'user',      content: 'User's actual message' },
    { role: 'assistant', content: [...] },  // previous turns
    // ...
  ],
  tools: toolSchemas,                   // alphabetically sorted
  thinking: thinkingConfig,             // { type: 'adaptive' } or disabled
  betas: ['interleaved-thinking-2025-05-14', ...],
  stream: true,
}
```

### HTTP request execution

```typescript
// src/services/api/client.ts
client.beta.messages.stream(params)
```

The Anthropic SDK client is configured with:
- API key (from `ANTHROPIC_API_KEY` env or OS Keychain)
- Attribution header: `X-API-Source: cli`
- Version header: `X-CLI-Version: {semver}`
- Base URL (configurable for Bedrock/Vertex/proxy)
- Retry logic (`withRetry()` in `src/services/api/withRetry.ts`)

---

## 9. Stage 7 — SSE Stream Processing

**Primary file:** `src/query.ts` lines 659–863

The `for await` loop over `deps.callModel()` processes each Server-Sent Event from the stream.

### Stream event types

| Event type | Action |
|---|---|
| `text_delta` | Appended to current `AssistantMessage.message.content[].text` → yielded to REPL |
| `thinking_delta` | Appended to thinking block (shown as collapsible in UI) |
| `tool_use` start | New `ToolUseBlock` created, input JSON accumulates |
| `tool_use` complete | `needsFollowUp = true`, block pushed to `toolUseBlocks[]` |
| `message_delta` (stop_reason) | Sets the stop reason (but the code uses `needsFollowUp`, not stop_reason directly — see comment in source) |
| `error` | Yielded as synthetic `AssistantMessage` with `isApiErrorMessage: true` |

### Streaming tool execution (gates.streamingToolExecution)

When this gate is on (configured via `buildQueryConfig()`), the `StreamingToolExecutor` (`src/services/tools/StreamingToolExecutor.ts`) is active:

```
tool_use input JSON fully received
  → StreamingToolExecutor.startTool(block)
  → permission check begins IMMEDIATELY
  → tool.call() begins BEFORE the model finishes streaming
```

This parallelizes tool execution with the tail of the model response, reducing wall-clock latency.

### Withholding recoverable errors

The stream loop **withholds** certain error messages from the REPL until recovery is attempted:

- **Prompt-too-long (413)** → try context collapse drain → try reactive compact → surface if both fail
- **Max output tokens** → try recovery loop (up to 3 times) → surface if exhausted
- **Media size error** → try reactive compact strip → surface if failed

This prevents the REPL from showing an error that the engine is about to automatically recover from.

---

## 10. Stage 8 — Tool Execution Loop

**Primary file:** `src/services/tools/toolOrchestration.ts` line 19

After the model finishes streaming, if `needsFollowUp === true`:

```typescript
for await (const update of runTools(
  toolUseBlocks,
  assistantMessages,
  canUseTool,
  toolUseContext,
)) {
  yield update.message   // tool result messages → REPL renders them
  toolResults.push(...)
}
```

### Concurrency partitioning

`partitionToolCalls()` (line 91) groups the tool calls from a single assistant turn:

```
tool call list:
  [FileRead, FileRead, Grep, BashTool(write), FileEdit]
              │
              ▼
  Batch 1: [FileRead, FileRead, Grep]  → isConcurrencySafe = true
                                          → run ALL THREE in parallel
  Batch 2: [BashTool(write)]            → isConcurrencySafe = false
                                          → run alone, serially
  Batch 3: [FileEdit]                   → isConcurrencySafe = false
                                          → run alone, serially
```

Concurrency is determined by `tool.isConcurrencySafe(input)`. Read-only tools (FileRead, Grep, Glob, WebFetch, etc.) return `true`. Write tools return `false`.

Default max concurrency: `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` env var, default `10`.

### Permission check flow

For each tool invocation, `canUseTool()` (`src/hooks/useCanUseTool.ts`) runs this decision tree:

```
1. Is tool name in DENY rules?
   YES → reject immediately (no prompt)

2. Is tool in ALLOW rules? (wildcard match)
   YES → auto-allow

3. Is permission mode 'bypassPermissions'?
   YES → auto-allow everything

4. Is tool.isReadOnly(input) === true?
   YES + mode allows read-only auto → auto-allow

5. Is permission mode 'plan'?
   YES → show planned action, ask once for batch

6. Default mode:
   → Show PermissionRequest dialog in terminal
   → Wait for user keypress (y/n/always/never)
```

Rule matching uses prefix-based wildcard patterns:

```
Bash(git *)       → matches any git subcommand
FileEdit(/src/*)  → matches any file under /src/
FileRead(*)       → matches any file path
```

Environment variables in commands are stripped before matching (e.g., `TMPDIR=/tmp git status` → matches `Bash(git *)`).

### Tool execution

`runToolUse()` in `src/services/tools/toolExecution.ts` calls `tool.call(args, toolUseContext)`.

Each tool lives in `src/tools/{ToolName}/{ToolName}.ts` and follows the `buildTool()` pattern:

```typescript
export const BashTool = buildTool({
  name: 'Bash',
  inputSchema: z.object({
    command: z.string(),
    timeout: z.number().optional(),
    description: z.string().optional(),
    run_in_background: z.boolean().optional(),
    dangerouslyDisableSandbox: z.boolean().optional(),
  }),
  async call(args, context) { ... },
  async checkPermissions(input, context) { ... },
  isConcurrencySafe(input) { return false },
  isReadOnly(input) { return isReadOnlyBashCommand(input.command) },
})
```

The tool result is wrapped in a `UserMessage`:

```typescript
{
  type: 'user',
  message: {
    role: 'user',
    content: [{
      type: 'tool_result',
      tool_use_id: block.id,   // must match the tool_use block's ID
      content: resultString,
      is_error: false,
    }]
  },
  toolUseResult: resultString,
  sourceToolAssistantUUID: assistantMessage.uuid,
}
```

---

## 11. Stage 9 — Loop Continuation

After all tools in a turn execute, their results are merged back into the message state:

```typescript
// src/query.ts continue site (~line 1192)
state = {
  ...state,
  messages: [
    ...messages,
    ...assistantMessages,   // model's tool_use response
    ...toolResults,         // our tool_result responses
  ],
  turnCount: turnCount + 1,
  transition: { reason: 'tool_use' },
}
continue  // → top of while(true) → Stage 5 again
```

The loop makes a **new API call** with the full extended history. The model sees:

```
[original conversation]
[assistant: "I'll check that file" + tool_use block]
[user: tool_result with file contents]
```

And continues generating from there. This repeats until the model returns a response with no tool_use blocks (`needsFollowUp === false`).

### Turn limits

The loop enforces hard limits:

```typescript
if (maxTurns && turnCount >= maxTurns) {
  return { reason: 'max_turns' }
}
```

Default `maxTurns` is unlimited in interactive mode. SDK/headless callers set their own limits. The `--max-turns` CLI flag sets it for `--print` mode.

---

## 12. Stage 10 — Stop Hooks & Termination

**Primary file:** `src/query/stopHooks.ts`

When `needsFollowUp === false` (model said end_turn), stop hooks run:

```typescript
const stopHookResult = await handleStopHooks(
  [...messagesForQuery, ...assistantMessages],
  systemPrompt,
  userContext,
  systemContext,
  toolUseContext,
  querySource,
)
```

Stop hooks are shell scripts or commands configured by the user that fire after each model turn. If a stop hook returns a "retry" signal, the query loop continues one more iteration.

### Terminal return values

The generator returns one of:

| Reason | Meaning |
|---|---|
| `end_turn` | Normal completion |
| `aborted_streaming` | User pressed Esc / Ctrl+C |
| `max_turns` | Hit turn limit |
| `blocking_limit` | Context window full, auto-compact off |
| `model_error` | API error that couldn't be recovered |
| `image_error` | Image too large to process |

---

## 13. Stage 11 — UI Rendering (Throughout)

**Primary files:** `src/screens/REPL.tsx`, `src/components/VirtualMessageList.tsx`

The REPL is a React component that iterates the async generator from `QueryEngine.submitMessage()`. Every yielded message triggers `setMessages()` → React state update → Ink re-render.

### Message rendering pipeline

```
SDKMessage yielded
  → setMessages(prev => [...prev, message])
  → React schedules re-render
  → Ink flushes to terminal (< 50ms)
```

Each message type has a dedicated renderer:

| Message | Renderer | Location |
|---|---|---|
| `AssistantMessage` (text) | Markdown renderer | `src/components/Messages.tsx` |
| `AssistantMessage` (thinking) | Collapsible thinking block | `src/components/ThinkingBlock.tsx` |
| Tool use invocation | `tool.renderToolUseMessage()` | `src/tools/{Name}/UI.tsx` |
| Tool result | `tool.renderToolResultMessage()` | `src/tools/{Name}/UI.tsx` |
| `SystemMessage` (warning/info) | Colored text | `src/components/Messages.tsx` |
| `ProgressMessage` | Live updating progress | `src/components/ProgressMessage.tsx` |

### Spinner

While a query is in-flight, the `<SpinnerWithVerb>` component shows:

```
⠸ Analyzing...
⠼ Searching...
⠴ Thinking...
```

Verbs come from `src/constants/spinnerVerbs.ts` — 188 verbs, rotated randomly. Custom verbs can be added via settings. The spinner mode switches between `querying` (API call) and `executing` (tool run).

### Virtual list

For long conversations, `<VirtualMessageList>` (`src/components/VirtualMessageList.tsx`) virtualizes rendering — only visible messages are mounted in the DOM. This keeps the terminal responsive during very long agentic runs.

---

## 14. Stage 12 — Session Cleanup

**Primary file:** `src/utils/sessionStorage.ts`

After the turn ends (generator exhausts):

```typescript
// src/utils/sessionStorage.ts
await recordTranscript(
  sessionId,
  agentId,
  allMessages,
)

await saveCurrentSessionCosts()

await flushSessionStorage()
```

### Session transcript

Messages are serialized as newline-delimited JSON to:

```
~/.claude/projects/{cwd-hash}/{sessionId}.jsonl
```

Each line is one message. This enables:
- `/resume` — restore and continue any previous session
- `--continue` flag — pick up the last session automatically
- `/export` — export to markdown/JSON

### REPL state reset

After cleanup, the REPL:

1. Clears the `isProcessing` flag
2. Clears the input buffer
3. Fires `QueryGuard.release()` → if queue is non-empty, starts next queued turn
4. Focuses the `<PromptInput>` component
5. Optionally shows the cost summary (`useCostSummary()`)

---

## 15. Complete Data Flow Diagram

```
╔══════════════════════════════════════════════════════════════════════╗
║  USER PRESSES ENTER                                                  ║
╚══════════════════════╦═══════════════════════════════════════════════╝
                       │
                       ▼
         ┌─────────────────────────────┐
         │   src/screens/REPL.tsx      │
         │   useInput() → Enter key    │
         │   PromptInput submit cb     │
         └──────────────┬──────────────┘
                        │ input: string
                        ▼
         ┌─────────────────────────────────────────┐
         │  processUserInput()                     │
         │  src/utils/processUserInput/            │
         │  processUserInput.ts                    │
         │                                         │
         │  ┌─ slash command? ──────────────────┐  │
         │  │  LocalCommand  → return text      │  │
         │  │  LocalJSXCommand → render JSX     │  │
         │  │  PromptCommand → build prompt     │  │
         │  └───────────────────────────────────┘  │
         │                                         │
         │  ┌─ submit hooks? ────────────────────┐ │
         │  │  blocking → abort, return          │ │
         │  └────────────────────────────────────┘ │
         │                                         │
         │  createUserMessage()                    │
         │  getAttachmentMessages()                │
         └────────────────┬────────────────────────┘
                          │ Message[]
                          ▼
         ┌────────────────────────────┐
         │  QueryGuard               │
         │  isActive? → enqueue      │
         │  else → proceed           │
         └──────────────┬────────────┘
                        │
                        ▼
         ┌──────────────────────────────────────────────┐
         │  QueryEngine.submitMessage()                 │
         │  src/QueryEngine.ts:209                      │
         │                                              │
         │  Promise.all([                               │
         │    getSystemPrompt(),   ← Channel A static   │
         │    getUserContext(),    ← Channel B data      │
         │    getSystemContext(),  ← Channel A dynamic   │
         │  ])                                          │
         │                                              │
         │  assemble systemPrompt object                │
         └──────────────────┬───────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────────────┐
         │  query() → queryLoop()                       │
         │  src/query.ts:219, 241                       │
         │                                              │
         │  ┌─────────────────────────────────────────┐ │
         │  │  while (true):                          │ │
         │  │                                         │ │
         │  │  [pre-flight]                           │ │
         │  │  getMessagesAfterCompactBoundary()      │ │
         │  │  applyToolResultBudget()                │ │
         │  │  snipCompactIfNeeded()                  │ │
         │  │  microcompact()                         │ │
         │  │  applyCollapsesIfNeeded()               │ │
         │  │  autocompact()                          │ │
         │  │  token blocking check                   │ │
         │  │                                         │ │
         │  │  [context finalization]                 │ │
         │  │  appendSystemContext()  ← Channel A     │ │
         │  │  prependUserContext()   ← Channel B     │ │
         │  │  normalizeMessagesForAPI()              │ │
         │  │  splitSysPromptPrefix() ← cache_control │ │
         │  │                                         │ │
         │  │  [API call]                             │ │
         │  │  client.beta.messages.stream()          │ │
         │  │        │                                │ │
         │  │        ▼                                │ │
         │  │  for await (event of stream):           │ │
         │  │  ├─ text_delta → yield → REPL renders  │ │
         │  │  ├─ tool_use   → needsFollowUp = true  │ │
         │  │  └─ end        → break                 │ │
         │  │                                         │ │
         │  │  [tool execution]                       │ │
         │  │  if needsFollowUp:                      │ │
         │  │    runTools()                           │ │
         │  │    ├─ partitionToolCalls()              │ │
         │  │    │   read-only → parallel batch       │ │
         │  │    │   write     → serial               │ │
         │  │    ├─ canUseTool() ← permission check   │ │
         │  │    └─ tool.call() ← execute             │ │
         │  │                                         │ │
         │  │    messages += [assistant + results]    │ │
         │  │    continue ◄────────────────────────── │ │
         │  │                                         │ │
         │  │  if !needsFollowUp:                     │ │
         │  │    handleStopHooks()                    │ │
         │  │    return { reason: 'end_turn' }        │ │
         │  └─────────────────────────────────────────┘ │
         └──────────────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────┐
         │  Session cleanup             │
         │  recordTranscript()          │
         │  saveCurrentSessionCosts()   │
         │  QueryGuard.release()        │
         │  REPL resets → await input   │
         └──────────────────────────────┘
```

---

## 16. Timing Reference

| Phase | Typical Duration | Notes |
|---|---|---|
| Input processing | < 5ms | In-process, no I/O |
| `fetchSystemPromptParts()` | 100–500ms | Parallelized git + file I/O |
| QueryGuard acquire | 0ms (no contention) | May queue if concurrent |
| First API byte (TTFT) | 500ms–3s | Network + model load |
| Streaming (full response) | 1–30s | Model + output length dependent |
| Tool: FileRead | 5–50ms | SSD read |
| Tool: Grep/Glob | 10–200ms | Ripgrep subprocess |
| Tool: BashTool | 100ms–5s | Subprocess + process overhead |
| Tool: WebFetch | 200ms–3s | Network dependent |
| Tool: AgentTool | 5s–5min | Spawns full sub-query |
| Per tool-use round-trip | +TTFT | Full new API call |
| `recordTranscript()` | 10–50ms | Async file write |
| UI re-render (Ink) | < 16ms | React scheduler |

**Observed end-to-end latencies:**

- Simple read + respond: ~1–4s
- Code edit task (3–5 tools): ~10–30s
- Large codebase task (10+ tools): ~1–5min
- Multi-agent coordinator task: ~5–30min

---

## 17. Key Architectural Decisions Explained

### Why is there a `while (true)` loop?

Each tool-use block requires a complete API round-trip. The model sends `stop_reason: tool_use` when it wants to call a tool. Claude Code executes it, appends the result, and calls the API again. The model continues generating from where it left off, now with the tool result in context.

This loop is the **agentic engine**. Without it, Claude Code would be a one-shot query system. The loop is what enables multi-step tasks.

### Why are context delivery split into two channels?

**Cache economics.**

The system prompt is cached globally for 5 minutes across all requests from the same API key. A 10,000-token system prompt cached globally saves ~$0.03 per cache hit at current pricing.

If CLAUDE.md content lived in the system prompt, any edit to your `CLAUDE.md` would bust the entire cache. By injecting it into `messages[0]` instead, the system prompt stays byte-identical across turns, maximizing cache hits.

The rule: **anything that could change between turns → Channel B. Everything static → Channel A.**

### Why are tools sorted alphabetically?

Tool descriptions are part of the system prompt. If you add a new MCP server with a tool named "Alpha", and tools are sorted by insertion order, "Alpha" would insert at the beginning of the tool list — shifting every other tool's position and busting the entire tool-list cache for every session.

Alphabetical sorting means a new tool only changes two positions: its own insertion point and nothing else — **preserving prefix caching** for all tools that come before it alphabetically.

### Why does the message array include `isMeta: true` messages?

Some messages are **operational infrastructure**, not conversation content:
- The `<system-reminder>` block (CLAUDE.md + date) is `isMeta: true`
- Tool result messages that are intermediate steps
- Synthetic messages injected by compaction

These are stripped from UI display and some export formats, but **always sent to the API** so Claude has the full operational context.

### Why does `QueryEngine` persist state across `submitMessage()` calls?

Unlike a stateless function, `QueryEngine` owns the conversation. Across multiple turns (multiple Enter presses), it keeps:
- `mutableMessages` — the full history
- `readFileState` — which file versions Claude has seen (for stale-file detection)
- `totalUsage` — cumulative token costs
- `abortController` — shared signal for all in-flight requests

This enables features like `/clear` (resets `mutableMessages`), cost tracking, and proper abort propagation.

---

## 18. Source File Index

All files referenced in this document:

| File | Lines | Role in Pipeline |
|---|---|---|
| `src/screens/REPL.tsx` | ~2,200 | Stage 0: Input capture, UI rendering |
| `src/components/PromptInput/PromptInput.js` | — | Text input widget |
| `src/utils/processUserInput/processUserInput.ts` | ~300 | Stage 1: Command detection & dispatch |
| `src/utils/slashCommandParsing.ts` | — | Slash command parser |
| `src/commands.ts` | ~25K | Command registry & routing |
| `src/utils/messages.ts` | — | Stage 2: Message construction helpers |
| `src/utils/attachments.ts` | — | @file references, image handling |
| `src/utils/QueryGuard.ts` | — | Stage 3: Turn serialization |
| `src/QueryEngine.ts` | ~46K | Stage 4: Main conversation manager |
| `src/utils/queryContext.ts` | ~120 | Parallel context assembly |
| `src/context.ts` | ~200 | Git context + CLAUDE.md reading |
| `src/constants/prompts.ts` | — | Static system prompt sections |
| `src/utils/claudemd.ts` | — | CLAUDE.md hierarchy resolver |
| `src/query.ts` | ~1,300 | Stage 5: Inner query loop |
| `src/utils/api.ts` | ~500 | appendSystemContext(), prependUserContext() |
| `src/services/api/claude.ts` | ~900 | Stage 6: API request builder |
| `src/services/api/client.ts` | — | Anthropic SDK client configuration |
| `src/services/api/withRetry.ts` | — | Retry logic, fallback model |
| `src/services/tools/toolOrchestration.ts` | ~150 | Stage 8: Tool concurrency engine |
| `src/services/tools/toolExecution.ts` | — | Individual tool execution |
| `src/services/tools/StreamingToolExecutor.ts` | — | Parallel streaming tool execution |
| `src/hooks/useCanUseTool.ts` | — | Permission check entry point |
| `src/hooks/toolPermission/` | — | Permission rule matching |
| `src/tools/` | 40 dirs | All tool implementations |
| `src/query/stopHooks.ts` | — | Stage 10: Post-turn hooks |
| `src/utils/sessionStorage.ts` | — | Stage 12: Transcript persistence |
| `src/constants/spinnerVerbs.ts` | — | 188 spinner verbs |
| `src/services/compact/autoCompact.ts` | — | Automatic context compaction |
| `src/services/compact/microCompact.ts` | — | Micro-compaction of tool results |
| `src/utils/tokenBudget.ts` | — | Token budget management |

---

## See Also

- [`CLAUDE_CODE_DEEP_GUIDE.md`](./CLAUDE_CODE_DEEP_GUIDE.md) — Full system documentation (tools, prompts, features, patterns)
- [`docs/architecture.md`](./docs/architecture.md) — High-level architecture overview
- [`docs/tools.md`](./docs/tools.md) — Complete tool catalog
- [`docs/subsystems.md`](./docs/subsystems.md) — Bridge, MCP, permissions deep dives
- [`docs/exploration-guide.md`](./docs/exploration-guide.md) — How to navigate the source

---

*Generated from full source analysis of `/Users/dangnguyen/claude_code_cli/src/` · April 2026*
