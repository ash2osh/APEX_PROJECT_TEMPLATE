# Template hardening — design

**Status:** approved for planning
**Date:** 2026-09-09
**Plan:** [`../plans/2026-09-09-template-hardening.md`](../plans/2026-09-09-template-hardening.md)

## Problem

A full review of the template found 28 defects across six subsystems. Every
finding below was verified against the code in this repository — by reading it,
by running the loaders and the extractor, or by prototyping the replacement
logic. Findings marked **not reproduced** are hardening, not demonstrated bugs,
and are recorded so nobody re-derives them.

The template's own contract is that the `.sh` and `.ps1` halves of each script
pair behave identically, that generated mirrors are replaced atomically or not
at all, and that guards fail closed. Most findings are places where one of
those three promises is not kept.

## Verified findings

### Configuration loaders (`scripts/load_env.*`)

| # | Finding | Evidence |
|---|---|---|
| F2 | A whitespace-only line is **rejected** by Bash, **skipped** by PowerShell. | Ran both loaders on a `.env` with a `"   "` line: Bash `invalid line`, PowerShell loads. |
| F3 | A whitespace-only *value* is **accepted** by Bash, **rejected** by PowerShell. | `PROJECT_NAME=   ` → Bash `ACCEPTED`, PowerShell `PROJECT_NAME is required`. |
| F19 | A relative `PROJECT_ENV_FILE` resolves against the caller's CWD, not the repo root. | From `apps/`: `configuration file not found: .env.reltest` in both loaders. `README.md` documents exactly this relative form. |
| F20 | An inline comment is silently swallowed into `PROJECT_NAME`, the one setting with no validation. | `PROJECT_NAME=inventory # the good one` → `PROJECT_NAME=[inventory # the good one]`. Validated settings fail with a message that never mentions comments. |
| F25 | Bash leaves `project_env_fail` and `project_env_validate_unique_csv` defined in the caller; PowerShell removes its helper and claims in a comment to be mirroring Bash. | `declare -F` after sourcing. |
| F28 | `load_env.ps1` quote-stripping throws `ArgumentOutOfRangeException` on a one-character value of `"` or `'` (`Substring(1, -1)`). | Read of `load_env.ps1:38-41`; Bash keeps the character. |

**Decision — which behavior wins.** A whitespace-only *line* is not a
configuration error; PowerShell's behavior wins and Bash learns to skip it. A
whitespace-only *value* is a configuration error; PowerShell's behavior wins
and Bash learns to reject it. Both changes land in `load_env.sh` only.

**Decision — inline comments.** Values stay literal, as documented. Add one
uniform rule to both loaders: an **unquoted** value containing whitespace
followed by `#` is rejected with a message naming the cause. Quoting the value
is the escape hatch for a legitimate `#`. This closes the silent-swallow half
and the cryptic-error half with a single rule.

### Database backup (`scripts/backup_db.*`)

| # | Finding | Evidence |
|---|---|---|
| F4 | Oracle recycle-bin objects abort the entire backup, and the error names no object. | `ALL_OBJECTS` includes `BIN$<base64>==$0`; base64 of 16 bytes always carries `=` padding, so the name fails `^[A-Za-z0-9_$#]+$` and `backup_db.sql:79` raises ORA-20020 before the driver is spooled. |
| F21 | Split-schema backups install ten empty directories. | Simulated `TABLES_SCHEMA=APP_DATA`, `CODE_SCHEMA=APP_CODE`: `APP_DATA/{views,packages,procedures,functions,triggers}` and `APP_CODE/{tables}` are empty. |
| F24 | `backup_db.ps1`'s `finally` uses `-ErrorAction Stop`, so a locked handle turns a completed backup into a thrown error. | Read of `backup_db.ps1:134-136`; Bash ignores `rm -rf` failure in its trap. |

**Correction to a widely-assumed failure mode.** The abort is ORA-20020 from
the name guard, *not* ORA-31603 from `DBMS_METADATA.GET_DDL` — the guard runs
first and the driver is never generated. The distinction matters for the fix:
the remedy must touch **all three** queries, because the guard
(`backup_db.sql:56`) and the manifest (`backup_db.sql:275`) read `ALL_OBJECTS`,
which has no `DROPPED` column, while only the driver (`backup_db.sql:104`)
reads `ALL_TABLES`, which does. Fixing only the driver moves the failure from
ORA-20020 to "manifest expects N but M were written".

