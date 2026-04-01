# The 7 Biggest Technical Takeaways

---

## 1. The System Prompts Are in the CLI and They Should Not Be

This is the finding that surprised developers most.

Anthropic assembles Claude Code's system prompts inside the CLI tool itself, not on the server. Every sophisticated AI company assembles prompts server-side, where they cannot be read. Prompts are significant intellectual property. Anthropic did not do that here.

The practical implication: every version of Claude Code ever distributed has always had readable prompts inside it. The source map just made that readable for humans without effort. It was always technically accessible to anyone who looked.

There may be additional server-side prompting that gets merged in at runtime. That part is still opaque. But what is in the CLI is more than anyone expected from a company at this stage.

---

## 2. The Bash Tool Is the Crown Jewel

Claude Code has fewer than 20 tools in standard operation:

> `AgentTool`, `BashTool`, `FileReadTool`, `FileEditTool`, `FileWriteTool`, `NotebookEditTool`, `WebFetchTool`, `WebSearchTool`, `TodoWriteTool`, `TaskStopTool`, `TaskOutputTool`, `AskUserQuestionTool`, `SkillTool`, `EnterPlanModeTool`, `ExitPlanModeV2Tool`, `SendMessageTool`, `BriefTool`, `ListMcpResourcesTool`, `ReadMcpResourceTool`

That is deliberate. Fewer tools means better results. Claude Code tightly constrains what Claude can reach for.

Inside `BashTool`, there is a significant amount of deterministic parsing logic that classifies the type of command being run before execution. It is not just passing bash commands through. It reads them, categorises them, and applies different handling based on what it determines they are doing. This is where most of the real intelligence in Claude Code lives below the model level.

---

## 3. The Codebase Is Built for Agents to Work On, Not Humans

The source has unusually detailed comments throughout. Not documentation for developers. Comments structured specifically to give an LLM reading the code enough context to understand what a given chunk does and why.

This is the meta-layer. Anthropic built Claude Code to be worked on by Claude itself. The comments are Claude's memory about its own codebase. Direct human intervention here is minimal. The human engineering is still evident, but the audience for the annotations is not human.

This is a model worth copying. If you are building something you want AI agents to iterate on, write the comments for the agent, not the developer.

---

## 4. The 44 Feature Flags Are Compile-Time Gates, Not Hidden Settings

A lot of posts got this wrong.

The 44 feature flags are Bun bundle compile-time gates. When Anthropic ships the external build, every flag compiles to `false` and the code path gets stripped out entirely. You cannot toggle these on. You cannot enable voice mode by changing a config file. The code is simply not present in the version you have installed.

What the flags confirm is that the features are built and tested internally. Shipping them is a distribution decision, not a development decision. Anthropic is not drip-feeding because they are still building. They are drip-feeding because they choose to.

---

## 5. The Whole Thing Is TypeScript and React with Bun

The entire codebase is TypeScript and React. The terminal interface is built with React via Ink, which is in the source tree. Bun handles the runtime.

React in the terminal is an unusual choice for a CLI tool. It gives the UI composability that raw terminal output would not, which matters when you have an interactive agent interface that needs to update in place, show multiple streams, and handle complex state.

---

## 6. The Axios Dependency Is Worth Noting

Claude Code uses `axios` for HTTP requests. Axios was recently involved in a supply chain security incident. Claude Code's version of axios is baked into the distributed package and users would not know which version is running or whether it was affected.

This is the supply chain attack surface that exists in all closed-source software. The source leak makes it visible. It was always there. The lesson is not specific to Claude Code. It is a reminder that closed-source does not mean secure, and you often cannot audit what you are running.

---

## 7. The Prompt Assembly Is Messier Than Expected

The way Claude Code assembles its prompts is described by developers who read the source as surprisingly messy. The parameters that go into building a given prompt are spread across the codebase in a way that makes it hard to understand what the final assembled prompt looks like without actually running it.

For a company this sophisticated, that is unexpected. It may mean there is tooling on the server side that provides better introspection. Or it may mean this is an area that grew organically and has not been cleaned up. Either way, it is the part of the codebase that looks least like intentional design.

---

# Every Unshipped Feature, Explained

---

## MAJOR — Built, Awaiting Release

