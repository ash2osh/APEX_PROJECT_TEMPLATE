#!/usr/bin/env python3
"""Graphify extractor for Oracle APEX APEXLANG export files."""

from __future__ import annotations

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

DISPLAY_TYPES = {
    "app": "App",
    "page": "Page",
    "region": "Region",
    "process": "Process",
    "dynamic_action": "Dynamic Action",
    "list": "List",
    "lov": "LOV",
    "authentication": "Authentication",
    "authorization": "Authorization",
    "app_process": "Application Process",
    "build_option": "Build Option",
}

DECLARATION_RE = re.compile(
    r'^\s*([A-Za-z][A-Za-z0-9-]*)'
    r'(?:\s+("(?:[^"\\]|\\.)*"|[A-Za-z0-9_.-]+))?\s*\(\s*$'
)
NAME_RE = re.compile(r'^\s*name\s*:\s*(.*?)\s*$')
CLOSE_COMPONENT_RE = re.compile(r'^\s*\)\s*$')
PROPERTY_RE = re.compile(r'^\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*?)\s*$')
REFERENCE_RE = re.compile(r'^\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*@([^\s\]}]+)')
PAGE_TARGET_RE = re.compile(r'\bpage\s*:\s*(\d+)\b', re.IGNORECASE)
APEX_URL_PAGE_RE = re.compile(r'f\?p=[^:\s]*:(\d+):', re.IGNORECASE)
SQL_IDENTIFIER = (
    r'(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*)'
    r'(?:\s*\.\s*(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*))*'
)
READ_RE = re.compile(rf'\b(?:FROM|JOIN)\s+({SQL_IDENTIFIER})', re.IGNORECASE)
WRITE_RE = re.compile(
    rf'\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO)\s+({SQL_IDENTIFIER})',
    re.IGNORECASE,
)
PAREN_CALL_RE = re.compile(
    rf'\b({SQL_IDENTIFIER}\s*\.\s*(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*))\s*\(',
    re.IGNORECASE,
)
STATEMENT_CALL_RE = re.compile(
    rf'^\s*({SQL_IDENTIFIER}\s*\.\s*(?:"[^"]+"|[A-Za-z][A-Za-z0-9_$#]*))\s*;',
    re.IGNORECASE | re.MULTILINE,
)

COMPONENT_REFERENCE_PROPERTIES = {
    "listofvalues": "lov",
    "namedlov": "lov",
    "lov": "lov",
    "buildoption": "build_option",
    "authentication": "authentication",
    "authenticationscheme": "authentication",
    "list": "list",
}

IGNORED_SQL_OBJECTS = {
    "dual",
}

SQL_PROPERTY_NAMES = {
    "sqlquery",
    "plsqlcode",
    "plsqlfunctionbody",
    "functionbody",
    "whereclause",
}


class ApexlangParseError(ValueError):
    """Raised when an APEXlang file is structurally incomplete."""


@dataclass
class Frame:
    kind: str
    identifier: str
    line: int
    node_id: str | None
    architectural_owner: str | None


def make_id(*parts: object) -> str:
    """Return a stable Graphify-compatible identifier."""
    raw = "_".join(str(part) for part in parts if str(part))
    normalized = re.sub(r"[^a-zA-Z0-9]+", "_", raw)
    return re.sub(r"_+", "_", normalized).strip("_").lower()


def _clean_identifier(value: str | None, fallback: str) -> str:
    if not value:
        return fallback
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value


def _application_id(path: Path, text: str) -> str:
    parts = path.parts
    for index, part in enumerate(parts):
        if part == "apps" and index + 2 < len(parts) and parts[index + 2].isdigit():
            return parts[index + 2]
    match = re.search(r"(?m)^\s*app\s+(\d+)\s*\(\s*$", text)
    return match.group(1) if match else "unknown"


def _source_location(line: int) -> str:
    return f"L{line}"


