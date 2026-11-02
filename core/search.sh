#!/usr/bin/env bash
# codebase-search helper: ripgrep wrapper with git grep / grep fallbacks.
# Usage: search.sh <command> [args]   (run "search.sh help" for the list)
set -u

have() {
  # SEARCH_NO_RG=1 forces the git grep / grep fallbacks (useful for testing).
  if [ "$1" = "rg" ] && [ "${SEARCH_NO_RG:-0}" = "1" ]; then return 1; fi
  command -v "$1" >/dev/null 2>&1
}

RG_EXCLUDES=(
  -g '!node_modules' -g '!.git' -g '!dist' -g '!build' -g '!.next'
  -g '!coverage' -g '!target' -g '!vendor' -g '!.venv' -g '!venv'
  -g '!__pycache__' -g '!*.min.js' -g '!*.min.css' -g '!*.map'
  -g '!package-lock.json' -g '!yarn.lock' -g '!pnpm-lock.yaml' -g '!*.lock'
  --max-filesize "${SEARCH_MAX_FILESIZE:-2M}"   # skip huge blobs/dumps: big speed win
)
GREP_EXCLUDES=(
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist
  --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage
  --exclude-dir=target --exclude-dir=vendor --exclude-dir=.venv
  --exclude-dir=venv --exclude-dir=__pycache__
  --exclude='*.min.js' --exclude='*.map' --exclude='*.lock'
  --exclude=package-lock.json
)
MAX_LINES="${SEARCH_MAX_LINES:-200}"

# search <extra rg flags...> -- <pattern> <path> [glob]
_search() {
  local flags=() pattern path glob
  while [ "$1" != "--" ]; do flags+=("$1"); shift; done
  shift
  pattern="$1"; path="${2:-.}"; glob="${3:-}"
  # Flags understood by every backend (-w, -C<n>); rg-only ones (-S) are dropped in fallbacks.
  local fb=() f
  for f in ${flags[@]+"${flags[@]}"}; do
    case "$f" in -w|-C*) fb+=("$f") ;; esac
  done
  local g=(); [ -n "$glob" ] && g=(-g "$glob")
  local inc=(); [ -n "$glob" ] && inc=(--include="$glob")
  # Fast path: patterns with no regex metacharacters run as literal (-F), skipping the regex engine.
  local fixed=() re='[][\.^$*+?(){}|]'
  [[ "$pattern" =~ $re ]] || fixed=(-F)
  if have rg; then
    rg -n --no-heading --max-columns 300 --max-columns-preview \
      --max-count "${SEARCH_MAX_PER_FILE:-30}" ${fixed[@]+"${fixed[@]}"} ${flags[@]+"${flags[@]}"} "${RG_EXCLUDES[@]}" ${g[@]+"${g[@]}"} -e "$pattern" "$path" 2>/dev/null | head -n "$MAX_LINES"
  elif [ -d "$path" ] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$path" && git grep -n -E ${fb[@]+"${fb[@]}"} -e "$pattern" -- ${glob:+"$glob"} 2>/dev/null | head -n "$MAX_LINES")
  else
    # --include must come first: GNU grep only excludes non-matching files when --include is the first file filter.
    grep -rnE ${inc[@]+"${inc[@]}"} ${fb[@]+"${fb[@]}"} "${GREP_EXCLUDES[@]}" -e "$pattern" "$path" 2>/dev/null | head -n "$MAX_LINES"
  fi
}

