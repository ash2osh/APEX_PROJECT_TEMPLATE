# Domain-Focused APEX Knowledge Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent, domain-only Graphify integration that extracts useful architectural relationships from APEXlang and indexes application context.

**Architecture:** A self-contained, repository-owned Python extractor parses APEXlang into Graphify-compatible nodes and edges. The existing setup utility copies that extractor into each isolated Graphify installation and registers `.apx`; `.graphifyignore` limits Graphify to `apps/`, `database/`, and `app_context/`, while documented full semantic extraction adds context and normal `graphify update .` retains it.

**Tech Stack:** Python 3 standard library, Graphify's node/edge JSON contract, Graphify CLI, `unittest`, Bash/PowerShell template checks, Oracle APEXlang and SQL/PLSQL text parsing.

**Spec:** `docs/superpowers/specs/2026-08-29-domain-apex-graph-design.md`

## Global Constraints

- Index source only from `apps/`, `database/`, and `app_context/`; explicitly exclude `ai_generate/`.
- Emit architectural nodes only: applications, pages, regions, processes, dynamic actions, relevant shared components, and database symbols.
- Do not emit standalone nodes for page items, buttons, report columns, templates, CSS, JavaScript, or static assets.
- Preserve source path and line on every extracted node and edge.
- Keep the extractor canonical in the repository and copy it into Graphify only through the idempotent setup utility.
- Support shebang launchers and compiled Windows Graphify launchers.
- Never execute `.env` as shell code and do not access a database for this work.
- Preserve unrelated untracked `apps/`, `database/`, and `app_context/` content.
- Do not commit during this execution unless the user separately authorizes a commit.
- Keep temporary fixtures under `scratch/` and generated `graphify-out/` gitignored.

## File Structure

- Create `scripts/graphify_apexlang_extractor.py`: self-contained APEXlang parser and Graphify-compatible `extract_apexlang(path)` entry point.
- Create `scripts/test_graphify_apexlang_extractor.py`: parser topology, dependency, malformed-input, and stable-ID unit tests.
- Modify `setup_graphify_apx.py`: install the canonical extractor, patch routing, verify content, and smoke-test the installed copy.
- Modify `scripts/test_setup_graphify.py`: fixture Graphify package tests for clean, repeated, outdated, partial, and incompatible installs.
- Modify `.graphifyignore`: root domain allowlist plus APEX export-payload exclusions.
- Create `scripts/test_graphify_corpus.py`: assert allowlist behavior using Graphify when available and static contract checks otherwise.
- Modify `scripts/test_template.sh`: run the focused extractor and corpus tests.
- Modify `.agents/rules/graphify.md`: domain-only query/update rules and semantic-context refresh gate.
- Modify `.agents/workflows/graphify.md`: portable setup, initial full extraction, code update, context update, forced rebuild, and upgrade instructions.
- Modify `AGENTS.md` and `README.md`: expose the persistent setup contract to template users.
- Modify `self_improve.md` only if implementation exposes a new reusable failure mode supported by test evidence.

---

### Task 1: Structural APEXlang Extractor

**Files:**
- Create: `scripts/graphify_apexlang_extractor.py`
- Create: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: a filesystem `pathlib.Path` containing one APEXlang export file.
- Produces: `extract_apexlang(path: Path) -> dict[str, object]` with `nodes`, `edges`, and optional `error`; every node has `id`, `label`, `file_type`, `source_file`, and `source_location`; every edge has `source`, `target`, `relation`, `confidence`, `source_file`, `source_location`, and `weight`.
- Produces: `ApexlangParseError(ValueError)` for unbalanced component delimiters or multiline fences.
- Produces stable IDs through `make_id(*parts: object) -> str` using lowercase alphanumeric/underscore normalization.

- [ ] **Step 1: Write failing structural tests**

Add fixtures directly in `scripts/test_graphify_apexlang_extractor.py` and load the extractor by file path so tests do not require Graphify:

```python
SAMPLE = '''\
app 102 (
    name: APEXToGo
)
page 4 (
    name: Home
    region categories (
        name: Categories
    )
    dynamicAction open-search (
        name: Open Search
    )
    process create-order (
        name: Create Order
    )
)
'''

def test_extracts_architectural_containment(self):
    result = self.extract(SAMPLE, "apps/DEMO/102/pages/p00004-home.apx")
    by_id = {node["id"]: node for node in result["nodes"]}
    self.assertIn("apex_app_102_page_4", by_id)
    self.assertIn("apex_app_102_page_4_region_categories", by_id)
    self.assertIn("apex_app_102_page_4_dynamic_action_open_search", by_id)
    self.assertIn("apex_app_102_page_4_process_create_order", by_id)
    pairs = {(e["source"], e["target"], e["relation"]) for e in result["edges"]}
    self.assertIn(("apex_app_102", "apex_app_102_page_4", "contains"), pairs)
    self.assertIn(("apex_app_102_page_4", "apex_app_102_page_4_region_categories", "contains"), pairs)

def test_ignores_nonarchitectural_components_as_nodes(self):
    result = self.extract('''page 4 (\n button checkout (\n )\n pageItem P4_X (\n )\n)\n''')
    labels = {n["label"] for n in result["nodes"]}
    self.assertFalse(any("checkout" in label.lower() for label in labels))
    self.assertFalse(any("p4_x" in label.lower() for label in labels))
```

Also assert source line fields, same-named regions in different pages receiving different IDs, comment/array/brace handling, and repeat extraction producing byte-equivalent sorted nodes and edges.

- [ ] **Step 2: Run structural tests and confirm failure**

Run:

```bash
python3 scripts/test_graphify_apexlang_extractor.py -v
```

Expected: import/file-not-found failure for `scripts/graphify_apexlang_extractor.py`.

- [ ] **Step 3: Implement the structural parser**

Implement these focused types and functions:

```python
from dataclasses import dataclass
from pathlib import Path
import re

ARCHITECTURAL_TYPES = {
    "app": "app",
    "page": "page",
    "region": "region",
    "process": "process",
    "dynamicAction": "dynamic_action",
    "list": "list",
    "lov": "lov",
    "authentication": "authentication",
    "authorization": "authorization",
    "appProcess": "app_process",
    "buildOption": "build_option",
}

@dataclass
class Frame:
    kind: str
    identifier: str
    line: int
    node_id: str | None
    architectural_owner: str | None

class ApexlangParseError(ValueError):
    pass

def make_id(*parts: object) -> str:
    raw = "_".join(str(part) for part in parts if str(part))
    return re.sub(r"_+", "_", re.sub(r"[^a-zA-Z0-9]+", "_", raw)).strip("_").lower()

def extract_apexlang(path: Path) -> dict[str, object]:
    try:
        text = path.read_text(encoding="utf-8")
        return parse_apexlang(text, path)
    except (OSError, UnicodeError, ApexlangParseError) as exc:
        return {"nodes": [], "edges": [], "error": str(exc)}
```

`parse_apexlang` must:

1. Derive the numeric application ID from the path segment after schema under `apps/`; accept an `app N (` declaration as the authoritative fallback.
2. Add one file node using the full source path.
3. Scan line by line while tracking component `(` frames, property-group `{` names, arrays, block comments, and triple-backtick fences.
4. Recognize declaration lines with a strict anchored regular expression; never treat text inside a fence as APEXlang.
5. Emit nodes only for `ARCHITECTURAL_TYPES`.
6. Attach a page to `apex_app_<id>`, and attach region/process/dynamic-action nodes to their page. Attach retained shared components directly to the app.
7. Update labels when a `name:` property is read, without changing IDs.
8. Return an error and no cacheable nodes if a fence or component delimiter remains open at EOF.

Use labels such as `App 102: APEXToGo`, `Page 4: Home`, and `Region: Categories`; keep the application/page number in metadata where helpful but do not require Graphify-specific classes.

- [ ] **Step 4: Run structural tests**

Run:

```bash
python3 scripts/test_graphify_apexlang_extractor.py -v
```

Expected: all structural, source-line, ignored-detail, malformed-input, and stable-ID tests pass.

- [ ] **Step 5: Review the focused diff**

Run:

```bash
git diff --check -- scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
git diff -- scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
```

Expected: no whitespace errors; only the new extractor and its tests appear.

---

### Task 2: Navigation, Security, SQL, and PL/SQL Relationships