def _node(
    node_id: str,
    label: str,
    source_path: str,
    line: int | None,
    **metadata: object,
) -> dict:
    result = {
        "id": node_id,
        "label": label,
        "file_type": "code",
        "source_file": source_path,
        "source_location": _source_location(line) if line is not None else None,
    }
    if metadata:
        result["metadata"] = metadata
    return result


def _edge(source: str, target: str, relation: str, source_path: str, line: int) -> dict:
    return {
        "source": source,
        "target": target,
        "relation": relation,
        "confidence": "EXTRACTED",
        "source_file": source_path,
        "source_location": _source_location(line),
        "weight": 1.0,
    }


def _label(kind: str, identifier: str, name: str | None = None) -> str:
    display = DISPLAY_TYPES[kind]
    if kind in {"app", "page"}:
        return f"{display} {identifier}" + (f": {name}" if name else "")
    return f"{display}: {name or identifier}"


def _nearest_page(frames: list[Frame]) -> str | None:
    for frame in reversed(frames):
        if frame.kind == "page" and frame.node_id:
            return frame.node_id
    return None


def _nearest_owner(frames: list[Frame], fallback: str) -> str:
    for frame in reversed(frames):
        if frame.architectural_owner:
            return frame.architectural_owner
    return fallback


def _strip_sql_comments_and_literals(text: str) -> str:
    """Mask SQL comments and literals while preserving offsets and newlines."""
    masked = list(text)
    pattern = re.compile(r"--[^\n]*|/\*.*?\*/|'(?:''|[^'])*'", re.DOTALL)
    for match in pattern.finditer(text):
        masked[match.start():match.end()] = [
            "\n" if char == "\n" else " " for char in match.group(0)
        ]
    return "".join(masked)


def _reference_label(value: str) -> str:
    return re.sub(r"\s*\.\s*", ".", value.strip())


def _sql_dependencies(text: str) -> tuple[set[str], set[str], set[str]]:
    clean = _strip_sql_comments_and_literals(text)
    reads_clean = re.sub(
        r'\bEXTRACT\s*\([^()]*\)',
        lambda match: "".join("\n" if char == "\n" else " " for char in match.group(0)),
        clean,
        flags=re.IGNORECASE,
    )
    cte_names = {
        _reference_label(match.group(1)).casefold()
        for match in re.finditer(
            rf'\b({SQL_IDENTIFIER})\s+AS\s*\(\s*SELECT\b',
            reads_clean,
            re.IGNORECASE,
        )
    }
    reads = {
        _reference_label(match.group(1))
        for match in READ_RE.finditer(reads_clean)
        if _reference_label(match.group(1)).casefold() not in cte_names
    }
    writes = {_reference_label(match.group(1)) for match in WRITE_RE.finditer(clean)}
    calls = {
        _reference_label(match.group(1))
        for pattern in (PAREN_CALL_RE, STATEMENT_CALL_RE)
        for match in pattern.finditer(clean)
    }
    reads = {name for name in reads if name.casefold() not in IGNORED_SQL_OBJECTS}
    calls = {
        name
        for name in calls
        if not name.casefold().startswith(("apex_", "sys.", "dbms_"))
    }
    return reads, writes, calls


def _strip_comments(line: str, in_block_comment: bool) -> tuple[str, bool]:
    output: list[str] = []
    index = 0
    while index < len(line):
        if in_block_comment:
            end = line.find("*/", index)
            if end < 0:
                return "".join(output), True
            in_block_comment = False
            index = end + 2
            continue
        if line.startswith("/*", index):
            in_block_comment = True
            index += 2
            continue
        if line.startswith("//", index):
            break
        output.append(line[index])
        index += 1
    return "".join(output), in_block_comment