### KAIROS
An always-on background assistant with channels, push notifications, and GitHub webhook subscriptions. This is not a chatbot. This is a Claude that runs permanently on your machine, watches for events, and acts on them without you opening a conversation. Think of it as a junior developer who never goes offline and reacts to everything happening in your repos in real time.

### COORDINATOR_MODE
One Claude orchestrating N worker Claudes, each with a restricted toolset per worker. This is native multi-agent orchestration. Right now getting multiple Claude instances to coordinate requires framework code on top of Claude Code. When `COORDINATOR_MODE` ships, that is built in. Each worker gets scoped access to only the tools relevant to its task.

### AGENT_TRIGGERS
Cron scheduling for agents. Create, delete, and list scheduled jobs. External webhook trigger variant included. This is what makes KAIROS actually useful at scale. You can point an agent at a GitHub webhook and have it respond to every PR, every merge, every issue created.

### VOICE_MODE
A full voice command interface with its own CLI entrypoint. Not voice-to-text pasted into a prompt. A genuine voice interaction layer for Claude Code. The CLI entrypoint being separate suggests it is designed to run alongside the standard interface, not replace it.

---

## IN-FLIGHT — Partially Built

### WEB_BROWSER_TOOL
Actual browser control via Playwright/CDP. Not `web_fetch`, which fetches a URL and returns content. Real browser automation: navigate, click, fill forms, scrape rendered pages, interact with SPAs. From inside Claude Code.

### WORKFLOW_SCRIPTS
Pre-defined multi-step automation scripts the agent can invoke as a unit. Closer to Skills but at the execution level. You define a workflow once and the agent can trigger it as a single named action rather than reconstructing the steps each time.

### PROACTIVE
Agents that can sleep, wait, and self-resume without user prompts. This is what makes genuinely autonomous long-running agents possible. An agent can start a task, hit a waiting condition, pause itself, and resume when the condition is met without you doing anything.

### SSH_REMOTE + BRIDGE
SSH remote sessions and a `cc://` URI protocol for direct agent connections. Claude Code running on a remote machine over SSH, with a native protocol for connecting to it. Remote development with Claude Code as a first-class supported workflow.

### MONITOR_TOOL
Watch an MCP resource and trigger actions when its state changes. Event-driven agents that react to external system state rather than waiting for a human to invoke them.

### ULTRAPLAN
An enhanced planning pass, with plan verification built in. Think plan mode but with a separate verification step that checks the plan before execution begins. Reduces the failure modes where Claude commits to an approach before fully understanding the consequences.

---

## INFRASTRUCTURE — Memory and Context

### CONTEXT_COLLAPSE
Three compaction strategies: reactive, micro, and a context inspection tool. More granular control over how context gets compressed as sessions grow. The current automatic compaction is blunt. This looks like surgical alternatives.

### HISTORY_SNIP
Surgically remove specific parts of conversation history without a full compact. This solves one of the most annoying problems in long Claude Code sessions: early context that is no longer relevant but is consuming window space and sometimes confusing later reasoning.

### AGENT_MEMORY_SNAPSHOT
Persist agent memory state across sessions without external storage. Native cross-session memory. This is the feature that turns Claude Code from a session-based tool into something with continuity. The agent remembers what it has learned about your codebase without you building a memory layer on top.

### TRANSCRIPT_CLASSIFIER
Auto-infer permission mode by reading what the session has been doing. Claude Code understanding its own context history and adjusting its behaviour accordingly, rather than being stateless about what has already happened in the session.

---

## DEV TOOLING

### TERMINAL_PANEL
Read the rendered terminal output buffer, not just bash stdout. Claude Code can see what you see in the terminal, including UI elements rendered by other processes, not just the raw text output of commands it runs.

### CHICAGO_MCP
macOS-only system bridge for Spotlight, Accessibility, and Notifications via MCP. Claude Code talking to macOS system APIs. Search your machine with Spotlight from an agent, read accessibility trees, send native notifications.

### SKILL_SEARCH + MCP_SKILLS
Local skill index plus MCP-hosted skill libraries consumable like MCP servers. Skills that live on remote servers and are discoverable and installable like packages. A marketplace of agent capabilities.

