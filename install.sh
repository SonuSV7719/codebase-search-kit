#!/usr/bin/env bash
# Installs the codebase-search kit into a project for a given coding agent.
# Usage: ./install.sh <agent> [project_dir] [--force]
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START='<!-- codebase-search:start -->'
END='<!-- codebase-search:end -->'

usage() {
  cat <<'EOF'
Usage: ./install.sh <agent> [project_dir] [--force]

Agents:
  codex          -> AGENTS.md              (OpenAI Codex, and many tools that read AGENTS.md)
  claude         -> CLAUDE.md              (Claude Code, rules style)
  claude-skill   -> .claude/skills/codebase-search/   (Claude Code, full skill)
  gemini         -> GEMINI.md              (Gemini CLI)
  cursor         -> .cursor/rules/codebase-search.mdc
  copilot        -> .github/copilot-instructions.md
  windsurf       -> .windsurf/rules/codebase-search.md
  cline          -> .clinerules            (Cline / Roo style)
  aider          -> CONVENTIONS.md         (then run: aider --read CONVENTIONS.md)
  all            -> all of the above except claude-skill

project_dir defaults to the current directory. --force re-installs over an existing block.
EOF
  exit 1
}

agent="${1:-}"; [ -z "$agent" ] && usage
proj="${2:-.}"; force=0
for a in "$@"; do [ "$a" = "--force" ] && force=1; done
[ "$proj" = "--force" ] && proj="."
[ -d "$proj" ] || { echo "Project directory not found: $proj" >&2; exit 1; }
proj="$(cd "$proj" && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  cat >&2 <<'EOF'
WARNING: ripgrep (rg) is not installed. The rules will still install, but searches will be much slower.
  macOS:    brew install ripgrep
  Ubuntu:   sudo apt install ripgrep
  Windows:  winget install BurntSushi.ripgrep.MSVC   (or: choco install ripgrep)
  Any OS:   cargo install ripgrep
EOF
fi

install_tools() {
  mkdir -p "$proj/.codebase-search"
  cp "$KIT/core/search.sh" "$proj/.codebase-search/search.sh"
  cp "$KIT/core/PLAYBOOK.md" "$proj/.codebase-search/PLAYBOOK.md"
  chmod +x "$proj/.codebase-search/search.sh"
  echo "  installed tools -> $proj/.codebase-search/"
}

# Append the rules block to a file, wrapped in markers so it can be found/removed later.
add_block() {
  local f="$1" header="${2:-}"
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && grep -qF "$START" "$f"; then
    if [ "$force" = 1 ]; then
      # remove the old block, then re-add
      awk -v s="$START" -v e="$END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
      echo "  already installed in $f (use --force to reinstall)"; return 0
    fi
  fi
  {
    if [ ! -s "$f" ] && [ -n "$header" ]; then printf '%s\n\n' "$header"; fi
    if [ -s "$f" ]; then echo; fi
    echo "$START"
    cat "$KIT/core/RULES.md"
    echo "$END"
  } >> "$f"
  echo "  wrote $f"
}

# Write a whole file that carries its own front matter (Cursor / Windsurf rule files).
write_rule_file() {
  local f="$1" frontmatter="$2"
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && [ "$force" != 1 ]; then echo "  $f exists (use --force to overwrite)"; return 0; fi
  { printf '%s\n' "$frontmatter"; echo; cat "$KIT/core/RULES.md"; } > "$f"
  echo "  wrote $f"
}

do_agent() {
  case "$1" in
    codex)   install_tools; add_block "$proj/AGENTS.md" ;;
    claude)  install_tools; add_block "$proj/CLAUDE.md" ;;
    gemini)  install_tools; add_block "$proj/GEMINI.md" ;;
    aider)   install_tools; add_block "$proj/CONVENTIONS.md"
             echo "  tip: start with  aider --read CONVENTIONS.md  (or add 'read: CONVENTIONS.md' to .aider.conf.yml)" ;;
    copilot) install_tools; add_block "$proj/.github/copilot-instructions.md" ;;
    cline)
      install_tools
      if [ -d "$proj/.clinerules" ]; then
        write_rule_file "$proj/.clinerules/codebase-search.md" ""
      else
        add_block "$proj/.clinerules"
      fi ;;
    cursor)
      install_tools
      write_rule_file "$proj/.cursor/rules/codebase-search.mdc" "---
description: Fast, Claude-Code-style code search and navigation. Use for any task that involves finding, tracing, or changing code.
alwaysApply: true
---" ;;
    windsurf)
      install_tools
      write_rule_file "$proj/.windsurf/rules/codebase-search.md" "---
trigger: always_on
description: Fast, Claude-Code-style code search and navigation
---" ;;
    claude-skill)
      local d="$proj/.claude/skills/codebase-search"
      mkdir -p "$d/scripts"
      cp "$KIT/skill/codebase-search/SKILL.md" "$d/SKILL.md"
      cp "$KIT/skill/codebase-search/scripts/search.sh" "$d/scripts/search.sh"
      chmod +x "$d/scripts/search.sh"
      echo "  installed skill -> $d"
      echo "  tip: for ALL projects copy skill/codebase-search to ~/.claude/skills/" ;;
    *) echo "Unknown agent: $1" >&2; usage ;;
  esac
}

echo "Installing codebase-search for '$agent' into $proj"
if [ "$agent" = "all" ]; then
  for a in codex claude gemini cursor copilot windsurf cline aider; do echo "[$a]"; do_agent "$a"; done
else
  do_agent "$agent"
fi
echo "Done. Next: ask your agent a search question (see README.md > Quick test)."