**Scope.** F4 only bites when `PREFIXES=*`. With a real prefix,
`INSTR(name, 'APP_') = 1` excludes recycle-bin rows from all three queries.

### Mirror replacement (`scripts/replace_mirror.*`)

| # | Finding | Evidence |
|---|---|---|
| F5 | The two implementations cannot see each other's lock: Bash makes a `cksum`-named **directory**, PowerShell a SHA-256-named **file**. | `replace_mirror.sh:125` vs `replace_mirror.ps1:102`. On Windows both shells are present. |
| F6 | A killed process leaves a lock that blocks every future run, with no staleness detection and no message naming the path to remove. | pwsh: `CreateNew` on an existing file throws; Bash `mkdir` on an existing directory fails. |
| F7 | Replacement across multiple apps or schemas is not atomic. | `export_apps.sh:83-86` and `backup_db.sh:136-139` replace in a loop with no rollback; export *is* correctly all-or-nothing, replacement is not. |

**Decision — lock protocol.** Both implementations adopt one documented
protocol: same path, same file format, atomic exclusive create, and an explicit
staleness break. PowerShell keeps `FileMode::CreateNew` rather than switching to
`OpenOrCreate`; `OpenOrCreate` would let PowerShell silently steal a lock held
by Bash, which holds no OS handle. Staleness recovery comes from the explicit
break path instead, which works for both.

**Decision — atomicity.** `replace_mirror.*` accepts N staged/destination
pairs, validates and locks all of them, then moves with an unwind stack. All
moves are same-filesystem renames, so the unwind is exact.

### APEXlang extractor (`scripts/graphify_apexlang_extractor.py`)

| # | Finding | Evidence |
|---|---|---|
| F12 | Comma joins lose every table after the first. | `FROM orders o, customers c, order_items i` → `reads={'ORDERS'}`. |
| F13 | `WITH t (a,b) AS (SELECT …)` is not recognized as a CTE, so `FROM t` emits a phantom table. | `CTE_RE` requires `IDENTIFIER AS ( SELECT` with no column list. |
| F14 | Cross-application navigation is attributed to the calling application. | `f?p=102:1:` inside app 101 → edge to `apex_app_101_page_1`. |
| F15 | `references_component` edges are emitted with no target node, unlike the `authorizationScheme` branch which creates a `synthetic_reference` placeholder. | Read of the reference branch in `parse_apexlang`. |
| F16 | A malformed `.apx` returns `{"nodes": [], "edges": [], "error": …}` and disappears from the graph with no operator-visible signal. | Read of `extract_apexlang`. |
| F17 | **Not reproduced.** The catch tuple is narrow, but no escaping exception was found. | 13 targeted adversarial inputs plus 4000 random strings: 0 escapes. |
| F18 | **Won't fix by regex.** Unqualified calls (`log_event('m');`) are not detected. | Confirmed; the dot requirement is load-bearing — dropping it makes `NVL(`, `SUBSTR(` into `calls` edges. |

**Decision — F12 and F13 land together.** Parsing the full `FROM` list without
widening CTE detection would multiply phantom nodes rather than reduce them.

**Decision — F17 and F16 land together.** Broadening to `except Exception`
while the `error` field remains unread makes failures *more* silent. The catch
widens only alongside a stderr warning.

**Decision — F18 is documented, not fixed.** Correct detection needs the
`database/` symbol table, which is not available during per-file extraction. A
test pins current behavior so a future contributor does not "fix" it into a
flood of false edges.

### Graphify installer (`setup_graphify_apx.py`)

| # | Finding | Evidence |
|---|---|---|
| F8 | `if not all(results): return False` short-circuits before `invalidate_apx_cache`, so one stale orphan environment leaves the *working* environment with stale `.apx` AST cache. | `setup_graphify_apx.py:262-264`. This is the exact regression `self_improve.md` records. |
| F9 | The `tree-sitter-sql` install discards stdout and stderr and never checks an exit code. | `setup_graphify_apx.py:249-252`. |
| F10 | A glob sweep patches every Graphify directory it can find and requires all to succeed. | `setup_graphify_apx.py:33-46`. Note that "use the current interpreter" is not a fix: for a `uv tool install`, the invoking Python is never the tool's interpreter — which is why the sweep exists. The shim's shebang, already read at `:240-248`, is the right target. |
| F11 | A Graphify upgrade silently reverts the patches; nothing detects the reverted state at query time. | `verify_installation()` exists but only runs when a human remembers to rerun setup. |