**Files:**
- Modify: `scripts/graphify_apexlang_extractor.py`
- Modify: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: the `Frame` stack and multiline blocks produced by Task 1.
- Produces: `navigates_to`, `references_component`, `secured_by`, `reads_from`, `writes_to`, and `calls` edges.
- Produces: unresolved database/shared-component nodes with an empty `source_file` and `origin_file` set to the referencing `.apx` path so Graphify can rewire them to unique definitions.

- [ ] **Step 1: Add failing relationship tests**

Use a fixture containing a navigation list entry, a page authorization, a region SQL query, and a process PL/SQL body:

```python
RELATIONSHIPS = '''\
page 8 (
    name: Cart
    security {
        authorizationScheme: @must-not-be-public-user
    }
    region cart-lines (
        source {
            sqlQuery:
                ```sql
                select i.name
                  from sample_restaurant_items i
                  join sample_restaurant_order_items oi on oi.item_id = i.id
                ```
        }
    )
    process checkout (
        code:
            ```plsql
            insert into sample_restaurant_orders(id) values (1);
            sample_restaurant_manage_orders.create_order;
            ```
    )
)
list navigation-menu (
    entry cart (
        link { target: { page: 8 } }
    )
)
'''
```

Assert exact edge tuples:

```python
self.assertEdge(result, "apex_app_102_page_8", "must_not_be_public_user", "secured_by")
self.assertEdge(result, "apex_app_102_page_8_region_cart_lines", "sample_restaurant_items", "reads_from")
self.assertEdge(result, "apex_app_102_page_8_region_cart_lines", "sample_restaurant_order_items", "reads_from")
self.assertEdge(result, "apex_app_102_page_8_process_checkout", "sample_restaurant_orders", "writes_to")
self.assertEdge(result, "apex_app_102_page_8_process_checkout", "sample_restaurant_manage_orders_create_order", "calls")
self.assertEdge(result, "apex_app_102_list_navigation_menu", "apex_app_102_page_8", "navigates_to")
```

Add negative cases proving keywords inside SQL comments/string literals and `&ITEM.` substitutions do not become objects or calls. Add a structured `target { page: 5 }`, an `f?p=&APP_ID.:7:` URL, and an `@shared-lov` component-reference fixture.

- [ ] **Step 2: Run relationship tests and confirm failure**

Run:

```bash
python3 scripts/test_graphify_apexlang_extractor.py -v
```

Expected: structural tests pass; new relationship assertions fail because edges are absent.

- [ ] **Step 3: Implement relationship collection**

Add these helpers with deterministic outputs:

```python
SQL_IDENT = r'(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*)(?:\s*\.\s*(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*))*'

def strip_sql_comments_and_literals(text: str) -> str:
    masked = list(text)
    for match in re.finditer(r"--[^\n]*|/\*.*?\*/|'(?:''|[^'])*'", text, re.S):
        masked[match.start():match.end()] = [
            "\n" if char == "\n" else " " for char in match.group(0)
        ]
    return "".join(masked)

def sql_dependencies(text: str) -> tuple[set[str], set[str], set[str]]:
    clean = strip_sql_comments_and_literals(text)
    reads = {m.group(1) for m in re.finditer(rf"\b(?:FROM|JOIN)\s+({SQL_IDENT})", clean, re.I)}
    writes = {m.group(1) for m in re.finditer(
        rf"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO)\s+({SQL_IDENT})",
        clean,
        re.I,
    )}
    calls = {m.group(1) for m in re.finditer(rf"\b({SQL_IDENT}\s*\.\s*{SQL_IDENT})\s*(?:\(|;)", clean)}
    return reads, writes, calls

def add_reference_node(nodes: list[dict], seen: set[str], label: str, source_path: str) -> str:
    node_id = make_id(label)
    if node_id not in seen:
        nodes.append({"id": node_id, "label": label, "file_type": "code",
                      "source_file": "", "source_location": "", "origin_file": source_path})
        seen.add(node_id)
    return node_id

def add_edge(edges: list[dict], source: str, target: str, relation: str,
             source_path: str, line: int, context: str | None = None) -> None:
    edge = {"source": source, "target": target, "relation": relation,
            "confidence": "EXTRACTED", "source_file": source_path,
            "source_location": f"L{line}", "weight": 1.0}
    if context is not None:
        edge["context"] = context
    if edge not in edges:
        edges.append(edge)
```