cmd="${1:-help}"; [ $# -gt 0 ] && shift

case "$cmd" in
  files)
    pat="${1:?usage: files <pattern> [path]}"; path="${2:-.}"
    if have rg; then
      rg --files "${RG_EXCLUDES[@]}" "$path" 2>/dev/null | rg -i -e "$pat" | head -n 100
    else
      find "$path" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' \
        -not -path '*/dist/*' -not -path '*/build/*' | grep -iE -e "$pat" | head -n 100
    fi ;;

  text)
    _search -S -- "${1:?usage: text <regex> [path] [glob]}" "${2:-.}" "${3:-}" ;;

  ctx)
    _search -S -C3 -- "${1:?usage: ctx <regex> [path]}" "${2:-.}" ;;

  def)
    name="${1:?usage: def <Name> [path]}"
    pat="(function|def|class|interface|type|enum|struct|trait|fn|func|record|object|module|const|let|var)[[:space:]]+${name}\\b|\\b${name}[[:space:]]*[:=][[:space:]]*(async[[:space:]]*)?(\\(|function|class)|^[[:space:]]*${name}[[:space:]]*\\(\\)[[:space:]]*\\{"
    _search -- "$pat" "${2:-.}" ;;

  refs)
    _search -w -- "${1:?usage: refs <Name> [path]}" "${2:-.}" ;;

  count)
    pat="${1:?usage: count <regex> [path]}"; path="${2:-.}"
    if have rg; then
      rg -c -S "${RG_EXCLUDES[@]}" -e "$pat" "$path" 2>/dev/null | sort -t: -k2 -nr | head -n 40
    else
      grep -rcE "${GREP_EXCLUDES[@]}" -e "$pat" "$path" 2>/dev/null | grep -v ':0$' | sort -t: -k2 -nr | head -n 40
    fi ;;

  slice)
    file="${1:?usage: slice <file> <start> <end>}"; s="${2:?start}"; e="${3:?end}"
    awk -v s="$s" -v e="$e" 'NR>=s && NR<=e {printf "%d\t%s\n", NR, $0}' "$file" ;;

  layout)
    path="${1:-.}"
    if have rg; then
      rg --files "${RG_EXCLUDES[@]}" "$path" 2>/dev/null
    else
      find "$path" -type f -not -path '*/node_modules/*' -not -path '*/.git/*'
    fi | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -n 40 ;;

  both)
    a="${1:?usage: both <regexA> <regexB> [path]}"; b="${2:?regexB}"; path="${3:-.}"
    if have rg; then
      rg -l "${RG_EXCLUDES[@]}" -e "$a" "$path" 2>/dev/null | xargs -r rg -l -e "$b" 2>/dev/null | head -n 100
    else
      grep -rlE "${GREP_EXCLUDES[@]}" -e "$a" "$path" 2>/dev/null | xargs -r grep -lE -e "$b" 2>/dev/null | head -n 100
    fi ;;

  missing)
    a="${1:?usage: missing <regexA> <regexB> [path]}"; b="${2:?regexB}"; path="${3:-.}"
    if have rg; then
      rg -l "${RG_EXCLUDES[@]}" -e "$a" "$path" 2>/dev/null | xargs -r rg --files-without-match -e "$b" 2>/dev/null | head -n 100
    else
      grep -rlE "${GREP_EXCLUDES[@]}" -e "$a" "$path" 2>/dev/null | xargs -r grep -LE -e "$b" 2>/dev/null | head -n 100
    fi ;;

  ast)
    pat="${1:?usage: ast <ast-pattern> [lang] [path]}"; lang="${2:-}"; path="${3:-.}"
    # NB: plain `sg` is also a Linux group command (shadow-utils); only trust it if it is ast-grep.
    if have ast-grep; then bin=ast-grep
    elif have sg && sg --version 2>/dev/null | grep -qi ast-grep; then bin=sg
    else
      echo "ast-grep not installed (npm i -g @ast-grep/cli, or brew/cargo install ast-grep). Falling back: use 'text' with a regex or rg -U." >&2
      exit 2
    fi
    if [ -n "$lang" ]; then "$bin" run -p "$pat" -l "$lang" "$path" 2>/dev/null | head -n "$MAX_LINES"
    else "$bin" run -p "$pat" "$path" 2>/dev/null | head -n "$MAX_LINES"; fi ;;

  hist)
    txt="${1:?usage: hist <text> [regex] [path]}"; mode="${2:-}"; path="${3:-.}"
    flag=-S; [ "$mode" = "regex" ] && flag=-G
    git -C "$path" log "$flag$txt" --date=short --format='%h %ad %an  %s' 2>/dev/null | head -n 30 ;;

  help|*)
    cat <<'EOF'
search.sh <command> [args]
  files  <pattern> [path]        find files by name (regex, case-insensitive)
  text   <regex> [path] [glob]   line-numbered content search (smart case)
  ctx    <regex> [path]          hits with 3 lines of context
  def    <Name> [path]           likely definitions of a symbol
  refs   <Name> [path]           whole-word usages of a symbol
  count  <regex> [path]          hits per file, sorted
  slice  <file> <start> <end>    numbered line range of a file
  layout [path]                  file counts per directory
  both   <A> <B> [path]          files containing both regexes
  missing <A> <B> [path]         files containing A but NOT B
  ast    <pattern> [lang] [path] structural search (needs ast-grep)
  hist   <text> [regex] [path]   git log -S (or -G with "regex") for who changed text
env: SEARCH_MAX_LINES (default 200) caps output
EOF
    ;;
esac
