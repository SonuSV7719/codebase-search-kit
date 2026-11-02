
# Codebase Search (Claude Code style)

Do not guess and do not read whole repos. Search iteratively with cheap, precise tools: **locate -> narrow -> read a slice -> trace -> verify**. No embeddings or index are needed; the technique is disciplined use of glob, grep, and ranged reads.

## Tool priority

1. **Glob / file listing** - find files by name or path pattern.
2. **Grep (ripgrep)** - find content by regex. Always line-numbered, always scoped.
3. **Ranged Read** - open only the lines you need (offset + limit), never a whole large file.
4. **Read-only sub-agent (Explore)** - for sweeps that would take many searches; it returns a conclusion, not file dumps.
5. **Shell** (`rg`, `git grep`, `git log`, `git blame`) - only when no dedicated tool covers it. Avoid `cat`, `find | xargs grep`, `ls -R`.

If the agent has dedicated Glob/Grep/Read tools, use them instead of shell equivalents. If it only has a shell, use `.codebase-search/search.sh` (see below) or the `rg` recipes in this file.

## The loop

### 1. Orient (only if the repo is unfamiliar)
- Look at the top-level layout and the manifest: `package.json`, `pyproject.toml`, `go.mod`, `pom.xml`, `Cargo.toml`, `*.csproj`.
- Read `README`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING` if they exist.
- Identify the language, framework, test runner, and entry points. Do not read more than this up front.

### 2. Locate broadly
- Name guess: glob `**/*auth*`, `**/*.service.ts`, `**/test_*.py`.
- Content guess: `rg -l "<term>"` (files only) to see how widespread it is before reading anything.
- If hits are huge (>50 files), narrow: add a file type (`-t py`), a directory, or a more specific term. If zero hits, widen (see "When nothing is found").

### 3. Narrow with context
- `rg -n -C3 "<term>" path/` shows hits with surrounding lines.
- Use `-w` for whole words, `-F` for literal strings containing regex characters, `-i` only when case is unknown, `-U` for multiline patterns.
- Prefer one regex with alternation over many searches: `rg -n "createUser|create_user|CreateUser"`.

### 4. Read a slice
- Read about 40-120 lines around the hit, not the file. Expand only if the slice is clearly cut off mid-function or mid-class.
- For large files, first grep for structure (`rg -n "^(class|def|function|export)"  file`), then read the section you need.

### 5. Trace
- **Definition**: `rg -n "(function|def|class|interface|type|enum|struct|trait|fn|func)\s+Name\b"` and `Name\s*[:=]\s*(async\s*)?(\(|function)`.
- **Callers/usages**: `rg -nw "Name"` then exclude the definition and tests as needed.
- **Imports**: `rg -n "import .*Name|from .* import .*Name|require\(.*name"`.
- **Config/env**: search the string key (`rg -n "DATABASE_URL"`) across code, `.env.example`, Docker, CI, and docs.
- **Routes/handlers**: search the path string (`"/api/users"`) and the framework's decorator (`@app.get`, `@Get(`, `router.`).
- **Tests**: find usages in `tests/`, `__tests__`, `*.spec.*`, `*_test.go` to learn intended behavior.
- **History**: `git log -S "symbol" --oneline` and `git blame -L start,end file` explain why code exists.

### 6. Verify before acting
- Confirm the thing you found is the one in use (not dead code, a mock, a vendored copy, or a generated file).
- Check the second-order impact: who else calls this? what tests cover it?
- Read the file region again immediately before editing it. Make the smallest edit that works.

## Search strategy rules

- **Parallelize independent searches.** Issue several greps/globs in one step when they do not depend on each other.
- **Try name variants**: camelCase, PascalCase, snake_case, kebab-case, SCREAMING_CASE, plural/singular, abbreviations (`config`/`cfg`/`conf`).
- **Search for strings the user sees**: UI text, error messages, log lines, CLI flags, route paths. They usually lead straight to the code.
- **Start from the error/stack trace** when there is one: grep the exact message (a short stable fragment), then the file:line in the trace.
- **Exclude noise**: `node_modules`, `.git`, `dist`, `build`, `.next`, `coverage`, `target`, `vendor`, `.venv`, `__pycache__`, lockfiles, minified files, generated code. ripgrep respects `.gitignore` by default; use `--no-ignore` only when you deliberately need ignored files.
- **Cap output**: `| head -100` or `-m 5` per file. Too many hits means the query is too broad, not that you should read them all.
- **Count first when unsure**: `rg -c "term" | sort -t: -k2 -nr | head` shows where a term concentrates.
- **Do not repeat the same query.** If a search misses, change the term, scope, or angle.

## Scale effort to the question

| Question type | Typical effort |
| --- | --- |
| "Where is X defined?" | 1-3 searches |
| "How does feature Y work?" | 5-15 calls: entry point -> handlers -> data layer -> tests |
| "Find every place that does Z" / audits / cross-cutting refactors | Sweep with a read-only sub-agent or batches of parallel greps; list all hits before editing any |

For wide sweeps, delegate to a read-only exploring sub-agent with an exact brief: what to find, which dirs, which name variants, thoroughness level, and what to return (file:line + one-line finding). Do not also run the same search yourself.

## When nothing is found

1. Loosen: drop `-w`, add `-i`, shorten the term to a stem (`authenticat`).
2. Try other spellings and naming conventions.
3. Search non-code files: `.md`, `.json`, `.yaml`, `.env*`, `Dockerfile`, CI configs.
4. Check ignored/generated dirs: `rg --no-ignore --hidden "term"`.
5. Check the dependency: the code may live in `node_modules`/`site-packages`/`vendor`.
6. Search git history: `git log -S "term" --all --oneline`.
7. Only then conclude it does not exist, and say what you searched.

## Speed and efficiency (be fast, spend little)

Speed comes from doing the **cheapest thing that could answer the question first** and from never making the machine or the model read more than needed.

### Cost ladder (always climb from the bottom)
1. **Filename/path glob** - near-instant: `rg --files | rg -i "auth"` or a Glob tool.
2. **Files-only content search** - `rg -l -F "term"` (tells you *where*, prints almost nothing).
3. **Counts** - `rg -c "term"` to see concentration before reading hits.
4. **Capped hits** - `rg -n -m 5 -F "term" path/` (max 5 hits per file).
5. **Hits with context** - `rg -n -C3 ...` only on the 1-3 files that matter.
6. **Ranged read** - 40-120 lines around a hit.
7. **Sub-agent sweep** - only when steps 1-6 would take many rounds; it keeps bulky results out of your context.

### Make each search itself fast
- **Use `-F` for literal text** (identifiers, error messages, paths). It skips the regex engine. `search.sh` does this automatically when the pattern has no regex characters.
- **Scope first**: pass a directory, `-t <type>` or `-g '<glob>'`. Searching `src/auth/` beats searching `.`.
- **Cap everything**: `-m N` per file, `| head -N` overall (ripgrep stops as soon as the pipe closes), `--max-filesize 2M`, `--max-columns 300 --max-columns-preview` so minified/one-line files cannot flood output.
- **Keep ignore rules on**: ripgrep already skips `.gitignore`d, hidden and binary files. Avoid `--no-ignore`, `--hidden`, and `-a` unless you have a reason; they can multiply the search space 100x.
- **Avoid slow regex shapes**: leading `.*`, nested quantifiers, huge alternations of long words, and lookarounds (needs `-P`). Anchor with `\b`, literal prefixes, or `^`. Use `-U` (multiline) only when required.
- **Do not use `--sort`** (it disables parallelism). Leave ripgrep unsorted; it uses all cores by default.
- **Use `-i`/`-S` deliberately**: smart-case (`-S`) is cheap; fully case-insensitive on large repos is slower, so use it only when casing is genuinely unknown.
- **Prefer `git grep`** in giant, mostly-tracked repos when ripgrep is unavailable; it searches the index and is very fast. Use `git ls-files` instead of `find`.
- **Fast file listing**: `rg --files -g '*.py'` is much faster than `find . -name '*.py'`.
- **Never `cat`/`ls -R` the repo**, and never grep `node_modules`, build output, or lockfiles.

### Make the model fast too (fewer round trips, fewer tokens)
- **Batch independent searches in one step** (parallel tool calls). Three greps in one turn are about 3x faster than three sequential turns.
- **One regex with alternation** instead of several searches: `rg -n -F -e foo -e bar -e baz`.
- **Print less**: `-l` for files, `-c` for counts, `-o` for only the matched text, `-m` caps. Read the code only after you know the file.
- **Narrow before widening context**: `-C0` first; add `-C3` only if hits are ambiguous.
- **Stop when you have the answer and one confirmation.** Do not keep searching to be thorough once two independent routes agree.
- **Reuse what you learned**: remember paths, names and conventions found earlier in the session instead of re-searching.
- **Cache expensive discoveries** (e.g. the entry point, the router file, the naming convention) in your notes and refer back.
- **Delegate bulk reading** to a sub-agent so that thousands of lines never enter your own context.

### Recommended ripgrep defaults (optional, global speed/noise tuning)
Create `~/.ripgreprc` and set `export RIPGREP_CONFIG_PATH=~/.ripgreprc`:
```
--smart-case
--max-columns=300
--max-columns-preview
--max-filesize=2M
--glob=!node_modules
--glob=!.git
--glob=!dist
--glob=!build
--glob=!*.min.*
--glob=!*.map
--glob=!*.lock
```

### Tuning knobs for `.codebase-search/search.sh`
`SEARCH_MAX_LINES` (total output cap, default 200), `SEARCH_MAX_PER_FILE` (hits per file, default 30), `SEARCH_MAX_FILESIZE` (default 2M).

## Hard searches (when the obvious grep fails)

Hard searches are solved by reasoning about *where the answer must leave evidence*, then testing that cheaply. Work like a detective, not a keyword matcher.

### A. Hypothesis-driven search
1. Write down what you are looking for in one sentence.
2. List 2-4 hypotheses for where/how it could live (e.g. "a middleware", "a DB trigger", "a cron job", "a frontend hook").
3. Test each with the cheapest search that could disprove it. Kill hypotheses fast; keep a running list of what is ruled out.
4. If 5+ calls pass with no progress, stop, restate the goal, and change angle instead of repeating the same kind of query.

### B. You don't know the name (concept search)
- Harvest vocabulary first: read one adjacent file you *do* know, plus README/docs/tests/commit messages, and collect the domain's real terms. Then grep those.
- Search synonyms and domain words together: `rg -n -i "retry|backoff|attempt|resilien|circuit"`.
- Search what users see: UI labels, error text, log messages, CLI help, API field names, i18n keys. Then follow the key to the code.
- Search test names and fixtures: `rg -n "should .*refund|test_.*refund|describe\(.*refund"`. Tests describe behavior in plain words.
- Search comments and TODOs: `rg -n -i "TODO|FIXME|HACK|XXX" | rg -i "term"`.
- Use directory and file names as clues (`ls` a promising folder, then glob inside it).

### C. Multi-hop tracing (follow the data/control flow)
Keep an explicit trace list and extend it one hop at a time, each with `file:line`:
`entry point -> route/handler -> service/use-case -> repository/client -> storage/external API`
- Start at whichever end you know (a route string, a DB column, an error message, a button label).
- Go **downstream** by reading calls inside the function; go **upstream** with `rg -nw "functionName"`.
- At each hop confirm the next hop's real name; do not assume.

### D. Indirect and dynamic wiring (why plain grep misses things)
| Pattern | How to find it |
| --- | --- |
| String-built names (`"handle_" + kind`, ``on${Event}``) | Grep the prefix/suffix string, then list candidates: `rg -n "handle_\w+"` |
| Registries / decorators / plugins | Search the decorator or `register(` call: `rg -n "@(register|route|command|task)\b"` |
| Dependency injection / containers | Search the interface/token name, bindings, `provide`, `bind(`, `@Inject`, `providers:` |
| Event buses, pub/sub, queues | Search the **event/topic name** for both producers (`emit`, `publish`, `send`) and consumers (`on`, `subscribe`, `listen`) |
| Config-driven behavior | Search the config key in code, `.env*`, YAML/JSON, Dockerfile, CI, Helm/Terraform |
| Reflection / dynamic import | Search `getattr`, `importlib`, `require(` with variables, `Class.forName`, `__import__`, entry points in manifests |
| ORM/DB columns vs fields | Search both the snake_case column and the camelCase field; check migrations and raw SQL |
| Generated code / codegen | Find the generator input (proto, OpenAPI, GraphQL schema, `.prisma`) and edit there, not the output |
| Frontend <-> backend | Match the route string, HTTP verb, and payload field names on both sides |
| Feature flags | Search the flag name, then the flag-evaluation function to find all branches |

### E. Structural queries
- **Multiline**: `rg -U "try\s*\{[^}]*\}\s*catch\s*\([^)]*\)\s*\{\s*\}"` (empty catch blocks).
- **AST-aware** (when `ast-grep` is available): `.codebase-search/search.sh ast 'console.log($$$)' ts` or `sg -p 'def $F($$$): $$$' -l python`. Use it for "all calls of X with Y as an argument", "all functions that return a Promise", "all classes extending Base".
- Fall back to regex plus a ranged read to confirm structure.

### F. Set logic (co-occurrence, absence, difference)
- Files containing **both** A and B: `.codebase-search/search.sh both "A" "B"`.
- Files containing A but **missing** B (e.g. routes without auth, handlers without logging, fetches without error handling): `.codebase-search/search.sh missing "A" "B"`.
- Compare two sets: `comm -23 <(rg -l "A" | sort) <(rg -l "B" | sort)`.
- Count to find hot spots: `.codebase-search/search.sh count "term"`.

### G. History and "why/when did this change"
- Who added or removed a string: `git log -S "text" --oneline` (exact) or `-G "regex"`; `.codebase-search/search.sh hist "text"`.
- Trace one file's life: `git log --follow --oneline -- path/file`.
- Why a line exists: `git blame -L start,end path/file`, then `git show <sha>`.
- Regression hunting: `git bisect` with a failing test, or diff against a known-good tag: `git diff v1.2..HEAD -- path`.

### H. Large repos and monorepos
- Read the workspace manifest (`pnpm-workspace.yaml`, `lerna.json`, `go.work`, `Cargo.toml [workspace]`, Bazel/Nx config) and the dependency graph before searching everything.
- Scope each search to one package or service; run per-package searches in parallel.
- For wide sweeps, spawn read-only sub-agents, one per area, each with a precise brief (see below), then merge their findings.

### I. Use runtime evidence when static search stalls
- Run the failing test or command and read the stack trace; grep the exact frames.
- Add a temporary log/print at a suspected chokepoint to confirm which path executes (remove it afterwards).
- Grep logs, build output, and CI artifacts for the message.
- Check what is actually installed or generated (`node_modules/<pkg>`, `site-packages`, build output) when the source is not in the repo.

### J. Cross-check before you conclude
- Reach the answer by a second independent route (e.g. definition search *and* usage search *and* test search). If they disagree, keep digging.
- Look for duplicates and overrides (same name in multiple modules, subclass overrides, mocks, vendored copies).
- Explicitly list what you ruled out and what you could not verify.

### Sub-agent brief template (for broad or parallel sweeps)
```
Goal: <one sentence>
Scope: <dirs/packages>   Exclude: <generated/vendor>
Look for: <names, variants, strings, patterns>
Thoroughness: medium | very thorough
Read-only. Return: file:line + one-line finding per hit, then a 3-line summary of gaps.
```

### Honest limits
This skill gives the agent a method and tools, not extra intelligence. Results are only as good as the underlying model and the tools it can call. Without real Grep/Glob/Read tools or shell access with `rg`, quality drops sharply. For truly semantic questions on huge codebases, add a code-search MCP server or an embedding index *on top of* these techniques, not instead of them.

## Anti-patterns

- Reading whole files "to get context".
- Running `cat` on large or binary files, or `ls -R` / `find .` on the whole repo.
- Guessing a function signature or file path instead of grepping for it.
- Editing a file you have not read in this session.
- Trusting a single grep hit without checking for other definitions or overrides.
- Stopping at the first plausible match when several modules share the name.
- Searching only `src/`; configs, scripts, tests, and docs often hold the real answer.

## Reporting results

- Cite locations as `path/to/file.ext:LINE`.
- Lead with the answer, then the evidence trail (2-6 key locations), not a narration of every command.
- State confidence and gaps: what you verified, what you inferred, what you could not find.

## Helper script

`.codebase-search/search.sh` wraps ripgrep (falls back to `git grep`/`grep`) with sane excludes:

```
.codebase-search/search.sh files  <name-substring-or-regex> [path]     # find files by name
.codebase-search/search.sh text   <regex> [path] [glob]                # line-numbered content search
.codebase-search/search.sh ctx    <regex> [path]                       # hits with 3 lines of context
.codebase-search/search.sh def    <Name> [path]                        # likely definitions of a symbol
.codebase-search/search.sh refs   <Name> [path]                        # whole-word usages
.codebase-search/search.sh count  <regex> [path]                       # hits per file, sorted
.codebase-search/search.sh slice  <file> <start> <end>                 # numbered line range
.codebase-search/search.sh layout [path]                               # file counts per directory
.codebase-search/search.sh both   <regexA> <regexB> [path]             # files containing both
.codebase-search/search.sh missing <regexA> <regexB> [path]            # files with A but WITHOUT B
.codebase-search/search.sh ast    <ast-pattern> [lang] [path]          # structural search (needs ast-grep)
.codebase-search/search.sh hist   <text> [regex] [path]                # git history: who added/removed text
```

## Raw ripgrep cheatsheet

```
rg -l "term"                      # files that match
rg -n -C3 "term" src/             # hits + 3 lines context
rg -nw "Name"                     # whole word
rg -nF "a.b(c)"                   # literal, no regex
rg -n "foo|bar|baz"               # alternation
rg -t py -t ts "term"             # by file type
rg -g "*.test.*" "term"           # glob include
rg -g "!**/generated/**" "term"   # glob exclude
rg -U "start(.|\n)*?end"          # multiline
rg -c "term" | sort -t: -k2 -nr   # concentration
rg --files | rg -i "auth"         # find files by name
rg --no-ignore --hidden "term"    # include ignored/hidden
```

## Using this skill in other agents

- **Claude Code / Claude.ai**: place this folder where skills are loaded.
- **Cursor / Windsurf / Copilot / Codex / others**: copy the body of this file into `AGENTS.md`, `.cursor/rules/`, `.windsurfrules`, or `.github/copilot-instructions.md`, and make sure `rg` is installed and the agent can run shell commands or has grep/glob/read tools.