Implement conservative Oracle identifier patterns supporting unquoted names,
`schema.object`, and quoted segments. After comments and literals are masked:

- Collect reads after `FROM` and `JOIN`.
- Collect writes after `INSERT INTO`, `UPDATE`, `DELETE FROM`, and `MERGE INTO`.
- Collect callable `package.procedure(` and `package.procedure;` expressions from PL/SQL fences, excluding SQL clauses and APEX built-ins unless the call is schema/package qualified.
- Normalize unresolved target IDs with `make_id(identifier)` while retaining source spelling in labels.
- Attach dependencies to the nearest architectural owner, not to ignored item/button/entry frames.
- Create page target IDs as `apex_app_<app>_page_<number>`.
- Map authorization properties to `secured_by`; map component-reference property names to the relevant app-scoped shared-component target when the family is known, falling back to a normalized unresolved stub.
- Deduplicate equal `(source, target, relation, source_file, source_location)` edges.

Support single-line nested target blocks by tokenizing braces on the line rather than requiring each brace to occupy its own line.

- [ ] **Step 4: Run all extractor tests**

Run:

```bash
python3 scripts/test_graphify_apexlang_extractor.py -v
```

Expected: all relationship and negative-noise tests pass.

- [ ] **Step 5: Exercise the extractor against current demo exports**

Run a read-only summary without writing generated files:

```bash
python3 - <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("apx", "scripts/graphify_apexlang_extractor.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
files = list(Path("apps").rglob("*.apx"))
results = [module.extract_apexlang(path) for path in files]
errors = [(str(path), result.get("error")) for path, result in zip(files, results) if result.get("error")]
edges = sum(len(result.get("edges", [])) for result in results)
print({"files": len(files), "edges": edges, "errors": errors[:10]})
raise SystemExit(1 if errors or edges == 0 else 0)
PY
```

Expected: every retained demo `.apx` file parses without error and total edges are nonzero.

---

### Task 3: Persistent Graphify Installer

**Files:**
- Modify: `setup_graphify_apx.py`
- Modify: `scripts/test_setup_graphify.py`

**Interfaces:**
- Consumes: canonical `scripts/graphify_apexlang_extractor.py`.
- Produces: `patch_graphify_dir(base: Path) -> bool`, which copies the canonical module to `base / "extractors" / "apexlang.py"`, patches imports/routing, verifies exact installed content, and returns false on any partial/incompatible package.
- Produces: `smoke_test_graphify_dir(base: Path) -> tuple[bool, str]` using the installed extractor entry point against a scratch fixture.

- [ ] **Step 1: Replace installer fixtures with failing persistence tests**

Build a minimal fake Graphify package containing:

```python
# detect.py
CODE_EXTENSIONS = {'.sql',}

# extract.py
from graphify.extractors.sql import extract_sql
_DISPATCH = {".sql": extract_sql,}
_EXTRA_FOR_EXTENSION = {".sql": "sql",}
```

Tests must assert:

- The canonical extractor is copied to `extractors/apexlang.py`.
- `extract.py` imports `extract_apexlang` and maps `.apx` to it, never `extract_sql`.
- `detect.py` recognizes `.apx` as code.
- A second patch is byte-for-byte idempotent.
- Replacing the installed extractor with stale content is repaired.
- Missing `detect.py`, `extract.py`, registration anchors, or canonical extractor returns false.
- A late failure leaves setup reporting false even if an earlier file was patchable.

- [ ] **Step 2: Run installer tests and confirm failure**

Run:

```bash
python3 scripts/test_setup_graphify.py -v
```

Expected: failures because current setup maps `.apx` to SQL and does not copy or smoke-test the canonical extractor.

- [ ] **Step 3: Implement copy-and-register setup**

Refactor setup into small gates:

