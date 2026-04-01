#!/usr/bin/env bash
# install_claude_tools.sh
# Installs Serena MCP, Context7 MCP, hooks, and plugin configuration
# into a local Claude Code project (.claude/settings.json).
#
# Usage:
#   bash install_claude_tools.sh                    # uses CWD as project root
#   bash install_claude_tools.sh /path/to/project   # explicit project root
#   bash install_claude_tools.sh --global            # write to ~/.claude/settings.json

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────

GLOBAL_MODE=false
PROJECT_DIR=""

for arg in "$@"; do
  case "$arg" in
    --global) GLOBAL_MODE=true ;;
    -*) echo "Unknown flag: $arg"; exit 1 ;;
    *) PROJECT_DIR="$arg" ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"   # resolve to absolute path

CLAUDE_GLOBAL="$HOME/.claude"
CLAUDE_PROJECT="$PROJECT_DIR/.claude"

if [[ "$GLOBAL_MODE" == true ]]; then
  SETTINGS_FILE="$CLAUDE_GLOBAL/settings.json"
  SETTINGS_LABEL="global (~/.claude/settings.json)"
else
  SETTINGS_FILE="$CLAUDE_PROJECT/settings.json"
  SETTINGS_LABEL="project ($SETTINGS_FILE)"
fi

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[→]${NC} $1"; }
title() { echo -e "\n${BOLD}$1${NC}"; }

# ─── Dependency checks ────────────────────────────────────────────────────────

check_deps() {
  title "Checking dependencies"

  command -v python3 &>/dev/null \
    && log "python3: $(python3 --version)" \
    || err "python3 is required — install it and retry"

  if command -v uvx &>/dev/null; then
    log "uvx: $(uvx --version 2>&1 | head -1)"
  elif command -v uv &>/dev/null; then
    log "uv found — uvx available via 'uv tool'"
  else
    warn "uv/uvx not found — installing via astral.sh..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    log "uv installed"
  fi

  if command -v node &>/dev/null && command -v npx &>/dev/null; then
    log "node: $(node --version)  npx: $(npx --version)"
  else
    warn "node/npx not found — Context7 MCP requires Node.js (https://nodejs.org)"
    warn "Skipping Context7 MCP installation"
    SKIP_CONTEXT7=true
  fi

  SKIP_CONTEXT7="${SKIP_CONTEXT7:-false}"
}

# ─── JSON merge (pure Python, no jq needed) ───────────────────────────────────

# Usage: merge_json BASE_FILE PATCH_FILE  → merged JSON on stdout
merge_json() {
  python3 - "$1" "$2" <<'PYEOF'
import json, sys

def deep_merge(base, patch):
    result = dict(base)
    for k, v in patch.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v)
        elif k in result and isinstance(result[k], list) and isinstance(v, list):
            # append list items that aren't already present (by JSON equality)
            existing = {json.dumps(i, sort_keys=True) for i in result[k]}
            for item in v:
                if json.dumps(item, sort_keys=True) not in existing:
                    result[k].append(item)
                    existing.add(json.dumps(item, sort_keys=True))
        else:
            result[k] = v
    return result

base_path, patch_path = sys.argv[1], sys.argv[2]
try:
    base = json.loads(open(base_path).read())
except (FileNotFoundError, json.JSONDecodeError):
    base = {}
patch = json.loads(open(patch_path).read())
print(json.dumps(deep_merge(base, patch), indent=2))
PYEOF
}

# Write a JSON patch into the target settings file
apply_patch() {
  local patch_file="$1"
  local label="$2"
  local dir
  dir="$(dirname "$SETTINGS_FILE")"
  mkdir -p "$dir"
  [[ -f "$SETTINGS_FILE" ]] || echo "{}" > "$SETTINGS_FILE"

  local tmp
  tmp="$(mktemp)"
  merge_json "$SETTINGS_FILE" "$patch_file" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  log "$label"
}

# ─── Serena MCP ───────────────────────────────────────────────────────────────