def parse_apexlang(text: str, path: Path) -> dict[str, object]:
    """Parse architectural APEXlang declarations from *text*."""
    source_path = str(path)
    app_id = _application_id(path, text)
    app_node_id = make_id("apex", "app", app_id)
    file_node_id = make_id(source_path)
    nodes: list[dict] = [_node(file_node_id, path.name, source_path, None)]
    node_by_id = {file_node_id: nodes[0]}
    edges: list[dict] = []
    edge_keys: set[tuple[str, str, str, str, str]] = set()
    frames: list[Frame] = []
    in_fence = False
    in_block_comment = False
    pending_property: str | None = None
    fence_owner: str | None = None
    fence_start = 0
    fence_lines: list[str] = []
    fence_is_database_code = False

    def add_node(node: dict) -> None:
        existing = node_by_id.get(node["id"])
        if existing is None:
            node_by_id[node["id"]] = node
            nodes.append(node)

    def add_reference_node(label: str) -> str:
        node_id = make_id(label)
        if node_id not in node_by_id:
            node = _node(node_id, label, "", None, origin_file=source_path)
            node["source_location"] = ""
            node_by_id[node_id] = node
            nodes.append(node)
        return node_id

    def add_edge(source: str, target: str, relation: str, line: int) -> None:
        candidate = _edge(source, target, relation, source_path, line)
        key = (
            source,
            target,
            relation,
            candidate["source_file"],
            candidate["source_location"],
        )
        if key not in edge_keys:
            edge_keys.add(key)
            edges.append(candidate)

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        fence_count = raw_line.count("```")
        if in_fence:
            if fence_count % 2:
                block = "\n".join(fence_lines)
                if fence_owner and fence_is_database_code:
                    reads, writes, calls = _sql_dependencies(block)
                    for target in sorted(reads, key=str.casefold):
                        add_edge(fence_owner, add_reference_node(target), "reads_from", fence_start)
                    for target in sorted(writes, key=str.casefold):
                        add_edge(fence_owner, add_reference_node(target), "writes_to", fence_start)
                    for target in sorted(calls, key=str.casefold):
                        add_edge(fence_owner, add_reference_node(target), "calls", fence_start)
                in_fence = False
                fence_owner = None
                fence_lines = []
                fence_is_database_code = False
                pending_property = None
            else:
                fence_lines.append(raw_line)
            continue
        if fence_count % 2:
            prefix = raw_line.split("```", 1)[0]
            property_match = PROPERTY_RE.match(prefix)
            if property_match:
                pending_property = property_match.group(1)
            language = raw_line.split("```", 1)[1].strip().casefold()
            in_fence = True
            fence_owner = _nearest_owner(frames, app_node_id)
            fence_start = line_number + 1
            fence_lines = []
            fence_is_database_code = (
                language in {"sql", "plsql"}
                or (pending_property or "").casefold() in SQL_PROPERTY_NAMES
            )
            continue

        line, in_block_comment = _strip_comments(raw_line, in_block_comment)
        if not line.strip():
            continue

        declaration = DECLARATION_RE.match(line)
        if declaration:
            token = declaration.group(1)
            identifier = _clean_identifier(declaration.group(2), token)
            kind = ARCHITECTURAL_TYPES.get(token)
            node_id: str | None = None
            owner = _nearest_owner(frames, app_node_id)

            if kind == "app":
                if identifier.isdigit():
                    app_id = identifier
                    app_node_id = make_id("apex", "app", app_id)
                node_id = app_node_id
                add_node(
                    _node(node_id, _label(kind, app_id), source_path, line_number,
                          component_type=kind, application_id=app_id)
                )
                add_edge(file_node_id, node_id, "contains", line_number)
                owner = node_id
            elif kind == "page":
                node_id = make_id("apex", "app", app_id, "page", identifier)
                add_node(
                    _node(node_id, _label(kind, identifier), source_path, line_number,
                          component_type=kind, application_id=app_id, page_id=identifier)
                )
                add_edge(file_node_id, node_id, "contains", line_number)
                add_edge(app_node_id, node_id, "contains", line_number)
                owner = node_id
            elif kind:
                if kind in {"region", "process", "dynamic_action"}:
                    parent_id = _nearest_page(frames) or app_node_id
                    node_id = make_id(parent_id, kind, identifier)
                else:
                    parent_id = app_node_id
                    node_id = make_id(parent_id, kind, identifier)
                add_node(
                    _node(node_id, _label(kind, identifier), source_path, line_number,
                          component_type=kind, application_id=app_id,
                          component_identifier=identifier)
                )
                add_edge(parent_id, node_id, "contains", line_number)
                owner = node_id

            frames.append(
                Frame(
                    kind=kind or token,
                    identifier=identifier,
                    line=line_number,
                    node_id=node_id,
                    architectural_owner=node_id or owner,
                )
            )
            continue

        if CLOSE_COMPONENT_RE.match(line):
            if not frames:
                raise ApexlangParseError(f"unexpected component close at {source_path}:L{line_number}")
            frames.pop()
            pending_property = None
            continue

        name_match = NAME_RE.match(line)
        if name_match and frames:
            name = _clean_identifier(name_match.group(1), frames[-1].identifier)
            frame = frames[-1]
            if frame.node_id and frame.node_id in node_by_id:
                node_by_id[frame.node_id]["label"] = _label(frame.kind, frame.identifier, name)

        owner = _nearest_owner(frames, app_node_id)
        reference_match = REFERENCE_RE.match(line)
        if reference_match:
            property_name = reference_match.group(1).casefold()
            raw_reference = reference_match.group(2)
            reference = _clean_identifier(raw_reference, raw_reference)
            is_template_reference = reference.startswith("/")
            reference = reference.lstrip("/")
            if property_name in COMPONENT_REFERENCE_PROPERTIES and not is_template_reference:
                target_kind = COMPONENT_REFERENCE_PROPERTIES[property_name]
                target = make_id(app_node_id, target_kind, reference)
                add_edge(owner, target, "references_component", line_number)

        for page_match in PAGE_TARGET_RE.finditer(line):
            target = make_id("apex", "app", app_id, "page", page_match.group(1))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)
        for page_match in APEX_URL_PAGE_RE.finditer(line):
            target = make_id("apex", "app", app_id, "page", page_match.group(1))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)

        property_match = PROPERTY_RE.match(line)
        if property_match:
            pending_property = property_match.group(1)
            property_name = pending_property.casefold()
            property_value = property_match.group(2).strip()
            if property_name == "authorizationscheme" and property_value:
                reference = _clean_identifier(property_value.lstrip("@"), property_value)
                target = make_id(app_node_id, "authorization", reference)
                add_node(
                    _node(
                        target,
                        _label("authorization", reference),
                        source_path,
                        line_number,
                        component_type="authorization",
                        application_id=app_id,
                        synthetic_reference=True,
                    )
                )
                add_edge(owner, target, "secured_by", line_number)
            if property_name in SQL_PROPERTY_NAMES and property_value:
                reads, writes, calls = _sql_dependencies(property_value)
                for target in sorted(reads, key=str.casefold):
                    add_edge(owner, add_reference_node(target), "reads_from", line_number)
                for target in sorted(writes, key=str.casefold):
                    add_edge(owner, add_reference_node(target), "writes_to", line_number)
                for target in sorted(calls, key=str.casefold):
                    add_edge(owner, add_reference_node(target), "calls", line_number)

    if in_fence:
        raise ApexlangParseError(f"unclosed multiline fence in {source_path}")
    if frames:
        opened = frames[-1]
        raise ApexlangParseError(
            f"unclosed component '{opened.kind} {opened.identifier}' "
            f"from {source_path}:L{opened.line}"
        )

    return {"nodes": nodes, "edges": edges}


def extract_apexlang(path: Path) -> dict[str, object]:
    """Graphify extractor entry point."""
    try:
        text = path.read_text(encoding="utf-8")
        return parse_apexlang(text, path)
    except (OSError, UnicodeError, ApexlangParseError) as exc:
        return {"nodes": [], "edges": [], "error": str(exc)}