```python
REPO_ROOT = Path(__file__).resolve().parent
CANONICAL_EXTRACTOR = REPO_ROOT / "scripts" / "graphify_apexlang_extractor.py"

def patched_detector(text: str) -> str | None:
    if "'.apx'" in text or '".apx"' in text:
        return text
    marker = "'.sql',"
    return text.replace(marker, "'.sql', '.apx',", 1) if marker in text else None

def patched_dispatch(text: str) -> str | None:
    text = text.replace("from graphify.extractors.sql import extract_sql",
                        "from graphify.extractors.sql import extract_sql\n"
                        "from graphify.extractors.apexlang import extract_apexlang", 1)
    if '".apx": extract_sql,' in text:
        text = text.replace('".apx": extract_sql,', '".apx": extract_apexlang,', 1)
    elif '".apx": extract_apexlang,' not in text and '".sql": extract_sql,' in text:
        text = text.replace('".sql": extract_sql,',
                            '".sql": extract_sql,\n    ".apx": extract_apexlang,', 1)
    required = ("from graphify.extractors.apexlang import extract_apexlang",
                '".apx": extract_apexlang,')
    return text if all(value in text for value in required) else None

def verify_installation(base: Path) -> tuple[bool, str]:
    installed = base / "extractors" / "apexlang.py"
    if not installed.is_file() or installed.read_bytes() != CANONICAL_EXTRACTOR.read_bytes():
        return False, "installed extractor differs from canonical source"
    extract_text = (base / "extract.py").read_text(encoding="utf-8")
    detect_text = (base / "detect.py").read_text(encoding="utf-8")
    if '".apx": extract_apexlang,' not in extract_text:
        return False, ".apx dispatch is not registered"
    if "'.apx'" not in detect_text and '".apx"' not in detect_text:
        return False, ".apx is not classified as code"
    return True, "ok"

def patch_graphify_dir(base: Path) -> bool:
    detect_path, extract_path = base / "detect.py", base / "extract.py"
    installed_path = base / "extractors" / "apexlang.py"
    if not all(path.is_file() for path in (CANONICAL_EXTRACTOR, detect_path, extract_path)):
        return False
    originals = {path: path.read_bytes() for path in (detect_path, extract_path)}
    detect_new = patched_detector(originals[detect_path].decode("utf-8"))
    extract_new = patched_dispatch(originals[extract_path].decode("utf-8"))
    if detect_new is None or extract_new is None:
        return False
    old_installed = installed_path.read_bytes() if installed_path.exists() else None
    try:
        detect_path.write_text(detect_new, encoding="utf-8")
        extract_path.write_text(extract_new, encoding="utf-8")
        shutil.copyfile(CANONICAL_EXTRACTOR, installed_path)
        return verify_installation(base)[0]
    except OSError:
        for path, content in originals.items():
            path.write_bytes(content)
        if old_installed is None:
            installed_path.unlink(missing_ok=True)
        else:
            installed_path.write_bytes(old_installed)
        return False
```

Requirements:

- Copy with `shutil.copyfile` only after all required package files and patch anchors have been validated in memory.
- Replace a legacy `".apx": extract_sql` mapping with `extract_apexlang`.
- Add one import from `graphify.extractors.apexlang` and one `.apx` dispatch entry.
- Keep `.apx` in the SQL optional-dependency map only if the new extractor actually imports the SQL parser; otherwise remove that false dependency.
- Write modified package files only after producing all patched strings successfully.
- Verify copied bytes match the canonical extractor.
- Smoke test through the Graphify CLI interpreter when available; fixture tests may import the copied file directly because their fake package is intentionally incomplete.
- Print the exact Graphify base path and failed gate without exposing environment variables or credentials.

- [ ] **Step 4: Run installer and extractor tests**

Run:

```bash
python3 scripts/test_setup_graphify.py -v
python3 scripts/test_graphify_apexlang_extractor.py -v
```

Expected: all tests pass.

- [ ] **Step 5: Run setup against the current isolated Graphify installation**

Run:

```bash
python3 setup_graphify_apx.py
python3 setup_graphify_apx.py
```

Expected: both runs succeed; the second run reports an already-current or successfully configured installation without changing installed bytes.

---

### Task 4: Domain-Only Corpus Allowlist

**Files:**
- Modify: `.graphifyignore`
- Create: `scripts/test_graphify_corpus.py`
- Modify: `scripts/test_template.sh`

**Interfaces:**
- Consumes: Graphify gitignore-style last-match-wins and parent-reinclusion semantics.
- Produces: only `apps/`, `database/`, and `app_context/` candidates, with nested APEX payload exclusions.

- [ ] **Step 1: Write failing corpus-contract tests**

In `scripts/test_graphify_corpus.py`, statically require these root rules:

```text
/*
!/apps/
!/database/
!/app_context/
```

