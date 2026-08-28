# Interactive Initialization and Target Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe conversational `/init` workflow and route table metadata, code metadata, and APEX operations through three explicit database target profiles.

**Architecture:** The strict `.env` loaders remain the single configuration boundary and validate every profile without executing file content. Target-aware guards select one explicit profile, application export uses only the APEX profile, and database backup stages table and code passes before atomically replacing one or two schema mirrors. A canonical portable skill owns the interactive workflow, with thin Claude discovery and slash-command adapters.

**Tech Stack:** Bash, PowerShell, Oracle SQLcl SQL/PLSQL, Markdown agent skills, Python link/skill validators, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-28-interactive-init-and-target-profiles-design.md`

## Global Constraints

- Never execute `.env` as shell or PowerShell code and never place credentials in it.
- Require all table, code, and APEX profile keys; reject legacy single-profile keys.
- Production profiles are read-only and require a named role plus a non-owner expected user.
- A production-like saved-connection name classified as non-production must stop before connecting and ask the user to clarify.
- APEX exports stage under `scratch/`, perform no validation, and replace only a clean exact app mirror.
- Database backups export only tables, views, packages, standalone procedures/functions, and triggers; they never export data.
- Both database metadata passes and manifests must succeed before any schema mirror is replaced.
- Preserve unrelated working-tree changes and do not hand-edit generated mirrors under `database/`.

---

### Task 1: Three-profile environment contract and guards

**Files:**
- Modify: `.env.example`
- Modify: `scripts/test_template.sh`
- Modify: `scripts/test_template.ps1`
- Modify: `scripts/load_env.sh`
- Modify: `scripts/load_env.ps1`
- Modify: `scripts/check_db_target.sh`
- Modify: `scripts/check_db_target.ps1`

**Interfaces:**
- Consumes: literal `KEY=VALUE` files selected by `PROJECT_ENV_FILE`.
- Produces: `check_db_target.sh <read|write> <tables|code|apex>` and `check_db_target.ps1 -Operation <read|write> -Target <tables|code|apex>`; each maps its selected profile to schema, saved connection, expected user, and required role.

- [ ] **Step 1: Replace the test fixture with the complete new contract**

  Add all `TABLES_*`, `CODE_*`, and `APEX_*` keys to the Bash and PowerShell fixtures. Assert that identical profiles load successfully, profile-specific values remain literal, a missing profile role cannot inherit from the process, and each target accepts a safe development read.

- [ ] **Step 2: Add rejection and production-isolation tests**

  Assert that a legacy `DB_TARGET_SCHEMA` line is rejected; a production-like alias fails only when its selected target is checked; production writes fail for each target; and production reads require a non-`NONE` role and a non-owner expected user.

- [ ] **Step 3: Run the focused tests and verify red state**

  Run: `bash scripts/test_template.sh`

  Expected: FAIL because the loaders reject new keys or the guards do not accept a target.

- [ ] **Step 4: Implement the strict three-profile loaders**

  Allow and require exactly the shared keys plus these profile keys:

  ```text
  TABLES_SCHEMA TABLES_SQLCL_CONNECTION TABLES_EXPECTED_USER TABLES_REQUIRED_ROLE
  CODE_SCHEMA CODE_SQLCL_CONNECTION CODE_EXPECTED_USER CODE_REQUIRED_ROLE
  APEX_PARSING_SCHEMA APEX_SQLCL_CONNECTION APEX_EXPECTED_USER APEX_REQUIRED_ROLE
  ```

  Validate every schema/user/role as an uppercase Oracle identifier, every connection as `[A-Za-z0-9][A-Za-z0-9._-]*`, and keep `NONE` valid at loader time so the target guard can enforce production policy.

- [ ] **Step 5: Implement explicit target selection in both guards**

  Select values through `case`/`switch`, never `eval`, then apply the existing production-alias, read-only, role, and non-owner checks to the selected values. Include the selected target and variable family in error messages.

- [ ] **Step 6: Update `.env.example` and run the focused tests**

  Run: `bash scripts/test_template.sh`

  Expected: PASS through the environment and guard checks.

---

### Task 2: APEX-profile application export

**Files:**
- Modify: `scripts/test_template.sh`
- Modify: `scripts/export_apps.sh`
- Modify: `scripts/export_apps.ps1`

**Interfaces:**
- Consumes: the `apex` target guard and `APEX_PARSING_SCHEMA`, `APEX_SQLCL_CONNECTION`, `APEX_EXPECTED_USER`, `APEX_REQUIRED_ROLE`.
- Produces: a staged and normalized mirror at `apps/<APEX_PARSING_SCHEMA>/<APEX_APP_SLUG>` with no validation command.

- [ ] **Step 1: Add static routing regression checks**

  Assert both wrappers call the APEX target guard, pass only APEX profile values to SQLcl, construct the app path with `APEX_PARSING_SCHEMA`, retain marker checks, and contain no active legacy profile references or validation invocation.

- [ ] **Step 2: Run the repository test and verify red state**

  Run: `bash scripts/test_template.sh`

  Expected: FAIL because the export wrappers still use the legacy profile.

- [ ] **Step 3: Route both wrappers through the APEX profile**

  Call the target guard with `read apex`, use the APEX saved connection and identity arguments, stage beneath `scratch/`, validate `application.apx` and `.apex/apexlang.json`, normalize staging, and replace the exact APEX parsing-schema mirror.

- [ ] **Step 4: Run the repository test**

  Run: `bash scripts/test_template.sh`

  Expected: PASS through application export static checks.

---

### Task 3: Scoped two-profile database metadata backup

**Files:**
- Modify: `scripts/test_template.sh`
- Modify: `scripts/backup_db.sql`
- Modify: `scripts/backup_db.sh`
- Modify: `scripts/backup_db.ps1`

**Interfaces:**
- Consumes: table and code profile values plus the generic `verify_db_access.sql` positional definitions.
- Produces: `backup_db.sql <schema> <tables|code> <environment> <expected-user> <required-role>`; table and code manifests named `manifest-tables.txt` and `manifest-code.txt`.

- [ ] **Step 1: Add scoped-backup contract tests**

  Assert SQL accepts `object_scope`, writes a scope-specific driver and manifest, gates `TABLE` to `tables`, gates `VIEW`, `PACKAGE`, `PACKAGE BODY`, `PROCEDURE`, `FUNCTION`, and `TRIGGER` to `code`, and rejects any other scope. Assert wrappers run both target guards, both SQLcl passes before replacement, and deduplicate replacement destinations when schemas match.

- [ ] **Step 2: Run the repository test and verify red state**

  Run: `bash scripts/test_template.sh`

  Expected: FAIL because backup currently uses one profile and one manifest.

- [ ] **Step 3: Add scope selection to `backup_db.sql`**

  Define `object_scope` as argument 2 and shift generic verification arguments to positions 3–5. Validate the scope in PL/SQL, suffix the generated driver with the scope, predicate each driver query by scope, and generate a scope-specific expected-type manifest.

- [ ] **Step 4: Implement the Bash two-pass orchestration**

  Preflight every unique destination with `git status --porcelain --untracked-files=all -- database/<schema>` before the first SQLcl invocation. Create one staged schema tree per unique schema, run table and code passes with explicit values, require both manifests, then call `replace_mirror.sh` once per unique schema.

- [ ] **Step 5: Implement equivalent PowerShell orchestration**

  Build two explicit target records, deduplicate schemas case-sensitively after loader normalization, preflight all destinations, run both passes, require both manifests, and replace only after every pass succeeds.

- [ ] **Step 6: Run the repository tests**

  Run: `bash scripts/test_template.sh`

  Expected: PASS through scoped backup checks.

---

### Task 4: Interactive initialization skill and command

**Files:**
- Create: `.agents/skills/initialize-project/SKILL.md`
- Create: `.claude/skills/initialize-project/SKILL.md`
- Create: `.claude/commands/init.md`
- Modify: `AGENTS.md`
- Modify: `.agents/skills/SKILLS.md`
- Modify: `scripts/test_template.sh`

**Interfaces:**
- Consumes: optional `/init` argument as a proposed project name and the exact `.env` contract from Task 1.
- Produces: a portable conversational initialization workflow that writes only confirmed literal settings, validates through both loaders where available, and preflights `read` for all targets without connecting.

- [ ] **Step 1: Read the skill-authoring instructions**

  Read `.agents/skills/superpowers/writing-skills/SKILL.md` and `/home/ash/.codex/skills/.system/skill-creator/SKILL.md` in full before creating skill files.

- [ ] **Step 2: Add discovery and safety tests**

  Assert the canonical and Claude skill files and Claude command exist; canonical frontmatter declares `name: initialize-project`; command content forwards `$ARGUMENTS`; the canonical skill prohibits secrets and database connections, requires overwrite confirmation, references all three target guards, and conditionally routes `INSTALL_UC_APX=true` to the installer skill.

- [ ] **Step 3: Run the repository test and verify red state**

  Run: `bash scripts/test_template.sh`

  Expected: FAIL because initialization discovery files do not exist.

- [ ] **Step 4: Create the canonical skill**

  Encode the question sequence, reuse choices, validation rules, safe known-key parsing of an existing `.env`, redacted summary, explicit confirmation, literal serialization order, non-connecting guard commands, and conditional optional-tool installation from the approved spec.

- [ ] **Step 5: Create portable discovery adapters**

  Route `/init`, `/init <name>`, `$initialize-project`, and natural-language initialization requests from `AGENTS.md`; create a thin Claude skill pointer and a slash-command file that treats `$ARGUMENTS` as data.

- [ ] **Step 6: Validate the skill and run tests**

  Run the repository's available skill validator against `.agents/skills/initialize-project`, then run `bash scripts/test_template.sh`.

  Expected: skill validation and repository tests PASS.

---

### Task 5: Documentation and CI parity

**Files:**
- Modify: `README.md`
- Modify: `agents.md`
- Modify: `app_context/README.md`
- Modify: `docs/production-database-safety.md`
- Modify: `.agents/workflows/uc-apx.md` if it describes setup entry points
- Modify: `.github/workflows/template-checks.yml` only if current commands omit changed tests
- Modify: `scripts/test_template.ps1`

**Interfaces:**
- Consumes: the implemented `/init`, profile names, and wrapper command signatures.
- Produces: user-facing setup and safety guidance with Bash/PowerShell parity.

- [ ] **Step 1: Find every active legacy variable and command signature**

  Run:

  ```bash
  rg -n 'DB_TARGET_SCHEMA|SQLCL_CONNECTION|DB_EXPECTED_USER|DB_REQUIRED_ROLE|check_db_target\.(sh|ps1)' \
    --glob '!docs/superpowers/specs/**' --glob '!docs/superpowers/plans/**' .
  ```

  Classify each hit as code, test, docs, or intentionally historical before editing.

- [ ] **Step 2: Update user and agent documentation**

  Document `/init ash`, manual `.env` setup, same-or-different profiles, SQLcl credential ownership, APEX-only app routing, split metadata routing, production read-only requirements, scratch staging, and the no-validation export boundary.

- [ ] **Step 3: Complete native PowerShell parity tests**

  Exercise literal loading, all target selections, legacy-key rejection, production alias classification, role requirements, owner rejection, and write blocking with the new command signature.

- [ ] **Step 4: Run static and cross-platform checks available locally**

  Run Bash syntax checks, Python compilation/tests, local-link checks, PowerShell parsing when `pwsh` is installed, and `bash scripts/test_template.sh`.

  Expected: all available checks PASS; unavailable platform tools are reported as a verification boundary.

---

### Task 6: Final review, commit, and push

**Files:**
- Review: every path changed by Tasks 1–5

**Interfaces:**
- Consumes: a green implementation and clean review findings.
- Produces: committed and pushed changes on `main` as explicitly authorized by the user.

- [ ] **Step 1: Run the verification-before-completion workflow**

  Re-run the full test commands from a fresh state and record exit status/output. Confirm no live Oracle connection was attempted by tests.

- [ ] **Step 2: Run the requesting-code-review workflow**

  Review the complete diff against the design, focusing on literal `.env` parsing, production isolation, both-passes-before-replacement ordering, same-schema deduplication, slash-command input handling, and broken links.

- [ ] **Step 3: Inspect repository state and commit**

  Run `git diff --check`, inspect `git status --short`, stage only intended files, and commit with a message describing interactive initialization and target profiles.

- [ ] **Step 4: Synchronize and push**

  Confirm the remote branch has not diverged, rebase only if necessary and safe, push `main`, then verify `origin/main` resolves to the new commit.
