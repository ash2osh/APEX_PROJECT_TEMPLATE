---
name: add-region-or-item-to-page
description: Add a region, page item, button, process, or branch to an existing apexlang page. Use when the user asks to "add a column", "add a button", "add a region", "add a validation", or otherwise extend an existing `pages/pNNNNN-*.apx` file. The `uc-apx create region`, `uc-apx create page-item`, and `uc-apx create button` CLI families cover most cases; for everything else, follow the hand-edit playbook below.
---

# Adding regions, items, buttons, and processes to an existing page

There are two paths:

1. **Use the CLI** — seven command families splice new constructs into an existing page's `.apx` and reparse to validate:
   - `uc-apx create region <type>` for `form`, `static-content`, `classic-report`, `interactive-grid`, `interactive-report`, `cards`, `chart`, `faceted-search`, plus the Universal-Theme **theme template components** `avatar`, `comments`, `content-row`, `timeline`, `metric-card`, `media-list`, and the layout helper `flexbox-container`. See [Theme template components](#theme-template-components).
   - `uc-apx create page-item <type>` for `text`, `select`, `hidden`, `switch`, `date`, `number`, `radio-group`, `checkbox-group`, `display-only`.
   - `uc-apx create button <kind>` for `redirect`, `cancel`, `submit`, `save`, `create`, `delete`.
   - `uc-apx create process plsql` for executeCode processes; `uc-apx create dynamic-action refresh-on-dialog-close` for the canonical post-modal DA.
   - `uc-apx create validation` for page validations (10 MMD shapes — `function-body-boolean`, `plsql-expression`, `sql-expression`, `regexp`, `not-null`, `numeric`, `valid-date`, `valid-timestamp`, `no-rows-returned`, `rows-returned`).
   - `uc-apx create computation` for page computations writing into a target item (`static-value`, `item`, `plsql-expression`, `function-body`, `sql-query`).
   - `uc-apx create branch` for after-submit page-navigation branches (anonymous; uniqueness by `execution.sequence`).
   - `uc-apx edit column` for rewriting an existing IG / CR / IR column (type, LOV, default, readonly) without a hand-edit — including turning an **interactiveReport / interactiveGrid** column into an avatar or badge (`--type avatar|badge` + `--badge-*` / `--avatar-*`).
   See [Path A](#path-a-uc-apx-create-region-cli) below.
2. **Hand-edit the `.apx` file** — for region types the CLI doesn't cover yet (`chart` variants, breadcrumb, …) and for non-plsql process types and dynamic-action scenarios beyond refresh-on-dialog-close. See [Path B](#path-b-hand-edit-playbook).

In both cases, validation after the change is **mandatory** — see step 5.

## When to use this skill

- The user asks to add a region, item, button, process, computation, validation, branch, or dynamic action to an existing page.
- A previous workflow (e.g. a freshly scaffolded page) needs additional components before it can be useful.

**Do not** use this skill when:

- The whole page is new — use [skills/edit/create-page/SKILL.md](../create-page/SKILL.md) first, then come here.
- The construct lives in `shared-components/` (LOV, list, breadcrumb, …) — use [skills/edit/edit-shared-component/SKILL.md](../edit-shared-component/SKILL.md).
- The change is to an existing component on the page — open the `.apx` file and edit the relevant lines directly.

## Path A: `uc-apx create region` CLI

The CLI handles eight region types today: `form`, `static-content`, `classic-report`, `interactive-grid`, `interactive-report`, `cards`, `chart`, `faceted-search`. It writes directly into the target page's `.apx` file, auto-derives sequence numbers and kebab-case region IDs from `--name`, and re-parses the result to fail fast on a broken splice. **Prefer this path whenever the type matches.**

### Gather column metadata BEFORE invoking the CLI (form + classic-report + interactive-grid + interactive-report)

For `form`, `classic-report`, `interactive-grid`, and `interactive-report` you must know which columns the region binds to **before** you call the CLI. Without this context the CLI produces an empty region the user has to flesh out by hand. Sources, in preference order:

1. **The user told you** — names, types, primary key. Use what they said verbatim.
2. **An existing page already binds to the same table** — `uc-apx search "tableName: USERS"` and inspect a sibling form region; the columns + types are right there.
3. **The DB schema** — if the user can give you the `desc <table>` output or the DDL, parse name + type + length from it.
4. **Best-effort fallback** — propose a column list to the user (e.g. `ID:number,NAME:varchar2:200`) and confirm before invoking.

Never invent columns silently. If the right metadata isn't available, ask once.

### Column-spec syntax

`--column NAME[:TYPE[:LENGTH]][,NAME...]`

- `TYPE` ∈ `varchar2` (default), `number`, `date`, `timestamp`, `clob`.
- `LENGTH` applies only to `varchar2` and feeds `validation.maxLength`. Default `4000`.
- Multiple columns are comma-separated; no whitespace inside commas.

### Form

```bash
uc-apx --app-dir <root> create region form \
    --page <id|alias|name> \
    --name "User Details" \
    --table USERS \
    --column "ID:number,FIRST_NAME:varchar2:50,EMAIL:varchar2:200,BIO:clob,CREATED:date" \
    --pk-column ID \
    --required-column "FIRST_NAME,EMAIL"
```

When `--column` is provided you get a working CRUD form:

- **PageItems**: each non-PK column → labeled `pageItem` (textField / numberField / datePicker / textarea). varchar2 items carry `settings.trimSpaces: none`, `appearance.width: 32`, and `validation.maxLength` from `LENGTH`. The PK column → hidden `pageItem` with `primaryKey: true`, `queryOnly: true`, and `security.sessionStateProtection: checksumRequiredSessionLevel`. `queryOnly: true` keeps APEX's auto-DML processes from including the PK in INSERT/UPDATE column lists — without it identity-generated PKs trip `ORA-32795`. Default PK is the first `--column` entry; override with `--pk-column`. Use `uc-apx edit column --query-only=false` to opt out for a writable natural-key PK.
- **Required columns** (`--required-column NAME[,NAME]`): switch the matching items to `template: @/required-floating` and emit `validation.valueRequired: true`.
- **Buttons** (auto-emitted): `Cancel` (action `definedByDynamicAction`), `Delete` (DML delete + PK-not-null gate + confirmation), `Save` (DML update + PK-not-null gate), `Create` (DML insert + PK-is-null gate). Skip with `--no-buttons`.
- **Processes** (auto-emitted): `formInitialization` (before-header) + `formAutoRowProcessing`. Skip with `--no-processes`.
- **Cancel wiring**: the Cancel button uses `action: definedByDynamicAction`. After scaffolding, add a `dynamicAction` for `@cancel` that calls `closeDialog` (modal pages) or `redirectThisApp` (full-page forms) — see [Path B](#path-b-hand-edit-playbook).
- **Omitting `--column`**: you get just the region shell (no items, no buttons, no processes). Useful as a starting point when you don't know the column list yet.

### Classic-report

```bash
uc-apx --app-dir <root> create region classic-report \
    --page <id|alias|name> --name "Activity" \
    --sql "select id, action, created from audit_log where status = 'OPEN' order by created desc" \
    --column "ID:number,ACTION:varchar2:100,CREATED:date"
```

- Source is **SQL-only** (the `--table` shape was retired — author your SELECT, including any WHERE / ORDER BY, directly). `--sql` and `--column` are both required.
- The column order must match the SQL projection (each gets a 1-based `reportColumnQueryId`).
- Headings are humanized from column names (`FIRST_NAME` → `First Name`).
- Number columns: `heading.alignment: end` **and** `layout.columnAlignment: end` (so data + heading stay aligned).
- Date/timestamp columns: alignment `center` on both, plus `appearance.formatMask: DD-MON-YYYY`.
- Every column carries `derivedColumn: N` so APEX knows it's from the source rather than computed.

### Interactive-grid

```bash
# Table-backed → editable with auto row processing (Insert/Update/Delete)
# Use --where for a user-scoped or otherwise filtered view.
uc-apx --app-dir <root> create region interactive-grid \
    --page <id|alias|name> --name "My Predictions" \
    --table WC_PREDICTIONS \
    --where "username = :APP_USER" \
    --column "ID:number,USERNAME:varchar2:120,MATCH_ID:number,GUESS:number,CREATED:date" \
    --pk-column ID

# SQL-backed → read-only by default (editable requires manual row processing)
uc-apx --app-dir <root> create region interactive-grid \
    --page <id|alias|name> --name "Recent Sales" \
    --sql "select id, region, sale_amount, sale_date from sales where region in ('NA','EU')" \
    --column "ID:number,REGION:varchar2:60,SALE_AMOUNT:number,SALE_DATE:date"
```

- Exactly one of `--table` / `--sql` is required. `--column` is required (must include the PK).
- **`--where <expr>`**: only valid with `--table`; splices `whereClause: <expr>` into the source block (rejected with `--sql` since the user already controls the WHERE there). Use this for user-scoped grids (`username = :APP_USER`) or any other filter you'd put on a `select * from T`.
- **Primary key**: rendered as a hidden column with `source.primaryKey: true` **and `source.queryOnly: true`** so APEX's auto-row-processing process skips it on insert/update (avoids `ORA-32795: cannot insert into a generated always identity column` for identity-generated PKs — the dominant APEX 26.1 pattern). Default PK is the first `--column` entry; override with `--pk-column NAME`. For a writable natural-key PK, flip queryOnly off afterwards: `uc-apx edit column --page <id> --region <r> --column <name> --query-only=false`.
- **savedReport**: a primary saved report with `displayColumn` entries for every column is auto-emitted — APEX's MMD schema rejects an IG with zero `savedReport` children.
- **Table-backed**: editable by default. Emits `edit { enabled: true, allowedOperations: [add, update, delete] }` and an `interactiveGridAutoRowProcessing` process keyed by `editableRegion: @<id>`.
- **SQL-backed**: read-only by default. To make it editable, hand-edit in an `edit` block and wire manual row-processing — auto row processing only works against a `tableName` source.
- **Pagination**: `type: scroll` (the IG-native default).
- Date/timestamp columns auto-get `appearance.formatMask: DD-MON-YYYY` (mandatory per Oracle's IG guardrails); number/date columns get matching `heading.alignment` + `layout.columnAlignment`.

### Interactive-report

```bash
uc-apx --app-dir <root> create region interactive-report \
    --page <id|alias|name> --name "Activity Log" \
    --sql "select id, action, created from audit_log where actor = :APP_USER order by created desc" \
    --column "ID:number,ACTION:varchar2:200,CREATED:date"
```

- Source is **SQL-only** (the `--table` shape was retired — author your SELECT, including any WHERE / ORDER BY, directly). `--sql` and `--column` are both required.
- Columns are read-only by default (`type: plainText`).
- **dataType is UPPERCASE** (`STRING`, `NUMBER`, `DATE`, `CLOB`, `OTHER`) — unlike classic-report and interactive-grid which use the Oracle lowercase types. The CLI handles this automatically based on the column spec.
- **SQL projection matching**: IR maps columns by NAME, not position — no `reportColumnQueryId` is emitted. Make sure each `--column NAME` matches a select-list alias in the SQL.
- Pagination defaults to `rowRangesXToY` and a default `whenNoDataFound` message is set. Tweak both by hand-editing the region after scaffolding.
- Same alignment + formatMask conventions as classic-report: numbers end-align, dates center-align with `DD-MON-YYYY` mask.
- Common follow-ups: turn the auto-generated ID column into a row-level link to a modal-dialog form with `uc-apx create link-column --page <id> --region <region> --column ID --target-page <N> --item-pair PNN_ID=#ID#` (see [#create-link-column](#create-link-column-rewrite-an-ircr-column-as-a-row-level-link)). Other tweaks remain hand-edits per [Path B](#path-b-hand-edit-playbook): add `columnFormatting.htmlExpression` for badge rendering, set `column.lov.sharedComponent: @<alias>` for LOV-mapped display values, add `actionsMenu` / `download` toolbar config.

### Static-content

```bash
uc-apx --app-dir <root> create region static-content \
    --page <id|alias|name> --name "Help Text" \
    --html "<p>Click <strong>Save</strong> to commit changes.</p>"
```

- `--html` is optional; defaults to `<!-- TODO -->`. Multi-line HTML is supported; the renderer indents subsequent lines into the surrounding code block.

### Cards

```bash
uc-apx --app-dir <root> create region cards \
    --page <id|alias|name> --name "All Teams" \
    --sql "select team_id, name, country_code, group_code from wc_teams order by group_code, name" \
    --pk-column TEAM_ID --title-column NAME \
    --subtitle-column COUNTRY_CODE --badge-column GROUP_CODE \
    --action-page 11
```

- Source: `--table` (synthesised as `select * from T`) or `--sql` (inline SELECT). Exactly one is required.
- **Required**: `--pk-column` (primary key, projected by the source) and `--title-column` (card heading).
- **Optional slots**: `--subtitle-column`, `--body-column` *or* `--body-html`, `--icon-class` (static `fa-*`), `--badge-column`.
- **Body slot — column vs HTML**: `--body-column COL` renders the raw column value. `--body-html` accepts an HTML expression with `&COL.` substitutions and emits `body.advancedFormatting: true` so the markup renders verbatim. Use it whenever the card body wants more than a single column — e.g. a `<ul>` of comma-split values, badges around status text, or a multi-line layout. Example: `--body-html "<ul>&TEAMS.</ul>"` for a card per group where TEAMS comes back from `listagg`.
- **Media**: `--media-source urlColumn|blobColumn` + `--media-column COL`; `blobColumn` additionally requires `--media-mime-column COL`. Optional `--media-position first|body|background`.
- **Row-action redirect** (`--action-page N`): emits a `fullCard` action targeting page N. The `target.items` block is auto-populated with `P<N>_<pk-column>: &<pk-column>.` so the row's PK lands in the target page's item without a hand-edit — the 95% case. Pass `--action-item-pair NAME=VALUE` (repeatable) when you need additional bindings or want to override the default entirely. The flag follows the same `NAME=VALUE` shape as `create button redirect --item-pair`.
- **Replace an existing region** (e.g. converting IR → cards): pass `--force` and reuse the old region's `--id`. The previous region is deleted in place and the new cards region inherits `layout.sequence` and `slot` from it (override with explicit `--sequence` / `--slot`). Preview the change with `--force --dry-run` to see the new region's body without touching the file.
- **Deferred to Phase 3** (per the CLI help text): REST source, secondaryBody, icon variants beyond `iconClass`, multiple buttons per card, `componentAppearance.gridColumns`, paginated cards. For any of these, scaffold the baseline and then hand-edit per [Path B](#path-b-hand-edit-playbook).

### Faceted-search

Unique among the region scaffolders: `create region faceted-search` emits **two** regions in one atomic edit — the `facetedSearch` region itself plus the sibling `classicReport` results region it filters, wired together via `source { filteredRegion: @<results-id> }`.

```bash
uc-apx --app-dir <root> create region faceted-search \
    --page <id|alias|name> --name "Search" \
    --sql "select project, status, budget from projects" \
    --column "PROJECT:varchar2:100,STATUS:varchar2:50,BUDGET:number" \
    --facet "search:PROJECT,STATUS" \
    --facet "checkbox:STATUS" \
    --facet "range:BUDGET:STATIC2:<200;|200,200 - 300;200|300,>=300;300|"
```

- **Two regions, one command.** The classic-report ("results") gets `--results-name` (default `<name> Results`) and `--results-id` (default `<results-name>` slugged) — both overridable. It uses the same SQL + column shape as `create region classic-report`.
- **Slots and sequences default for a two-column layout**: classic-report → `slot: body, sequence: next+10`; faceted-search → `slot: leftColumn, sequence: next+20`. Override either with `--slot` / `--results-slot` / `--sequence`. Note: `leftColumn` requires a 2-column page template (e.g. `@/left-side-column`); for the default 1-column `@/standard` template, pass `--slot body` so both regions render.
- **`--facet TYPE:ARGS`** (repeatable, ≥1 required). Three types:
  - `search` — bare full-text facet (sequence 10). `search:COL1,COL2,COL3` narrows it to specific source columns via `source { dbColumns: ... }`.
  - `checkbox:COLUMN` — `checkboxGroup` with `lov { type: distinctValues }` against `source { databaseColumn: COLUMN }`.
  - `range:COLUMN:STATIC2:<payload>` — numeric range facet. The STATIC2 LOV payload is passed through verbatim (the format is `STATIC2:display;value|min,display;value|...`). Examples: `STATIC2:<200;|200,200 - 300;200|300,>=300;300|`. Always emits `source { databaseColumn: COLUMN, dataType: number }`.
- **Facet IDs follow the APEXlang convention**: `P<page-id>_<COLUMN>` (e.g. `P42_BUDGET`, `P42_SEARCH`). Labels are humanized from column names.
- **`--force`** replaces both regions on collision (the FS id and the results id are checked separately). `--dry-run` prints both rendered blocks and leaves the file untouched.
- **Facet columns must exist in the SQL projection.** The CLI doesn't cross-check — `apex validate --official` will catch any mismatch.

### Theme template components

Universal Theme ships a family of `type: themeTemplateComponent/<X>` regions that render a SQL result set through a pre-built template. Six are content components scaffolded by `uc-apx create region <component>` — all SQL-backed (`--sql` + `--column`, same column-spec syntax as classic-report), all rendering one entity per row (`componentAppearance.display: report`):

| Component | Use it for | Required mappings | Avatar | Badge |
|---|---|---|---|---|
| `avatar` | one image/initials/icon per row (people, logos) | `--avatar-type image\|initials\|icon` + matching source | — | — |
| `comments` | threaded discussion / status feed | `--comment-text-column --user-name-column --date-column` | plugin (`--avatar-type` initials\|icon) | — |
| `content-row` | rich list rows with primary actions | `--title-column --description-column` | plugin (`--avatar-icon` / initials) | plugin |
| `timeline` | chronological events | `--user-name-column --date-column --title-column --description-column` | settings flag | plugin |
| `metric-card` | KPI tiles | `--title-column --metric-column --meta-column` | plugin | plugin |
| `media-list` | compact item list with sort | `--title-column --description-column` | plugin (`--avatar-icon`) | plugin |

**Choosing a component:** showing a person/identity → `avatar`; a discussion → `comments`; KPI numbers → `metric-card`; time-ordered events → `timeline`; a rich row list with an avatar + actions → `content-row`; a lighter list with optional sort → `media-list`.

Shared optional flags across all six: `--display-avatar` / `--display-badge` (turn the decorations on — **a displayed badge requires `--badge-label` + `--badge-value-column`**), `--pagination-rows N`, `--slot`, `--column-span`, `--no-new-row`, `--id`, `--pk-column`, `--dry-run`, `--force`. Example:

```bash
uc-apx --app-dir <root> create region timeline \
    --page <id> --name "Activity" \
    --sql "select id, who, when_at, what, descr, color from events" \
    --column "ID:number,WHO,WHEN_AT:date,WHAT,DESCR,COLOR" --pk-column ID \
    --user-name-column WHO --date-column WHEN_AT --title-column WHAT --description-column DESCR \
    --display-badge --badge-label Status --badge-value-column COLOR --badge-state-column COLOR
```

**Badge has no standalone region** — it only renders as a report column. **Avatar and badge double as IR/IG columns**: use `uc-apx edit column --page <p> --region <r> --column <C> --type badge --badge-label … --badge-value-column …` (or `--type avatar --avatar-type initials --avatar-initials-column …`). The badge/avatar column type is only valid on `interactiveReport` / `interactiveGrid` regions — on a `classicReport` column the same look is a hand-edited `columnFormatting.htmlExpression` with `{with/}…{apply THEME$BADGE/}` (the CLI steers you there if you try).

### `flexbox-container` — a layout helper, not a content component

`uc-apx create region flexbox-container` scaffolds a `themeTemplateComponent/flexboxContainer` region: a **layout-only** container (no SQL, no columns, `display: regionOnly`) that arranges its **child** regions in a flex row or column. Reach for it whenever the default 12-column grid fights you — to put regions **side by side with equal height**, stack them in a gapped column, or let them **wrap responsively**:

```bash
uc-apx --app-dir <root> create region flexbox-container \
    --page <id> --name "Cards Row" \
    --direction row --gap lg --align-items stretch --flex-behavior growIfNeeded
```

Flags map straight to `settings`: `--direction row|column`, `--gap sm|md|lg`, `--align-items start|center|end|stretch`, `--justify-content start|center|end|spaceBetween`, `--wrap wrap|noWrap`, `--flex-behavior growIfNeeded`. After creating it, point the child regions at it by setting their `layout.parentRegion: @<container-id>` and `slot: subRegions` (a hand-edit, or pass `--slot subRegions` when creating the children once the container exists). It's a good default for grouping metric-cards, charts, or any set of regions you want laid out as a clean responsive row instead of grid columns.

### Page items (`uc-apx create page-item <type>`)

Add a single input/display field to an **existing region** on a page. The item is rendered as a direct page child with `layout.region: @<region-id>`. ID convention: `P<page-id>_<NAME>` (override with `--id`).

Shared flags (every subcommand): `--page`, `--region`, `--name`, optional `--label`, `--slot` (default `regionBody`), `--sequence` (default: max existing + 10), `--id`, `--dry-run`. `--region` is required for every subcommand **except `hidden`**, which auto-picks the first non-breadcrumb / non-navigationBar region when the flag is omitted (hidden items don't render, so the parent region is purely organizational).

| Type | Subcommand | Notable flags |
|---|---|---|
| `textField` / `textarea` / `password` | `text` | `--multiline` (textarea), `--password`, `--max-length`, `--required` |
| `hidden` | `hidden` | Session-state-protected (`checksumRequiredSessionLevel`); `--region` is optional (auto-picks a content region; emits a stderr note if you pin to a breadcrumb / navigationBar). For PK-bearing hidden items use `create region form --pk-column` instead. |
| `switch` | `switch` | `--default Y\|N`, `--required` |
| `selectList` / `radioGroup` / `checkboxGroup` | `select` / `radio-group` / `checkbox-group` | Exactly one LOV: `--static-values "D1;R1,D2;R2"` / `--sql "select d, r from t"` / `--lov <alias>` (shared component). `--required` |
| `numberField` | `number` | `--min`, `--max` (emit `settings { minValue, maxValue }`), `--required` |
| `datePicker` | `date` | `--format-mask` (default `DD-MON-YYYY`), `--required` |
| `displayOnly` | `display-only` | `--value <static-text>` (emits `default { type: static }`) |

Examples:

```bash
uc-apx --app-dir <root> create page-item text  --page 100 --region filter --name SEARCH --max-length 100
uc-apx --app-dir <root> create page-item select --page 100 --region filter --name STATUS \
    --static-values "Open;O,Closed;C,All;ALL"
uc-apx --app-dir <root> create page-item date  --page 100 --region filter --name START_DATE
uc-apx --app-dir <root> create page-item hidden --page 100 --name TOKEN  # --region auto-picked
```

Note: items emitted by this command are **free-standing** (no `source { formRegion: … }` binding). For form-bound items use `create region form --column NAME:TYPE`.

### Buttons (`uc-apx create button <kind>`)

Add a single button to an existing region. Construct id defaults to a kebab-case slug of `--label`; `buttonName` defaults to its UPPERCASE form.

Shared flags: `--page`, `--region`, `--label`, optional `--name`, `--id`, `--slot`, `--sequence`, `--hot`, `--dry-run`. Each kind has its own slot default (see below).

| Kind | `behavior.action` | Default slot | Notable flags |
|---|---|---|---|
| `redirect` | `redirectThisApp` | `next` | `--target-page <n>` (required), repeatable `--item-pair NAME=VALUE` (e.g. `--item-pair P50_ID=#ID#`). Emits `target.clearCache`. |
| `cancel` | `definedByDynamicAction` | `close` | On modal-dialog pages (`appearance.pageMode: modalDialog`), **auto-emits a sibling dynamicAction** `cancel-dialog-<button-id>` → `action: cancelDialog`. On non-modal pages, only the button is emitted; NextSteps tells the user to wire a DA. |
| `submit` | `submitPage` | `next` | `--confirmation-message`, `--confirmation-style` (`danger`/`warning`/`info`/`success`). No DML. |
| `save` | `submitPage` + `databaseAction: update` | `change` | `hot: true`. `--pk-item P<n>_NAME` → `serverSideCondition { type: itemIsNotNull }`. |
| `create` | `submitPage` + `databaseAction: insert` | `create` | `hot: true`. `--pk-item P<n>_NAME` → `serverSideCondition { type: itemIsNull }`. |
| `delete` | `submitPage` + `databaseAction: delete` | `delete` | Always `requiresConfirmation: true` + danger styling + `executeValidations: false`. `--pk-item P<n>_NAME` → `serverSideCondition { type: itemIsNotNull }`. |

Examples:

```bash
# Parent-page button that opens a modal-dialog
uc-apx --app-dir <root> create button redirect --page 100 --region bar --label "Open Confirm" --target-page 160

# Close button on a modal-dialog page — auto-emits cancel-dialog DA
uc-apx --app-dir <root> create button cancel --page 160 --region buttons --label "Close"

# Standard form-button trio
uc-apx --app-dir <root> create button save   --page 100 --region bar --label "Save Changes" --pk-item P100_ID
uc-apx --app-dir <root> create button create --page 100 --region bar --label "Add Row"      --pk-item P100_ID
uc-apx --app-dir <root> create button delete --page 100 --region bar --label "Remove Row"   --pk-item P100_ID
```

Note: the save/create/delete trio overlaps with what `create region form` already emits in bulk. Reach for these standalone commands when (a) you scaffolded a region without `--column`, (b) you want extra buttons beyond the auto-emitted four, or (c) you're attaching buttons to a hand-built (non-CLI) region.

### Dynamic actions (`uc-apx create dynamic-action <kind>`)

Today the only kind is `refresh-on-dialog-close` — Pass 2 of the modal-dialog parent-page wiring. Splices a standalone `dynamicAction ... when { event: apexafterclosedialog }` into the parent (non-modal) page so a region refreshes after the modal closes.

| Flag | Meaning |
|---|---|
| `--page` | Parent page (numeric ID, alias, or name). Required. |
| `--refresh-region @<id>` | Region to refresh after close (`affectedElements.region`). Required. |
| `--trigger-button @<id>` | Fire only when the modal was opened by this specific button (`selectionType: button`). Use for explicit "open dialog" buttons (e.g. "Add Row"). |
| `--trigger-region @<id>` | Fire when ANY modal opened from this region closes (`selectionType: region`). Use for IR/CR row-level link columns where multiple rows can each open a modal. |
| `--id` / `--name` / `--sequence` | Optional overrides. Defaults: `refresh-<trigger>-on-close`, `Refresh on Dialog Close (<trigger>)`, max existing DA sequence + 10. |

Pick exactly one of `--trigger-button` / `--trigger-region`. Both flavors share one renderer; the difference is just which `selectionType` + ref pair lands in the `when {}` block.

```bash
# Add Row → modal opens → close → refresh customers IR
uc-apx --app-dir <root> create dynamic-action refresh-on-dialog-close \
    --page 100 --refresh-region customers --trigger-button add-row

# Edit pencil column on the IR opens a modal → close → refresh same IR
uc-apx --app-dir <root> create dynamic-action refresh-on-dialog-close \
    --page 100 --refresh-region customers --trigger-region customers
```

### `create link-column` (rewrite an IR/CR column as a row-level link)

Pass 2 of the modal-dialog wiring: turn an existing classic-report or interactive-report column into a `type: link` action column that opens another page with row-substitution-token (`#COL#`) passthrough. The column is rewritten in place — heading text, sequence, `source.dataType` etc. are preserved.

| Flag | Meaning |
|---|---|
| `--page` | Page that hosts the report region. Required. |
| `--region` | Parent region id (must be `classicReport` or `interactiveReport`). Required. |
| `--column` | Column id (NAME) to rewrite. Required. |
| `--target-page` | Page number the link opens. Required. |
| `--item-pair NAME=VALUE` | Repeatable. Splices into `link.target.items`. Use `#COL#` to pass the row's column value (e.g. `--item-pair P200_ID=#ID#`). |
| `--clear-cache` | Page(s) to clear-cache (default = `--target-page`). |
| `--link-text` | HTML / text rendered as the link body. Default: the edit-pencil img (`<img src="#IMAGE_PREFIX#app_ui/img/icons/apex-edit-pencil.png" …>`). |
| `--heading` | Override `heading.heading` text (default: keep existing). |
| `--center` | Force `heading.alignment` + `layout.columnAlignment` to `center` (default true; typical for icon-only links). |
| `--disable-user-actions` | Emit `enableUsersTo { hide: false sort: false … }` (default true; typical for an action column). |

```bash
# Convert the auto-scaffolded ID column on page 100 into an edit-pencil
# link that opens modal page 200 with the row's PK pre-populated.
uc-apx --app-dir <root> create link-column \
    --page 100 --region customers --column ID \
    --target-page 200 \
    --item-pair P200_ID=#ID#
```

Then wire the parent-refresh-on-close DA so closing the modal updates the report (pick `--trigger-region <region>` because every row's link triggers from the same region):

```bash
uc-apx --app-dir <root> create dynamic-action refresh-on-dialog-close \
    --page 100 --refresh-region customers --trigger-region customers
```

interactiveGrid is intentionally excluded — IG has a different column-link taxonomy (action columns); hand-edit those per [Path B](#path-b-hand-edit-playbook).

### `uc-apx edit column` (rewrite an existing IG / CR / IR column in place)

Sibling to `create link-column`: switch a column's `type:`, attach an LOV, splice in a `default { ... }` block, or flip the column to read-only — all without a hand-edit. Works on `interactiveGrid`, `classicReport`, and `interactiveReport` regions.

| Flag | Meaning |
|---|---|
| `--page` / `--region` / `--column` | Locate the target column. Required. |
| `--type <name>` | Rewrite the top `type:` property. Accepts kebab-case (`select-list`, `number`, `text`, `date`, `hidden`, `display-only`, `textarea`, `switch`, `radio-group`, `checkbox-group`, `rich-text`) or a raw apexlang token. |
| `--lov @<alias>` | Wipe the existing `lov { ... }` block and write `type: sharedComponent` + `lov: @<alias>`. Strip a leading `@` if present. |
| `--lov-sql <SELECT>` | Like `--lov` but `type: sqlQuery`. The SELECT must return `(display, return)` pairs. |
| `--lov-static "D1;R1,D2;R2"` | Like `--lov` but `type: staticValues`. |
| `--null-display-value <text>` | Adds `lov.nullDisplayValue: <text>` (e.g. `- Select Match -`). Requires an LOV (existing or newly set in the same call). |
| `--default-plsql <body>` | Wipe + rewrite `default { type: functionBody; plsqlFunctionBody: \`\`\`plsql ... \`\`\` }`. The canonical "current-user default" pattern. |
| `--default-static <value>` | Wipe + rewrite `default { type: static; staticValue: <value> }`. |
| `--readonly` | Add (or upsert) `readOnly { type: always }`. |
| `--query-only` | Tri-state. `--query-only` adds `source.queryOnly: true` (column is read on query, skipped on insert/update — required for identity-generated PKs to avoid `ORA-32795`). `--query-only=false` removes the property. Omit the flag to leave it untouched. |
| `--badge-label` / `--badge-value-column` / `--badge-state-column` / `--badge-icon` | Turn the column into a badge (`type: themeTemplateComponent/badge` + a wiped-and-rewritten `settings { label, value, state, icon }`). Implies `--type badge`. Label + value are mandatory. **IR / IG only** (classicReport uses an htmlExpression hand-edit). |
| `--avatar-type` / `--avatar-initials-column` / `--avatar-image-column` / `--avatar-icon` / `--avatar-css-classes` | Turn the column into an avatar (`type: themeTemplateComponent/avatar` + `settings`). Implies `--type avatar`. Mutually exclusive with the `--badge-*` flags. **IR / IG only**. |

```bash
# Editable IG over a per-user table: default USERNAME to v('APP_USER')
# and turn the FK column into a shared-LOV dropdown.
uc-apx --app-dir <root> edit column \
    --page 50 --region my-predictions --column USERNAME \
    --default-plsql "return v('APP_USER');"
uc-apx --app-dir <root> edit column \
    --page 50 --region my-predictions --column MATCH_ID \
    --type select-list --lov @matches-lov \
    --null-display-value "- Select Match -"
```

The IG/form scaffolders already mark the PK column as `source.queryOnly: true` so identity-generated PKs don't trip `ORA-32795` on submit. Override only when the PK is a writable natural key:

```bash
uc-apx --app-dir <root> edit column \
    --page 50 --region my-predictions --column EXTERNAL_REF \
    --query-only=false
```

`--lov*` and `--default-*` use **wipe-and-rewrite** semantics: re-running with a different source replaces the previous block cleanly instead of producing a Frankenstein block with stray properties from the old shape.

### After the CLI runs

The CLI re-parses the modified file before writing. If parsing fails, the page is left untouched. Once it returns successfully, **still** run validate per step 5 — local checks may flag broken references, and `--official` is the only path that catches MMD-schema issues.

### Going further (post-scaffold hand-edits)

The CLI emits a SQLcl-clean baseline. For production quality you typically still hand-edit a few things via [Path B](#path-b-hand-edit-playbook). Knobs Oracle's APEXlang skills document that **the CLI does not expose**:

- **Custom format masks** beyond the date default — e.g. `FML999G999G999G999G990D00` for currency, `999G990` for integer counts. Set on `column.appearance.formatMask` for classic-report or `pageItem.appearance.format` for forms.
- **Column rendering** as link / image / downloadBlob / percentGraph — set `column.type` and the matching block (`link`, `appearance.backgroundColor`/`foregroundColor`, etc.).
- **HTML rendering in columns**: emit raw values from SQL and add `columnFormatting.htmlExpression` to wrap them in badges/spans. Don't return HTML directly from the query.
- **LOV-backed columns/items**: set `column.type: plainTextBasedOnLov` + `lov.sharedComponent: @<lovAlias>` (report) or change item `type: selectList` and add `lov { type, staticValues|sqlQuery|sharedComponent }` (form).
- **Cancel button wiring**: add a `dynamicAction` triggered by `@cancel` whose action is `closeDialog` (modal) or `redirectThisApp` with a `target.page:` (full page).
- **Authorization**: `security.authorizationScheme: @<scheme>` on region, button, or column.
- **Visibility gating**: `serverSideCondition { type, item, value|list }` on any construct.
- **Header/footer**, **non-default pagination**, **custom "no data" messages**: the region exposes `headerAndFooter`, `pagination.type`, `messages.whenNoDataFound`.

Add these by editing the produced `.apx` file directly, then re-run `uc-apx validate --official` to confirm SQLcl still accepts the result.

## Path B: hand-edit playbook

For region types not yet covered by the CLI (`chart` variants beyond cartesian + pie, breadcrumb regions, …) and for non-plsql process types and dynamic-action scenarios beyond `refresh-on-dialog-close`.

> **Note:** Validations, computations, branches, and page-level PL/SQL processes now have CLI scaffolders (`uc-apx create validation|computation|branch|process plsql`). Hand-edit those only if a flag is missing — but first check the CLI help; it almost certainly covers your case.

> **Inverse operation: deletion.** To *remove* any of these constructs (whether scaffolded by the CLI or hand-edited), use the `uc-apx delete` family — see [skills/edit/delete-component/SKILL.md](../delete-component/SKILL.md). Don't hand-edit `.apx` files just to delete; the CLI handles the indent-aware splice, the trailing-blank cleanup, and the ref-safety gate.

```
1. Locate the page file              → uc-apx pages | uc-apx page <id>
2. Inspect the construct kind        → uc-apx shape region (or pageItem, button, …)
3. Find a similar existing instance  → uc-apx search; uc-apx component <id>
4. Hand-edit the page .apx           → Read + Edit
5. Validate                          → uc-apx validate (--official if SQLcl is present)
```

### Step 1: locate the page file

```bash
uc-apx pages --app-dir <root>             # list all pages with file paths
uc-apx page <id> --app-dir <root>         # detail for one page incl. file path
```

The file is `pages/pNNNNN-<slug>.apx`. All sub-page constructs live inside that file's top-level `page <N> ( ... )` block.

### Step 2: inspect the construct kind

```bash
uc-apx shape region --app-dir <root>
uc-apx shape pageItem --app-dir <root>
uc-apx shape button --app-dir <root>
uc-apx shape process --app-dir <root>
```

Each report shows the properties and blocks instances of that kind use in this app. Properties with `count == instanceCount` are conventional and you probably want them too. See [skills/read/inspect-construct-schema/SKILL.md](../../read/inspect-construct-schema/SKILL.md).

### Step 3: find a similar instance

```bash
# A static-content region similar to what you want
uc-apx search "type: staticContent" --app-dir <root>

# A button that submits + redirects
uc-apx search "action: redirect" --app-dir <root>

# Then dump the full structure of one as a template
uc-apx component <id> --app-dir <root>
```

Copy that structure verbatim, then change only the values you need.

### Step 4: hand-edit the page file

Open the page file. Children of the page live as top-level siblings of properties — they go after the property blocks but inside the page's outer `( ... )`:

```
page 2 (
    name: Sales History Content Row
    alias: SALES-HISTORY-CONTENT-ROW
    title: Sales History Content Row
    appearance { ... }
    navigation { ... }
    security { ... }

    region APEX$13260232210874771292 (    # ← children start here
        name: Timer
        type: dynamicContent
        ...
    )

    region APEX$50764435396818709550 (
        name: Sales History
        type: themeTemplateComponent/contentRow
        ...
    )
)
```

**Construct templates** (copy + adjust):

A static-content region:

```
region APEX$<unique-digits> (
    name: My Region
    type: staticContent
    layout {
        sequence: 30
        slot: BODY
    }
    appearance {
        template: @/standard
        templateOptions: #DEFAULT#
    }
    source {
        html: 
            ```html
            <p>Hello world</p>
            ```
    }
)
```

A page item (text field):

```
pageItem MY_ITEM (
    label: My Item
    type: textField
    region: @<parent-region-id-or-alias>
    layout {
        sequence: 10
    }
    appearance {
        template: @/optional-floating
    }
)
```

A button:

```
button MY_BUTTON (
    name: MY_BUTTON
    label: Save
    region: @<parent-region-id-or-alias>
    layout {
        sequence: 30
        slot: REGION_POSITION_03
    }
    appearance {
        template: @/text-with-icon
        hotKey: Ctrl+S
    }
    behavior {
        action: redirect              # or "submitPage"
        target {
            type: page
            page: @<target-page>
        }
    }
)
```

A PL/SQL process:

```
process APEX$<unique-digits> (
    name: Process My Form
    type: plsqlCode
    point: afterSubmit
    sequence: 10
    settings {
        plsqlCode: 
            ```plsql
            begin
                update emp set sal = nvl(sal,0) + 100 where empno = :P2_EMPNO;
            end;
            ```
    }
)
```

### Key conventions

- **Indentation**: 4 spaces per nesting level. Every property/child on its own line.
- **IDs**: For most regions/processes use `APEX$<20-ish digits>` to match the export style. For page items and buttons, named identifiers (`MY_ITEM`, `MY_BUTTON`) are common and conventional.
- **`layout.sequence`**: Use multiples of 10 (10, 20, 30…). Pick a value that places your construct where the user expects in the rendered order.
- **`layout.slot`**: Region slots use values like `BODY`, `REGION_POSITION_01`, `SUB_REGIONS`. Pattern-match against neighbors in the same page.
- **`region: @<parent>`**: Page items and buttons must reference a parent region. The parent must exist on the same page.
- **References**: `@APEX$<id>` resolves by exact ID; `@aliasName` resolves to the construct whose ID equals `aliasName`; `@/template-name` is a system/theme reference (don't invent these — they must exist in the target theme).
- **Code blocks**: Triple-backtick fence + language tag. Languages: `sql`, `plsql`, `javascript-browser`, `css`, `html`.

### Step 5: validate

This step is **not optional**. See [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md).

## Quick check: did I parse?

After saving, the fastest signal that the file is structurally valid:

```bash
uc-apx page <id> --app-dir <root>
```

If it returns a result, the file parsed. If it errors, the file has a syntax issue — fix the parser error before running the full validate.

## Common pitfalls

- **Inserting a child in the wrong block.** Children of the page go directly inside the page's `( ... )`. Don't put them inside `appearance { ... }` or `layout { ... }`.
- **Forgetting the parent `region:` on items/buttons.** They will parse but won't render where you expect; validate may not catch this. Pattern-match against an existing page item.
- **Invented theme templates.** `@/standard` and `@/drawer` are safe; other names depend on the active theme. If unsure, copy the value from a working sibling region.
- **Forgetting `templateOptions: #DEFAULT#`.** Without it, optional template options may resolve to nothing and rendering surprises follow.
- **Wrong code-block language tag.** Triple-backtick fence without a tag breaks language-sensitive editors. Always tag with `sql`, `plsql`, `javascript-browser`, `css`, or `html`.

## Validate before you declare done

After editing, run validate from the app root:

```bash
uc-apx validate --app-dir <project-root>
```

If `sql` (SQLcl 26.1.2+) is on `$PATH`, prefer the full check:

```bash
uc-apx validate --app-dir <project-root> --official
```

**Do not declare the change done until validate exits clean.** If validate errors, read the file and line it reports, fix the issue, and re-run. See [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md) for how to interpret each issue kind.

## Reference

- Parser: [parser/parser.go](../../../parser/parser.go)
- Schema inspection: [skills/read/inspect-construct-schema/SKILL.md](../../read/inspect-construct-schema/SKILL.md)
- Validate workflow: [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md)