Require nested exclusions for `.apex`, `deployments`, `workspace-components`, static-file directories, theme static files, and `static-files.apx`. If the `graphify` command is available, import its interpreter's `graphify.detect` in a subprocess and assert representative paths:

```python
included = [
    "apps/DEMO/102/pages/p00004-home.apx",
    "apps/DEMO/102/shared-components/lists.apx",
    "database/DEMO/tables/SAMPLE_RESTAURANT.sql",
    "app_context/102/context.md",
]
excluded = [
    ".agents/skills/superpowers/brainstorming/scripts/server.cjs",
    "scripts/backup_db.sh",
    "setup_graphify_apx.py",
    "ai_generate/2026-08-29/change.sql",
    "apps/DEMO/102/.apex/apexlang.json",
    "apps/DEMO/102/deployments/default.json",
    "apps/DEMO/102/workspace-components/app-groups/sample-applications.apx",
    "apps/DEMO/102/shared-components/static-files.apx",
    "apps/DEMO/102/shared-components/static-files/logo.png",
]
```

Add the two new Python test scripts to `scripts/test_template.sh` after the existing setup test.

- [ ] **Step 2: Run corpus tests and confirm failure**

Run:

```bash
python3 scripts/test_graphify_corpus.py -v
```

Expected: failure because `.graphifyignore` currently permits `.agents`, scripts, root Python, workspace components, and `static-files.apx`.

- [ ] **Step 3: Replace `.graphifyignore` with the allowlist**

Use root-anchored patterns so future template directories are excluded by default:

```gitignore
/*
!/apps/
!/database/
!/app_context/

/apps/**/.apex/
/apps/**/deployments/
/apps/**/workspace-components/
/apps/**/static-files.apx
/apps/**/static-files/
```

Retain explicit log/BLOB exclusions only when they are not already covered. Do not re-include `ai_generate/`, scripts, tests, agent skills, or root documentation.

- [ ] **Step 4: Run focused and template tests**

Run:

```bash
python3 scripts/test_graphify_corpus.py -v
bash scripts/test_template.sh
```

Expected: corpus tests pass and the existing template suite remains green.

---

### Task 5: Portable Workflow Documentation

