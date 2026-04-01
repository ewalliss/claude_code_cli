# Contributing

Thanks for your interest in contributing to Claude Code CLI!

## What You Can Contribute

- **Documentation** — Improve or expand the [docs/](docs/) directory
- **MCP Server** — Enhance the exploration MCP server in [mcp-server/](mcp-server/)
- **Bug fixes** — Fix issues in the MCP server or supporting infrastructure
- **Tooling** — Scripts or tools that aid in studying the source code
- **Analysis** — Write-ups, architecture diagrams, or annotated walkthroughs

## Getting Started

### Prerequisites

- **Bun** (runtime & package manager)
- **Node.js** 18+ (for the MCP server)
- **Git**

### Setup

```bash
git clone https://github.com/TaGoat/claude_code_cli.git
cd claude_code_cli
```

### MCP Server Development

```bash
cd mcp-server
npm install
npm run dev    # Run with tsx (no build step)
npm run build  # Compile to dist/
```

### Linting & Type Checking

```bash
# From the repo root
npm run lint        # Biome lint
npm run typecheck   # TypeScript type check
```

## Code Style

- TypeScript with strict mode
- ES modules
- 2-space indentation
- Descriptive variable names, minimal comments

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b my-feature`)
3. Make your changes
4. Commit with a clear message
5. Push and open a pull request

## Questions?

Open an issue on [GitHub](https://github.com/TaGoat/claude_code_cli/issues).