### Documentation, hygiene, CI

| # | Finding | Evidence |
|---|---|---|
| F1 | Graphify is documented as **required** in `README.md:23,50` and **optional / not guaranteed** in `AGENTS.md:194`, `.agents/rules/graphify.md:10`, `.agents/workflows/graphify.md:29`. | Agents treat `AGENTS.md` as authoritative, so the README loses. |
| F22 | PowerShell uses glob-expanding `-Path` in `normalize_apx.ps1:14`, `backup_db.ps1:89,103`, `export_apps.ps1:21` while being careful with `-LiteralPath` everywhere else. | A clone under a directory containing `[` or `]` misbehaves. |
| F23 | `normalize_apx` diverges by platform: `perl -pi` preserves a BOM, `normalize_apx.ps1:16-18` strips it. | Same input, different bytes, on the one file type `.gitattributes` exists to keep stable. |
| F26 | `install-uc-apx/SKILL.md` invokes `load_env.ps1` without dot-sourcing while `initialize-project/SKILL.md:167` dot-sources it; `AGENTS.md` §6 still holds `<PROJECT>_DATA` placeholders with nothing checking that setup step 4 happened; CI runs `bash -n` but no shellcheck despite `# shellcheck source=` directives. | Read of all three. |
| F27 | Local state only: `graphify-out/` was built at `65af9ae` (HEAD is `8bbdc7d`) and all 162 indexed sources are gone from disk, while `.agents/rules/graphify.md` is `trigger: always_on` and routes every agent to it. Empty demo directories remain under `apps/DEMO/`, `app_context/10{1,2}`, `ai_generate/DEMO`. | `graphify-out/graph.json` `built_at_commit` vs `git rev-parse HEAD`. |

**Decision — F1 resolves toward optional.** Every rule in
`.agents/rules/graphify.md` is already gated on `graphify-out/graph.json`
existing, and the scripts work without it. "Optional but strongly recommended"
is the truthful position and the README is the outlier. **This is the one
decision worth confirming before Phase 6 lands** — if Graphify is meant to be
hard-required, the fix inverts and the gating in the rules file must go.

### Recorded, no action

- `Select-Object -Unique` is case-insensitive in PowerShell 5.1, but schemas are
  validated uppercase first, so no input can reach it ambiguously.
- `[int]::TryParse` accepts a leading sign where the Bash manifest parser
  requires `^[0-9]+$`; a `COUNT(*)` cannot be negative.
- `check_db_target.sh`'s unconditional `shopt -u nocasematch` cannot leak: the
  script runs as a subprocess, never sourced.

## Non-goals

- No new runtime dependencies. The extractor stays standard-library-only —
  `_patched_dispatch` deliberately removes a `".apx": "sql"` dependency gate.
- No change to the production read-only model. It stays an instruction with
  wrapper-level refusal, not a privilege audit.
- No `uc-apx` or Graphify vendoring.
- No rebuild of `graphify-out/` as part of the plan; F27 is local state and the
  plan only makes it detectable.

## Constraints carried into the plan

- The `.sh` / `.ps1` pair must stay behaviorally identical; every parity fix
  needs an assertion in **both** `test_template.sh` and `test_template.ps1`.
- PowerShell must run on Windows PowerShell 5.1 **and** 7 — no .NET 5+ APIs
  (`SHA256::HashData`, `Convert::ToHexString`), and `-cmatch` / `-cnotmatch`
  wherever letter case is part of the contract.
- Python 3.10+ (the extractor uses `str | None` in runtime signatures).
- `.apx` stays LF-only; `database/` is never hand-edited; temporary files live
  only under `scratch/`; `.env` is parsed as data and never executed.
- CI runs both suites on Linux and Windows, plus a PSScriptAnalyzer 5.1
  compatibility profile. All of it must stay green.