**Files:**
- Modify: `.agents/rules/graphify.md`
- Modify: `.agents/workflows/graphify.md`
- Modify: `AGENTS.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: setup and update behavior from Tasks 1-4.
- Produces: one consistent command contract for fresh clones, code changes, context changes, forced rebuilds, and Graphify upgrades.

- [ ] **Step 1: Add failing documentation assertions**

Extend `scripts/test_graphify_corpus.py` to require all documentation surfaces to contain the canonical commands and concepts:

```text
python3 setup_graphify_apx.py
graphify extract . --force
graphify update .
app_context
Graphify upgrade
```

Assert the workflow no longer recommends `--code-only` for the initial build and no longer describes `.apx` as SQL extraction.

- [ ] **Step 2: Run documentation assertions and confirm failure**

Run:

```bash
python3 scripts/test_graphify_corpus.py -v
```

Expected: failure on the old `--code-only` and `.apx -> SQL` workflow text.

- [ ] **Step 3: Update rules and workflow**

Document exactly:

- Fresh clone: install optional Graphify separately, run `python3 setup_graphify_apx.py`, configure a supported semantic backend, then run `graphify extract . --force`.
- APEX or database source change: run `graphify update .`.
- `app_context/*.md` change: run incremental `graphify extract .` so semantic hashes refresh.
- `.graphifyignore` change or deliberate large deletion: run the forced full extraction and verify allowed/excluded sources.
- Graphify upgrade: rerun setup before any update; setup owns and verifies the copied extractor.
- Queries should begin with `graphify query`, with `path`/`explain` for focused follow-up.
- Verification must inspect source roots, representative APEX edges, and context results rather than only process exit status.

Keep `AGENTS.md` concise and route details to `.agents/workflows/graphify.md`. Add a README link or short optional-tooling example so a new template user can discover setup without reading agent-only rules.

- [ ] **Step 4: Run link and documentation checks**

Run:

```bash
python3 scripts/test_graphify_corpus.py -v
python3 scripts/check_local_links.py .
git diff --check -- .agents/rules/graphify.md .agents/workflows/graphify.md AGENTS.md README.md
```

Expected: all checks pass and no documentation contradicts the full semantic initial build.

---

### Task 6: End-to-End Rebuild and Acceptance Verification

**Files:**
- Generated locally: `graphify-out/graph.json`
- Generated locally: `graphify-out/GRAPH_REPORT.md`
- Generated locally: `graphify-out/manifest.json`
- Modify if evidence warrants: `self_improve.md`

**Interfaces:**
- Consumes: installed extractor, domain allowlist, current demo `apps/`, `database/`, and `app_context/` content.
- Produces: a queryable domain-only graph satisfying the spec's acceptance criteria.

- [ ] **Step 1: Run all focused tests before rebuilding**

Run:

```bash
python3 scripts/test_graphify_apexlang_extractor.py -v
python3 scripts/test_setup_graphify.py -v
python3 scripts/test_graphify_corpus.py -v
bash scripts/test_template.sh
```

Expected: all commands pass.

- [ ] **Step 2: Verify semantic backend selection without exposing secrets**

Check only whether supported credential variable names are set; never print values. Record the backend Graphify will use from its CLI output. If no configured backend can process Markdown, stop before claiming context acceptance and report the exact missing prerequisite.

- [ ] **Step 3: Rebuild from the domain allowlist**

Run:

```bash
python3 setup_graphify_apx.py
graphify extract . --force
```

Expected: setup succeeds, extraction includes Markdown semantic work, and Graphify writes a new graph/report/manifest. If the CLI requires an explicit already-configured backend, pass only the backend name—never a credential value.

- [ ] **Step 4: Assert source-root and relationship invariants**

Run read-only JSON checks:

```bash
jq -e 'all(.nodes[]; ((.source_file // "") == "") or (.source_file | startswith("apps/") or startswith("database/") or startswith("app_context/")))' graphify-out/graph.json
jq -e '[.links[] | select((.source_file // "") | endswith(".apx"))] | length > 0' graphify-out/graph.json
jq -e '[.nodes[] | select((.source_file // "") | startswith("app_context/"))] | length > 0' graphify-out/graph.json
```

Also assert no source contains `/.apex/`, `/deployments/`, `/workspace-components/`, `/static-files/`, or ends with `/static-files.apx`; no label equals `server.cjs`; and no source begins with `.agents/`, `scripts/`, or `ai_generate/`.

- [ ] **Step 5: Run representative graph queries**

Run:

```bash
graphify query "Which database tables does APEXToGo page 4 read?"
graphify query "Which navigation components lead to APEXToGo page 8?"
graphify query "What does the checkout process write and which package does it call?"
graphify query "What are the known cart-state gotchas for APEXToGo?"
```

Expected:

- Page 4 reaches `SAMPLE_RESTAURANT` or `SAMPLE_RESTAURANT_CATEGORIES` through `reads_from`.
- Navigation reaches page 8 through `navigates_to`.
- Checkout reaches an order table or `SAMPLE_RESTAURANT_MANAGE_ORDERS` through `writes_to`/`calls` where present in the exported source.
- The gotcha query cites `app_context/102/context.md` and describes session-specific APEX collection state.

- [ ] **Step 6: Inspect hubs and final diff**

Run:

```bash
graphify god-nodes --top 15
sed -n '1,180p' graphify-out/GRAPH_REPORT.md
git diff --check
git status --short --branch
git diff -- .graphifyignore setup_graphify_apx.py scripts .agents/rules/graphify.md .agents/workflows/graphify.md AGENTS.md README.md docs/superpowers
```

Expected: hubs describe APEX applications/pages/database objects rather than vendored servers or maintenance scripts; no unrelated user files are modified.

- [ ] **Step 7: Record a durable lesson only if supported**

If implementation evidence reveals a reusable repository-specific failure not already captured—such as Graphify accepting an extractor that returns file nodes but zero edges—add one `self_improve.md` entry with Trigger, Evidence, Preferred behavior, and Verification. Otherwise leave `self_improve.md` unchanged.

- [ ] **Step 8: Final verification before completion**

Invoke `superpowers:verification-before-completion`, rerun the narrow focused tests plus the complete template suite, and report exact graph source/edge/context counts. Do not claim completion if semantic context is absent or if any graph source falls outside the domain allowlist.