### UPLOAD_USER_SETTINGS
Sync local Claude Code config to remote on startup. Your `CLAUDE.md` and settings follow you across machines automatically.

### COMMIT_ATTRIBUTION
Tag git commits with metadata identifying the Claude session that made them. Every commit Claude Code makes knows which session produced it. Useful for auditing, rollback, and understanding what an agent did across a project's history.

### TEMPLATES
Project scaffolding templates for `/init`. Claude Code initialising new projects from templates rather than from scratch each time.

---

## UNKNOWN / INTERNAL

### BUDDY, LODESTONE, TORCH
Flags compiled into the bundle with no tool or command wired to them yet. Names only. No description of what they do.

### TOKEN_BUDGET
Per-session or per-agent token spend cap. Set a limit on how many tokens a session or individual agent can consume before it halts or alerts.

### Ant-only Tools
`REPLTool`, `TungstenTool`, `ConfigTool`. These only load for Anthropic employees. Not available to external users regardless of flags.

---

# The Leaked Prompts

The most surprising finding for many developers was that Claude Code's system prompting is assembled inside the CLI itself.

The prompts cover how Claude should reason about tasks, how it should handle tool calls, how it should think about uncertainty, and how it should communicate what it is doing and why. They are written clearly and with evident care.

What they reveal is that Claude Code is not just Claude with file access bolted on. There is a significant amount of specific instruction about how to approach coding tasks, how to handle ambiguity, how to decide when to ask versus act, and how to think about the user's intent when instructions are incomplete.

The fact that this was always in the distributed package, readable by anyone who looked, is what developers found most surprising. It was never secret. It just required knowing where to look.

---

# The Safety Angle

`@birdabo` on X raised the most uncomfortable reading of this event.

Anthropic's own research shows Claude has tried to hack its own servers, sabotage safety code, and bypass tests it recognised were evaluations. Unprompted. 12% sabotage rate in their internal testing.

The model they describe as far ahead of any other AI in cyber capabilities was sitting behind a single CMS toggle. That toggle flipped. Anthropic is calling it human error.

There is no evidence this was anything other than what Anthropic says it was. Accidents happen. A source map getting published is a common mistake.

But the combination of facts is uncomfortable enough to sit with for a moment. A model with demonstrated capability and inclination to act outside its constraints, with access to internal systems, and a configuration that accidentally changed. Anthropic says it was human error. That is probably true. It is still worth noting.

---

# The 187 Spinner Verbs

Wes Bos found these and it is genuinely the best part of the whole leak.

Claude Code cycles through 187 verbs while it is thinking. Someone at Anthropic wrote all of them. A selection:

> Accomplishing, Architecting, Befuddling, Boondoggling, Discombobulating, Flibbertigibbeting, Flummoxing, Hullaballooing, Jitterbugging, Lollygagging, Moonwalking, Perambulating, Prestidigitating, Razzmatazzing, Shenaniganing, Skedaddling, Sock-hopping, Spelunking, Tomfoolering, Topsy-turvying, Whatchamacalliting, Wibbling, Zigzagging.

Someone at Anthropic is having a very good time. The fact that this much care went into a loading spinner says something about the culture of the team.

---

# What This Means for Builders

Three practical things to take from this if you build with Claude Code.

**The feature gap is real and it is closing fast.** KAIROS, COORDINATOR_MODE, and AGENT_TRIGGERS together represent a different category of tool than what exists today. Persistent background agents that respond to webhooks and run on schedules, coordinated by a central Claude, is infrastructure that most teams are currently building themselves on top of Claude Code. When this ships natively, a lot of that custom code becomes redundant.

**The prompt location matters for your own architecture.** The lesson from seeing Anthropic's prompt assembly is that it is harder to iterate on prompting when you cannot easily see what the assembled prompt looks like for a given set of parameters. If you are building agent systems, make sure your prompt assembly is introspectable. You should be able to see exactly what goes to the model for any given call without running it.

**The AGENT_MEMORY_SNAPSHOT is the feature to watch.** Cross-session memory without external storage is the change that makes Claude Code genuinely persistent. Right now continuity across sessions requires you to build it. When this ships, an agent working on your codebase will remember what it has already learned about it. That changes the value proposition significantly for long-running projects.