install_serena() {
  title "Installing Serena MCP"
  info "Semantic code navigation, symbol search, and memory management"

  # Resolve uvx binary (uv may expose it as `uv tool run`)
  local uvx_cmd="uvx"
  command -v uvx &>/dev/null || uvx_cmd="uv tool run"

  local patch
  patch="$(mktemp)"
  # Use python3 to write JSON safely (avoids shell quoting issues with paths)
  python3 - "$PROJECT_DIR" "$uvx_cmd" "$patch" <<'PYEOF'
import json, sys
project_dir, uvx_cmd, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

# uvx_cmd might be "uv tool run" (two words) — split into list
cmd_parts = uvx_cmd.split()
cmd = cmd_parts[0]
prefix_args = cmd_parts[1:]   # e.g. ["tool", "run"] or []

config = {
  "mcpServers": {
    "serena": {
      "command": cmd,
      "args": prefix_args + [
        "--from", "git+https://github.com/oraios/serena",
        "serena-mcp-server",
        "--context", "ide-assistant",
        "--project-dir", project_dir,
      ],
      "env": {}
    }
  }
}
with open(out_path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

  apply_patch "$patch" "Serena MCP → serena-mcp-server (project-dir: $PROJECT_DIR)"
  rm -f "$patch"
}

# ─── Context7 MCP ─────────────────────────────────────────────────────────────

install_context7() {
  title "Installing Context7 MCP"
  info "Up-to-date library documentation lookup"

  local patch
  patch="$(mktemp)"
  cat > "$patch" <<'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": {}
    }
  }
}
EOF

  apply_patch "$patch" "Context7 MCP → @upstash/context7-mcp"
  rm -f "$patch"
}

# ─── Hooks ────────────────────────────────────────────────────────────────────

install_hooks() {
  title "Installing hooks"
  info "PreToolUse, PostToolUse, Notification, Stop"

  local patch
  patch="$(mktemp)"
  cat > "$patch" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[pre-hook] bash → $CLAUDE_TOOL_INPUT_COMMAND\" >&2"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[pre-hook] file write/edit → $CLAUDE_TOOL_INPUT_FILE_PATH\" >&2"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[post-hook] file written → $CLAUDE_TOOL_INPUT_FILE_PATH\" >&2"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[notification] $CLAUDE_NOTIFICATION\" >&2"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[stop] Claude finished responding\" >&2"
          }
        ]
      }
    ]
  }
}
EOF

  apply_patch "$patch" "Hooks (PreToolUse/PostToolUse/Notification/Stop)"
  rm -f "$patch"
}

# ─── Skills note ──────────────────────────────────────────────────────────────

note_skills() {
  title "Skills & Plugins"
  info "Skills (trl-fine-tuning, peft, vllm, speckit.*, feature-dev, etc.)"
  info "are built into Claude Code — no installation required."
  info "They are invoked via the Skill tool or slash commands (e.g. /plan)."
  info ""
  info "To see all available skills in a session, check the <system-reminder>"
  info "block at the top of any conversation — it lists every loaded skill."
}

# ─── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Installation complete${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Settings written to: ${BLUE}${SETTINGS_FILE}${NC}"
  echo ""
  echo -e "  MCPs installed:"
  echo -e "    ${GREEN}✓${NC} serena     — semantic code nav + memory"
  [[ "$SKIP_CONTEXT7" == false ]] && \
  echo -e "    ${GREEN}✓${NC} context7   — library docs lookup" || \
  echo -e "    ${YELLOW}✗${NC} context7   — skipped (node/npx not found)"
  echo ""
  echo -e "  Hooks configured:"
  echo -e "    ${GREEN}✓${NC} PreToolUse   (Bash, Write, Edit)"
  echo -e "    ${GREEN}✓${NC} PostToolUse  (Write, Edit)"
  echo -e "    ${GREEN}✓${NC} Notification"
  echo -e "    ${GREEN}✓${NC} Stop"
  echo ""
  echo -e "  ${YELLOW}Restart Claude Code to activate new MCP servers.${NC}"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Claude Code Tools Installer${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Mode    : ${SETTINGS_LABEL}"
  echo -e "  Project : ${PROJECT_DIR}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  check_deps
  install_serena
  [[ "$SKIP_CONTEXT7" == false ]] && install_context7
  install_hooks
  note_skills
  print_summary
}

main
