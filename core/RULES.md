## Codebase search rules (fast, Claude-Code style)

Use these whenever a task requires finding, understanding, tracing, or changing code. Never guess paths, names, or signatures: search first.

### Loop
locate -> narrow -> read a slice -> trace -> verify. Do not read whole files or whole repos.

### Cost ladder (cheapest first)
1. File name/path search: `rg --files | rg -i "<name>"`
2. Files-only content search: `rg -l -F "<text>"`
3. Counts: `rg -c "<text>"`
4. Capped hits: `rg -n -m 5 "<text>" <dir>`
5. Context on only the 1-3 relevant files: `rg -n -C3 "<text>" <file>`
6. Ranged read: about 40-120 lines around a hit, not the whole file
7. Read-only sub-agent / parallel sweep for broad questions, if your tool supports it

### Fast-search rules
- Literal text (identifiers, error messages, paths): use `-F`.
- Scope every search with a directory, `-t <type>`, or `-g '<glob>'`.
- Cap output (`-m N`, `| head -100`). Keep ignore rules on; never search node_modules, dist, build output, or lockfiles.
- Use one regex with alternation instead of many searches. Run independent searches in parallel.
- Try name variants: camelCase, PascalCase, snake_case, kebab-case, plural/singular, abbreviations.
- Search what users see: UI text, error messages, log lines, route strings, config keys, test names.
- Do not repeat a query that missed; change the term, scope, or angle.
- Stop once two independent routes agree on the answer.

### Tracing
- Definition: `rg -n "(function|def|class|interface|type|enum|struct|fn|func)\s+Name\b"`
- Usages: `rg -nw "Name"`
- Also check tests, config, docs, and history: `git log -S "text" --oneline`

### Before editing
Re-read the target region, check for duplicates, overrides, mocks, and generated files, make the smallest change, then run the relevant tests.

### Helper script
`.codebase-search/search.sh <cmd>` where cmd is one of:
`files`, `text`, `ctx`, `def`, `refs`, `count`, `slice`, `layout`, `both`, `missing`, `ast`, `hist`. Run it with no arguments for usage.

### Hard searches
For concept searches (you do not know the name), indirect wiring (events, DI, registries, config-driven behavior), "find X but not Y", multi-hop traces, monorepos, or regressions: read `.codebase-search/PLAYBOOK.md` first and follow it.

### Reporting
Give the answer first, then evidence as `path:line`. State what you verified, what you inferred, and what you could not find.
